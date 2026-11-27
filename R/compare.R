# Comparing two runs.
#
# The failure these two functions exist to prevent is a before/after table that
# charges to a modification whatever else moved between the two runs. It has
# three costumes, all seen on this project:
#
#   - the populations differ, so a tier rate moves without any case behaving
#     differently (three tier sets on this machine differ by 17 points for
#     exactly this reason);
#   - the two sides are read in different conventions, so NO-because-no-pair on
#     one side meets absent-from-the-result-frame on the other -- that one
#     reported 159 identities moved where 28 had;
#   - the ids are positional, so an id join returns a base rate that looks like
#     a result (joined on R<k> across two rebuilds of the SAME grant file the
#     recipient names agreed on nothing at all).
#
# So pf_compare_runs() refuses rather than returns in all three cases, and
# pf_stamp_diff() says what actually changed instead of leaving the reader to
# claim it.

#' Say what differs between two run stamps
#'
#' Every checkpoint and every result from [pf_run_batches()] carries a
#' `pf_stamp` recording what produced it. [pf_run_batches()] compares stamps to
#' refuse a stale resume; this reports the same comparison instead of throwing
#' it, which is what a before/after section needs as its heading.
#'
#' A section heading derived from the two artifacts cannot claim a change the
#' artifacts do not show. That is the whole point of reading it from here rather
#' than typing it.
#'
#' @param a,b Two stamps, or two objects carrying one: a frame or list with a
#'   `pf_stamp` attribute, or a path to an `.rds` file holding one.
#' @param labels Names for the two sides, used in printing.
#' @return A data frame of class `pf_stamp_diff`, one row per setting and one
#'   further row per decomposed difference inside a changed setting:
#'   \describe{
#'     \item{key}{The stamp setting — `config`, `passes`, `ref_cols`, ...}
#'     \item{item}{`NA` on the setting's own row; otherwise the component that
#'       moved, e.g. `distinct_name_min_idf` or `B2-token / min_pair_idf`.}
#'     \item{status}{`same`, `changed`, `added` or `removed`.}
#'     \item{before,after}{The two values, formatted for printing.}
#'   }
#' @seealso [pf_compare_runs()], which calls this when both sides are stamped.
#' @examples
#' a <- structure(data.frame(x = 1), pf_stamp = list(method = "fast", recover = TRUE))
#' b <- structure(data.frame(x = 1), pf_stamp = list(method = "full", recover = TRUE))
#' pf_stamp_diff(a, b)
#' @export
pf_stamp_diff <- function(a, b, labels = c("before", "after")) {
  sa <- .pf_stamp_of(a, labels[1])
  sb <- .pf_stamp_of(b, labels[2])
  keys <- union(names(sa), names(sb))
  rows <- list()
  add <- function(key, item, status, before, after)
    rows[[length(rows) + 1L]] <<- data.frame(
      key = key, item = item, status = status,
      before = before, after = after, stringsAsFactors = FALSE)

  for (k in keys) {
    in_a <- k %in% names(sa)
    in_b <- k %in% names(sb)
    if (!in_a || !in_b) {
      add(k, NA_character_, if (in_a) "removed" else "added",
          if (in_a) .pf_fmt_setting(sa[[k]]) else NA_character_,
          if (in_b) .pf_fmt_setting(sb[[k]]) else NA_character_)
      next
    }
    if (.pf_same_setting(sa[[k]], sb[[k]])) {
      add(k, NA_character_, "same", .pf_fmt_setting(sa[[k]]),
          .pf_fmt_setting(sb[[k]]))
      next
    }
    add(k, NA_character_, "changed", .pf_fmt_setting(sa[[k]]),
        .pf_fmt_setting(sb[[k]]))
    d <- .pf_decompose(k, sa[[k]], sb[[k]])
    for (i in seq_len(nrow(d)))
      add(k, d$item[i], d$status[i], d$before[i], d$after[i])
  }
  out <- if (length(rows))
    do.call(rbind, rows)
  else
    data.frame(key = character(0), item = character(0), status = character(0),
               before = character(0), after = character(0),
               stringsAsFactors = FALSE)
  rownames(out) <- NULL
  structure(out, class = c("pf_stamp_diff", "data.frame"), labels = labels)
}

