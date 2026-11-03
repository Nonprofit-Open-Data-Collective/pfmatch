#' Collapse grant rows to distinct recipient identities
#'
#' The main scale lever for the full grant file. Grants repeat heavily — the same
#' foundation funds the same charity every year, and thousands of foundations fund
#' the same large charities — so matching distinct *recipient identities* rather
#' than grant rows removes work without removing recall.
#'
#' It also buys recall outright. Because a cluster is one organization by
#' construction, a match found for any member **propagates to every member**: a
#' truncated, misspelled, or acronymic variant inherits the EIN resolved for an
#' easier variant sitting in the same cluster. See [pf_propagate_matches()].
#'
#' @section Two levels:
#' \describe{
#'   \item{`"exact"`}{group by the normalized key `(name_key, street_key, zip5)`.
#'     A hash group-by; linear and safe.}
#'   \item{`"fuzzy"`}{additionally cluster the *surviving distinct keys* — a much
#'     smaller set — within a geographic block, joining names whose Jaro-Winkler
#'     similarity clears `threshold`. Absorbs `ST JUDES` / `ST JUDE CHILDRENS
#'     RESEARCH HOSP`.}
#' }
#'
#' @section Guarding against over-merging:
#' Two different organizations can share an address (`FIRST PRESBYTERIAN CHURCH`
#' and `FIRST PRESBYTERIAN FOUNDATION` at one Boca Raton ZIP). Fuzzy clustering
#' therefore requires high name similarity **and** applies npmatch's hard veto
#' predicates — conflicting embedded numbers, ordinals, or directions — so
#' `LOCAL 32` never merges with `LOCAL 45`, nor `FIRST` with `SECOND`. Inspect the
#' result with [pf_dedup_report()] before trusting it.
#'
#' @name pf_dedup_doc
NULL
# Suffixes that mark the SAME entity under a different corporate wrapper. Safe to
# strip when deciding identity: "American Heart Association" and "American Heart
# Association Inc" are one organization.
.pf_corporate_suffixes <- function() c(
  "INC", "INCORPORATED", "CORP", "CORPORATION", "CO", "COMPANY",
  "LLC", "LTD", "LIMITED", "LLP", "LP", "PC", "PLLC")
# Suffixes that frequently mark a DIFFERENT, affiliated entity with its own EIN:
# a university and its foundation, a museum and its endowment. npmatch's
# name_key strips these -- correct for *matching* (both should be candidates),
# wrong for *identity* (merging them would lock one EIN across both). The MAYBE
# audit found this foundation-vs-operating split in 7 of 100 cases.
.pf_affiliate_suffixes <- function() c(
  "FOUNDATION", "FDN", "FOUND", "FUND", "TRUST", "ASSOCIATION", "ASSN",
  "SOCIETY", "INSTITUTE", "ORGANIZATION", "ORG", "ENDOWMENT", "ALUMNI",
  "AUXILIARY", "GUILD", "FRIENDS")
