#!/usr/bin/env Rscript
# ============================================================================
# grade-hand-slice.R -- score the model labelers against the hand slice.
#
# This is dev/TRUTH-LABELING-PROTOCOL.md section 6 step 4, the step that turns
# the round's agreement figures into an error rate. The hand labels are the
# TRUTH argument; the models are the thing being graded.
#
# THE SCHEMA GLUE, AND WHY IT IS NEEDED. pf_grade_verdicts() was built to grade
# an ADJUDICATOR ARM -- pf_verdict_cols(), verdicts MATCH / NONE / AMBIGUOUS --
# against a truth table in pf_truth_schema(). The model's stage-1 labels are in
# the TRUTH schema (ORG_FOUND / NO_ORG_* / UNRESOLVED), so they cannot be passed
# as `verdicts` unconverted: pf_read_verdicts() would refuse `ORG_FOUND` as an
# unknown level, and there is no `ein` column for it to read.
#
# So they are mapped, and the mapping is lossy in exactly one direction:
#
#   ORG_FOUND          -> MATCH,     ein = correct_ein
#   NO_ORG_INDIVIDUAL  -> NONE   \   three classes collapse to one, because
#   NO_ORG_NOT_EXEMPT  -> NONE    >  MATCH/NONE/AMBIGUOUS has no finer level.
#   NO_ORG_UNFINDABLE  -> NONE   /   Nothing is lost: the HUMAN's class is kept
#   UNRESOLVED         -> AMBIGUOUS  on the truth side, where the grade reads it.
#
#   basis web -> QUOTE | inference -> INFER | reference -> NONE
#     (`evidence_class` is required by the verdict schema and is not the
#      quantity being graded here; mapped faithfully where there is an
#      equivalent and left NONE where there is not.)
#
# Using the grade taxonomy rather than a single agreement rate is the point:
# CORRECT / WRONG_EIN / FALSE_MATCH / MISSED / RULED_OUT separate a model that
# named the wrong organisation from one that invented an organisation from one
# that missed a real one, and those three failures have different consequences
# for every figure in section 6b.7.
#
# min_confidence = "low" IS PASSED DELIBERATELY. The default is "medium", which
# drops every truth row whose confidence is `low` -- and on a 40-case slice
# those are the hard cases, the ones most likely to be where a model is wrong.
# Silently grading 34 of 40 and reporting it as the slice is precisely the
# defect dev/PLAUSIBLE-WRONG-NUMBERS.md catalogues.
#
# USAGE  Rscript dev/grade-hand-slice.R
#        PF_HAND_TRUTH=<csv> Rscript dev/grade-hand-slice.R   # a dry run
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
DD  <- file.path(PF, "data-dev")
OUT <- file.path(DD, "round-stage1-handslice")
SHARD <- 99L

HAND <- Sys.getenv("PF_HAND_TRUTH", file.path(OUT, "shard-99-truth.csv"))
HELD <- file.path(OUT, "HELD-slice-design-and-model-labels.csv")
KEY  <- file.path(OUT, "SLICE-KEY.csv")

say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() cat(strrep("=", 78), "\n")
hr(); say("HAND SLICE vs THE MODEL LABELERS"); hr()

## ---- the hand labels, validated the same way a model shard is -------------
h <- as.data.table(utils::read.csv(HAND, colClasses = "character"))
filled <- h[nzchar(trimws(verdict))]
say("hand file %s: %d rows, %d filled", basename(HAND), nrow(h), nrow(filled))
if (!nrow(filled))
  stop(paste0("no verdicts filled in yet.\n",
       "  Fill shard-99-truth.csv first; see the README in that directory."),
       call. = FALSE)
if (nrow(filled) < nrow(h))
  say("  NOTE: %d rows still blank -- graded on the %d that are filled",
      nrow(h) - nrow(filled), nrow(filled))

key <- as.data.table(utils::read.csv(KEY, colClasses = "character"))
cols <- pf_shard_schema()
say("")
hv <- pf_read_truth(as.data.frame(filled[, ..cols]), key = key,
                    population = unique(filled$population)[1L], verbose = TRUE)
hv <- as.data.table(hv)

## ---- the models, converted into the verdict schema ------------------------
held <- as.data.table(utils::read.csv(HELD, colClasses = "character"))
m <- held[grant_id %in% hv$grant_id]
say("\nmodel labels for those cases: %d", nrow(m))

VMAP <- c(ORG_FOUND = "MATCH", NO_ORG_INDIVIDUAL = "NONE",
          NO_ORG_NOT_EXEMPT = "NONE", NO_ORG_UNFINDABLE = "NONE",
          UNRESOLVED = "AMBIGUOUS")
EMAP <- c(web = "QUOTE", inference = "INFER", reference = "NONE")
mv <- data.table(
  grant_id       = m$grant_id,
  verdict        = VMAP[m$verdict],
  ein            = ifelse(m$verdict == "ORG_FOUND", m$correct_ein, NA_character_),
  confidence     = m$confidence,
  evidence_class = ifelse(is.na(EMAP[m$basis]), "NONE", EMAP[m$basis]),
  evidence       = m$note,
  runner_up_ein  = NA_character_)
if (any(is.na(mv$verdict)))
  stop("a model verdict is outside pf_truth_levels(); the held file is wrong.",
       call. = FALSE)

## ---- grade ----------------------------------------------------------------
say("")
g <- pf_grade_verdicts(mv, truth = as.data.frame(hv[, ..cols]),
                       population = unique(hv$population)[1L],
                       min_confidence = "low", verbose = TRUE)
