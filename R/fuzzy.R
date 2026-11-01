# ============================================================================
# Character-level recovery: the one failure shape the cascade cannot see.
#
# Every pass in pf_staged_passes() and pf_recovery_passes() is an EXACT-equality
# block -- A1..A5 on name_key or dba_key plus ZIP5 or state, B1/B2 on a shared
# name token within state, C1/C2 on an exact name anywhere, D1 on initials, D2
# on an 18-character prefix plus ZIP5. npmatch offers no approximate comparator
# at the blocking stage at all, so a single-character edit in the one
# distinctive token leaves nothing anywhere to block on:
#
#   THE WESMINSTER SCHOOL  (ATLANTA GA 30327) -> THE WESTMINSTER SCHOOLS, 30327
#   COCORDIA UNIVERSITY    (MEQUON WI 53097)  -> CONCORDIA UNIVERSITY,    53097
#   THE PASSONISTS         (JAMAICA NY 11432) -> PASSIONIST MISSIONARIES, 11432
#
# All three correct rows are in the reference AT THE FILED ZIP5, so pass A1 --
# name_key + ZIP5, the cheapest pass in the cascade -- misses each of them by
# one letter. They are not scored and rejected; no pass produces a pair at all,
# so nothing reaches the sheet a reviewer or an LLM would read. That is why no
# adjudication tier can recover them: adjudication ranks candidates, and there
# are none.
#
# Measured on the 100-case NO sample: 3 of 91. See dev/NO-TIER-EXPERIMENT.md.
#
# WHY A GENERATOR AND NOT A PASS.
#
# np_block() has no fuzzy mode, so "D3-fuzzy" cannot be written in the pass
# vocabulary used by pf_staged_passes(). It does not need to be: np_block()
# returns nothing but an np_blocks frame of .x / .y row indices, and
# np_compare() accepts exactly that frame through its `candidates` argument. So
# this generates candidate pairs and hands them to the SAME comparator,
# selector and tiering code every other pass goes through. The YES/MAYBE/NO
# decision is not reimplemented here, and a fuzzy pair has to clear the same
# bar as an exact one.
# ============================================================================