# A stamp from whatever the caller had to hand. Erroring here with the side's
# name is worth the few lines: "argument a is not stamped" sends the reader to
# the wrong artifact half the time.
.pf_stamp_of <- function(x, label = "stamp") {
  if (is.character(x) && length(x) == 1L) {
    if (!file.exists(x)) stop(sprintf("%s: no such file: %s", label, x),
                              call. = FALSE)
    x <- readRDS(x)
  }
  s <- attr(x, "pf_stamp")
  if (!is.null(s)) return(s)
  # a bare stamp, passed straight in
  if (is.list(x) && !is.data.frame(x) &&
      any(c("normalizer", "passes", "config", "method") %in% names(x)))
    return(x)
  stop(sprintf(paste0(
    "%s carries no pf_stamp, so there is nothing to compare it by.\n",
    "  Runs from pf_run_batches() are stamped; an artifact built by an ad-hoc\n",
    "  script calling pf_match_grants() directly is not. Rebuild it through\n",
    "  pf_run_batches(), or compare the frames without a stamp diff."), label),
    call. = FALSE)
}

.pf_fmt_setting <- function(v) {
  if (is.null(v)) return("NULL")
  if (is.atomic(v) && length(v) == 1L) return(.pf_fmt_scalar(v))
  if (is.character(v)) return(sprintf("%d values", length(v)))
  if (is.data.frame(v)) return(sprintf("%d x %d", nrow(v), ncol(v)))
  if (is.table(v)) return(paste(sprintf("%s=%d", names(v), as.integer(v)),
                                collapse = ", "))
  plural <- function(n, one, many) sprintf("%d %s", n, if (n == 1L) one else many)
  if (.pf_is_pass_list(v)) return(plural(length(v), "pass", "passes"))
  if (is.list(v)) return(plural(length(v), "setting", "settings"))
  if (is.atomic(v)) return(plural(length(v), "value", "values"))
  class(v)[1]
}

.pf_fmt_scalar <- function(v) {
  if (is.null(v) || length(v) != 1L) return("(absent)")
  if (is.na(v)) return("NA")
  if (is.numeric(v)) {
    if (is.integer(v) || v == round(v)) format(v, big.mark = ",", trim = TRUE)
    else format(v, trim = TRUE)
  } else as.character(v)
}

# Name what moved inside a changed setting. Each branch here exists because
# all.equal()'s own report is unreadable for that shape: "2 string mismatches"
# does not say which column was added, and a nested pass list reports a
# component path rather than a pass name.
.pf_decompose <- function(key, a, b) {
  none <- data.frame(item = character(0), status = character(0),
                     before = character(0), after = character(0),
                     stringsAsFactors = FALSE)
  row <- function(item, status, before, after)
    data.frame(item = item, status = status, before = before, after = after,
               stringsAsFactors = FALSE)

  # A scalar needs no decomposition: the setting's own row already carries both
  # values, and a second row saying "1 string mismatch" is noise that also
  # breaks the item-is-NA test for a top-level row.
  scalar <- function(v) is.null(v) || (is.atomic(v) && length(v) == 1L)
  if (scalar(a) && scalar(b)) return(none)

  # a set of column names: the added and removed ones are the whole story
  if (is.character(a) && is.character(b) && length(a) > 1L && length(b) > 1L) {
    gone <- setdiff(a, b); new <- setdiff(b, a)
    out <- none
    if (length(gone)) out <- rbind(out, row("removed", "removed",
                                            paste(gone, collapse = ", "), NA_character_))
    if (length(new)) out <- rbind(out, row("added", "added", NA_character_,
                                           paste(new, collapse = ", ")))
    return(out)
  }
  # the pass table: keyed by pass name, then by argument
  if (identical(key, "passes") && .pf_is_pass_list(a) && .pf_is_pass_list(b))
    return(.pf_decompose_passes(a, b))
  # a flat named list of settings, which is what np_config() and dyad_config are
  if (is.list(a) && is.list(b) && !is.null(names(a)) && !is.null(names(b)))
    return(.pf_decompose_list(a, b))
  if (is.table(a) && is.table(b))
    return(.pf_decompose_list(as.list(a), as.list(b)))
  # anything else: all.equal's report, which is at least precise about numbers
  ae <- tryCatch(all.equal(a, b), error = function(e) NULL)
  if (is.character(ae) && length(ae))
    return(row("value", "changed", NA_character_,
               paste(utils::head(ae, 4L), collapse = "; ")))
  none
}

