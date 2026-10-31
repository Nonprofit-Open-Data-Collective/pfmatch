#!/usr/bin/env Rscript
# ============================================================================
# adjudicate-06-calib-score.R -- settle the ablation on ~200 labelled cases.
#
# dev/ADJ-EXP-ABLATION.log reached its conclusion on 27 hand-adjudicated cases,
# where one case is 3.7 points and none of the three McNemar tests came close
# to significance (model p = 0.687, search p = 1.000). The direction was
# consistent across accuracy, clearance and cost -- enough to act on, not
# enough to settle. This runs the same three arms over the calibration packet
# and pools the paired comparisons.
#
# WHAT POOLING IS AND IS NOT VALID FOR, which is the whole design:
#
#   VALID    the PAIRED tests. McNemar uses only cases where two arms disagree
#            and asks which is right more often on those. Adding heterogeneous
#            strata adds concordant pairs, which the test discards. So pooling
#            the calibration strata with the experiment's 27 is legitimate and
#            is where the power comes from.
#
#   NOT VALID a single pooled accuracy. The calibration strata are three
#            separately-drawn label sets, one of them deliberately subsampled
#            (dev/adjudicate-05-calib-packet.R, note 2). Accuracy is therefore
#            reported WITHIN stratum and never as one number. The only
#            unbiased tier-level figure remains stratum A of the experiment.
#
# It also re-tests the thing the routing policy rests on. That policy comes
# from high 12/12, medium 10/11, low 0/4 -- n = 4 in the tier that decides
# whether to escalate. If confidence does not order accuracy at n = 200, the
# cascade recommendation does not survive, whatever the ablation says.
#
# OUTPUT  dev/ADJ-CAL-RESULTS.log
# USAGE   Rscript dev/adjudicate-06-calib-score.R
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
DD <- file.path(PF, "data-dev")

say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() cat(strrep("=", 78), "\n")
h2  <- function(s) { cat("\n"); cat(strrep("-", 78), "\n"); cat(s, "\n")
                     cat(strrep("-", 78), "\n") }
wilson <- function(k, n, conf = 0.95) {
  if (n == 0) return(c(est = NA, lo = NA, hi = NA))
  z <- qnorm(1 - (1 - conf) / 2); p <- k / n; d <- 1 + z^2 / n
  c(est = p,
    lo = max(0, (p + z^2 / (2 * n) - z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2))) / d),
    hi = min(1, (p + z^2 / (2 * n) + z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2))) / d))
}
rate <- function(k, n) { w <- wilson(k, n)
  sprintf("%3d/%-3d = %5.1f%% (95%% CI %.1f-%.1f)", k, n, 100 * w[["est"]],
          100 * w[["lo"]], 100 * w[["hi"]]) }
e9 <- function(x) { v <- gsub("[^0-9]", "", as.character(x))
                    ifelse(nchar(v) == 9L, v, NA_character_) }
nz <- function(x, alt = "-") { if (is.null(x) || length(x) == 0L) return(alt)
  x <- as.character(x)[1]; if (is.na(x) || !nzchar(x)) alt else x }

# Exact McNemar on the discordant pairs, with the detail needed to read it.
mcnemar <- function(x, y, lab) {
  ok <- !is.na(x) & !is.na(y)
  x <- x[ok]; y <- y[ok]
  b  <- sum(x == "CORRECT" & y != "CORRECT")    # x right, y wrong
  c_ <- sum(x != "CORRECT" & y == "CORRECT")    # y right, x wrong
  n  <- b + c_
  p  <- if (n == 0) NA_real_ else stats::binom.test(c_, n, 0.5)$p.value
  say("  %-26s %3d gained, %3d lost, %3d discordant, p = %s", lab, c_, b, n,
      if (is.na(p)) "n/a" else sprintf("%.4f", p))
  invisible(c(gained = c_, lost = b, n = n, p = p))
}

## ---- load ------------------------------------------------------------------
need <- c("ADJ-CAL-LIGHT.rds", "ADJ-CAL-DEEP.rds", "ADJ-CAL-DEEP-nosearch.rds",
          "ADJ-CAL-CASES.rds", "ADJ-CAL-TRUTH.rds")
