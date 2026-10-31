#!/usr/bin/env Rscript
# ============================================================================
# adjudicate-03-score.R -- the two answers, and what each one is worth.
#
# Reads the frozen packet, both tiers' verdicts and the hand-adjudicated truth,
# and reports:
#
#   Q1  How many MAYBEs would clear to YES on inspection?
#       From stratum A only (simple random, 68 cases), so the rate is an
#       unbiased estimate for the 1,044-case tier. Reported at three
#       thresholds, because "clears to YES" is a policy choice and not a
#       measurement: any MATCH, MATCH at medium+ confidence, and MATCH that
#       the deep arm externally CONFIRMED. The third is the only one that has
#       survived something like the check dev/ADJUDICATION-PLAN.md section 1
#       killed the auto-accept rule with.
#
#   Q2  How reliable is the light adjudicator?
#       Three different things, deliberately not averaged together:
#         (a) ABSOLUTE accuracy on the 32 hand-adjudicated cases -- the only
#             figure that is accuracy rather than agreement, for BOTH arms.
#         (b) AGREEMENT with the deep arm on all 100: verdict concordance,
#             exact-EIN concordance, and Cohen's kappa, which discounts the
#             agreement two reviewers get for free by both favouring MATCH.
#         (c) WHERE it fails: accuracy sliced by the light arm's own stated
#             confidence and evidence class, and by the structural features
#             the auto-accept rule failed on (ties, thin margins, pass).
#             (c) is the only part that is actionable -- it says whether a
#             cheap pass can be trusted on a subset and escalated elsewhere.
#
# THE ORDER OF THESE MATTERS. (a) comes first because it gates the rest: the
# deep arm is a model, not truth, and using it as a reference standard for the
# 68 is only defensible if it is accurate on the 32. If it is not, this script
# says so and declines to present the agreement figures as a reliability claim.
#
# WHAT "CORRECT" MEANS, which is the easiest thing to get wrong here.
# A truth row reading ORG_FOUND means a human found the organisation. It does
# NOT mean the organisation's EIN is among the five candidates -- and when it
# is not, NONE is the correct answer and a MATCH on any candidate is an error.
# `truth_in_packet` carries that distinction and every accuracy figure below
# respects it. Scoring against a target that assumes an answer is present is
# the failure dev/LLM-REVIEW-INSTRUCTIONS.md opens by warning about, and it
# would flatter both arms.
#
# OUTPUT  data-dev/ADJ-EXP-SCORED.rds + .csv, and dev/ADJ-EXP-RESULTS.log
#
# USAGE  Rscript dev/adjudicate-03-score.R
#        PF_ADJ_TAG=-r2 Rscript dev/adjudicate-03-score.R
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
DD  <- file.path(PF, "data-dev")
TAG <- Sys.getenv("PF_ADJ_TAG", "")

say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() cat(strrep("=", 78), "\n")
h2  <- function(s) { cat("\n"); cat(strrep("-", 78), "\n"); cat(s, "\n");
                     cat(strrep("-", 78), "\n") }

# Wilson score interval. Used rather than the normal approximation because
# every denominator here is small (68, 32, and subsets of those) and Wald
# intervals on 20-of-32 are wrong in a way that matters for the conclusion.
wilson <- function(k, n, conf = 0.95) {
  if (n == 0) return(c(est = NA, lo = NA, hi = NA))
  z <- qnorm(1 - (1 - conf) / 2); p <- k / n
  d <- 1 + z^2 / n
  c(est = p,
    lo = max(0, (p + z^2 / (2 * n) - z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2))) / d),
    hi = min(1, (p + z^2 / (2 * n) + z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2))) / d))
}
pct <- function(w) if (is.na(w[["est"]])) "n/a" else
  sprintf("%.1f%% (95%% CI %.1f-%.1f)", 100 * w[["est"]], 100 * w[["lo"]], 100 * w[["hi"]])
rate <- function(k, n) sprintf("%d/%d = %s", k, n, pct(wilson(k, n)))