.pf_is_pass_list <- function(x)
  is.list(x) && length(x) &&
    all(vapply(x, function(p) is.list(p) && !is.null(p$name), logical(1)))

.pf_decompose_passes <- function(a, b) {
  na <- vapply(a, function(p) as.character(p$name)[1], character(1))
  nb <- vapply(b, function(p) as.character(p$name)[1], character(1))
  out <- data.frame(item = character(0), status = character(0),
                    before = character(0), after = character(0),
                    stringsAsFactors = FALSE)
  for (p in setdiff(na, nb))
    out <- rbind(out, data.frame(item = p, status = "removed",
                                 before = "present", after = NA_character_,
                                 stringsAsFactors = FALSE))
  for (p in setdiff(nb, na))
    out <- rbind(out, data.frame(item = p, status = "added",
                                 before = NA_character_, after = "present",
                                 stringsAsFactors = FALSE))
  for (p in intersect(na, nb)) {
    pa <- a[[which(na == p)[1]]]; pb <- b[[which(nb == p)[1]]]
    if (.pf_same_setting(pa, pb)) next
    d <- .pf_decompose_list(
      if (is.list(pa$args)) pa$args else list(),
      if (is.list(pb$args)) pb$args else list())
    if (!nrow(d)) {
      out <- rbind(out, data.frame(item = p, status = "changed",
                                   before = "(not in args)",
                                   after = "(not in args)",
                                   stringsAsFactors = FALSE))
      next
    }
    d$item <- paste(p, d$item, sep = " / ")
    out <- rbind(out, d)
  }
  out
}

.pf_decompose_list <- function(a, b) {
  keys <- union(names(a), names(b))
  out <- data.frame(item = character(0), status = character(0),
                    before = character(0), after = character(0),
                    stringsAsFactors = FALSE)
  for (k in keys) {
    in_a <- k %in% names(a); in_b <- k %in% names(b)
    if (in_a && in_b && .pf_same_setting(a[[k]], b[[k]])) next
    out <- rbind(out, data.frame(
      item = k,
      status = if (!in_a) "added" else if (!in_b) "removed" else "changed",
      before = if (in_a) .pf_fmt_setting(a[[k]]) else NA_character_,
      after  = if (in_b) .pf_fmt_setting(b[[k]]) else NA_character_,
      stringsAsFactors = FALSE))
  }
  out
}

