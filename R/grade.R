# Grading a reviewed adjudication round against ground truth.
#
# dev/ADJUDICATION-PREREQS.md §3 is the finding this file is built around: eight
# of its twelve tests are cuts of ONE labelling round, and running them as two
# phases with two packets "produce[s] another pair of incomparable denominators".
# So the harness takes one labelled round and returns the cuts, rather than
# offering a per-test function that each caller points at whatever it has.
#
# WHY IT EXISTS BEFORE THE LABELS DO. T1 is a data-collection round, and no
# amount of code produces it. What code can do beforehand is fix the arithmetic
# and the denominators, so that when the labels arrive the tests are a function
# call rather than a fresh analysis -- which is how dev/adjudicate-03-score.R,
# -06-calib-score.R and -12-no-score.R each ended up with their own wilson(),
# their own grade vocabulary and their own denominator. Three implementations of
# one statistic is the state dev/PLACES-SYNC.md exists to prevent for address
# keys, and it already happened here.
#
# WHAT IT DOES NOT DO. It does not accept, promote, or choose a policy -- see
# R/verdicts.R. It reports accuracy with an interval and refuses the
# comparisons that would be unsound.

#' A Wilson score interval
#'
#' The interval to quote on a small-n rate, and the reason this is exported
#' rather than local: `dev/ADJUDICATION-PREREQS.md` T8 records the two
#' structural flags at **60% on n=15** and **71% on n=7**, and concludes neither
#' "can carry a shipping decision". A normal approximation at n=7 gives
#' `71% ± 34` and runs off both ends of the probability scale; Wilson stays
#' inside it, which is what makes the smallness of the sample visible in the
#' figure instead of in a footnote.
#'
#' @param k Successes. @param n Trials.
#' @param conf Confidence level.
#' @return A two-column matrix of `lo` and `hi`, one row per element of `k`.
#'   `n == 0` gives `NA`, not an interval over nothing.
#' @examples
#' pf_wilson(9, 15)   # the flag at 60% on n=15
#' pf_wilson(5, 7)
#' @export
pf_wilson <- function(k, n, conf = 0.95) {
  k <- as.numeric(k); n <- as.numeric(n)
  if (length(k) != length(n)) {
    if (length(n) == 1L) n <- rep(n, length(k))
    else stop("`k` and `n` must be the same length", call. = FALSE)
  }
  if (any(k > n, na.rm = TRUE))
    stop("`k` cannot exceed `n`; got ", paste(utils::head(k[k > n], 3), collapse = ", "),
         " of ", paste(utils::head(n[k > n], 3), collapse = ", "), call. = FALSE)
  z <- stats::qnorm(1 - (1 - conf) / 2)
  p <- k / n
  d <- 1 + z^2 / n
  c0 <- (p + z^2 / (2 * n)) / d
  hw <- z * sqrt(pmax(0, p * (1 - p) / n + z^2 / (4 * n^2))) / d
  out <- cbind(lo = pmax(0, c0 - hw), hi = pmin(1, c0 + hw))
  out[is.na(n) | n == 0, ] <- NA_real_
  out
}

#' The grades a verdict can earn against ground truth
#'
#' @section Why these seven and not right/wrong:
#' The costly outcomes are not symmetric, and collapsing them hides the two the
#' pipeline most needs to count. `FALSE_MATCH` is a reviewer naming an EIN where
#' the truth table says no organisation exists at all — an individual payee, a
#' government body, a payee with no exemption of its own — which
#' [pf_evaluate()] already treats as an unambiguous false accept for a run.
#' `RULED_OUT` is narrower and worse than `WRONG_EIN`: adjudication had already
#' excluded that specific EIN, so the review contradicts a recorded negative
#' rather than merely missing.
#'
#' `UNSCOREABLE` exists so that an unscoreable case cannot be silently counted
#' as wrong. A truth row of `UNRESOLVED`, or a `MATCH` against a row with
#' neither a `correct_ein` nor a `wrong_ein`, carries no answer to compare with;
#' `is_correct` is `NA` on those rows and every denominator below excludes them.
#'
#' @return A character vector of the grade levels.
#' @examples
#' pf_grade_levels()
#' @export
pf_grade_levels <- function()
  c("CORRECT", "WRONG_EIN", "RULED_OUT", "FALSE_MATCH", "MISSED",
    "AMBIGUOUS", "UNSCOREABLE")