# Identity key: name_full with trailing CORPORATE suffixes removed but affiliate
# suffixes retained. Built from name_full, not name_key, precisely because
# name_key has already thrown the affiliate suffix away.
.pf_identity_key <- function(name_full) {
  v <- ifelse(is.na(name_full), "", name_full)
  corp <- .pf_corporate_suffixes()
  toks <- strsplit(v, " ", fixed = TRUE)
  vapply(toks, function(t) {
    t <- t[nzchar(t)]
    while (length(t) && t[length(t)] %in% corp) t <- t[-length(t)]
    paste(t, collapse = " ")
  }, character(1))
}
# Which affiliate-suffix tokens does a name carry? Two names whose sets differ
# are held apart even when the strings are otherwise near-identical.
.pf_affiliate_tokens <- function(name_full) {
  aff <- .pf_affiliate_suffixes()
  toks <- strsplit(ifelse(is.na(name_full), "", name_full), " ", fixed = TRUE)
  vapply(toks, function(t) paste(sort(unique(t[t %in% aff])), collapse = " "),
         character(1))
}
# Blocking key for fuzzy clustering: ZIP5 where present, else state, else "".
# A record with neither is never clustered (it stays a singleton).
.pf_geo_block <- function(d) {
  k <- ifelse(!is.na(d$zip5) & nzchar(d$zip5), paste0("Z", d$zip5),
       ifelse(!is.na(d$state) & nzchar(d$state), paste0("S", d$state), ""))
  k
}
# Single-linkage components over an edge list: a small dependency-free union-find
# with path halving. Edges are (i, j) index pairs into 1..n.
#
# `parent` lives in this frame, so the union step assigns with `<-`; only the
# nested find() needs `<<-` to reach back out to it.
.pf_components <- function(n, i, j) {
  parent <- seq_len(n)
  find <- function(x) {
    while (parent[x] != x) {
      parent[x] <<- parent[parent[x]]      # path halving
      x <- parent[x]
    }
    x
  }
  for (k in seq_along(i)) {
    a <- find(i[k]); b <- find(j[k])
    if (a != b) parent[max(a, b)] <- min(a, b)
  }
  vapply(seq_len(n), find, integer(1))
}
#' Deduplicate grant recipients
#'
#' @param grants A prepared frame from [pf_prepare_grants()].
#' @param method `"exact"` or `"fuzzy"` (fuzzy implies exact first).
#' @param threshold Jaro-Winkler similarity required to join two names in the
#'   same geographic block. Default 0.92.
#' @param max_block Blocks larger than this are compared exactly only, not
#'   fuzzily — a guard against a quadratic blow-up on a huge shared ZIP.
#' @param verbose Print the collapse ratio.
#' @return `grants` with four columns added: `recipient_id` (the identity's
#'   stable, content-derived id — the key the cascade and every label use; see
#'   [pf_identity_id()]), `recipient_key` (the canonical dedup key it hashes),
#'   `recipient_uid` (an integer position, kept for cheap within-run grouping
#'   and **not** safe to key a label on) and `recipient_n` (how many grant rows
#'   share the identity).
#' @export
pf_dedup <- function(grants, method = c("exact", "fuzzy"), threshold = 0.92,
                     max_block = 2000L, verbose = TRUE) {
  method <- match.arg(method)
  stopifnot(!is.null(grants$recip_name))
  say <- function(...) if (verbose) cat(sprintf(...), "\n")
  q <- npmatch::np_normalize(npmatch::np_query(grants, pf_map_grants()))
  q$ident_key <- .pf_identity_key(q$name_full)
  q$aff_tok   <- .pf_affiliate_tokens(q$name_full)
  # One definition of the exact key, shared with the rekey path. See
  # .pf_exact_keys().
  ek    <- .pf_exact_keys(grants)
  key   <- ek$key
  # rows with no name AND no address are not an identity -- keep them separate
  empty <- ek$empty
  key[empty] <- paste0("singleton", seq_len(sum(empty)))[seq_len(sum(empty))]
  uid <- match(key, unique(key))
  say("exact dedup: %s grant rows -> %s distinct keys (%.2fx collapse)",
      format(nrow(grants), big.mark = ","), format(max(uid), big.mark = ","),
      nrow(grants) / max(uid))
  if (method == "fuzzy") {
    first <- !duplicated(uid)
    d <- data.frame(uid = uid[first], name_key = q$ident_key[first],
                    aff_tok = q$aff_tok[first],
                    zip5 = q$zip5[first], state = q$state[first],
                    name_nums = q$name_nums[first], name_ord = q$name_ord[first],
                    name_dir = q$name_dir[first], stringsAsFactors = FALSE)
    d$blk <- .pf_geo_block(d)
    ok <- nzchar(d$blk) & !is.na(d$name_key) & nzchar(d$name_key)
    cand <- d[ok, , drop = FALSE]
    grp <- split(seq_len(nrow(cand)), cand$blk)
    # Blocks larger than max_block used to be dropped outright. At 100k rows
    # that never binds; on the full 12.5M-grant file roughly 500k of 3.38M keys
    # sit in state-level blocks over the cap, and they are the densest
    # neighbourhoods -- exactly where fuzzy matching earns its keep. Sub-block
    # them on the leading characters of the name key instead. Jaro-Winkler
    # weights the common prefix heavily, so two names agreeing to within 0.08
    # distance almost always share a first letter; splitting on it is close to
    # lossless and bounds the O(k^2) comparison inside each block.
    grp <- grp[lengths(grp) > 1L]
    n_capped <- 0L
    split_big <- function(ix, depth) {
      if (length(ix) <= max_block) return(list(ix))
      if (depth > 3L) { n_capped <<- n_capped + length(ix); return(list()) }
      sub <- split(ix, substr(cand$name_key[ix], 1L, depth))
      sub <- sub[lengths(sub) > 1L]
      unlist(lapply(sub, split_big, depth = depth + 1L), recursive = FALSE)
    }
    big <- lengths(grp) > max_block
    if (any(big)) {
      grp <- c(grp[!big], unlist(lapply(grp[big], split_big, depth = 1L),
                                 recursive = FALSE))
      grp <- grp[lengths(grp) > 1L]
    }
    if (n_capped)
      say("  %s keys left uncompared after 3 levels of sub-blocking",
          format(n_capped, big.mark = ","))
    say("fuzzy pass: %s blocks with 2-%d members (%s keys eligible)",
        format(length(grp), big.mark = ","), max_block,
        format(sum(lengths(grp)), big.mark = ","))
    # Accumulate into a list and flatten once. Appending with c() inside the
    # per-pair loop costs O(L^2) element copies in the number of accepted
    # joins, which is invisible at 100k and a real term at full scale.
    acc <- vector("list", length(grp)); n_veto <- 0L; bi <- 0L
    conflict <- function(a, b) {
      # npmatch's hard veto predicates: disjoint embedded numbers ("Local 32" vs
      # "Local 45"), ordinals ("First" vs "Second"), or directions ("SW" vs "SE").
      f <- function(x, y) {
        x <- x[!is.na(x)]; y <- y[!is.na(y)]
        length(x) && length(y) && !any(x %in% y)
      }
      if (f(strsplit(cand$name_nums[a], " ")[[1]], strsplit(cand$name_nums[b], " ")[[1]]) ||
          f(strsplit(cand$name_ord[a],  " ")[[1]], strsplit(cand$name_ord[b],  " ")[[1]]) ||
          f(strsplit(cand$name_dir[a],  " ")[[1]], strsplit(cand$name_dir[b],  " ")[[1]]))
        return(TRUE)
      # different affiliate suffix = probably a different EIN. "Denver Art Museum"
      # and "Denver Art Museum Foundation" score ~0.95 on Jaro-Winkler and are two
      # organizations; merging them would lock one EIN across both.
      !identical(cand$aff_tok[a], cand$aff_tok[b])
    }
    # Progress. The fuzzy pass is the longest single step in the pipeline and
    # used to print nothing between "N blocks" and "done", which makes a
    # full-file run unmanageable: there is no way to tell a slow pass from a
    # hung one. Report every 5% of blocks with a running rate and an estimate.
    n_blk <- length(grp)
    step  <- max(1L, n_blk %/% 20L)
    t_fz  <- proc.time()[["elapsed"]]
    for (ix in grp) {
      if (verbose && bi %% step == 0L && bi > 0L) {
        el <- proc.time()[["elapsed"]] - t_fz
        say("  fuzzy %3.0f%%  %s/%s blocks  %.0f s elapsed, ~%.0f s left",
            100 * bi / n_blk, format(bi, big.mark = ","),
            format(n_blk, big.mark = ","), el, el * (n_blk - bi) / max(bi, 1L))
        utils::flush.console()
      }
      bi <- bi + 1L
      nm <- cand$name_key[ix]
      dm <- stringdist::stringdistmatrix(nm, nm, method = "jw", p = 0.1)
      hit <- which(dm <= (1 - threshold) & upper.tri(dm), arr.ind = TRUE)
      if (!nrow(hit)) next
      ea <- integer(nrow(hit)); eb <- integer(nrow(hit)); nn <- 0L
      for (r in seq_len(nrow(hit))) {
        a <- ix[hit[r, 1]]; b <- ix[hit[r, 2]]
        if (conflict(a, b)) { n_veto <- n_veto + 1L; next }
        nn <- nn + 1L; ea[nn] <- a; eb[nn] <- b
      }
      if (nn) acc[[bi]] <- list(a = ea[seq_len(nn)], b = eb[seq_len(nn)])
    }
    acc <- acc[!vapply(acc, is.null, logical(1))]
    ei <- unlist(lapply(acc, `[[`, "a"), use.names = FALSE)
    ej <- unlist(lapply(acc, `[[`, "b"), use.names = FALSE)
    if (is.null(ei)) { ei <- integer(0); ej <- integer(0) }
    say("  %s fuzzy joins accepted, %s rejected by the number/ordinal/direction veto",
        format(length(ei), big.mark = ","), format(n_veto, big.mark = ","))
    comp <- .pf_components(nrow(cand), ei, ej)
    # remap: every uid in a component takes the component's smallest uid
    newuid <- cand$uid
    for (c0 in unique(comp)) {
      m <- comp == c0
      if (sum(m) > 1L) newuid[m] <- min(cand$uid[m])
    }
    remap <- stats::setNames(newuid, cand$uid)
    u <- as.character(uid)
    uid <- ifelse(u %in% names(remap), unname(remap[u]), uid)
    uid <- match(uid, unique(uid))
    say("fuzzy dedup: -> %s distinct identities (%.2fx total collapse)",
        format(max(uid), big.mark = ","), nrow(grants) / max(uid))
  }
  # --- the identity's stable id ----------------------------------------------
  #
  # `uid` is a POSITION. `match(key, unique(key))` numbers identities in order
  # of first appearance, and the fuzzy pass renumbers again by taking each
  # component's smallest uid, so both depend on which rows happen to be
  # present. Merging one pair of duplicates renumbers every identity after it.
  #
  # That is not theoretical. Two builds of the same grant population, the
  # second after a normalizer change merged 682 duplicates: joined on R<uid>
  # the recipient names did not agree at all -- R10000 was "Childrens
  # Guardian" in one and "CONGREGATION ATERES YESHAYA" in the other -- while
  # pf_population_id() was identical both times, because the grant file really
  # was the same one. A label keyed on a position therefore passed every check
  # available and landed on a different organisation
  # (dev/ADJ-ROUND-STAGE1-20261103.log).
  #
  # So the id is derived from the identity's own content: the lexicographically
  # smallest EXACT key in its cluster. Exact keys partition the rows, so each
  # belongs to exactly one identity and the minimum is canonical -- independent
  # of row order, of which uid the fuzzy component happened to take, and of how
  # many other identities exist. An identity whose key set changes gets a
  # different id, and that is the honest answer rather than a defect: a label
  # carrying the old id is then visibly absent instead of silently re-attached.
  #
  # Rows with neither a name nor an address are not an identity and have no
  # content to hash. They are keyed on OBJECTID, which is stable within a grant
  # file, and marked PFX- so a reader can see they are not content-identified.
  # They are always out of scope, so they never reach a round.
  ki <- .pf_identity_keys(key, uid, empty, grants$OBJECTID)
  grants$recipient_uid <- uid
  grants$recipient_key <- ki$key
  grants$recipient_id  <- ki$id
  grants$recipient_n   <- as.integer(table(uid)[as.character(uid)])
  say("identity ids: %s distinct, content-derived (%s not content-identified)",
      format(length(unique(ki$id)), big.mark = ","),
      format(sum(startsWith(ki$id, "PFX-")), big.mark = ","))
  grants
}