#' @rdname pf_stamp_diff
#' @param x A `pf_stamp_diff`.
#' @param ... Unused.
#' @export
print.pf_stamp_diff <- function(x, ...) {
  lab <- attr(x, "labels")
  if (!nrow(x)) { cat("<pf_stamp_diff>  both stamps are empty\n"); return(invisible(x)) }
  top <- x[is.na(x$item), , drop = FALSE]
  chg <- top$key[top$status != "same"]
  cat(sprintf("<pf_stamp_diff>  %s  ->  %s\n", lab[1], lab[2]))
  w <- max(nchar(top$key), 11L)
  for (i in seq_len(nrow(top))) {
    k <- top$key[i]
    if (top$status[i] == "same") {
      cat(sprintf("  %-*s %s  ==  %s\n", w, k, top$before[i], top$after[i]))
      next
    }
    cat(sprintf("  %-*s %s  ->  %s   %s\n", w, k, top$before[i], top$after[i],
                toupper(top$status[i])))
    sub <- x[!is.na(x$item) & x$key == k, , drop = FALSE]
    for (j in seq_len(nrow(sub)))
      cat(sprintf("  %-*s   %s: %s -> %s\n", w, "", sub$item[j],
                  ifelse(is.na(sub$before[j]), "absent", sub$before[j]),
                  ifelse(is.na(sub$after[j]), "absent", sub$after[j])))
  }
  cat(sprintf("\n  %d of %d settings moved%s\n", length(chg), nrow(top),
              if (length(chg)) paste0(": ", paste(chg, collapse = ", ")) else ""))
  if (length(chg) > 1L)
    cat("  more than one setting moved, so no effect can be attributed to any\n",
        "  one of them from these two runs alone.\n", sep = "")
  invisible(x)
}