miss <- need[!file.exists(file.path(DD, need))]
if (length(miss))
  stop(sprintf("missing: %s\n  Run, in order:\n    Rscript dev/adjudicate-05-calib-packet.R\n    PF_ADJ_SET=cal Rscript dev/adjudicate-01-light.R\n    PF_ADJ_SET=cal Rscript dev/adjudicate-02-deep.R\n    PF_ADJ_SET=cal PF_ADJ_NOSEARCH=1 PF_ADJ_TAG=-nosearch Rscript dev/adjudicate-02-deep.R",
               paste(miss, collapse = ", ")), call. = FALSE)

sink(file.path(PF, "dev", "ADJ-CAL-RESULTS.log"), split = TRUE)
close_log <- function() while (sink.number() > 0L) sink()

hr(); say("CALIBRATION -- the ablation on ~200 labelled cases"); hr()

grab <- function(f, pfx) {
  x <- as.data.table(readRDS(file.path(DD, f)))
  keep <- c("grant_id", "verdict", "ein", "confidence", "evidence_class",
            "evidence", "api_ok")
  o <- x[, ..keep]
  setnames(o, setdiff(keep, "grant_id"), paste0(pfx, "_", setdiff(keep, "grant_id")))
  o[[paste0(pfx, "_ein")]] <- e9(o[[paste0(pfx, "_ein")]])
  for (extra in c("searches", "search_confirmed"))
    if (!is.null(x[[extra]])) o[[paste0(pfx, "_", extra)]] <- x[[extra]]
  o
}
L <- grab("ADJ-CAL-LIGHT.rds", "l")
N <- grab("ADJ-CAL-DEEP-nosearch.rds", "n")
S <- grab("ADJ-CAL-DEEP.rds", "s")
cs <- as.data.table(readRDS(file.path(DD, "ADJ-CAL-CASES.rds")))
tr <- as.data.table(readRDS(file.path(DD, "ADJ-CAL-TRUTH.rds")))

d <- merge(merge(L, N, by = "grant_id"), S, by = "grant_id")
d <- merge(d, cs[, .(grant_id, stratum, batch_order, recip_name, recip_state)],
           by = "grant_id")
d <- merge(d, tr[, .(grant_id, target, correct_ein, truth_in_packet,
                     label_source, label_detail)], by = "grant_id")
setorder(d, batch_order)
say("cases with all three arms: %d", nrow(d))
d <- d[l_api_ok == TRUE & n_api_ok == TRUE & s_api_ok == TRUE &
       !is.na(l_verdict) & !is.na(n_verdict) & !is.na(s_verdict)]
say("complete on all three  : %d", nrow(d))
say("no-search arm searches (must be 0): %d", sum(d$n_searches, na.rm = TRUE))

grade <- function(v, ein, target, correct) {
  ifelse(is.na(target), NA_character_,
  ifelse(target == "MATCH",
    ifelse(v == "MATCH"     & !is.na(ein) & ein == correct, "CORRECT",
    ifelse(v == "AMBIGUOUS" & !is.na(ein) & ein == correct, "AMBIGUOUS_RIGHT",
    ifelse(v == "NONE", "MISS", "WRONG"))),
    ifelse(v == "NONE", "CORRECT",
    ifelse(v == "AMBIGUOUS", "AMBIGUOUS_WRONG", "WRONG"))))
}
for (a in c("l", "n", "s"))
  d[[paste0(a, "_grade")]] <- grade(d[[paste0(a, "_verdict")]],
      d[[paste0(a, "_ein")]], d$target, d$correct_ein)

arms <- list(c("l", "light  Haiku, packet"), c("n", "deep-  Opus, packet"),
             c("s", "deep+  Opus + search"))

## ============================================================================
h2("1. ACCURACY WITHIN STRATUM -- never pooled, and here is why")
## ============================================================================
say("%d cases: %s\n", nrow(d), paste(sprintf("%s=%d", names(table(d$stratum)),
                                             table(d$stratum)), collapse = "  "))
say("%-22s %-28s %-28s %s", "stratum (n)", "light", "deep-", "deep+")
for (st in sort(unique(d$stratum))) {
  s <- d[stratum == st]
  say("  %-20s %s  %s  %s", sprintf("%s (%d)", substr(st, 1, 14), nrow(s)),
      rate(sum(s$l_grade == "CORRECT"), nrow(s)),
      rate(sum(s$n_grade == "CORRECT"), nrow(s)),
      rate(sum(s$s_grade == "CORRECT"), nrow(s)))
}
say("\nThe E stratum is cases a geographic rule already got right, so every arm")
say("should score high there and it carries little information. H is the rule's")
say("failures and M a broader MAYBE draw: those are where the arms separate.")
say("A single pooled accuracy over these three would be an artefact of the mix.")