#' Candidate pairs from a near-miss name inside a geographic block
#'
#' Jaro-Winkler similarity on `name_key` within an exact ZIP5 block, falling
#' back to city plus state where the ZIP5 block is empty. Blocking first is what
#' makes this affordable: the pools are small (median 477 reference rows on the
#' NO sample, largest 2,940) and scoring one takes microseconds, against the
#' 223,151 candidates pass B2 generates on 5,000 grants.
#'
#' @section On the cutoff:
#' The default of 0.90 is set from measurement, not taste. Scoring all 91 cases
#' of the NO sample against their own ZIP5 pools:
#'
#' * 0.90 recovers 7 of the 33 identities the BMF does hold, and offers exactly
#'   one row across the 57 it does not -- `SEE SCHEDULE ATTACHED` against
#'   `SEE SCHEDULE O`, which the placeholder filter below removes.
#' * 0.85 recovers 11 of the 33, four more, but the highest-scoring personal
#'   name sits at 0.848: `ALEXANDER SCHWEIG` against `ALEXANDER GRAHAM BELL
#'   ASSOCIATION`. A one-point margin on 38 individuals is not a margin.
#'
#' That near-collision is structural rather than bad luck. Jaro-Winkler's prefix
#' bonus is exactly what rewards a shared first name, so individuals are the
#' population this comparator is worst at excluding, and `skip_personal` exists
#' to keep them out of the pool rather than leaving the cutoff to catch them.
#'
#' @param query A normalized query frame (from [npmatch::np_normalize()])
#'   carrying `name_key`, `zip5`, `city` and `state`.
#' @param reference A normalized reference frame with the same four columns.
#' @param cutoff Minimum Jaro-Winkler similarity. Read the section above before
#'   lowering it.
#' @param top_k Most candidates to emit per query row.
#' @param block Which blocks to try, in order. `"city_state"` is a fallback for
#'   a query row whose ZIP5 matches no reference row (6 of 91 on the NO sample),
#'   not an additional pass: a row the ZIP5 block resolved is not retried.
#' @param personal Optional logical vector, one per query row, from
#'   `looks_personal` on the prepared grants. Passed positionally, the same way
#'   [pf_add_recovery_keys()] takes `only_truncated`.
#' @param skip_personal Drop query rows flagged `personal` before scoring.
#' @param max_pool Refuse to score a block larger than this, and say so. A guard
#'   against a degenerate key -- an all-blank ZIP5 column collapsing the whole
#'   reference into one block -- not a tuning parameter.
#' @param verbose Report pool sizes and how many pairs were emitted.
#' @return An `np_blocks` frame of `.x` / `.y` indices, with a `sim` attribute
#'   holding the similarity of each emitted pair.
#' @seealso [pf_fuzzy_recover()], [pf_staged_passes()]
#' @export
pf_fuzzy_candidates <- function(query, reference, cutoff = 0.90, top_k = 5L,
                                block = c("zip5", "city_state"),
                                personal = NULL, skip_personal = TRUE,
                                max_pool = 20000L, verbose = TRUE) {
  if (!requireNamespace("stringdist", quietly = TRUE))
    stop("pf_fuzzy_candidates() needs the 'stringdist' package.", call. = FALSE)
  block <- match.arg(block, several.ok = TRUE)
  say <- function(...) if (verbose) message(sprintf(...))
  q <- as.data.frame(query); r <- as.data.frame(reference)
  need <- c("name_key", "zip5", "city", "state")
  miss <- setdiff(need, intersect(names(q), names(r)))
  if (length(miss))
    stop(sprintf("query and reference both need: %s", paste(miss, collapse = ", ")),
         call. = FALSE)
  if (!is.null(personal)) stopifnot(length(personal) == nrow(q))

  empty <- structure(data.frame(.x = integer(0), .y = integer(0)),
                     n_query = nrow(q), n_reference = nrow(r), sim = numeric(0),
                     class = c("np_blocks", "data.frame"))

  blank <- function(x) is.na(x) | !nzchar(trimws(as.character(x)))
  # A placeholder on either side is the one false offer this comparator makes at
  # any cutoff: two placeholders are near-identical strings describing nothing.
  # np_block() drops placeholder QUERY rows; here the reference side has to go
  # too, because SEE SCHEDULE ATTACHED scores 0.91 against SEE SCHEDULE O and
  # that was the single false offer in the 57 measured non-organisations.
  rp <- if (is.null(r$name_placeholder)) rep(FALSE, nrow(r)) else r$name_placeholder %in% TRUE
  qp <- if (is.null(q$name_placeholder)) rep(FALSE, nrow(q)) else q$name_placeholder %in% TRUE
  r_ok <- which(!rp & !blank(r$name_key))
  if (!length(r_ok)) { say("no usable reference rows"); return(empty) }

  skip <- blank(q$name_key) | qp
  n_personal <- 0L
  if (skip_personal && !is.null(personal)) {
    n_personal <- sum(!skip & personal %in% TRUE)
    skip <- skip | (personal %in% TRUE)
  }
  todo <- which(!skip)
  say("fuzzy scan: %s of %s query rows (%s blank or placeholder, %s personal)",
      format(length(todo), big.mark = ","), format(nrow(q), big.mark = ","),
      format(sum(blank(q$name_key) | qp), big.mark = ","),
      format(n_personal, big.mark = ","))
  if (!length(todo)) return(empty)

  zkey <- function(x) {
    v <- gsub("[^0-9]", "", as.character(x))
    ifelse(nchar(v) == 5L, v, NA_character_)
  }
  ckey <- function(city, st) {
    k <- paste(toupper(trimws(as.character(city))), toupper(trimws(as.character(st))))
    ifelse(blank(city) | blank(st), NA_character_, k)
  }
  # Index the reference once per block type. split() on the key is what keeps
  # this linear in the reference rather than quadratic in query x reference.
  idx <- list()
  if ("zip5" %in% block) {
    k <- zkey(r$zip5[r_ok])
    idx$zip5 <- split(r_ok[!is.na(k)], k[!is.na(k)])
  }
  if ("city_state" %in% block) {
    k <- ckey(r$city[r_ok], r$state[r_ok])
    idx$city_state <- split(r_ok[!is.na(k)], k[!is.na(k)])
  }
  qz <- zkey(q$zip5); qc <- ckey(q$city, q$state)

  oversize <- 0L; emitted <- vector("list", length(todo)); pool_n <- integer(0)
  for (n in seq_along(todo)) {
    i <- todo[n]
    pool <- NULL
    for (b in block) {
      key <- if (b == "zip5") qz[i] else qc[i]
      if (is.na(key)) next
      cand <- idx[[b]][[key]]
      if (length(cand)) { pool <- cand; break }
    }
    if (is.null(pool)) next
    if (length(pool) > max_pool) { oversize <- oversize + 1L; next }
    pool_n <- c(pool_n, length(pool))
    s <- 1 - stringdist::stringdist(q$name_key[i], r$name_key[pool],
                                    method = "jw", p = 0.1)
    keep <- which(s >= cutoff)
    if (!length(keep)) next
    o <- keep[order(-s[keep])]
    if (length(o) > top_k) o <- o[seq_len(top_k)]
    emitted[[n]] <- data.frame(.x = rep(i, length(o)), .y = pool[o], sim = s[o])
  }
  if (length(pool_n))
    say("block pools: median %s rows, largest %s",
        format(stats::median(pool_n), big.mark = ","),
        format(max(pool_n), big.mark = ","))
  if (oversize)
    say("SKIPPED %s query row(s) whose block exceeded max_pool = %s",
        oversize, format(max_pool, big.mark = ","))
  out <- do.call(rbind, emitted)
  if (is.null(out) || !nrow(out)) {
    say("no pair cleared the %.2f cutoff", cutoff)
    return(empty)
  }
  say("emitted %s pair(s) over %s query row(s) at cutoff %.2f",
      format(nrow(out), big.mark = ","),
      format(length(unique(out$.x)), big.mark = ","), cutoff)
  structure(data.frame(.x = as.integer(out$.x), .y = as.integer(out$.y)),
            n_query = nrow(q), n_reference = nrow(r), sim = out$sim,
            class = c("np_blocks", "data.frame"))
}

