#' Partition the reference by state, and run the cascade over the partition
#'
#' A shard's peak memory tracks the size of the reference it holds, and nothing
#' else moved it — not thread count, not batch size, not collecting between
#' passes, not collapsing duplicate reference rows
#' (`dev/MEMORY-FINDINGS.md`). Slicing the reference is therefore the only
#' measured route to running more than one shard at a time: the largest state
#' slice peaks at **5.24 GB against 37 GB for the whole reference**, so eleven
#' fit in 68 GB where one did before (`dev/STATE-PARTITION-FINDINGS.md`).
#'
#' @section Why nine of eleven passes partition:
#' Seven passes block on `state` outright, and `A1-name-zip5` and `D2-prefix`
#' block on ZIP5, which determines state. A query can only reach a reference row
#' in its own state under any of them, so holding the other 89% of the reference
#' buys nothing. The two that genuinely cross state lines — `C1-name-any` and
#' `C2-dba-any` — are also the cheapest in the cascade, 6,284 and 176 candidates
#' against `B2-token-concat`'s 71,105.
#'
#' @section The two things that make a slice behave like the whole:
#' **Corpus statistics.** `np_block()` gates tokens on document frequency and
#' IDF, both derived from the reference. Rebuilt on a slice they describe
#' California rather than the country, and a token common nationally but rare
#' in-state stops being gated — on the first attempt that produced *more*
#' candidate pairs from a tenth of the reference. [pf_partition_reference()]
#' therefore builds a **hybrid** index: rows positional within the slice, because
#' `ref_index$base$row` indexes the frame it was built from, and `df_base`,
#' `df_concat` and `n_reference` taken from the whole corpus.
#'
#' **Order of passes.** `np_cascade()` withholds queries that an earlier pass
#' resolved to YES, so a query's candidate set depends on how far it travelled.
#' Running the state-local passes first and the cross-state passes on what
#' remains changes what is pending when `C1`/`C2` run, relative to the monolithic
#' order where they sit between `B2` and `D1`. That is a real difference and it
#' is why [pf_run_partitioned()] is validated on tier agreement rather than
#' assumed identical.
#'
#' @name pf_partition
NULL

# The passes that can run against a single state's slice. A1 and D2 key on ZIP5
# rather than on `state`, but a ZIP5 lies in one state, so they are state-local
# in effect. Held as a constant rather than derived from each pass's `args`,
# because "blocks on ZIP5, therefore state-local" is a claim about US geography
# that a reader should be able to see and challenge.
.PF_STATE_LOCAL <- c("A1-name-zip5", "A2-name-state", "A3-name-dba",
                     "A4-dba-name", "A5-dba-dba", "B1-token-state",
                     "B2-token-concat", "D1-acronym", "D2-prefix")