# Cohen's kappa with the standard large-sample SE. Reported alongside raw
# agreement because two reviewers who both answer MATCH most of the time agree
# often by construction; kappa is what is left after removing that.
kappa2 <- function(a, b) {
  keep <- !is.na(a) & !is.na(b)
  a <- as.character(a)[keep]; b <- as.character(b)[keep]
  n <- length(a)
  if (n < 2) return(list(k = NA, se = NA, n = n, po = NA, pe = NA))
  lv <- union(unique(a), unique(b))
  ta <- table(factor(a, lv)) / n; tb <- table(factor(b, lv)) / n
  po <- mean(a == b); pe <- sum(ta * tb)
  k  <- if (pe == 1) NA else (po - pe) / (1 - pe)
  se <- if (pe == 1) NA else sqrt(po * (1 - po) / (n * (1 - pe)^2))
  list(k = k, se = se, n = n, po = po, pe = pe)
}

e9 <- function(x) { v <- gsub("[^0-9]", "", as.character(x))
                    ifelse(nchar(v) == 9L, v, NA_character_) }

# Printing helper: NA and NULL both become a dash. Deliberately not `%||%`,
# which tests for NULL only and would print a literal "NA" into the report.
nz <- function(x, alt = "-") {
  if (is.null(x) || length(x) == 0L) return(alt)
  x <- as.character(x)[1]
  if (is.na(x) || !nzchar(x)) alt else x
}

## ---- load ------------------------------------------------------------------
need <- c(light = sprintf("ADJ-EXP-LIGHT%s.rds", TAG),
          deep  = sprintf("ADJ-EXP-DEEP%s.rds", TAG),
          cases = "ADJ-EXP-CASES.rds", truth = "ADJ-EXP-TRUTH.rds")
miss <- need[!file.exists(file.path(DD, need))]
if (length(miss))
  stop(sprintf("missing: %s\n  Run stages 00-02 first.",
               paste(miss, collapse = ", ")), call. = FALSE)

lt <- as.data.table(readRDS(file.path(DD, need[["light"]])))
dp <- as.data.table(readRDS(file.path(DD, need[["deep"]])))
cs <- as.data.table(readRDS(file.path(DD, need[["cases"]])))
tr <- as.data.table(readRDS(file.path(DD, need[["truth"]])))

# Closed explicitly at the end of the script, NOT with on.exit(): on.exit at
# the top level of a script registers against no function frame and never
# fires, which leaves the log half-written and R exiting non-zero. Tested.
LOGF <- file.path(PF, "dev", sprintf("ADJ-EXP-RESULTS%s.log", TAG))
sink(LOGF, split = TRUE)
close_log <- function() while (sink.number() > 0L) sink()

hr(); say("MAYBE ADJUDICATION EXPERIMENT -- RESULTS"); hr()
say("run %s  light=%s  deep=%s", format(Sys.time(), "%Y-%m-%d %H:%M"),
    lt$model[1], dp$model[1])

d <- merge(
  lt[, .(grant_id, stratum, batch_order,
         l_verdict = verdict, l_ein = e9(ein), l_conf = confidence,
         l_class = evidence_class, l_evidence = evidence, l_ok = api_ok)],
  dp[, .(grant_id,
         d_verdict = verdict, d_ein = e9(ein), d_conf = confidence,
         d_class = evidence_class, d_evidence = evidence, d_ok = api_ok,
         d_search = search_confirmed, d_gt = ground_truth_name,
         d_findings = search_findings, d_searches = searches)],
  by = "grant_id")
d <- merge(d, cs[, .(grant_id, tie, n_close, overall_margin, overall_score,
                     pass, recip_name, recip_state, n_cand)],
           by = "grant_id", all.x = TRUE)
d <- merge(d, tr[, .(grant_id, truth_verdict, correct_ein, truth_in_packet,
                     adjudicable, truth_basis, truth_confidence)],
           by = "grant_id", all.x = TRUE)
setorder(d, batch_order)

say("\ncases scored: %d  (stratum A %d, stratum B %d)", nrow(d),
    sum(d$stratum == "A-estimation"), sum(d$stratum == "B-calibration"))
