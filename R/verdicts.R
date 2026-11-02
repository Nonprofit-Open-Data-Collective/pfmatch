# The seam between a reviewed sheet and the match it came from.
#
# pf_adjudicate() builds the sheet a human or a model reviews. Nothing in the
# package read the answers back, so every experiment in dev/ reimplemented the
# verdict contract and its own grading, which is how two of them ended up
# disagreeing about what "net zero" meant. These three functions put the
# contract in the package: the columns and levels, a reader that validates
# rather than trusts, and a join that records what the review concluded.
#
# WHAT THIS DELIBERATELY DOES NOT DO. It does not accept. No verdict changes a
# tier here, and pf_apply_verdicts() returns the reconciliation rather than a
# revised result frame. Auto-acceptance of the MAYBE tier was measured twice and
# failed -- 72% precision on 200 fresh cases against a first estimate of 18/18
# (dev/ADJUDICATION-PLAN.md section 1) -- and the thresholds that would make
# selective acceptance safe are the subject of tests that have not been run
# (dev/ADJUDICATION-PREREQS.md T3 and T4). A function that promoted a tier on a
# model's say-so would be shipping the decision those tests exist to inform.

#' The verdict contract
#'
#' The columns and levels a reviewed adjudication sheet comes back with, whether
#' the reviewer was a person or a model. `dev/adjudicate-lib.R` builds the same
#' set for the API request schema; this is the package's copy, and the one
#' [pf_read_verdicts()] validates against.
#'
#' @section The levels, and why each exists:
#' * `verdict` — `MATCH` names an EIN, `NONE` declines, `AMBIGUOUS` says the
#'   candidates cannot be separated. `NONE` is first-class on purpose: a
#'   reviewer with no good answer must be able to say so, and a schema without
#'   it collects a guess instead.
#' * `confidence` — the reviewer's own `high` / `medium` / `low`. Usable for
#'   *ordering* a queue and not for accepting: on the MAYBE search arm,
#'   confidence rose as accuracy fell (`dev/adjudicate-15-no-arms.R`).
#' * `evidence_class` — `QUOTE` (a sentence in the packet says so), `NTEE`
#'   (the classification implies it), `INFER` (neither, but the reviewer
#'   concluded it), `NONE`. Whether these rank by accuracy is unmeasured; the
#'   class is collected so that it can be tested.
#'
#' @return `pf_verdict_cols()`: the column names in order.
#'   `pf_verdict_levels()`: a named list of the permitted values per column.
#' @name pf_verdicts
#' @examples
#' pf_verdict_cols()
#' pf_verdict_levels()$verdict
#' @export
pf_verdict_cols <- function()
  c("grant_id", "verdict", "ein", "confidence", "evidence_class", "evidence",
    "runner_up_ein")

#' @rdname pf_verdicts
#' @export
pf_verdict_levels <- function()
  list(verdict        = c("MATCH", "NONE", "AMBIGUOUS"),
       confidence     = c("high", "medium", "low"),
       evidence_class = c("QUOTE", "NTEE", "INFER", "NONE"))

