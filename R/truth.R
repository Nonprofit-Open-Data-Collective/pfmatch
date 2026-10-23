# ============================================================================
# Scoring a run against hand-adjudicated ground truth.
#
# The point of this file is to replace a pattern that cost most of a working
# session: every configuration change produced a clear-rate delta, and a
# clear-rate delta cannot distinguish recall from false accepts. Each answer
# ended "the moved cells need adjudicating", and each adjudication was a bespoke
# script. pf_evaluate() makes any configuration scoreable in one call.
# ============================================================================

#' Ground-truth table columns
#'
#' The schema `data-dev/PF-TRUTH.csv` is written in by `dev/build-truth.R`.
#'
#' A row records the *correct answer for a grant*, never a judgement about some
#' run's pick. That distinction is the whole reason this table exists: a label
#' saying "the pipeline's choice was right" cannot score a different
#' configuration, because a different configuration chooses differently.
#'
#' @return A character vector of required column names.
#' @export
pf_truth_schema <- function() {
  c("truth_id",    # OBJECTID | TABLE_ID -- the published ef2 row key
    "grant_id",    # positional id; valid only within `population`
    "population",  # fingerprint of the grant-file set this row was adjudicated on
    "verdict",     # ORG_FOUND | NO_ORG_INDIVIDUAL | NO_ORG_NOT_EXEMPT |
                   # NO_ORG_UNFINDABLE | UNRESOLVED
    "correct_ein", # the right EIN, when one was established
    "wrong_ein",   # an EIN adjudication ruled OUT (a negative constraint)
    "basis",       # web | reference | inference
    "confidence")  # high | medium | low
}

#' Fingerprint a grant population
#'
#' Labels are not portable between grant vintages: `grant_id` is positional, so
#' the same id denotes a different grant in each population. Measured directly,
#' ids join across the two vintages at 96-97% while recipient names agree on
#' **0%**. Scoring a run against truth from another population therefore
#' produces confident nonsense, and [pf_evaluate()] refuses it.
#'
#' @param grants A frame carrying `OBJECTID` (the e-file document id).
#' @return A 16-character fingerprint.
#' @export
pf_population_id <- function(grants) {
  oid <- as.character(grants$OBJECTID)
  if (!length(oid) || all(is.na(oid)))
    stop("no OBJECTID column: cannot fingerprint this population. The archived ",
         "GT extracts have no OBJECTID (see inputs/archive-gt/README.md).",
         call. = FALSE)
  oid[is.na(oid)] <- ""
  substr(digest::digest(sort(unique(oid)), algo = "md5"), 1, 16)
}

.pf_e9 <- function(v) {
  v <- gsub("[^0-9]", "", as.character(v))
  ifelse(nchar(v) == 9L, v, NA_character_)
}