bad <- d[l_ok == FALSE | d_ok == FALSE | is.na(l_verdict) | is.na(d_verdict)]
if (nrow(bad)) {
  say("INCOMPLETE on %d case(s) -- excluded from every figure below:", nrow(bad))
  for (k in seq_len(min(8L, nrow(bad))))
    say("  %s  light=%s deep=%s", bad$grant_id[k],
        nz(bad$l_verdict[k], "FAIL"), nz(bad$d_verdict[k], "FAIL"))
}
d <- d[l_ok == TRUE & d_ok == TRUE & !is.na(l_verdict) & !is.na(d_verdict)]

## ---- the target answer, per case -------------------------------------------
# Built once, from truth, for the calibration stratum only.
d[, target := NA_character_]
d[adjudicable == TRUE & truth_verdict == "ORG_FOUND" & truth_in_packet == TRUE,
  target := "MATCH"]
d[adjudicable == TRUE & truth_verdict == "ORG_FOUND" & truth_in_packet == FALSE,
  target := "NONE"]
d[adjudicable == TRUE & grepl("^NO_ORG", truth_verdict), target := "NONE"]

# Graded, not binary: AMBIGUOUS naming the right EIN is a different animal from
# a confident wrong EIN, and collapsing them hides the error shape that
# dev/ADJUDICATION-PLAN.md section 1 found dominates (entity vs its own
# foundation). "MISS" is the conservative error -- answering NONE when an
# answer was there -- which costs recall, not precision.
grade <- function(verdict, ein, target, correct) {
  ifelse(is.na(target), NA_character_,
  ifelse(target == "MATCH",
    ifelse(verdict == "MATCH"     & !is.na(ein) & ein == correct, "CORRECT",
    ifelse(verdict == "AMBIGUOUS" & !is.na(ein) & ein == correct, "AMBIGUOUS_RIGHT",
    ifelse(verdict == "NONE", "MISS", "WRONG"))),
    # target == NONE: the correct answer is to decline
    ifelse(verdict == "NONE", "CORRECT",
    ifelse(verdict == "AMBIGUOUS", "AMBIGUOUS_WRONG", "WRONG"))))
}
d[, l_grade := grade(l_verdict, l_ein, target, correct_ein)]
d[, d_grade := grade(d_verdict, d_ein, target, correct_ein)]

A <- d[stratum == "A-estimation"]
B <- d[stratum == "B-calibration" & !is.na(target)]

## ============================================================================
h2("(a) ABSOLUTE ACCURACY on the hand-adjudicated cases -- the gate")
## ============================================================================
say("%d of the %d calibration cases carry a usable target.", nrow(B),
    sum(d$stratum == "B-calibration"))
say("Of those, the correct answer is MATCH on %d and NONE on %d.",
    sum(B$target == "MATCH"), sum(B$target == "NONE"))
say("\n%d case(s) where a human found the org but its EIN is NOT in the packet:",
    sum(B$truth_verdict == "ORG_FOUND" & B$truth_in_packet == FALSE, na.rm = TRUE))
say("  on those, NONE is correct and any MATCH is an error, however plausible.")