#' Split a reference bundle into per-state shards
#'
#' @param ref A bundle from [pf_build_reference()], already carrying
#'   `ref_index`, `name_freq` and `token_idf` for the whole corpus.
#' @param states Which states to build. Defaults to every state present.
#' @param min_rows States with fewer rows than this are merged into a single
#'   `"_SMALL"` shard, so the territories do not each pay a process.
#' @param verbose Report the shard sizes.
#' @return A list of bundles, one per shard, each holding a sliced `reference`
#'   and a hybrid `ref_index`. `name_freq` and `token_idf` are shared unchanged —
#'   they are consumed by scoring, which must see the whole corpus.
#' @rdname pf_partition
#' @export
pf_partition_reference <- function(ref, states = NULL, min_rows = 5000L,
                                   token_cols = c("name_key", "name_acro"),
                                   verbose = TRUE) {
  stopifnot(is.list(ref), !is.null(ref$reference), !is.null(ref$ref_index))
  say <- function(...) if (verbose) { cat(sprintf(...), "\n"); flush.console() }
  r <- ref$reference
  st <- r$state
  st[is.na(st) | !nzchar(st)] <- "_NONE"
  tab <- table(st)
  if (is.null(states)) states <- names(tab)
  small <- names(tab)[tab < min_rows]
  lab <- ifelse(st %in% small, "_SMALL", st)
  keep <- lab %in% c(setdiff(states, small), if (length(small)) "_SMALL")
  labs <- sort(unique(lab[keep]))
  say("partitioning %s reference rows into %d shards (states under %s rows merged into _SMALL)",
      format(nrow(r), big.mark = ","), length(labs), format(min_rows, big.mark = ","))

  # One index per token column the passes block on -- NOT just `name_key`.
  # np_block() validates a supplied index with .np_ref_index_ok(), which
  # compares `token_col`; a mismatch is not an error, it silently rebuilds the
  # index inline from the reference it was handed. On a shard that means the
  # slice's own document frequencies, so the whole-corpus graft never applies and
  # the pass gates on in-state token rarity.
  #
  # That is not hypothetical: D1-acronym blocks on `name_acro`, and with only a
  # name_key index the TN shard lost HILLENGALE HHH -> HIS HELPING HANDS, a pair
  # the monolithic run makes. Both sides sit in TN; the pass simply gated
  # differently.
  # The whole-corpus index for each token column, built ONCE. Building these
  # inside the per-shard loop instead costs a full pass over the reference per
  # shard -- ~50x the work for an identical result.
  gidx <- ref$ref_index
  globals <- lapply(token_cols, function(tc)
    if (identical(tc, gidx$token_col)) gidx else {
      say("  building whole-corpus index for %s ...", tc)
      npmatch::np_ref_index(r, token_col = tc)
    })
  names(globals) <- token_cols

  out <- lapply(labs, function(L) {
    idx <- which(lab == L)
    sl <- r[idx, , drop = FALSE]
    mk <- function(tc, global) {
      ix <- npmatch::np_ref_index(sl, token_col = tc)
      # Rows must be slice-positional -- ref_index$base$row indexes the frame it
      # was built from -- while the statistics must be whole-corpus. That split
      # is the entire reason a shard can reproduce the unsliced blocking.
      ix$df_base     <- global$df_base
      ix$df_concat   <- global$df_concat
      ix$n_reference <- global$n_reference
      ix
    }
    ixs <- lapply(token_cols, function(tc) mk(tc, globals[[tc]]))
    names(ixs) <- token_cols
    say("  %-8s %9s rows", L, format(nrow(sl), big.mark = ","))
    list(reference = sl, ref_index = ixs[[token_cols[1]]], ref_index_by = ixs,
         name_freq = ref$name_freq, token_idf = ref$token_idf, shard = L)
  })
  names(out) <- labs
  structure(out, class = "pf_partition", n_reference = nrow(r))
}

#' Route queries to shards by the field the blocker uses
#'
#' Queries must be routed on the **normalized** `state`, not on the raw recorded
#' one. The two disagree on only 2 of 74,673 identities, so this is not where the
#' recall goes — but 770 carry no normalized state at all, and those match
#' nothing under a state-blocked pass by construction. They are routed to
#' `"_NONE"` and reach the reference only through the cross-state phase, which is
#' exactly the set of passes that could ever have matched them.
#'
#' @param query A normalized `np_query`.
#' @param shards Names of the available shards.
#' @return A character vector of shard labels, one per query row.
#' @rdname pf_partition
#' @export
pf_route_queries <- function(query, shards) {
  st <- query$state
  st[is.na(st) | !nzchar(st)] <- "_NONE"
  ifelse(st %in% shards, st,
         if ("_SMALL" %in% shards) "_SMALL" else "_NONE")
}