say("\ntarget mix per stratum (MATCH means the right EIN is among the candidates)")
print(table(stratum = d$stratum, target = d$target))

## ============================================================================
h2("2. THE PAIRED TESTS -- valid pooled, and this is the power")
## ============================================================================
say("calibration set alone, %d cases", nrow(d))
m_cal <- mcnemar(d$l_grade, d$n_grade, "model   light -> deep-")
s_cal <- mcnemar(d$n_grade, d$s_grade, "search  deep- -> deep+")
t_cal <- mcnemar(d$l_grade, d$s_grade, "total   light -> deep+")

# Pool with the experiment's 27, which ran the same three arms on the same
# schema. Different packet, same task and same arms, so the pairs are
# comparable even though the samples are not.
ef <- file.path(DD, c("ADJ-EXP-LIGHT.rds", "ADJ-EXP-DEEP-nosearch.rds",
                      "ADJ-EXP-DEEP.rds", "ADJ-EXP-TRUTH.rds"))
if (all(file.exists(ef))) {
  eL <- grab("ADJ-EXP-LIGHT.rds", "l"); eN <- grab("ADJ-EXP-DEEP-nosearch.rds", "n")
  eS <- grab("ADJ-EXP-DEEP.rds", "s")
  etr <- as.data.table(readRDS(file.path(DD, "ADJ-EXP-TRUTH.rds")))
  e <- merge(merge(eL, eN, by = "grant_id"), eS, by = "grant_id")
  e <- merge(e, etr[, .(grant_id, truth_verdict, correct_ein = e9(correct_ein),
                        truth_in_packet, adjudicable)], by = "grant_id")
  e[, target := NA_character_]
  e[adjudicable == TRUE & truth_verdict == "ORG_FOUND" & truth_in_packet == TRUE,
    target := "MATCH"]
  e[adjudicable == TRUE & truth_verdict == "ORG_FOUND" & truth_in_packet == FALSE,
    target := "NONE"]
  e[adjudicable == TRUE & grepl("^NO_ORG", truth_verdict), target := "NONE"]
  e <- e[!is.na(target)]
  for (a in c("l", "n", "s"))
    e[[paste0(a, "_grade")]] <- grade(e[[paste0(a, "_verdict")]],
        e[[paste0(a, "_ein")]], e$target, e$correct_ein)
  say("\npooled with the experiment's %d scorable cases = %d paired cases",
      nrow(e), nrow(d) + nrow(e))
  pg <- function(a) c(d[[paste0(a, "_grade")]], e[[paste0(a, "_grade")]])
  m_all <- mcnemar(pg("l"), pg("n"), "model   light -> deep-")
  s_all <- mcnemar(pg("n"), pg("s"), "search  deep- -> deep+")
  t_all <- mcnemar(pg("l"), pg("s"), "total   light -> deep+")
} else {
  say("\n(experiment arms not all present; calibration set only)")
  m_all <- m_cal; s_all <- s_cal; t_all <- t_cal
}

say("\nwhat the sample can now resolve")
# list(), not c(): c("model", m_all) flattens the named numeric vector into a
# character one and the names go with it.
steps <- list(list(nm = "model", v = m_all), list(nm = "search", v = s_all),
              list(nm = "total", v = t_all))
for (z in steps) {
  nm <- z$nm; v <- z$v
  dir <- if (is.na(v[["p"]]) || v[["n"]] == 0) "" else
    sprintf(" -- %s", if (v[["gained"]] > v[["lost"]]) "the second arm is better"
            else if (v[["gained"]] < v[["lost"]]) "THE SECOND ARM IS WORSE"
            else "a dead heat")
  say("  %-7s %d discordant pairs -> %s%s", nm, v[["n"]],
      if (is.na(v[["p"]])) "no evidence either way" else
      if (v[["p"]] < 0.05) sprintf("SIGNIFICANT at 0.05 (p = %.4f)", v[["p"]]) else
        sprintf("not significant (p = %.4f)", v[["p"]]), dir)
}
# The smallest split of a given number of discordant pairs that would reach
# p<0.05 -- the honest statement of what this n can and cannot detect.
mde <- function(n) { if (n < 6) return(NA_integer_)
  for (k in seq(ceiling(n/2), n)) if (stats::binom.test(k, n, 0.5)$p.value < 0.05) return(k)
  NA_integer_ }