if (nrow(B) >= 5) {
  say("\n                        light            deep")
  for (g in c("CORRECT", "AMBIGUOUS_RIGHT", "MISS", "AMBIGUOUS_WRONG", "WRONG"))
    say("  %-20s  %3d             %3d", g, sum(B$l_grade == g), sum(B$d_grade == g))
  lw <- wilson(sum(B$l_grade == "CORRECT"), nrow(B))
  dw <- wilson(sum(B$d_grade == "CORRECT"), nrow(B))
  say("\nstrict accuracy (CORRECT only)")
  say("  light : %s", rate(sum(B$l_grade == "CORRECT"), nrow(B)))
  say("  deep  : %s", rate(sum(B$d_grade == "CORRECT"), nrow(B)))
  ll <- wilson(sum(B$l_grade %in% c("CORRECT", "AMBIGUOUS_RIGHT")), nrow(B))
  dl <- wilson(sum(B$d_grade %in% c("CORRECT", "AMBIGUOUS_RIGHT")), nrow(B))
  say("lenient accuracy (right EIN even if hedged)")
  say("  light : %s", rate(sum(B$l_grade %in% c("CORRECT", "AMBIGUOUS_RIGHT")), nrow(B)))
  say("  deep  : %s", rate(sum(B$d_grade %in% c("CORRECT", "AMBIGUOUS_RIGHT")), nrow(B)))
  say("\nconfident-and-wrong -- the error that is never reviewed again:")
  say("  light : %s", rate(nrow(B[l_grade == "WRONG" & l_conf == "high"]), nrow(B)))
  say("  deep  : %s", rate(nrow(B[d_grade == "WRONG" & d_conf == "high"]), nrow(B)))

  GATE <- 0.75
  say("\n--")
  if (is.na(dw[["est"]]) || dw[["est"]] < GATE) {
    say("GATE NOT MET. The deep arm is %.0f%% accurate on the cases with a known",
        100 * dw[["est"]])
    say("answer, below the %.0f%% a reference standard needs. The agreement", 100 * GATE)
    say("figures below are therefore reported as AGREEMENT BETWEEN TWO MODELS")
    say("and NOT as the light arm's reliability: a light case matching the deep")
    say("arm cannot be called right when the deep arm is often wrong.")
    DEEP_IS_STANDARD <- FALSE
  } else {
    say("GATE MET. The deep arm is %s accurate on the known-answer cases,", pct(dw))
    say("so its verdicts on the other %d are usable as a reference standard,", nrow(A))
    say("with that error rate carried into every figure drawn from them.")
    DEEP_IS_STANDARD <- TRUE
  }
  say("Deep over light by %+.1f points on the same %d cases.",
      100 * (dw[["est"]] - lw[["est"]]), nrow(B))
} else {
  say("\nToo few targets (%d) to state an accuracy. Gate cannot be evaluated.", nrow(B))
  DEEP_IS_STANDARD <- FALSE
}

## ============================================================================
h2("Q1  HOW MANY MAYBEs CLEAR TO YES")
## ============================================================================
say("Stratum A only: %d cases drawn simple-random from the MAYBEs with no", nrow(A))
say("prior adjudication. The calibration cases are excluded -- they were")
say("selected by earlier audits, so including them would bias this rate.")
say("\nDeep-arm verdict distribution on those %d:", nrow(A))
print(table(A$d_verdict))

cl_any  <- A[d_verdict == "MATCH"]
cl_conf <- A[d_verdict == "MATCH" & d_conf %in% c("high", "medium")]
cl_ext  <- A[d_verdict == "MATCH" & d_conf %in% c("high", "medium") &
             d_search == "CONFIRMED"]
say("\nclearance to YES, at three thresholds")
say("  any MATCH                        : %s", rate(nrow(cl_any), nrow(A)))
say("  MATCH at medium+ confidence      : %s", rate(nrow(cl_conf), nrow(A)))
say("  + externally CONFIRMED by search : %s", rate(nrow(cl_ext), nrow(A)))