#' Grade a reviewed round against ground truth
#'
#' Joins verdicts to the truth table and grades each one. Accuracy is reported
#' with a Wilson interval over the scoreable cases only.
#'
#' @section The population guard, and why it stops rather than warns:
#' `grant_id` is positional, so the same id denotes a different grant in each
#' grant vintage — measured, ids join across the two known vintages at 96–97%
#' while recipient names agree on **0%** ([pf_population_id()]). A round graded
#' against truth from another population is not a weak result, it is a
#' confident one about nothing, so a mismatch is an error. Pass `population`
#' whenever the caller knows it.
#'
#' @section What it refuses to compute:
#' Precision on the YES mass (`ADJUDICATION-PREREQS.md` T11) is **not** derivable
#' here and is not reported. A truth table assembled out of cells the pipeline
#' failed on cannot measure precision on the cells it cleared; that needs its own
#' stratified sample, and T11 says so.
#'
#' @param verdicts A frame from [pf_read_verdicts()], or anything it accepts.
#' @param truth The ground-truth table or a path to it; defaults to
#'   `data-dev/PF-TRUTH.csv`. Must satisfy [pf_truth_schema()].
#' @param population Optional fingerprint to enforce, from [pf_population_id()].
#' @param min_confidence Drop truth rows weaker than this, as in [pf_evaluate()].
#' @param verbose Print the grade table and the accuracy interval.
#' @return An object of class `pf_graded`: a data frame of one row per verdict
#'   with `grade` and `is_correct` (`NA` where unscoreable), carrying
#'   `attr(, "accuracy")` (`k`, `n`, `rate`, `lo`, `hi`) and
#'   `attr(, "counts")`.
#' @seealso [pf_grade_by()] for the T3/T4/T8 cuts, [pf_grade_layers()] for T5.
#' @examples
#' \dontrun{
#' v <- pf_read_verdicts("round-1-verdicts.csv")
#' g <- pf_grade_verdicts(v, population = pf_population_id(p$grants))
#' attr(g, "accuracy")
#' pf_grade_by(g, "evidence_class")
#' }
#' @export
pf_grade_verdicts <- function(verdicts, truth = NULL, population = NULL,
                              min_confidence = c("medium", "high", "low"),
                              verbose = TRUE) {
  min_confidence <- match.arg(min_confidence)
  v <- if (inherits(verdicts, "pf_verdicts")) verdicts else pf_read_verdicts(verdicts)
  v <- as.data.frame(v, stringsAsFactors = FALSE)

  if (is.null(truth)) truth <- file.path("data-dev", "PF-TRUTH.csv")
  if (is.character(truth) && length(truth) == 1L) {
    if (!file.exists(truth)) stop("truth table not found: ", truth, call. = FALSE)
    truth <- utils::read.csv(truth, colClasses = "character", stringsAsFactors = FALSE)
  }
  t0 <- as.data.frame(truth, stringsAsFactors = FALSE)
  miss <- setdiff(pf_truth_schema(), names(t0))
  if (length(miss))
    stop("truth table is missing columns: ", paste(miss, collapse = ", "),
         call. = FALSE)
  if (length(unique(t0$population)) > 1L)
    stop("truth table mixes populations; grading would be meaningless.", call. = FALSE)
  if (!is.null(population) && !identical(as.character(population), t0$population[1]))
    stop(sprintf(paste0(
      "population mismatch: the round is %s, the truth table is %s.\n",
      "  grant_id is positional, so these ids are not comparable -- across the\n",
      "  two known vintages names agree on 0%% of joined ids."),
      population, t0$population[1]), call. = FALSE)

  RANK <- c(low = 1L, medium = 2L, high = 3L)
  keep <- !is.na(RANK[t0$confidence]) & RANK[t0$confidence] >= RANK[[min_confidence]]
  dropped_conf <- sum(!keep)
  t0 <- t0[keep, , drop = FALSE]

  i <- match(as.character(v$grant_id), as.character(t0$grant_id))
  unlabelled <- is.na(i)
  if (all(unlabelled))
    stop(sprintf(paste0(
      "none of the %d verdicts has a truth row at this confidence floor (%s).\n",
      "  Either the round and the table are different populations, or the",
      " labels were not built for these cases."),
      nrow(v), min_confidence), call. = FALSE)

  tv  <- t0$verdict[i]
  cein <- .pf_ein(t0$correct_ein[i])
  wein <- .pf_ein(t0$wrong_ein[i])
  vein <- .pf_ein(v$ein)
  no_org <- !is.na(tv) & grepl("^NO_ORG", tv)
  unresolved <- !is.na(tv) & tv == "UNRESOLVED"

  grade <- rep(NA_character_, nrow(v))
  is_match <- v$verdict == "MATCH"
  grade[unlabelled | unresolved] <- "UNSCOREABLE"
  ok <- is.na(grade)
  grade[ok & v$verdict == "AMBIGUOUS"] <- "AMBIGUOUS"
  ok <- is.na(grade)
  # NONE is right exactly where the truth says no organisation exists, and
  # wrong where an EIN is known. It is UNSCOREABLE nowhere: a truth row that
  # reached this point carries one of the two answers.
  grade[ok & v$verdict == "NONE" &  no_org]        <- "CORRECT"
  grade[ok & v$verdict == "NONE" & !is.na(cein)]   <- "MISSED"
  ok <- is.na(grade)
  grade[ok & is_match &  no_org]                   <- "FALSE_MATCH"
  ok <- is.na(grade)
  grade[ok & is_match & !is.na(cein) & !is.na(vein) & vein == cein] <- "CORRECT"
  ok <- is.na(grade)
  grade[ok & is_match & !is.na(wein) & !is.na(vein) & vein == wein] <- "RULED_OUT"
  ok <- is.na(grade)
  grade[ok & is_match & !is.na(cein)]              <- "WRONG_EIN"
  grade[is.na(grade)]                              <- "UNSCOREABLE"

  out <- v
  out$truth_verdict <- tv
  out$correct_ein   <- cein
  out$grade         <- factor(grade, levels = pf_grade_levels())
  out$is_correct    <- ifelse(grade == "UNSCOREABLE", NA, grade == "CORRECT")

  k <- sum(out$is_correct %in% TRUE)
  n <- sum(!is.na(out$is_correct))
  w <- pf_wilson(k, n)
  acc <- data.frame(k = k, n = n, rate = if (n > 0) k / n else NA_real_,
                    lo = w[1, "lo"], hi = w[1, "hi"])
  cnt <- list(verdicts = nrow(v), unlabelled = sum(unlabelled),
              dropped_below_confidence = dropped_conf,
              unresolved = sum(unresolved),
              scoreable = n, by_grade = table(out$grade))
  attr(out, "accuracy") <- acc
  attr(out, "counts")   <- cnt
  class(out) <- c("pf_graded", "data.frame")

  if (verbose) {
    .pf_hr(verbose)
    .pf_say(verbose, "graded %d verdicts against %d truth rows", nrow(v), nrow(t0))
    .pf_say(verbose, "  %s", paste(sprintf("%s %d", names(cnt$by_grade),
                                           as.integer(cnt$by_grade)),
                                   collapse = " | "))
    .pf_say(verbose, "  accuracy %d/%d = %.1f%% [%.1f, %.1f]  (scoreable only)",
            k, n, 100 * acc$rate, 100 * acc$lo, 100 * acc$hi)
    if (cnt$unlabelled)
      .pf_say(verbose, "  %d verdicts have no truth row and are excluded, not counted wrong",
              cnt$unlabelled)
    .pf_say(verbose, "  precision on the YES mass is not derivable here; see PREREQS T11")
  }
  out
}