#' Read a reviewed adjudication sheet
#'
#' Validates a verdict frame against [pf_verdict_cols()] and
#' [pf_verdict_levels()] and returns it with stable columns and a normalized
#' EIN. Everything it refuses, it refuses loudly: the failure mode this guards
#' against is a review that looks complete and is quietly over a different set
#' of cases than the one it was asked about.
#'
#' @section What it rejects, and why each one is a stop:
#' * **A missing required column.** Reading an absent column returns `NULL`, and
#'   a count over `NULL` is `0` rather than an error, so a renamed `verdict`
#'   column would report every case as undecided.
#' * **An unknown level.** A value outside [pf_verdict_levels()] is a schema
#'   that moved, and every count below it is then over a smaller frame than the
#'   one reported.
#' * **A duplicated `grant_id`.** Two verdicts for one identity double-count it
#'   in one direction and leave the disagreement invisible.
#' * **A `MATCH` with no EIN.** The verdict claims an answer it does not carry.
#'
#' Optional columns (`search_confirmed`, anything a particular run added) are
#' carried through untouched.
#'
#' @param v A data frame of verdicts, or a path to a CSV of them.
#' @param ids Optional character vector of the identities that were sent for
#'   review. When given, a verdict for an identity that was not sent is an
#'   error, and identities sent but not returned are reported in the
#'   `missing` attribute rather than passing unnoticed.
#' @return A data frame with [pf_verdict_cols()] first and any extra columns
#'   after, one row per `grant_id`, with `attr(, "missing")` listing requested
#'   identities that came back without a verdict.
#' @seealso [pf_apply_verdicts()] to reconcile these against the match.
#' @export
pf_read_verdicts <- function(v, ids = NULL) {
  if (is.character(v) && length(v) == 1L)
    v <- utils::read.csv(v, colClasses = "character", stringsAsFactors = FALSE)
  v <- as.data.frame(v, stringsAsFactors = FALSE)
  need <- pf_verdict_cols()
  miss <- need[!need %in% names(v)]
  if (length(miss))
    stop(sprintf(paste0(
      "these verdict columns are absent: %s\n",
      "  present: %s\n",
      "  A count over an absent column is 0 rather than an error, so this",
      " would have read as every case undecided."),
      paste(miss, collapse = ", "), paste(names(v), collapse = ", ")),
      call. = FALSE)
  for (nm in need) v[[nm]] <- as.character(v[[nm]])
  v$ein <- .pf_ein(v$ein)
  v$runner_up_ein <- .pf_ein(v$runner_up_ein)

  lv <- pf_verdict_levels()
  for (nm in names(lv)) {
    bad <- setdiff(stats::na.omit(unique(v[[nm]])), lv[[nm]])
    if (length(bad))
      stop(sprintf(paste0(
        "`%s` carries %s, outside the permitted set.\n  permitted: %s\n",
        "  A level the code below does not mention is excluded from every",
        " count at once."),
        nm, paste(sprintf("`%s`", bad), collapse = ", "),
        paste(lv[[nm]], collapse = ", ")), call. = FALSE)
  }
  if (anyDuplicated(v$grant_id)) {
    d <- unique(v$grant_id[duplicated(v$grant_id)])
    stop(sprintf("%d identities carry more than one verdict: %s", length(d),
                 paste(utils::head(d, 5), collapse = ", ")), call. = FALSE)
  }
  noein <- which(v$verdict == "MATCH" & is.na(v$ein))
  if (length(noein))
    stop(sprintf("%d MATCH verdicts name no EIN: %s", length(noein),
                 paste(utils::head(v$grant_id[noein], 5), collapse = ", ")),
         call. = FALSE)

  if (!is.null(ids)) {
    extra <- setdiff(v$grant_id, as.character(ids))
    if (length(extra))
      stop(sprintf(paste0(
        "%d verdicts are for identities that were not sent for review: %s\n",
        "  A review over a different set than the one requested is not a",
        " review of it."),
        length(extra), paste(utils::head(extra, 5), collapse = ", ")),
        call. = FALSE)
  }
  out <- v[, c(need, setdiff(names(v), need)), drop = FALSE]
  attr(out, "missing") <- if (is.null(ids)) character(0)
                          else setdiff(as.character(ids), out$grant_id)
  # Mark it validated. pf_apply_verdicts() dispatches on this class and not on
  # "does it look like a verdict frame": a raw frame carrying the right column
  # names and a character EIN is indistinguishable from a checked one by
  # inspection, so a shape test would wave unvalidated input straight through.
  class(out) <- c("pf_verdicts", "data.frame")
  out
}