## ---- post-stratification on tie -------------------------------------------
# Stratum A was drawn simple-random, but the realised draw over-sampled ties:
# 75.0% against the tier's 59.1% (binom.test p = 0.009). Ties are the harder
# cases -- npmatch could not separate the top two candidates at all -- so the
# raw rate above is biased DOWNWARD, by roughly 5 points under any plausible
# difference in clearance between tied and untied cases.
#
# `tie` is known for all 1,044 identities, so the fix is post-stratification
# rather than a re-draw: estimate clearance within each tie class and reweight
# by the tier's own proportions. Re-drawing until a sample looks balanced is
# itself a selection rule and would invalidate the intervals.
#
# The variance is the stratified one, sum(W^2 * p(1-p)/n), so a stratum with
# few cases widens the interval instead of silently narrowing it. Where a
# stratum is empty the adjustment is not computed at all.
TIE_W <- c(`TRUE` = NA_real_, `FALSE` = NA_real_)
tie_file <- file.path(DD, "ADJ-EXP-TIEWEIGHTS.rds")
if (file.exists(tie_file)) {
  TIE_W <- readRDS(tie_file)
} else {
  bf <- file.path(PF, "dev", "BASELINE-2026-10C", "benchmark-1k-augmented.rds")
  if (file.exists(bf)) {
    bb <- as.data.table(readRDS(bf))[tier == "MAYBE"]
    TIE_W <- c(`TRUE` = mean(bb$tie, na.rm = TRUE), `FALSE` = mean(!bb$tie, na.rm = TRUE))
  }
}
poststrat <- function(sub, pool) {
  if (any(is.na(TIE_W))) return(NULL)
  est <- 0; var <- 0
  for (lv in c("TRUE", "FALSE")) {
    pl <- pool[as.character(tie) == lv]
    if (!nrow(pl)) return(NULL)
    p <- nrow(sub[as.character(tie) == lv]) / nrow(pl)
    est <- est + TIE_W[[lv]] * p
    var <- var + TIE_W[[lv]]^2 * p * (1 - p) / nrow(pl)
  }
  se <- sqrt(var); z <- qnorm(0.975)
  c(est = est, lo = max(0, est - z * se), hi = min(1, est + z * se), se = se)
}
if (!any(is.na(TIE_W))) {
  say("\ntie-adjusted clearance (post-stratified on the tier's %.1f%% / %.1f%% tie split;",
      100 * TIE_W[["TRUE"]], 100 * TIE_W[["FALSE"]])
  say("this draw of stratum A is %.1f%% ties, so the raw rates above run low)",
      100 * mean(A$tie, na.rm = TRUE))
  for (nm in c("any MATCH", "medium+ conf", "+ confirmed")) {
    sub <- switch(nm, "any MATCH" = cl_any, "medium+ conf" = cl_conf, "+ confirmed" = cl_ext)
    ps  <- poststrat(sub, A)
    raw <- wilson(nrow(sub), nrow(A))
    if (is.null(ps)) { say("  %-14s : not computable (a tie stratum is empty)", nm); next }
    say("  %-14s : %.1f%% (95%% CI %.1f-%.1f)   raw %.1f%%, shift %+.1f pt", nm,
        100 * ps[["est"]], 100 * ps[["lo"]], 100 * ps[["hi"]],
        100 * raw[["est"]], 100 * (ps[["est"]] - raw[["est"]]))
  }
  say("  by tie class, any MATCH:")
  for (lv in c("TRUE", "FALSE")) {
    pl <- A[as.character(tie) == lv]
    if (nrow(pl)) say("    tie=%-5s n=%-3d %s", lv, nrow(pl),
                      rate(nrow(cl_any[as.character(tie) == lv]), nrow(pl)))
  }
}
# Projections use the tie-adjusted estimate where it is computable, because
# that is the better estimate of the tier; the raw one is shown beside it so
# the adjustment is never hidden inside a headline number.
est_for <- function(nm) {
  sub <- switch(nm, "any MATCH" = cl_any, "medium+ conf" = cl_conf, "+ confirmed" = cl_ext)
  ps  <- if (!any(is.na(TIE_W))) poststrat(sub, A) else NULL
  if (!is.null(ps)) list(w = ps, lab = "tie-adj") else
    list(w = wilson(nrow(sub), nrow(A)), lab = "raw")
}
say("\nprojected onto the 1,044-case augmented MAYBE tier")
for (nm in c("any MATCH", "medium+ conf", "+ confirmed")) {
  e <- est_for(nm); w <- e$w
  say("  %-14s : %4.0f cases  (95%% CI %.0f-%.0f)  [%s]", nm,
      1044 * w[["est"]], 1044 * w[["lo"]], 1044 * w[["hi"]], e$lab)
}

say("\nwhat that does to the benchmark's clear rate (4,748 identities, 2,979 YES)")
for (nm in c("any MATCH", "medium+ conf", "+ confirmed")) {
  e <- est_for(nm); w <- e$w
  add <- 1044 * w[["est"]]
  say("  %-14s : %.2f%% -> %.2f%%  (+%.2f points, CI +%.2f to +%.2f)  [%s]", nm,
      100 * 2979 / 4748, 100 * (2979 + add) / 4748, 100 * add / 4748,
      100 * 1044 * w[["lo"]] / 4748, 100 * 1044 * w[["hi"]] / 4748, e$lab)
}
say("\nNOT a precision claim. These are a model's verdicts, carrying the error")
say("rate measured in section (a) above. The ceiling is %.1f%% -- a MAYBE whose",
    100 * nrow(cl_any) / max(1, nrow(A)))