#' Score a run against ground truth
#'
#' @param run A run result: `pf_match_grants()$result` or a frame with an id
#'   column (`grant_id` or `.id`), a `tier`, and an EIN column (`ein`,
#'   `overall_ein` or `ein9`).
#' @param truth The ground-truth table, or a path to it. Defaults to
#'   `data-dev/PF-TRUTH.csv`.
#' @param population Optional fingerprint to enforce. When supplied and it
#'   disagrees with the truth table, this errors rather than scoring.
#' @param min_confidence Drop truth rows weaker than this. `"medium"` (the
#'   default) keeps web- and reference-based labels and the stratified
#'   inferences; `"high"` keeps only web-confirmed EINs.
#'
#' @section What it can and cannot measure:
#' Recall is measured against the truth rows that carry a `correct_ein`.
#' Precision on the YES mass is **not** measurable from a truth table built out
#' of cells the pipeline failed on — that needs a random stratified sample.
#' What *is* measurable without one is **false clears**: truth rows asserting no
#' organisation exists at all (an individual payee, a government body, a payee
#' with no exemption of its own) must never be YES, so any that are are
#' unambiguous false accepts.
#'
#' @return An object of class `pf_eval`: a list of `summary` (one row) and
#'   `detail` (per-case).
#' @export
pf_evaluate <- function(run, truth = NULL, population = NULL,
                        min_confidence = c("medium", "high", "low")) {
  min_confidence <- match.arg(min_confidence)
  if (is.null(truth)) truth <- file.path("data-dev", "PF-TRUTH.csv")
  if (is.character(truth)) {
    if (!file.exists(truth)) stop("truth table not found: ", truth, call. = FALSE)
    truth <- data.table::fread(truth, colClasses = "character")
  }
  truth <- data.table::as.data.table(truth)
  miss <- setdiff(pf_truth_schema(), names(truth))
  if (length(miss)) stop("truth table is missing columns: ",
                         paste(miss, collapse = ", "), call. = FALSE)
  if (data.table::uniqueN(truth$population) > 1L)
    stop("truth table mixes populations; scoring would be meaningless.", call. = FALSE)
  if (!is.null(population) && !identical(population, truth$population[1]))
    stop(sprintf(paste0("population mismatch: run is %s, truth is %s.\n",
         "  grant_id is positional, so these ids are not comparable -- across the\n",
         "  two known vintages names agree on 0%% of joined ids."),
         population, truth$population[1]), call. = FALSE)

  RANK <- c(low = 1L, medium = 2L, high = 3L)
  truth <- truth[RANK[confidence] >= RANK[[min_confidence]]]

  r <- data.table::as.data.table(run)
  idc <- intersect(c("grant_id", ".id"), names(r))[1]
  if (is.na(idc)) stop("run has no grant_id / .id column", call. = FALSE)
  einc <- intersect(c("ein9", "ein", "overall_ein"), names(r))[1]
  if (is.na(einc)) stop("run has no ein / overall_ein column", call. = FALSE)
  if (!"tier" %in% names(r)) {
    if ("status" %in% names(r)) r[, tier := status]
    else stop("run has no tier / status column", call. = FALSE)
  }
  r <- r[, .(grant_id = as.character(get(idc)), tier = as.character(tier),
             ein = .pf_e9(get(einc)))]

  d <- merge(truth, r, by = "grant_id", all.x = TRUE)
  d[, in_run := !is.na(tier)]
  d[, correct_ein := .pf_e9(correct_ein)][, wrong_ein := .pf_e9(wrong_ein)]
  d[, got_right := !is.na(ein) & !is.na(correct_ein) & ein == correct_ein]
  d[, got_ruled_out := !is.na(ein) & !is.na(wrong_ein) & ein == wrong_ein]
  d[, no_org := grepl("^NO_ORG", verdict)]
  cleared <- function(x) !is.na(x) & x == "YES"
  surfaced <- function(x) !is.na(x) & x %in% c("YES", "MAYBE")

  scoreable <- d[!is.na(correct_ein) & in_run]
  negatives <- d[no_org & in_run]

  s <- data.table::data.table(
    population      = truth$population[1],
    truth_rows      = nrow(d),
    in_run          = sum(d$in_run),
    # recall, on the rows where a correct EIN is known
    recall_n        = nrow(scoreable),
    right_and_yes   = sum(scoreable$got_right & cleared(scoreable$tier)),
    right_any_tier  = sum(scoreable$got_right),
    right_surfaced  = sum(scoreable$got_right & surfaced(scoreable$tier)),
    # false clears: these should never be YES at all
    no_org_n        = nrow(negatives),
    no_org_cleared  = sum(cleared(negatives$tier)),
    no_org_surfaced = sum(surfaced(negatives$tier)),
    # picked an EIN adjudication explicitly ruled out
    ruled_out_yes   = sum(d$got_ruled_out & cleared(d$tier), na.rm = TRUE))
  s[, recall_yes := ifelse(recall_n > 0, right_and_yes / recall_n, NA_real_)]
  s[, recall_surfaced := ifelse(recall_n > 0, right_surfaced / recall_n, NA_real_)]
  s[, false_clear_rate := ifelse(no_org_n > 0, no_org_cleared / no_org_n, NA_real_)]
  structure(list(summary = s, detail = d), class = "pf_eval")
}