#' Retry the unresolved residual with fuzzy candidates
#'
#' Generates fuzzy pairs for every identity the cascade did not clear, scores
#' them through [npmatch::np_compare()] and [npmatch::np_score()], unions them
#' with the pairs the cascade already retained, and re-runs selection and
#' tiering over that union.
#'
#' @section Why the union, and not the fuzzy pairs alone:
#' Selecting over the fuzzy pairs by themselves would let a fuzzy row win an
#' identity that an exact pass had already beaten on the same identity -- 26 of
#' the 33 recoverable NO cases *did* have candidates, scored and rejected, so
#' this is the common case rather than an edge one. [npmatch::np_cascade()]
#' makes its own final decision over the deduped union of every pass, and this
#' reproduces that: the fuzzy pairs are one more pass's worth of rows, competing
#' on the same footing.
#'
#' A consequence worth stating, because it is the regression question: an
#' identity that already cleared YES is not in the residual, no pair is added to
#' it, and its selection is therefore bit-identical. The function asserts that
#' rather than trusting it.
#'
#' @section What it is NOT limited to:
#' The residual is every identity that has not cleared YES, which on the
#' production run is 845 NO *and* 1,044 MAYBE. "NO" is a tier assigned after
#' scoring, so it cannot be blocked on; and [npmatch::np_cascade()] drops an
#' identity from `pending` only when a pass clears it to YES, which is the same
#' rule. So this changes the MAYBE tier too -- it adds rows to the adjudication
#' queue and can change which row a MAYBE identity is holding. That is where a
#' regression has to look; the YES set is protected by construction.
#'
#' @param m A `pf_match` object from [pf_match_grants()], with its `pairs`
#'   attribute intact.
#' @param ref The same reference bundle the match was run against.
#' @param cutoff,top_k,block,skip_personal,max_pool Passed to
#'   [pf_fuzzy_candidates()].
#' @param method Scoring method, which must be the one the run used --
#'   [pf_match_grants()] does not record it on the object, so it cannot be read
#'   back off `m`. Scoring the fuzzy pairs under a different method than the
#'   pairs they are unioned with would make the comparison meaningless, and
#'   nothing would report it.
#' @param verbose Report the residual size, pairs added and tier movement.
#' @return A list with `result` (the re-tiered frame), `before` and `after` tier
#'   tables, `moved` (the identities whose tier changed, with their fuzzy
#'   similarity), and `n` (counts).
#' @seealso [pf_fuzzy_candidates()], [pf_recover_from_dictionary()]
#' @export
pf_fuzzy_recover <- function(m, ref, cutoff = 0.90, top_k = 5L,
                             block = c("zip5", "city_state"),
                             skip_personal = TRUE, max_pool = 20000L,
                             method = "hier", verbose = TRUE) {
  say <- function(...) if (verbose) message(sprintf(...))
  if (!inherits(m, "pf_match")) stop("`m` must be a pf_match object.", call. = FALSE)
  union0 <- attr(m$result, "pairs")
  if (is.null(union0))
    stop("m$result has no `pairs` attribute; re-run the match retaining pairs.",
         call. = FALSE)
  bundle <- if (is.list(ref) && !is.null(ref$reference)) ref else list(reference = ref)
  r <- bundle$reference
  config <- m$config
  res0 <- as.data.frame(m$result)

  # The query is rebuilt the way pf_match_grants() built it rather than carried
  # on the object: np_query() and np_normalize() are deterministic functions of
  # the grants frame, which `m` does keep, and a 4,900-row query is cheap. A
  # stored copy would be one more thing that can go stale against the grants.
  g <- m$grants
  q_in <- g[g$in_scope, , drop = FALSE]
  trunc <- if (!is.null(q_in$name_truncated)) q_in$name_truncated else NULL
  q <- pf_add_recovery_keys(npmatch::np_normalize(npmatch::np_query(q_in, pf_map_grants())),
                            only_truncated = trunc)
  personal <- if (!is.null(q_in$looks_personal)) q_in$looks_personal else NULL

  # The residual is everything that has not cleared YES, and that includes the
  # identities which are ABSENT from the result frame entirely because no pass
  # produced a single pair for them. On the production run that is 120 in-scope
  # identities, and they are the cases this function exists for -- an earlier
  # version took the residual from the result frame and silently excluded them.
  cleared <- as.character(res0$.id[as.character(res0$tier) == "YES"])
  resid   <- setdiff(as.character(q$.id), cleared)
  say("residual: %s of %s in-scope identities have not cleared YES",
      format(length(resid), big.mark = ","), format(nrow(q), big.mark = ","))
  if (!length(resid)) stop("nothing unresolved to retry.", call. = FALSE)

  keep  <- as.character(q$.id) %in% resid
  q_sub <- q[keep, , drop = FALSE]
  blk <- pf_fuzzy_candidates(q_sub, r, cutoff = cutoff, top_k = top_k,
                             block = block, personal = personal[keep],
                             skip_personal = skip_personal, max_pool = max_pool,
                             verbose = verbose)
  if (!nrow(blk)) {
    say("no fuzzy candidates; result unchanged")
    return(list(result = m$result, before = table(factor(as.character(res0$tier),
                c("YES", "MAYBE", "NO"))), after = NULL,
                moved = res0[0, , drop = FALSE], n = c(residual = length(resid),
                pairs = 0L, promoted = 0L)))
  }
  sim <- attr(blk, "sim")
  # .x indexes q_sub; np_compare() is called against the FULL query, so it has
  # to be remapped. np_cascade() does the identical remap on every pass -- read
  # past it and the pairs silently attach to the wrong identities.
  blk$.x <- match(q_sub$.id[blk$.x], q$.id)

  # addr_freq is not passed: np_cascade() computes it internally and does not
  # expose it, so there is nothing to hand over. np_compare() derives it from
  # the same reference, so it arrives at the same table -- but it is derived
  # twice, which is the one place a fuzzy pair's score could drift from an
  # exact pair's for a reason that is not the pair.
  pr <- npmatch::np_veto(npmatch::np_score(
    npmatch::np_compare(q, r, config, candidates = blk,
                        name_freq = bundle$name_freq,
                        token_idf = bundle$token_idf),
    config, method = method))
  fz <- as.data.frame(pr); fz$pass <- "D3-fuzzy"
  # blk$.x has already been remapped to index the full query above, so this
  # reconstructs the right key. np_veto() can drop rows, so fz may be shorter
  # than blk and the lookup has to be by key rather than positional.
  fz$fuzzy_sim <- sim[match(paste(fz$.id, fz$.ein),
                            paste(q$.id[blk$.x], r$.ein[blk$.y]))]

  u0 <- as.data.frame(union0); u0$fuzzy_sim <- NA_real_
  allp <- data.table::rbindlist(list(u0, fz), fill = TRUE)
  # Dedup exactly as np_cascade() does -- first occurrence of an id/ein pair
  # wins -- so an existing exact pair is never displaced by a fuzzy duplicate.
  allp <- as.data.frame(allp)[!duplicated(paste(allp$.id, allp$.ein)), , drop = FALSE]
  attr(allp, "cmp_cols") <- attr(union0, "cmp_cols")
  attr(allp, "profile")  <- attr(union0, "profile")
  class(allp) <- c("np_pairs", "data.frame")

  res <- npmatch::np_tier(npmatch::np_select(allp, config), config)
  before <- table(factor(as.character(res0$tier), c("YES", "MAYBE", "NO")))
  after  <- table(factor(as.character(res$tier),  c("YES", "MAYBE", "NO")))

  b <- stats::setNames(as.character(res0$tier), as.character(res0$.id))
  a <- stats::setNames(as.character(res$tier),  as.character(res$.id))
  ids <- union(names(b), names(a))
  bt <- ifelse(is.na(b[ids]), "ABSENT", b[ids])
  at <- ifelse(is.na(a[ids]), "ABSENT", a[ids])
  chg <- ids[bt != at]
  # The regression assertion, not a diagnostic: a YES identity is excluded from
  # the residual, so no pair of its own is added and its selection cannot move.
  # If one did, the residual or the dedup is wrong and every number below is too.
  broke <- chg[bt[match(chg, ids)] == "YES"]
  if (length(broke))
    stop(sprintf("%d identity/identities that had cleared YES changed tier (%s). The residual or the dedup is wrong.",
         length(broke), paste(utils::head(broke, 5), collapse = ", ")), call. = FALSE)

  moved <- res[as.character(res$.id) %in% chg, , drop = FALSE]
  if (nrow(moved)) {
    moved$tier_before <- bt[match(as.character(moved$.id), ids)]
    # overall_ein comes back off the selected pair but is not guaranteed to be
    # in the 9-digit form .ein carries, so both sides are normalized. Matching
    # raw would return NA for every row and report no similarity at all.
    k <- paste(allp$.id, .pf_ein(allp$.ein))
    moved$fuzzy_sim <- allp$fuzzy_sim[match(
      paste(moved$.id, .pf_ein(moved$overall_ein)), k)]
  }
  say("fuzzy pairs added: %s over %s identities",
      format(nrow(fz), big.mark = ","),
      format(length(unique(fz$.id)), big.mark = ","))
  say("tier movement: %s identities changed (%s now YES that were not)",
      format(length(chg), big.mark = ","),
      format(sum(at[match(chg, ids)] == "YES"), big.mark = ","))
  say("  before: %d YES | %d MAYBE | %d NO", before[["YES"]], before[["MAYBE"]], before[["NO"]])
  say("  after:  %d YES | %d MAYBE | %d NO", after[["YES"]], after[["MAYBE"]], after[["NO"]])
  list(result = res, before = before, after = after, moved = moved,
       n = c(residual = length(resid), pairs = nrow(fz),
             promoted = sum(at[match(chg, ids)] == "YES")))
}