say("recipient is simply not in the BMF cannot be cleared by any reviewer.")
if (!DEEP_IS_STANDARD)
  say("\nAND the gate in (a) did not pass, so treat every figure in this section\nas the deep model's opinion rather than an estimate of what would clear.")
say("\nwhy the rest do not clear:")
print(table(verdict = A[d_verdict != "MATCH"]$d_verdict,
            searched = A[d_verdict != "MATCH"]$d_search))

## ============================================================================
h2("Q2  HOW RELIABLE IS THE LIGHT ADJUDICATOR")
## ============================================================================
say("(b) AGREEMENT with the deep arm, all %d complete cases", nrow(d))
say("\nverdict cross-tab (rows light, columns deep):")
print(table(light = d$l_verdict, deep = d$d_verdict))

kv <- kappa2(d$l_verdict, d$d_verdict)
say("\nverdict agreement : %s", rate(sum(d$l_verdict == d$d_verdict), nrow(d)))
say("  chance agreement: %.1f%% -- two reviewers favouring the same verdict",
    100 * kv$pe)
say("  Cohen's kappa   : %.3f (SE %.3f)%s", kv$k, kv$se,
    if (!is.na(kv$k)) sprintf("  [%s]", if (kv$k >= .8) "near-perfect"
      else if (kv$k >= .6) "substantial" else if (kv$k >= .4) "moderate"
      else if (kv$k >= .2) "fair" else "slight -- barely above chance") else "")

both <- d[l_verdict %in% c("MATCH", "AMBIGUOUS") & d_verdict %in% c("MATCH", "AMBIGUOUS")]
say("\nwhere both named an EIN (%d cases), same EIN: %s", nrow(both),
    rate(sum(both$l_ein == both$d_ein, na.rm = TRUE), nrow(both)))
say("  Agreeing on MATCH while naming different EINs is the dangerous cell:")
say("  %d case(s). Verdict concordance alone would have scored those as agreement.",
    sum(both$l_ein != both$d_ein, na.rm = TRUE))

say("\nthe asymmetry -- which arm is more willing to answer")
say("  light MATCH %.1f%%  NONE %.1f%%  AMBIGUOUS %.1f%%",
    100 * mean(d$l_verdict == "MATCH"), 100 * mean(d$l_verdict == "NONE"),
    100 * mean(d$l_verdict == "AMBIGUOUS"))
say("  deep  MATCH %.1f%%  NONE %.1f%%  AMBIGUOUS %.1f%%",
    100 * mean(d$d_verdict == "MATCH"), 100 * mean(d$d_verdict == "NONE"),
    100 * mean(d$d_verdict == "AMBIGUOUS"))
say("  light MATCH where deep said NONE : %d  (would be false positives)",
    nrow(d[l_verdict == "MATCH" & d_verdict == "NONE"]))
say("  light NONE where deep said MATCH : %d  (recoverable, left on the table)",
    nrow(d[l_verdict == "NONE" & d_verdict == "MATCH"]))