#' Consistency across renderings of one organisation
#'
#' A ground-truth-free quality metric. One organisation is written many ways
#' across grants; grouping those renderings by **address** is independent of the
#' name comparator, so within a group every rendering should receive the same
#' EIN whatever that EIN turns out to be. Disagreement inside a group is a defect
#' regardless of which member is right.
#'
#' That independence from ground truth is the point. The anchor-based labels in
#' `PF-TRUTH-TRIANGULATED.csv` measured only ~50-60% precise, because a shared
#' street address also covers fiscal sponsors (`MULTIPLIERORG` and the Natural
#' Resources Defense Council), individual payees at an organisation's address
#' (`EDUCATIONAL GRANT - <person>`), and cases where the anchoring YES is itself
#' wrong (`Homes for our Troops`). None of that damages a disagreement count:
#' those groups are noisy in every configuration, so comparing configurations on
#' the same groups still isolates the change.
#'
#' It is necessary, not sufficient. A configuration that answers every rendering
#' identically and wrongly scores perfectly here, so read it alongside
#' [pf_evaluate()], never instead of it.
#'
#' @param run A run result, as for [pf_evaluate()].
#' @param groups `(grant_id, group_id)` from
#'   `dev/build-triangulation-sample.R`, or a path to it.
#' @param min_size Smallest group to score. Default 2.
#' @return A list of `summary` and `detail` (per group), class `pf_consistency`.
#' @export
pf_consistency <- function(run, groups = NULL, min_size = 2L) {
  if (is.null(groups)) groups <- file.path("data-dev", "TRIANGULATION-GROUPS.csv")
  if (is.character(groups)) {
    if (!file.exists(groups)) stop("groups file not found: ", groups, call. = FALSE)
    groups <- data.table::fread(groups, colClasses = "character")
  }
  groups <- data.table::as.data.table(groups)
  if (!all(c("grant_id", "group_id") %in% names(groups)))
    stop("groups needs grant_id and group_id", call. = FALSE)

  r <- data.table::as.data.table(run)
  idc  <- intersect(c("grant_id", ".id"), names(r))[1]
  einc <- intersect(c("ein9", "ein", "overall_ein"), names(r))[1]
  if (is.na(idc) || is.na(einc)) stop("run needs an id and an ein column", call. = FALSE)
  if (!"tier" %in% names(r) && "status" %in% names(r)) r[, tier := status]
  r <- r[, .(grant_id = as.character(get(idc)), tier = as.character(tier),
             ein = .pf_e9(get(einc)))]

  d <- merge(groups[, .(grant_id, group_id)], r, by = "grant_id")
  gg <- d[, .(n = .N,
              n_resolved = sum(!is.na(ein)),
              n_distinct_ein = data.table::uniqueN(ein[!is.na(ein)]),
              n_distinct_tier = data.table::uniqueN(tier)), by = group_id]
  gg <- gg[n >= min_size]
  scoreable <- gg[n_resolved >= 2L]

  s <- data.table::data.table(
    groups            = nrow(gg),
    rows              = sum(gg$n),
    groups_scoreable  = nrow(scoreable),
    ein_agree         = sum(scoreable$n_distinct_ein == 1L),
    ein_disagree      = sum(scoreable$n_distinct_ein > 1L),
    tier_mixed        = sum(gg$n_distinct_tier > 1L),
    partly_unresolved = sum(gg$n_resolved > 0L & gg$n_resolved < gg$n))
  s[, ein_agreement := ifelse(groups_scoreable > 0,
                              ein_agree / groups_scoreable, NA_real_)]
  structure(list(summary = s, detail = gg), class = "pf_consistency")
}

#' @export
print.pf_consistency <- function(x, ...) {
  s <- x$summary
  cat("<pf_consistency>\n")
  cat(sprintf("  %d groups, %d rows\n", s$groups, s$rows))
  cat(sprintf("  groups with >=2 resolved renderings : %d\n", s$groups_scoreable))
  cat(sprintf("     all renderings AGREE on one EIN  : %d  (%.1f%%)\n",
              s$ein_agree, 100 * s$ein_agreement))
  cat(sprintf("     renderings DISAGREE              : %d\n", s$ein_disagree))
  cat(sprintf("  groups spanning more than one tier  : %d\n", s$tier_mixed))
  cat(sprintf("  groups resolved only in part        : %d\n", s$partly_unresolved))
  cat("\n  Necessary, not sufficient: answering every rendering identically and\n")
  cat("  wrongly scores perfectly here. Read with pf_evaluate(), not instead.\n")
  invisible(x)
}

#' @export
print.pf_eval <- function(x, ...) {
  s <- x$summary
  cat("<pf_eval>  population", s$population, "\n")
  cat(sprintf("  truth rows %d, present in run %d\n", s$truth_rows, s$in_run))
  cat(sprintf("  RECALL   on %d rows with a known correct EIN:\n", s$recall_n))
  cat(sprintf("     correct EIN and YES      %4d  (%.1f%%)\n",
              s$right_and_yes, 100 * s$recall_yes))
  cat(sprintf("     correct EIN, YES or MAYBE%4d  (%.1f%%)\n",
              s$right_surfaced, 100 * s$recall_surfaced))
  cat(sprintf("     correct EIN at any tier  %4d\n", s$right_any_tier))
  cat(sprintf("  FALSE CLEARS on %d rows where NO organisation exists:\n", s$no_org_n))
  cat(sprintf("     wrongly YES              %4d  (%.1f%%)\n",
              s$no_org_cleared, 100 * s$false_clear_rate))
  cat(sprintf("     wrongly YES or MAYBE     %4d\n", s$no_org_surfaced))
  cat(sprintf("  picked an EIN ruled out     %4d\n", s$ruled_out_yes))
  cat("\n  NOTE: precision on the YES mass is not measurable from this table --\n")
  cat("  every row was drawn from a cell the pipeline failed on. See\n")
  cat("  dev/build-truth.R. False clears ARE a real precision signal.\n")
  invisible(x)
}