# The canonical key and stable id of every row's identity. Factored out of
# pf_dedup() so that rekeying an artifact built before these columns existed
# runs this code rather than a copy of it: a reimplementation that drifted by
# one character would hand out ids that look right and name other
# organisations, which is the failure the scheme exists to remove.
#
# `empty` marks rows with neither a name nor an address. They are not an
# identity and have nothing to hash, so they are keyed on OBJECTID -- stable
# within a grant file -- and prefixed PFX- so a reader can see they are not
# content-identified. They are always out of scope and never reach a round.
.pf_identity_keys <- function(key, uid, empty, objectid = NULL) {
  if (any(empty)) {
    oid <- if (is.null(objectid)) NULL else as.character(objectid)
    key[empty] <- if (!is.null(oid) && !anyDuplicated(oid[empty]))
                    paste0("\r\rPFX", oid[empty])
                  else paste0("\r\rPFXrow", which(empty))
  }
  ord <- order(uid, key)
  f1  <- !duplicated(uid[ord])
  canon <- character(max(uid))
  canon[uid[ord][f1]] <- key[ord][f1]
  ids <- ifelse(startsWith(canon, "\r\rPFX"),
                pf_identity_id(canon, prefix = "PFX-"),
                pf_identity_id(canon))
  # A collision would put two identities under one id -- the very failure this
  # removes -- so it is checked rather than assumed.
  seen <- nzchar(canon)
  if (anyDuplicated(ids[seen]))
    stop(sprintf(paste0(
      "%d of %d identity ids collide, so two identities would share one id.\n",
      "  The exact keys are meant to partition the rows; this means they did",
      " not.\n  Report it with the colliding keys: %s"),
      sum(duplicated(ids[seen])), sum(seen),
      paste(utils::head(canon[seen][duplicated(ids[seen]) |
                                    duplicated(ids[seen], fromLast = TRUE)], 2),
            collapse = " / ")), call. = FALSE)
  list(key = canon[uid], id = ids[uid])
}