#' Compare two runs case by case
#'
#' The population accounting and tier flow between two runs, computed on the
#' cases the two runs share and refusing rather than returning when the two
#' frames cannot be joined.
#'
#' @section What it refuses, and why:
#' Three refusals, each closing a measured failure.
#'
#' **Positional ids.** Identity ids have been content-derived (`PFI-`/`PFX-`)
#' since 2026-11-03. Before that they were a position among the deduplicated
#' recipients, so rebuilding the same grant file renumbered everything after the
#' first merge: joined on `R<k>` across two such runs the recipient names
#' agreed on nothing, while the population fingerprint was identical both times
#' because the grants really were the same file. An id join across that boundary
#' returns a base rate shaped like a result, so this stops unless both sides are
#' content-keyed. `by = "name"` is the deliberate way through, and marks the
#' comparison approximate.
#'
#' **An empty intersection.** Two frames with no id in common produce a flow
#' matrix of zeroes and a tidy table of nothing, which reads as "no case moved".
#'
#' **Mixed conventions.** [pf_status()] labels an identity with no candidate
#' anywhere `NO` and an out-of-scope one `OOS`; the result frame underneath omits
#' both. Reading one side in each convention once reported 159 identities moved
#' where 28 had. Both sides must arrive here in the [pf_status()] convention,
#' which is checked by requiring the levels of [pf_status_levels()] and nothing
#' else.
#'
#' @section What it reports that a tier table cannot:
#' A case that stays `YES` and changes its EIN has not moved in the flow matrix
#' and has changed its answer completely. Those are counted separately as
#' `same_tier_new_ein`, and they belong in any section claiming a modification
#' was inert.
#'
#' @param before,after Two [pf_status()]-shaped frames, or paths to `.rds` files
#'   holding one, or any list with a `status` component holding one.
#' @param by `"id"` joins on `grant_id` and requires content-derived ids on both
#'   sides. `"name"` joins on normalized recipient name, city and state, drops
#'   keys that are not unique on both sides, and marks the result approximate.
#' @param labels Names for the two sides.
#' @return An object of class `pf_compare`: a list of `ids` (the population
#'   accounting), `flow` (the tier matrix on the intersection), `transitions`,
#'   `net`, `moved` (one row per case whose tier or EIN changed),
#'   `same_tier_new_ein`, `stamp` (a [pf_stamp_diff()] when both sides carry
#'   one, else `NULL`) and `approximate`.
#' @seealso [pf_stamp_diff()] for what changed between the two runs,
#'   [pf_check_schema()] for whether a reference can run a pass table at all.
#' @export
pf_compare_runs <- function(before, after, by = c("id", "name"),
                            labels = c("before", "after")) {
  by <- match.arg(by)
  a <- .pf_status_frame(before, labels[1])
  b <- .pf_status_frame(after, labels[2])

  sh_a <- .pf_id_shape(a$grant_id)
  sh_b <- .pf_id_shape(b$grant_id)
  key_a <- if (by == "id") as.character(a$grant_id) else .pf_name_key(a)
  key_b <- if (by == "id") as.character(b$grant_id) else .pf_name_key(b)
  n_ambiguous <- 0L

  if (by == "id") {
    if (sh_a$kind != "content" || sh_b$kind != "content")
      stop(sprintf(paste0(
        "these frames cannot be joined on id.\n",
        "  id shape    %-24s vs  %s\n",
        "  identities  %-24s vs  %s\n",
        "  in common   %d\n\n",
        "  A positional id is a position among the deduplicated recipients, so\n",
        "  it names a different organisation in a run that merged a duplicate.\n",
        "  Joining on it returns a base rate. Re-run the older side through\n",
        "  pf_dedup() so its ids are content-derived, or pass by = \"name\" to\n",
        "  compare approximately and have the result say so."),
        sh_a$pattern, sh_b$pattern,
        format(nrow(a), big.mark = ","), format(nrow(b), big.mark = ","),
        length(intersect(key_a, key_b))), call. = FALSE)
  } else {
    # a name key that is not unique cannot be joined one-to-one, and a
    # many-to-many join would invent cases. Drop them and say how many.
    dup <- union(key_a[duplicated(key_a)], key_b[duplicated(key_b)])
    n_ambiguous <- length(dup)
    keep_a <- !key_a %in% dup; keep_b <- !key_b %in% dup
    a <- a[keep_a, , drop = FALSE]; key_a <- key_a[keep_a]
    b <- b[keep_b, , drop = FALSE]; key_b <- key_b[keep_b]
  }

  both <- intersect(key_a, key_b)
  if (!length(both))
    stop(sprintf(paste0(
      "these two frames share no cases, so there is nothing to compare.\n",
      "  %s  %s identities\n  %s  %s identities\n  in common    0\n\n",
      "  A flow matrix over an empty intersection is all zeroes, which reads\n",
      "  as \"nothing moved\". Check that both sides are the same population."),
      labels[1], format(nrow(a), big.mark = ","),
      labels[2], format(nrow(b), big.mark = ",")), call. = FALSE)

  ia <- match(both, key_a); ib <- match(both, key_b)
  sa <- .pf_tier(a$status[ia], labels[1])
  sb <- .pf_tier(b$status[ib], labels[2])
  flow <- table(before = sa, after = sb)

  ein_a <- .pf_e9(a$ein[ia]); ein_b <- .pf_e9(b$ein[ib])
  tier_moved <- as.character(sa) != as.character(sb)
  ein_moved <- !is.na(ein_a) & !is.na(ein_b) & ein_a != ein_b
  num <- function(v) if (is.null(v)) rep(NA_real_, length(both)) else as.numeric(v)
  chr <- function(v) if (is.null(v)) rep(NA_character_, length(both)) else as.character(v)

  moved <- data.frame(
    id             = both,
    recip_name     = chr(a$recip_name[ia]),
    recip_city     = chr(a$recip_city[ia]),
    recip_state    = chr(a$recip_state[ia]),
    before_status  = as.character(sa),
    after_status   = as.character(sb),
    before_ein     = ein_a,
    after_ein      = ein_b,
    ein_changed    = ein_moved,
    before_score   = num(a$score[ia]),
    after_score    = num(b$score[ib]),
    before_margin  = num(a$margin[ia]),
    after_margin   = num(b$margin[ib]),
    before_n_close = num(a$n_close[ia]),
    after_n_close  = num(b$n_close[ib]),
    before_pass    = chr(a$match_pass[ia]),
    after_pass     = chr(b$match_pass[ib]),
    stringsAsFactors = FALSE)
  moved$score_delta <- moved$after_score - moved$before_score
  moved$pass_changed <- !is.na(moved$before_pass) & !is.na(moved$after_pass) &
    moved$before_pass != moved$after_pass
  moved <- moved[tier_moved | ein_moved | moved$pass_changed, , drop = FALSE]
  rownames(moved) <- NULL

  tr <- as.data.frame(flow, stringsAsFactors = FALSE)
  names(tr) <- c("from", "to", "n")
  tr <- tr[tr$n > 0 & tr$from != tr$to, , drop = FALSE]
  tr <- tr[order(-tr$n), , drop = FALSE]
  rownames(tr) <- NULL

  lv <- pf_status_levels()
  net <- data.frame(
    tier   = lv,
    before = as.integer(table(sa)[lv]),
    after  = as.integer(table(sb)[lv]),
    stringsAsFactors = FALSE)
  net$delta <- net$after - net$before
  net$churn_in  <- as.integer(colSums(flow) - diag(flow))
  net$churn_out <- as.integer(rowSums(flow) - diag(flow))

  stamp <- tryCatch(pf_stamp_diff(before, after, labels), error = function(e) NULL)

  structure(list(
    labels = labels, by = by, approximate = by == "name",
    ids = list(shape_before = sh_a, shape_after = sh_b,
               n_before = nrow(a), n_after = nrow(b), n_both = length(both),
               n_before_only = sum(!key_a %in% both),
               n_after_only = sum(!key_b %in% both),
               n_ambiguous = n_ambiguous),
    flow = flow, transitions = tr, net = net, moved = moved,
    same_tier_new_ein = sum(!tier_moved & ein_moved),
    stamp = stamp), class = "pf_compare")
}