#' Run the cascade over a partitioned reference
#'
#' Phase 1 runs the state-local passes inside each shard. Phase 2 runs the
#' cross-state passes against the whole reference, on the queries no shard
#' resolved. The candidate sets are then unioned and **selected and tiered once**
#' — which is what `np_cascade()` does internally, and the reason a query's
#' runner-up margin is still computed across all of its candidates.
#'
#' @param grants A prepared frame from [pf_prepare_grants()].
#' @param part A [pf_partition_reference()] result.
#' @param ref The unpartitioned bundle, for the cross-state phase.
#' @param config,method Passed to the cascade.
#' @param passes Full pass list; split internally into state-local and
#'   cross-state.
#' @param verbose Per-shard progress.
#' @return A `pf_match`, the same class the monolithic path returns.
#' @rdname pf_partition
#' @export
pf_run_partitioned <- function(grants, part, ref, config = npmatch::np_config(),
                               method = "hier",
                               passes = c(pf_staged_passes("lean", concat = TRUE),
                                          pf_recovery_passes(state = TRUE)),
                               verbose = TRUE) {
  stopifnot(inherits(part, "pf_partition"))
  say <- function(...) if (verbose) { cat(sprintf(...), "\n"); flush.console() }
  tick <- function() proc.time()[["elapsed"]]

  local_p <- Filter(function(p) p$name %in% .PF_STATE_LOCAL, passes)
  cross_p <- Filter(function(p) !(p$name %in% .PF_STATE_LOCAL), passes)
  say("passes: %d state-local, %d cross-state (%s)", length(local_p),
      length(cross_p), paste(vapply(cross_p, function(p) p$name, character(1)),
                             collapse = ", "))

  q_in <- grants[grants$in_scope, , drop = FALSE]
  if (!nrow(q_in)) stop("no in-scope grants to match.", call. = FALSE)
  query <- pf_add_recovery_keys(npmatch::np_normalize(
    npmatch::np_query(q_in, pf_map_grants())))
  query$.id <- as.character(query$.id)
  route <- pf_route_queries(query, names(part))
  say("routed %s queries across %d shards", format(nrow(query), big.mark = ","),
      length(unique(route)))

  ## ---- phase 1: state-local passes, inside each shard ----------------------
  t0 <- tick(); acc <- list(); CMP <- NULL; PROF <- NULL
  for (L in names(part)) {
    i <- which(route == L)
    if (!length(i)) next
    # `_NONE` is NOT skipped, though the reasoning that it could be is seductive:
    # "a query with no state cannot match a state-blocked pass". It can. The
    # block key is built from the field as it stands, so a query with no state
    # joins reference rows that also have none -- and on the 1k benchmark exactly
    # one identity (HILLENGALE HHH -> HIS HELPING HANDS) is found that way, by
    # D1-acronym. Skipping the shard dropped it from the output entirely.
    s <- part[[L]]
    # Passes are grouped by the token column they block on, and each group gets
    # the hybrid index built for THAT column. Handing np_cascade() a single index
    # makes it silently rebuild one from the slice for any pass that blocks on a
    # different column, which reintroduces slice-local gating for exactly that
    # pass. Group order follows `passes`, so the cascade still runs tight to
    # loose.
    tcof <- function(p) p$args$token_col %||% "name_key"
    order_tc <- unique(vapply(local_p, tcof, character(1)))
    sp <- lapply(order_tc, function(tc) Filter(function(p) tcof(p) == tc, local_p))
    names(sp) <- order_tc
    # `pending` has to be carried ACROSS the groups by hand. Each np_cascade()
    # call starts its own pending set at every query it is given, so splitting
    # the passes into one call per token column silently re-runs the later passes
    # on queries an earlier pass had already resolved to YES. Those queries
    # collect candidates the monolithic cascade withheld from them, the extra
    # candidates become runner-ups, and the margin brake demotes them: measured
    # at 44 YES -> MAYBE on the 1k benchmark before this loop carried pending.
    prl <- list(); pend_i <- i
    for (tc in order_tc) {
      if (!length(pend_i)) break
      ixt <- s$ref_index_by[[tc]] %||% s$ref_index
      # np_cascade() stops if a pass set yields nothing, which is a reasonable
      # error for a whole run and a normal outcome for one token-column group on
      # one shard's residual -- a small state can easily have no acronym hits
      # left. Treat it as an empty contribution.
      rz <- tryCatch(
        npmatch::np_cascade(query[pend_i, , drop = FALSE], s$reference,
                            config = config, method = method,
                            passes = sp[[tc]], verbose = FALSE,
                            name_freq = s$name_freq, token_idf = s$token_idf,
                            ref_index = ixt),
        error = function(e) if (grepl("No candidate pairs", conditionMessage(e)))
                              NULL else stop(e))
      if (is.null(rz)) next
      pz <- attr(rz, "pairs")
      if (is.null(CMP)) { CMP <- attr(pz, "cmp_cols"); PROF <- attr(pz, "profile") }
      prl[[tc]] <- as.data.frame(pz)
      done <- as.character(as.data.frame(rz)$.id[
        as.character(as.data.frame(rz)$tier) == "YES"])
      pend_i <- pend_i[!(query$.id[pend_i] %in% done)]
    }
    pr <- as.data.frame(data.table::rbindlist(prl, fill = TRUE))
    pr <- .pf_dedup_pairs(pr)
    acc[[L]] <- pr
    say("  [%-8s] %6d queries -> %8s pairs", L, length(i),
        format(nrow(pr), big.mark = ","))
  }
  t_local <- tick() - t0
  say("phase 1 (state-local): %.0f s", t_local)

  ## ---- phase 2: cross-state passes, on the residual ------------------------
  # "Residual" means what the state phase did not resolve to YES, which is the
  # same rule np_cascade() applies between its own passes.
  pooled <- if (length(acc)) as.data.frame(data.table::rbindlist(acc, fill = TRUE))
            else NULL
  resolved <- character(0)
  if (!is.null(pooled) && nrow(pooled)) {
    cls <- .pf_reclass_pairs(pooled, CMP, PROF)
    sel <- npmatch::np_tier(npmatch::np_select(cls, config), config)
    resolved <- as.character(sel$.id[as.character(sel$tier) == "YES"])
  }
  pend <- setdiff(query$.id, resolved)
  say("phase 2: %s of %s queries still pending", format(length(pend), big.mark = ","),
      format(nrow(query), big.mark = ","))
  t0 <- tick()
  if (length(cross_p) && length(pend)) {
    j <- which(query$.id %in% pend)
    res2 <- npmatch::np_cascade(query[j, , drop = FALSE], ref$reference,
                                config = config, method = method,
                                passes = cross_p, verbose = FALSE,
                                name_freq = ref$name_freq,
                                token_idf = ref$token_idf,
                                ref_index = ref$ref_index)
    p2 <- attr(res2, "pairs")
    if (is.null(CMP)) { CMP <- attr(p2, "cmp_cols"); PROF <- attr(p2, "profile") }
    acc[["_CROSS"]] <- as.data.frame(p2)
    say("  [_CROSS  ] %6d queries -> %8s pairs", length(j),
        format(nrow(acc[["_CROSS"]]), big.mark = ","))
  }
  t_cross <- tick() - t0
  say("phase 2 (cross-state): %.0f s", t_cross)

  ## ---- combine: one union, one selection -----------------------------------
  if (!length(acc)) stop("no candidate pairs from any shard.", call. = FALSE)
  union <- as.data.frame(data.table::rbindlist(acc, fill = TRUE))
  union <- .pf_dedup_pairs(union)
  union <- .pf_reclass_pairs(union, CMP, PROF)
  say("union: %s pairs over %s queries", format(nrow(union), big.mark = ","),
      format(length(unique(union$.id)), big.mark = ","))
  out <- npmatch::np_tier(npmatch::np_select(union, config), config)
  attr(out, "pairs") <- union
  attr(out, "config") <- config

  structure(
    list(result = out, grants = grants,
         in_scope = q_in$grant_id,
         out_of_scope = grants$grant_id[!grants$in_scope],
         stages = NULL, config = config,
         timing = c(local = t_local, cross = t_cross,
                    match = t_local + t_cross),
         n = c(grants = nrow(grants), in_scope = nrow(q_in),
               out_of_scope = sum(!grants$in_scope),
               reference = attr(part, "n_reference"))),
    class = "pf_match")
}