## ---- (c) where it fails ----------------------------------------------------
say("\n")
say("(c) WHERE THE LIGHT ARM FAILS -- the only actionable part")
say("\nAgreement with the deep arm, sliced by the light arm's OWN stated")
say("confidence. If this is flat, the confidence signal is worthless for")
say("routing and a cheap pass cannot be trusted anywhere; if it rises, the")
say("high-confidence subset is a candidate for acceptance without escalation.")
for (cf in c("high", "medium", "low")) {
  s <- d[l_conf == cf]
  if (nrow(s)) say("  light confidence %-6s n=%-3d agree %s", cf, nrow(s),
                   rate(sum(s$l_verdict == s$d_verdict), nrow(s)))
}
say("\nby the light arm's evidence class (QUOTE is meant to be the strongest):")
for (ec in c("QUOTE", "NTEE", "INFER", "NONE")) {
  s <- d[l_class == ec]
  if (nrow(s)) say("  %-6s n=%-3d agree %s", ec, nrow(s),
                   rate(sum(s$l_verdict == s$d_verdict), nrow(s)))
}
say("\nby the structural features the auto-accept rule failed on:")
for (lab in c("tie", "no tie")) {
  s <- d[if (lab == "tie") tie == TRUE else tie == FALSE | is.na(tie)]
  if (nrow(s)) say("  %-8s n=%-3d agree %s", lab, nrow(s),
                   rate(sum(s$l_verdict == s$d_verdict), nrow(s)))
}
d[, mband := cut(overall_margin, c(-Inf, 0, 0.05, 0.15, Inf),
                 labels = c("<=0", "0-0.05", "0.05-0.15", ">0.15"))]
for (mb in levels(d$mband)) {
  s <- d[mband == mb]
  if (nrow(s)) say("  margin %-10s n=%-3d agree %s", mb, nrow(s),
                   rate(sum(s$l_verdict == s$d_verdict), nrow(s)))
}
say("\nby pass (the TOKEN_OVERLAP B-passes are the population npmatch caps")
say("below YES on purpose, and are where the auto-accept rule broke):")
pt <- d[, .(n = .N, agree = sum(l_verdict == d_verdict)), by = pass][order(-n)]
for (k in seq_len(nrow(pt)))
  if (pt$n[k] >= 3) say("  %-18s n=%-3d agree %s", pt$pass[k], pt$n[k],
                        rate(pt$agree[k], pt$n[k]))

if (nrow(B) >= 10) {
  say("\nAccuracy by light confidence, on the known-answer cases only. This is")
  say("the version of the slice above that is accuracy rather than agreement;")
  say("n is small, so read the intervals and not the point estimates.")
  for (cf in c("high", "medium", "low")) {
    s <- B[l_conf == cf]
    if (nrow(s)) say("  light %-6s n=%-3d correct %s", cf, nrow(s),
                     rate(sum(s$l_grade == "CORRECT"), nrow(s)))
  }
}

say("\nwhat search actually bought, where the two arms disagree:")
dis <- d[l_verdict != d_verdict]
say("  %d disagreements of %d (%.1f%%)", nrow(dis), nrow(d),
    100 * nrow(dis) / nrow(d))
if (nrow(dis)) print(table(deep_search = dis$d_search, deep_verdict = dis$d_verdict))
say("\n  A disagreement where the deep arm CONFIRMED its answer externally is")
say("  evidence the light arm was wrong. One marked INCONCLUSIVE is just two")
say("  models differing on the same packet, and is not evidence either way.")
if (nrow(dis)) {
  conf_dis <- nrow(dis[d_search == "CONFIRMED"])
  say("  externally confirmed disagreements: %d of %d", conf_dis, nrow(dis))
}

## ============================================================================
h2("(d) ROUTING -- what a cascade would cost and what it would get")
## ============================================================================
# Section (c) establishes that the light arm's stated confidence orders its
# accuracy. That is only worth anything if it converts into a policy, so the
# policies are priced here rather than left as an exercise.
#
# "Accuracy" below is against the 27 hand-adjudicated cases -- the only real
# target available. It is NOT agreement with the deep arm, because a cascade
# that escalates to the deep arm agrees with it by construction on everything
# it escalates, which would be a meaningless 100%.
#
# Costs are the measured per-case token costs from stages 01 and 02 scaled to
# the full 1,044-case tier. Web search is billed per use on top of the deep
# arm's token cost and is NOT included, so every deep-heavy row is understated.
# Measured per-case token cost INCLUDING cache traffic. The first version of
# this used 0.000625 / 0.03275, which came from an adj_cost() that charged only
# input+output -- and usage.input_tokens is reported exclusive of cached
# tokens, so 495K light and 4.08M deep cache-read tokens were costing nothing
# in the arithmetic. Correcting it moves the light arm +8% and the deep arm
# +25%, which changes every row of the table below.
C_LIGHT <- as.numeric(Sys.getenv("PF_ADJ_COST_LIGHT", "0.000674"))
C_DEEP  <- as.numeric(Sys.getenv("PF_ADJ_COST_DEEP",  "0.040905"))