g <- as.data.table(g)
acc <- attr(pf_grade_verdicts(mv, truth = as.data.frame(hv[, ..cols]),
                              population = unique(hv$population)[1L],
                              min_confidence = "low", verbose = FALSE), "accuracy")

say("")
hr(); say("WHAT THE MODELS GOT WRONG, AND IN WHICH DIRECTION"); hr()
print(table(grade = g$grade))
say("")
say("  CORRECT      model named the EIN the hand label establishes")
say("  WRONG_EIN    model named a real org, the wrong one")
say("  RULED_OUT    model named an EIN the hand label explicitly ruled OUT")
say("  FALSE_MATCH  model named an org where the hand label says none exists")
say("  MISSED       model declined; the hand label found an organisation")
say("  AMBIGUOUS    model returned UNRESOLVED")
say("  UNSCOREABLE  hand label is UNRESOLVED, so neither can be scored")

## ---- back to the round, with the slice's own weights ----------------------
hr(); say("THE ROUND-LEVEL ESTIMATE, WEIGHTED BACK"); hr()
say("The slice is stratified on the MODEL's verdict with floors on the small")
say("classes, so an unweighted rate over 40 cases is NOT the round's rate.")
say("Weighted with the draw's own sampling fractions:")
d <- merge(g[, .(grant_id, is_correct, grade)],
           held[, .(grant_id, slice_stratum = verdict,
                    w = as.numeric(slice_weight),
                    N_h = as.numeric(slice_pool_n),
                    overlap_agreed)], by = "grant_id")
sc <- d[!is.na(is_correct)]
say("")
per <- sc[, .(n_h = .N, k_h = sum(is_correct %in% TRUE), N_h = N_h[1L]), by = slice_stratum]
per[, p_h := k_h / n_h]
wl <- pf_wilson(per$k_h, per$n_h)
per[, `:=`(lo = round(100 * wl[, "lo"]), hi = round(100 * wl[, "hi"]))]
per[, rate := sprintf("%.0f%%", 100 * p_h)]
print(per[order(-N_h), .(slice_stratum, N_h, n_h, k_h, rate, lo, hi)])

Ntot <- sum(per$N_h)
est  <- sum(per$N_h / Ntot * per$p_h)
# Stratified estimator's variance, sum_h W_h^2 p_h(1-p_h)/n_h. A normal
# approximation and said to be one: at n_h of 3 it is poor, which is why the
# per-class Wilson cells above are the honest reads and this is the headline
# only because the round-level figure is what the question asks for.
va <- sum((per$N_h / Ntot)^2 * per$p_h * (1 - per$p_h) / per$n_h)
se <- sqrt(va)
say("")
# A stratum with no filled rows drops out of the estimator silently, and the
# estimate then covers a smaller round than the one it appears to describe.
# Ntot says so, but only to a reader who knows the round is 400.
gone <- setdiff(unique(held$verdict), per$slice_stratum)
if (length(gone))
  say("WARNING: %s has no scoreable row, so this estimate covers %d of 400\n  cases, not the round. Fill those rows before quoting it.",
      paste(gone, collapse = ", "), Ntot)
say("weighted model accuracy over the %d-case round: %.1f%%", Ntot, 100 * est)
say("  +/- 1.96 SE (normal approx, NOT Wilson): [%.1f, %.1f]",
    100 * max(0, est - 1.96 * se), 100 * min(1, est + 1.96 * se))
say("  scoreable %d of %d slice cases", nrow(sc), nrow(d))

## ---- the subgroup the whole exercise is about -----------------------------
say("")
hr(); say("THE CASES TWO MODELS AGREED ON"); hr()
say("Where both labelers resolved a case the same way, nothing inside the")
say("round can tell whether they were right together. These are those cases:")
ag <- sc[overlap_agreed == "TRUE"]
if (!nrow(ag)) {
  say("  none of the scoreable slice cases is an agreeing-overlap case.")
} else {
  wa <- pf_wilson(sum(ag$is_correct %in% TRUE), nrow(ag))
  say("  %d/%d = %.0f%% [%.0f, %.0f]  -- n is small; this is a floor, not a rate",
      sum(ag$is_correct %in% TRUE), nrow(ag),
      100 * mean(ag$is_correct %in% TRUE), 100 * wa[1, "lo"], 100 * wa[1, "hi"])
}

## ---- every disagreement, listed ------------------------------------------
say("")
hr(); say("EVERY CASE THE MODELS DID NOT GET RIGHT"); hr()
bad <- merge(g[grade %in% c("WRONG_EIN", "RULED_OUT", "FALSE_MATCH", "MISSED")],
             hv[, .(grant_id, hand_verdict = verdict, hand_ein = correct_ein,
                    hand_note = note)], by = "grant_id")
if (!nrow(bad)) say("  none.") else
for (i in seq_len(nrow(bad))) {
  say("\n  %s  [%s]", bad$grant_id[i], as.character(bad$grade[i]))
  say("    model: %s %s", bad$verdict[i], ifelse(is.na(bad$ein[i]), "", bad$ein[i]))
  say("    hand:  %s %s", bad$hand_verdict[i], bad$hand_ein[i])
  say("      %s", substr(bad$hand_note[i], 1, 150))
}
hr()
say("This slice prices stage 1's truth, and therefore every figure graded")
say("against it -- ADJUDICATION-PREREQS.md 6b.7 (a) through (d).")
hr()