# One convention on both sides, checked by insisting on the pf_status levels.
.pf_status_frame <- function(x, label) {
  if (is.character(x) && length(x) == 1L) {
    if (!file.exists(x)) stop(sprintf("%s: no such file: %s", label, x),
                              call. = FALSE)
    x <- readRDS(x)
  }
  if (is.list(x) && !is.data.frame(x) && !is.null(x$status) &&
      is.data.frame(x$status)) x <- x$status
  if (!is.data.frame(x))
    stop(sprintf("%s is a %s, not a pf_status() frame.", label, class(x)[1]),
         call. = FALSE)
  miss <- setdiff(c("grant_id", "status"), names(x))
  if (length(miss))
    stop(sprintf(paste0(
      "%s is missing %s, so it is not a pf_status() frame.\n",
      "  Both sides of a comparison have to arrive in one convention. Build\n",
      "  each with pf_status(), or read a pf_run_batches() checkpoint."),
      label, paste(miss, collapse = " and ")), call. = FALSE)
  if (anyDuplicated(as.character(x$grant_id)))
    stop(sprintf(paste0(
      "%s has %d duplicated grant_id values, so it is not one row per\n",
      "  identity. A checkpoint concatenated twice does this."),
      label, sum(duplicated(as.character(x$grant_id)))), call. = FALSE)
  x
}

.pf_tier <- function(v, label) {
  lv <- pf_status_levels()
  s <- as.character(v)
  # A case with no status is not comparable, and dropping it quietly would move
  # the denominator -- the failure this whole function exists to prevent.
  if (anyNA(s))
    stop(sprintf(paste0(
      "%s has %d rows with no status. Those cases cannot be compared, and\n",
      "  dropping them would change the denominator silently."),
      label, sum(is.na(s))), call. = FALSE)
  bad <- unique(s[!s %in% lv])
  if (length(bad))
    stop(sprintf(paste0(
      "%s carries status values that are not pf_status_levels(): %s.\n",
      "  The result-frame convention omits NO-because-no-pair and OOS rather\n",
      "  than labelling them, so a frame in that convention cannot be compared\n",
      "  against one in this convention -- the difference between the two gets\n",
      "  charged to whatever is being measured. Use pf_result_tiers() on BOTH\n",
      "  sides, or pf_status() on both."),
      label, paste(utils::head(bad, 5L), collapse = ", ")), call. = FALSE)
  factor(s, lv)
}