# The exact dedup key of every row, as pf_dedup() computes it. Shared for the
# same reason as .pf_identity_keys(): one definition, so a rekey cannot drift.
.pf_exact_keys <- function(grants) {
  q <- npmatch::np_normalize(npmatch::np_query(grants, pf_map_grants()))
  ident <- .pf_identity_key(q$name_full)
  key <- paste(ident,
               ifelse(is.na(q$street_key), "", q$street_key),
               ifelse(is.na(q$zip5), "", q$zip5), sep = "\r")
  empty <- !nzchar(ident) & (is.na(q$street_key) | !nzchar(q$street_key))
  list(key = key, empty = empty)
}
#' The distinct recipient frame to actually match
#'
#' One row per `recipient_uid`, choosing the **most complete** representative of
#' each cluster (longest name, then most address fields populated) so the match
#' runs against the best available spelling rather than an arbitrary one.
#'
#' @param grants Output of [pf_dedup()].
#' @return A data frame with one row per identity, carrying `recipient_uid` as
#'   the match key.
#' @export
pf_recipients <- function(grants) {
  stopifnot(!is.null(grants$recipient_uid))
  n_addr <- rowSums(!is.na(grants[, c("recip_street", "recip_city",
                                      "recip_state", "recip_zip5")]))
  score <- nchar(ifelse(is.na(grants$recip_name), "", grants$recip_name)) + 10 * n_addr
  ord <- order(grants$recipient_uid, -score)
  out <- grants[ord, , drop = FALSE]
  out <- out[!duplicated(out$recipient_uid), , drop = FALSE]
  # The match key for the cascade, and the key every label is written against.
  # Content-derived, not `paste0("R", recipient_uid)`: see pf_identity_id().
  out$grant_id <- if (!is.null(out$recipient_id)) as.character(out$recipient_id)
                  else paste0("R", out$recipient_uid)
  if (is.null(out$recipient_id))
    warning(paste0(
      "this frame has no recipient_id, so the cascade is keyed on R<position> ",
      "again.\n  Those ids are not stable across rebuilds and must not be ",
      "labelled against; re-run pf_dedup()."), call. = FALSE)
  rownames(out) <- NULL
  out
}
#' Propagate a match back from identities to grant rows
#'
#' @param grants Output of [pf_dedup()].
#' @param status A [pf_status()] frame computed over [pf_recipients()].
#' @return `grants` with the identity-level outcome joined onto every row.
#' @export
pf_propagate_matches <- function(grants, status) {
  # Join on whichever key the status frame was computed over. A frame keyed on
  # recipient_id joined by R<position> would match nothing, or -- worse, after a
  # rebuild -- match the wrong identities, so the two are never mixed.
  k <- if (!is.null(grants$recipient_id) &&
           any(as.character(grants$recipient_id) %in% as.character(status$grant_id)))
         as.character(grants$recipient_id)
       else paste0("R", grants$recipient_uid)
  i <- match(k, status$grant_id)
  if (all(is.na(i)))
    stop(paste0(
      "no grant row's identity key is in the status frame, so nothing would\n",
      "  propagate. The two were built from different runs, or the frame is\n",
      "  keyed on R<position> and these rows on recipient_id (or the reverse).\n",
      "  Check pf_frame_id() on both."), call. = FALSE)
  for (col in c("status", "ein", "bmf_name", "score", "match_pass"))
    grants[[col]] <- status[[col]][i]
  grants
}
#' Report on a dedup run
#'
#' @param grants Output of [pf_dedup()].
#' @param n Number of largest clusters to show.
#' @return Invisibly, the cluster-size table. Prints a summary.
pf_dedup_report <- function(grants, n = 15) {
  sz <- table(grants$recipient_uid)
  cat(sprintf("grant rows ............ %s\n", format(nrow(grants), big.mark = ",")))
  cat(sprintf("distinct identities ... %s\n", format(length(sz), big.mark = ",")))
  cat(sprintf("collapse ratio ........ %.2fx\n", nrow(grants) / length(sz)))
  cat(sprintf("singletons ............ %s (%.1f%%)\n",
              format(sum(sz == 1), big.mark = ","), 100 * mean(sz == 1)))
  cat("\ncluster size distribution:\n")
  print(table(cut(as.integer(sz), c(0, 1, 2, 5, 10, 50, Inf),
                  labels = c("1", "2", "3-5", "6-10", "11-50", ">50"))))
  big <- sort(sz, decreasing = TRUE)[seq_len(min(n, length(sz)))]
  cat("\nlargest clusters (check these for over-merging):\n")
  for (u in names(big)) {
    nm <- unique(grants$recip_name[grants$recipient_uid == as.integer(u)])
    cat(sprintf("  %4d rows | %s\n", big[[u]],
                paste(utils::head(nm, 3), collapse = " | ")))
  }
  invisible(sz)
}