say("\n  minimum detectable split at 0.05, given the discordant pairs observed:")
for (z in steps) {
  v <- z$v; k <- mde(v[["n"]])
  say("    %-7s n=%-3d needs %s", z$nm, v[["n"]],
      if (is.na(k)) "more pairs than exist -- underpowered at any split" else
        sprintf("%d of %d one way (observed %d gained / %d lost)", k, v[["n"]],
                v[["gained"]], v[["lost"]]))
}

## ============================================================================
h2("3. DOES CONFIDENCE STILL ORDER ACCURACY? -- the routing policy's premise")
## ============================================================================
say("The cascade rests on the light arm's own confidence separating its right")
say("answers from its wrong ones. At n=27 that was high 12/12, medium 10/11,")
say("low 0/4 -- four cases deciding the escalation tier. Re-tested here.\n")
for (a in arms) {
  say("%s", a[2])
  for (cf in c("high", "medium", "low")) {
    s <- d[get(paste0(a[1], "_confidence")) == cf]
    if (nrow(s)) say("  %-6s %s", cf, rate(sum(s[[paste0(a[1], "_grade")]] == "CORRECT"), nrow(s)))
  }
}
say("\nlight arm by evidence class")
for (ec in c("QUOTE", "NTEE", "INFER", "NONE")) {
  s <- d[l_evidence_class == ec]
  if (nrow(s)) say("  %-6s %s", ec, rate(sum(s$l_grade == "CORRECT"), nrow(s)))
}
lh <- d[l_confidence %in% c("high", "medium")]; ll <- d[l_confidence == "low"]
if (nrow(lh) && nrow(ll)) {
  tt <- stats::fisher.test(matrix(c(sum(lh$l_grade == "CORRECT"), nrow(lh) - sum(lh$l_grade == "CORRECT"),
                                    sum(ll$l_grade == "CORRECT"), nrow(ll) - sum(ll$l_grade == "CORRECT")), 2))
  say("\nhigh+medium vs low, Fisher exact: p = %.5f  %s", tt$p.value,
      if (tt$p.value < 0.05) "-- confidence DOES separate right from wrong" else
        "-- confidence does NOT separate; the routing policy loses its premise")
}

## ============================================================================
h2("4. PRECISION ON WHAT EACH ARM CLEARS -- what the vignette needs")
## ============================================================================
# Clearance alone overstates what a tier delivers: a MAYBE cleared to the wrong
# EIN is not a match, it is a silent error that is never reviewed again. The
# quantity that matters for an overall match rate is
#
#     YES + (MAYBE x clearance x precision-on-cleared)
#
# and precision-on-cleared is NOT the same as overall accuracy -- it is
# accuracy restricted to the cases the arm actually said MATCH to. An arm that
# clears cautiously can have poor overall accuracy and excellent precision on
# the subset it commits to, which is exactly the shape a cascade exploits.
say("Among the cases each arm called MATCH, how often was that the right EIN?")
say("(target-bearing cases only; a MATCH where the target is NONE is an error)\n")
say("%-22s %-30s %s", "arm", "precision on its own MATCHes", "share it called MATCH")
for (a in arms) {
  v <- d[[paste0(a[1], "_verdict")]]; g <- d[[paste0(a[1], "_grade")]]
  mm <- v == "MATCH"
  say("  %-20s %s   %5.1f%%", a[2],
      rate(sum(mm & g == "CORRECT"), sum(mm)), 100 * mean(mm))
}
say("\nsame, within the two informative strata")
for (st in c("M-maybe-random", "H-hard-rule-failed")) {
  s <- d[stratum == st]
  if (!nrow(s)) next
  say("  %s (n=%d)", st, nrow(s))
  for (a in arms) {
    v <- s[[paste0(a[1], "_verdict")]]; g <- s[[paste0(a[1], "_grade")]]
    if (sum(v == "MATCH")) say("    %-20s %s", a[2],
        rate(sum(v == "MATCH" & g == "CORRECT"), sum(v == "MATCH")))
  }
}
say("\nand restricted to high+medium confidence, which is what a cascade accepts")
for (a in arms) {
  cf <- d[[paste0(a[1], "_confidence")]]; v <- d[[paste0(a[1], "_verdict")]]
  g <- d[[paste0(a[1], "_grade")]]
  mm <- v == "MATCH" & cf %in% c("high", "medium")
  if (sum(mm)) say("  %-20s %s   (%5.1f%% of all cases)", a[2],
      rate(sum(mm & g == "CORRECT"), sum(mm)), 100 * mean(mm))
}