.pf_id_shape <- function(ids) {
  v <- as.character(ids)
  v <- v[!is.na(v) & nzchar(v)]
  if (!length(v)) return(list(kind = "empty", pattern = "(no ids)"))
  if (all(grepl("^PF[IX]-[0-9a-f]{16}$", v)))
    return(list(kind = "content", pattern = "^PF[IX]-[0-9a-f]{16}$"))
  if (all(grepl("^R[0-9]+$", v)))
    return(list(kind = "positional", pattern = "^R[0-9]+$"))
  if (all(grepl("^G[0-9]+$", v)))
    return(list(kind = "positional", pattern = "^G[0-9]+$"))
  if (any(grepl("^PF[IX]-[0-9a-f]{16}$", v)))
    return(list(kind = "mixed", pattern = "mixed PFI- and other"))
  list(kind = "unknown", pattern = "(unrecognized)")
}

# The same light normalization pf_frame_id() uses, so a name join here and a
# frame fingerprint there agree about what counts as the same rendering.
.pf_name_key <- function(x) {
  sq <- function(v) {
    s <- toupper(trimws(gsub(" +", " ", gsub("[^A-Za-z0-9 ]", " ", as.character(v)))))
    s[is.na(s)] <- ""
    s
  }
  paste(sq(x$recip_name), sq(x$recip_city), sq(x$recip_state), sep = "|")
}

#' @rdname pf_compare_runs
#' @param x A `pf_compare`.
#' @param ... Unused.
#' @export
print.pf_compare <- function(x, ...) {
  lab <- x$labels; i <- x$ids
  cat(sprintf("<pf_compare>  %s  ->  %s   joined on %s\n", lab[1], lab[2], x$by))
  if (x$approximate)
    cat("  APPROXIMATE: joined on normalized name, city and state, not on id.\n")
  cat(sprintf("  id shape      %s  |  %s\n", i$shape_before$pattern,
              i$shape_after$pattern))
  cat("\n  POPULATION\n")
  cat(sprintf("    in both           %9s   <- everything below is computed on these\n",
              format(i$n_both, big.mark = ",")))
  cat(sprintf("    only in %-9s %9s   <- left the population, not an outcome change\n",
              lab[1], format(i$n_before_only, big.mark = ",")))
  cat(sprintf("    only in %-9s %9s   <- entered the population\n",
              lab[2], format(i$n_after_only, big.mark = ",")))
  if (i$n_ambiguous)
    cat(sprintf("    ambiguous keys    %9s   <- dropped: not unique on both sides\n",
                format(i$n_ambiguous, big.mark = ",")))
  cat("\n  TIER FLOW\n")
  print(x$flow)
  cat("\n  NET AND CHURN\n")
  n <- x$net
  cat("    tier    before     after     delta    moved in   moved out\n")
  for (j in seq_len(nrow(n)))
    cat(sprintf("    %-6s %7s   %7s   %+7d   %9s   %9s\n", n$tier[j],
                format(n$before[j], big.mark = ","),
                format(n$after[j], big.mark = ","), n$delta[j],
                format(n$churn_in[j], big.mark = ","),
                format(n$churn_out[j], big.mark = ",")))
  cat(sprintf("\n    %s cases changed tier; churn is the number to read, not the net.\n",
              format(sum(n$churn_out), big.mark = ",")))
  cat(sprintf("    %s kept their tier and changed EIN -- invisible in the matrix above.\n",
              format(x$same_tier_new_ein, big.mark = ",")))
  if (!is.null(x$stamp)) {
    cat("\n  WHAT CHANGED BETWEEN THE RUNS\n")
    print(x$stamp)
  } else {
    cat("\n  No stamp on one or both sides, so what changed between these runs\n")
    cat("  is not recorded in the artifacts and must not be claimed from them.\n")
  }
  invisible(x)
}