#' Reconcile verdicts against the match they were drawn from
#'
#' Joins a verdict frame onto a `pf_match` and reports what the review concluded
#' relative to what the cascade concluded. **It accepts nothing**: no tier
#' changes, and the result frame is returned untouched. What it produces is the
#' frame an acceptance policy would be written against, once the tests that
#' would justify one have been run.
#'
#' @section Which tier convention this uses:
#' `tier_before` is [pf_status()]'s, not the result frame's. A verdict can exist
#' for an identity no blocking pass produced a pair for — that is most of the NO
#' tier — and the result frame has no row for those, so reading the prior tier
#' from it would silently drop them. The two conventions and the hazard of
#' mixing them are documented under [pf_report]; this function names the one it
#' uses because a comparison that does not is how 159 identities were once
#' reported as moved where 28 had.
#'
#' @param x A `pf_match` from [pf_match_grants()].
#' @param verdicts A frame from [pf_read_verdicts()], or anything it accepts.
#' @param verbose Print the reconciliation counts.
#' @return `x` with an `adjudication` element: one row per verdict, carrying
#'   `grant_id`, `tier_before`, `verdict`, `ein`, `pick_ein` (what the cascade
#'   chose, `NA` where it chose nothing), `agrees_with_pick`, `names_new_ein`,
#'   `confidence`, `evidence_class`, `evidence` and `runner_up_ein`; plus an
#'   `adjudication_counts` element. Nothing else in `x` is modified.
#' @examples
#' \dontrun{
#' m <- pf_match_grants(grants, ref)
#' sheet <- pf_adjudicate(m, bmf)
#' v <- pf_read_verdicts("verdicts.csv", ids = unique(sheet$grant_id))
#' m <- pf_apply_verdicts(m, v)
#' table(m$adjudication$agrees_with_pick, m$adjudication$verdict)
#' }
#' @seealso [pf_read_verdicts()], [pf_report] for the two tier conventions.
#' @export
pf_apply_verdicts <- function(x, verdicts, verbose = TRUE) {
  stopifnot(inherits(x, "pf_match"))
  # Validated input is identified by class, never by shape -- see pf_read_verdicts().
  v <- if (inherits(verdicts, "pf_verdicts")) verdicts else pf_read_verdicts(verdicts)

  st <- pf_status(x)
  unknown <- setdiff(v$grant_id, as.character(st$grant_id))
  if (length(unknown))
    stop(sprintf(paste0(
      "%d verdicts name identities absent from this match: %s\n",
      "  Either the verdicts belong to a different run or the keys have",
      " shifted; grant_id is positional and not stable across runs."),
      length(unknown), paste(utils::head(unknown, 5), collapse = ", ")),
      call. = FALSE)

  i <- match(v$grant_id, as.character(st$grant_id))
  pick <- .pf_ein(st$ein[i])
  out <- data.frame(
    grant_id     = v$grant_id,
    tier_before  = as.character(st$status[i]),
    verdict      = v$verdict,
    ein          = v$ein,
    pick_ein     = pick,
    agrees_with_pick = ifelse(is.na(v$ein) | is.na(pick), NA, v$ein == pick),
    names_new_ein    = !is.na(v$ein) & (is.na(pick) | v$ein != pick),
    confidence     = v$confidence,
    evidence_class = v$evidence_class,
    evidence       = v$evidence,
    runner_up_ein  = v$runner_up_ein,
    stringsAsFactors = FALSE)

  cnt <- list(
    verdicts    = nrow(out),
    by_verdict  = table(factor(out$verdict, pf_verdict_levels()$verdict)),
    by_tier     = table(factor(out$tier_before, pf_status_levels())),
    agrees      = sum(out$agrees_with_pick %in% TRUE),
    contradicts = sum(out$agrees_with_pick %in% FALSE),
    new_ein     = sum(out$names_new_ein),
    no_pick     = sum(is.na(out$pick_ein)))
  if (verbose) {
    .pf_hr(verbose); .pf_say(verbose, "adjudication reconciled, nothing accepted")
    .pf_say(verbose, "  %d verdicts over tiers: %s", cnt$verdicts,
            paste(sprintf("%s %d", names(cnt$by_tier), as.integer(cnt$by_tier)),
                  collapse = " | "))
    .pf_say(verbose, "  %s", paste(sprintf("%s %d", names(cnt$by_verdict),
                                           as.integer(cnt$by_verdict)),
                                   collapse = " | "))
    .pf_say(verbose, "  agrees with the pick %d | contradicts it %d | names an EIN the cascade did not %d",
            cnt$agrees, cnt$contradicts, cnt$new_ein)
    .pf_say(verbose, "  of those, %d are identities the cascade picked nothing for", cnt$no_pick)
    .pf_say(verbose, "  no tier changed: acceptance is a policy decision, not this function's")
  }
  x$adjudication <- out
  x$adjudication_counts <- cnt
  x
}