#' Cut a graded round by a recorded field
#'
#' The T3, T4 and T8 cuts: accuracy within each level of one column, each with
#' its own Wilson interval, so a 3-case cell cannot read like a finding.
#'
#' @section On monotonicity, which is reported and never assumed:
#' T3 gates the dropped `pf_adjudicate_auto()` on confidence being monotone, and
#' `dev/adjudicate-15-no-arms.R` records the MAYBE search arm's confidence
#' *rising as accuracy fell* — "worse than useless" — while Opus on the NO tier
#' was the inverse. So for `confidence` this orders the levels `high`, `medium`,
#' `low` and returns a `monotone` attribute that distinguishes decreasing,
#' increasing and neither. An increasing result is a finding, not a bug, and is
#' the one that forbids using confidence as a gate.
#'
#' @param graded A `pf_graded` from [pf_grade_verdicts()].
#' @param by Column name to cut on, e.g. `"confidence"` (T3),
#'   `"evidence_class"` (T4), a flag column (T8), or `"tier_before"`.
#' @param min_n Cells smaller than this are returned but marked
#'   `usable = FALSE`. Default 20.
#' @return A data frame with one row per level: `level`, `k`, `n`, `rate`,
#'   `lo`, `hi`, `usable`. `attr(, "monotone")` is set when `by` is an ordered
#'   scale; `attr(, "separated")` says whether the intervals are disjoint.
#' @examples
#' \dontrun{
#' pf_grade_by(g, "confidence")
#' pf_grade_by(g, "evidence_class")
#' }
#' @export
pf_grade_by <- function(graded, by, min_n = 20L) {
  stopifnot(inherits(graded, "pf_graded"))
  d <- as.data.frame(graded, stringsAsFactors = FALSE)
  if (is.null(d[[by]]))
    stop(sprintf(paste0(
      "`%s` is not a column of the graded round.\n  present: %s\n",
      "  Reading an absent column returns NULL and every cell below would be",
      " empty rather than wrong-looking."),
      by, paste(names(d), collapse = ", ")), call. = FALSE)

  # Ordered scales get their own order; anything else is sorted, so the output
  # is stable but no direction is implied.
  ORD <- list(confidence     = pf_verdict_levels()$confidence,
              evidence_class = pf_verdict_levels()$evidence_class,
              tier_before    = pf_status_levels())
  lv <- ORD[[by]]
  vals <- as.character(d[[by]])
  if (is.null(lv)) lv <- sort(unique(vals[!is.na(vals)]))
  else lv <- lv[lv %in% vals]
  if (!length(lv)) stop(sprintf("`%s` has no non-missing values.", by), call. = FALSE)

  rows <- lapply(lv, function(l) {
    s <- d$is_correct[!is.na(vals) & vals == l]
    k <- sum(s %in% TRUE); n <- sum(!is.na(s))
    w <- pf_wilson(k, n)
    data.frame(level = l, k = k, n = n,
               rate = if (n > 0) k / n else NA_real_,
               lo = w[1, "lo"], hi = w[1, "hi"], stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, rows)
  out$usable <- !is.na(out$n) & out$n >= min_n
  rownames(out) <- NULL

  if (!is.null(ORD[[by]])) {
    r <- out$rate[!is.na(out$rate)]
    attr(out, "monotone") <-
      if (length(r) < 2L) NA_character_
      else if (all(diff(r) <= 0)) "decreasing"
      else if (all(diff(r) >= 0)) "increasing"
      else "neither"
  }
  # Disjoint intervals are the only version of "this scale discriminates" that
  # survives a small cell, which is T4's whole question.
  fin <- out[!is.na(out$lo), , drop = FALSE]
  attr(out, "separated") <- nrow(fin) >= 2L &&
    all(fin$lo[-nrow(fin)] > fin$hi[-1] | fin$hi[-nrow(fin)] < fin$lo[-1])
  out
}

#' Compare layers or arms on the same cases
#'
#' T5 and T6. Takes one verdict frame per layer and refuses to compare them
#' unless they cover the *same* cases.
#'
#' @section Why unequal case sets are an error and not a caveat:
#' `ADJUDICATION-PREREQS.md` §3 is that the layers must run over the same
#' enriched cases, because two packets produce "another pair of incomparable
#' denominators" — the specific failure `dev/assert-lib.R` was written to stop
#' and the one that once reported 159 identities moved where 28 had. A function
#' that quietly intersected, or quietly did not, would make that failure look
#' exactly like a working comparison. So the case sets must match, and the
#' message names what is missing from which layer.
#'
#' @param layers A named list of verdict frames, one per layer or arm.
#' @param truth Passed to [pf_grade_verdicts()].
#' @param by Optional column to cut each layer by, usually `"tier_before"`,
#'   which is what turns Phase 4b's routing table from an extrapolation into a
#'   measurement.
#' @param ... Passed to [pf_grade_verdicts()].
#' @return A data frame of one row per layer (or layer x level), with Wilson
#'   intervals, carrying `attr(, "cases")`: the common case count.
#' @examples
#' \dontrun{
#' pf_grade_layers(list(layer0 = v0, layer1 = v1, layer3 = v3),
#'                 by = "tier_before")
#' }
#' @export
pf_grade_layers <- function(layers, truth = NULL, by = NULL, ...) {
  if (!is.list(layers) || is.null(names(layers)) || any(!nzchar(names(layers))))
    stop("`layers` must be a NAMED list of verdict frames, one per layer.",
         call. = FALSE)
  if (length(layers) < 2L)
    stop("comparing layers needs at least two.", call. = FALSE)

  ids <- lapply(layers, function(x) sort(unique(as.character(
    as.data.frame(x, stringsAsFactors = FALSE)$grant_id))))
  common <- Reduce(intersect, ids)
  bad <- vapply(ids, function(x) !identical(x, sort(common)), logical(1))
  if (any(bad)) {
    detail <- vapply(names(layers), function(nm) {
      extra <- setdiff(ids[[nm]], common); short <- setdiff(common, ids[[nm]])
      sprintf("%s: %d cases, %d not in every layer", nm, length(ids[[nm]]),
              length(extra) + length(short))
    }, character(1))
    stop(sprintf(paste0(
      "the layers do not cover the same cases, so their rates have different\n",
      "  denominators and are not comparable (PREREQS section 3).\n  %s\n",
      "  %d cases are common to all. Re-run the layers over one case set, or\n",
      "  subset to the common cases deliberately before calling this."),
      paste(detail, collapse = "\n  "), length(common)), call. = FALSE)
  }

  rows <- lapply(names(layers), function(nm) {
    g <- pf_grade_verdicts(layers[[nm]], truth = truth, verbose = FALSE, ...)
    if (is.null(by)) {
      a <- attr(g, "accuracy")
      data.frame(layer = nm, level = NA_character_, k = a$k, n = a$n,
                 rate = a$rate, lo = a$lo, hi = a$hi, stringsAsFactors = FALSE)
    } else {
      b <- pf_grade_by(g, by)
      data.frame(layer = nm, level = b$level, k = b$k, n = b$n, rate = b$rate,
                 lo = b$lo, hi = b$hi, stringsAsFactors = FALSE)
    }
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  attr(out, "cases") <- length(common)
  out
}