# np_select() reads `cmp_cols` off the pairs object to know which comparison
# columns are address-like, and `profile` to pick a weight set. rbindlist() drops
# attributes, so both have to be carried across from a shard's own pairs or every
# address view silently becomes NA.
#
# Taken from the shard rather than reconstructed from the column names: the
# comparison set is np_compare()'s business and a guess here would drift the
# moment it changes.
.pf_reclass_pairs <- function(df, cmp_cols, profile = NULL) {
  attr(df, "cmp_cols") <- cmp_cols
  attr(df, "profile")  <- profile
  class(df) <- c("np_pairs", "data.frame")
  df
}

# Reduce a pair set to one row per (.id, .ein), keeping the HIGHEST-SCORING row.
#
# np_cascade() keeps the FIRST occurrence instead -- deliberately, "keep tightest
# pass". That is a no-op while one EIN has one reference row, which is exactly
# true of the active BMF (1,924,822 rows, 1,924,822 EINs). It is not true of the
# augmented reference: 127,499 EINs carry several rows, those rows score
# differently, and keeping the first means the row that represents an EIN is
# decided by whichever pass reached it first.
#
# Measured monolithically on the 1k benchmark (dev/DEDUP-RULE.log): of 290,660
# repeated (.id, .ein) pairs only 4,201 disagree on score, but those 4,201 move
# 143 identities and the score rises on 138 of them -- median spread 0.140, max
# 0.900. Tier counts go 3015/1041/737 to 3099/1017/677. So keeping the first is
# not merely order-dependent, it discards a much better match for the same EIN.
#
# Ties in score fall back to the first, which preserves "tightest pass" for the
# case the original rule was written for.
.pf_dedup_pairs <- function(df) {
  if (!nrow(df)) return(df)
  o <- order(df$.id, df$.ein, -df$score)
  d <- df[o, , drop = FALSE]
  d[!duplicated(paste(d$.id, d$.ein)), , drop = FALSE]
}