# One row per policy: which cases the light arm's verdict is kept for, and
# which are escalated. The grade taken is the light arm's where kept and the
# deep arm's where escalated.
policies <- list(
  list(nm = "light only",              esc = function(x) rep(FALSE, nrow(x))),
  list(nm = "escalate low",            esc = function(x) x$l_conf == "low"),
  list(nm = "escalate low + INFER",    esc = function(x) x$l_conf == "low" |
                                                          x$l_class == "INFER"),
  list(nm = "escalate low + medium",   esc = function(x) x$l_conf %in% c("low", "medium")),
  list(nm = "escalate all but QUOTE+high",
       esc = function(x) !(x$l_conf == "high" & x$l_class == "QUOTE")),
  list(nm = "deep only",               esc = function(x) rep(TRUE, nrow(x))))

say("policy                        escalated   cost/1044   accuracy on the 27")
say(strrep("-", 76))
for (p in policies) {
  e_all <- p$esc(d)                       # escalation share over all 100
  e_B   <- p$esc(B)                       # and over the scorable subset
  share <- mean(e_all)
  cost  <- 1044 * (C_LIGHT + share * C_DEEP)
  g     <- ifelse(e_B, B$d_grade, B$l_grade)
  k     <- sum(g == "CORRECT"); n <- length(g)
  say("  %-28s %5.1f%%    $%7.2f    %s", p$nm, 100 * share, cost, rate(k, n))
}
say("\nSearch is billed per use on top of the deep arm's tokens, so every row")
say("with escalation is understated. The deep arm used %.1f searches/case here.",
    mean(dp$searches, na.rm = TRUE))
say("\nWhat the light arm leaves on the table, by its own confidence -- cases it")
say("declined (NONE/AMBIGUOUS) where the deep arm found a MATCH it confirmed:")
for (cf in c("high", "medium", "low")) {
  s <- d[l_conf == cf & l_verdict != "MATCH"]
  if (nrow(s)) say("  %-6s declined %-3d of which deep confirmed a MATCH: %d",
                   cf, nrow(s), nrow(s[d_verdict == "MATCH" & d_search == "CONFIRMED"]))
}

## ---- worked disagreements --------------------------------------------------
h2("WORKED DISAGREEMENTS -- for reading by eye")
show <- dis[order(-(d_search == "CONFIRMED"), l_conf)][seq_len(min(12L, nrow(dis)))]
for (k in seq_len(nrow(show))) {
  r <- show[k]
  say("\n%s  %s (%s)%s", r$grant_id, nz(r$recip_name), nz(r$recip_state),
      if (identical(r$stratum, "B-calibration")) "   [known answer]" else "")
  say("  light %s %s (%s/%s): %s", nz(r$l_verdict), nz(r$l_ein, ""),
      nz(r$l_conf), nz(r$l_class), substr(nz(r$l_evidence, ""), 1, 110))
  say("  deep  %s %s (%s/%s): %s", nz(r$d_verdict), nz(r$d_ein, ""),
      nz(r$d_conf), nz(r$d_search), substr(nz(r$d_evidence, ""), 1, 110))
  if (nzchar(nz(r$d_findings, ""))) say("  found: %s", substr(r$d_findings, 1, 150))
  if (!is.na(r$target))
    say("  TRUTH: %s -> correct answer %s (ein %s, in packet: %s)",
        r$truth_verdict, r$target, nz(r$correct_ein), r$truth_in_packet)
}

## ---- write -----------------------------------------------------------------
saveRDS(d, file.path(DD, sprintf("ADJ-EXP-SCORED%s.rds", TAG)))
fwrite(d,  file.path(DD, sprintf("ADJ-EXP-SCORED%s.csv", TAG)))
hr()
say("wrote data-dev/ADJ-EXP-SCORED%s.rds (%d cases, %d columns)", TAG, nrow(d), ncol(d))
say("wrote %s", LOGF)
hr()
close_log()