## ============================================================================
h2("5. THE CASCADE, re-priced on this sample")
## ============================================================================
source(file.path(PF, "dev", "adjudicate-lib.R"))
cost1 <- function(f) { x <- as.data.table(readRDS(file.path(DD, f)))
  adj_cost(x$model[1], sum(x$in_tokens), sum(x$out_tokens),
           sum(x$cache_read), sum(x$cache_write)) / nrow(x) }
CL <- cost1("ADJ-CAL-LIGHT.rds"); CN <- cost1("ADJ-CAL-DEEP-nosearch.rds")
CS <- cost1("ADJ-CAL-DEEP.rds")
say("measured per-case token cost on this run")
say("  light %.6f   deep- %.6f   deep+ %.6f", CL, CN, CS)
MB <- 1008713
esc <- d$l_confidence == "low"
say("\nescalating the light arm's low-confidence %d of %d (%.1f%%):",
    sum(esc), nrow(d), 100 * mean(esc))
for (z in list(c("n", "deep-, no search", CN), c("s", "deep+, with search", CS))) {
  g <- ifelse(esc, d[[paste0(z[1], "_grade")]], d$l_grade)
  say("  escalate low -> %-18s %s   $%s over the tier", z[2],
      rate(sum(g == "CORRECT"), nrow(d)),
      format(round(MB * CL + mean(esc) * MB * as.numeric(z[3])), big.mark = ","))
}
say("  light only, no escalation   %s   $%s", rate(sum(d$l_grade == "CORRECT"), nrow(d)),
    format(round(MB * CL), big.mark = ","))
for (z in list(c("n", "deep-, no search", CN), c("s", "deep+, with search", CS)))
  say("  %-28s %s   $%s", sprintf("%s on everything", z[2]),
      rate(sum(d[[paste0(z[1], "_grade")]] == "CORRECT"), nrow(d)),
      format(round(MB * as.numeric(z[3])), big.mark = ","))
say("\n(Tier-wide dollars use the %s projected MAYBE identities and this run's",
    format(MB, big.mark = ","))
say(" measured per-case costs. The ACCURACIES beside them are this sample's,")
say(" which is not a sample of that tier -- they rank the policies, they do not")
say(" predict the tier's accuracy.)")

## ---- where search still earns its place ------------------------------------
h2("6. CASES WHERE SEARCH FLIPPED A WRONG ANSWER RIGHT")
fx <- d[n_grade != "CORRECT" & s_grade == "CORRECT"]
bk <- d[n_grade == "CORRECT" & s_grade != "CORRECT"]
say("search fixed %d, broke %d", nrow(fx), nrow(bk))
for (lab in list(list("FIXED", fx), list("BROKE", bk))) {
  if (!nrow(lab[[2]])) next
  say("\n--- %s ---", lab[[1]])
  sh <- lab[[2]][seq_len(min(6L, nrow(lab[[2]])))]
  for (k in seq_len(nrow(sh))) {
    r <- sh[k]
    say("\n%s  %s  [%s, %s]", r$grant_id, nz(r$recip_name), r$stratum, r$label_detail)
    say("  target %s %s", r$target, nz(r$correct_ein, ""))
    say("  deep- %s %s -> %s", nz(r$n_verdict), nz(r$n_ein, ""), nz(r$n_grade))
    say("  deep+ %s %s (%s) -> %s", nz(r$s_verdict), nz(r$s_ein, ""),
        nz(r$s_search_confirmed), nz(r$s_grade))
    if (nzchar(nz(r$s_evidence, ""))) say("  %s", substr(r$s_evidence, 1, 120))
  }
}

saveRDS(d, file.path(DD, "ADJ-CAL-SCORED.rds"))
fwrite(d,  file.path(DD, "ADJ-CAL-SCORED.csv"))
hr(); say("wrote dev/ADJ-CAL-RESULTS.log and data-dev/ADJ-CAL-SCORED.{rds,csv}"); hr()
close_log()
