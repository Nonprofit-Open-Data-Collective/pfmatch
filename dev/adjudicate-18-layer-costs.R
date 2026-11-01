#!/usr/bin/env Rscript
# ============================================================================
# adjudicate-18-layer-costs.R -- what each adjudication layer costs at corpus
# scale, and what it buys.
#
# Every figure in dev/DEVELOPMENT-PLAN.md section "Phase 4b" is printed by this
# script rather than typed into the prose. That is not ceremony: this project
# has already shipped two wrong cost figures, both from hand-copying a number
# out of a run log (adj_cost() missing cache reads, then C_DEEP missing cache
# writes -- a 66% understatement that survived review because it looked
# plausible). A number that cannot be re-derived by running a file is a number
# nobody can check.
#
# INPUTS, all measured elsewhere in this repo and cited at point of use. None
# of them is estimated here.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() cat(strrep("=", 78), "\n")
usd <- function(x) paste0("$", formatC(round(x), format = "d", big.mark = ","))
nf  <- function(x) formatC(round(x), format = "d", big.mark = ",")

## ---- the corpus ------------------------------------------------------------
# dev/EFILEPF-DEDUP.log and dev/FULL-01-PREPARE.log. The 3.72x collapse is
# measured on a 12.56M-grant run, not extrapolated from a sample -- an earlier
# 1.8x estimate from a 100k sample was wrong by a factor of two.
ROWS      <- 17253199
IN_SCOPE  <- round(ROWS * 0.988)
COLLAPSE  <- 3.72
IDENT     <- round(IN_SCOPE / COLLAPSE)

# Tier shares on the IN-SCOPE denominator of 4,868, from
# dev/NO-TIER-EXPERIMENT.md "The denominator, which turned out to be part of
# the answer". Note NO = 845, not the baseline's 725: BASELINE-2026-10C's
# 4,748 "identities" are the result frame, which silently drops the 120
# in-scope identities no blocking pass produced a pair for. Those are the
# hardest retrieval failures in the file, so a NO-tier budget built on 725
# under-counts the tier by 14%.
BENCH_IN  <- 4868
BENCH     <- c(YES = 2979, MAYBE = 1044, NO = 845)
stopifnot(sum(BENCH) + 35 == 4903)          # +35 OOS = the full status table

share <- BENCH / BENCH_IN
n_tier <- round(IDENT * share)

hr(); say("CORPUS"); hr()
say("%s grant rows -> %s in scope -> %s identities at the measured %.2fx collapse",
    nf(ROWS), nf(IN_SCOPE), nf(IDENT), COLLAPSE)
print(data.table(tier = names(BENCH), bench_n = as.integer(BENCH),
                 share = sprintf("%.2f%%", 100 * share),
                 projected = nf(n_tier)), row.names = FALSE)

## ---- measured per-case costs -----------------------------------------------
# MAYBE arms: dev/ADJUDICATION-EXPERIMENT.md "Cost, which is where this lands".
# Cache traffic included in all three -- input_tokens excludes cached tokens,
# which is what made the first two figures wrong.
# NO arms: dev/NO-TIER-EXPERIMENT.md section 7. Haiku's figure is tiered: it
# prices a request by its WHOLE prompt, and 22 of 100 cases crossed the 100K
# step, so banking the run against the cheap rate would report ~$0.46 for the
# 100 instead of $1.308.
SEARCH_USD <- 0.01     # $10 per 1,000 searches, list price

arms <- rbindlist(list(
  data.table(tier = "MAYBE", arm = "light: Haiku, packet only",
             usd_case = 0.000674, searches = 0,    acc = "81.5% (22/27)",
             clears   = "55.9%"),
  data.table(tier = "MAYBE", arm = "deep-: Opus, packet only",
             usd_case = 0.030265, searches = 0,    acc = "88.9% (24/27)",
             clears   = "72.1%"),
  data.table(tier = "MAYBE", arm = "deep+: Opus + web search",
             usd_case = 0.067765, searches = 2.2,  acc = "92.6% (25/27)",
             clears   = "69.1%"),
  data.table(tier = "NO",    arm = "Haiku + web search",
             usd_case = 0.0131,   searches = 4.4,  acc = "30/91 recovered",
             clears   = "33.0%"),
  data.table(tier = "NO",    arm = "Opus + web search",
             usd_case = 0.0669,   searches = 3.2,  acc = "33/91 recovered",
             clears   = "36.3%")))

arms[, n := ifelse(tier == "MAYBE", n_tier[["MAYBE"]], n_tier[["NO"]])]
arms[, `:=`(tok = usd_case * n, srch_n = searches * n)]
arms[, srch := srch_n * SEARCH_USD]
arms[, total := tok + srch]

hr(); say("WHOLE-TIER COST, token billing and search billing separated"); hr()
print(arms[, .(tier, arm, n = nf(n), tokens = usd(tok),
               searches = nf(srch_n), search_bill = usd(srch),
               TOTAL = usd(total))], row.names = FALSE)

## ---- the thing the per-case ratio hides ------------------------------------
# The NO experiment reported Haiku as "5.1x cheaper, not the 40x the sticker
# prices suggest". That was a TOKEN ratio, and it was the honest number for
# what it measured. At tier scale it is not the bill: Haiku ran 37% MORE
# searches than Opus, searches are billed per use, and on this tier they are
# the larger half of the invoice.
hr(); say("THE RATIO THAT MATTERS IS NOT THE TOKEN RATIO"); hr()
h <- arms[arm == "Haiku + web search"]; o <- arms[arm == "Opus + web search"]
say("NO tier, %s identities", nf(h$n))
say("  tokens only : Haiku %s vs Opus %s  -> Opus costs %.1fx",
    usd(h$tok), usd(o$tok), o$tok / h$tok)
say("  full bill   : Haiku %s vs Opus %s  -> Opus costs %.2fx",
    usd(h$total), usd(o$total), o$total / h$total)
say("  search is %.0f%% of Haiku's bill and %.0f%% of Opus's",
    100 * h$srch / h$total, 100 * o$srch / o$total)
say("")
say("So on this tier the model choice is worth %s and the search budget is",
    usd(o$total - h$total))
say("worth %s. Capping max_uses is the lever; picking the cheap model is not.",
    usd(h$srch))
say("")
# Batch API halves token billing. Whether per-use search billing is discounted
# is NOT established here and must not be assumed -- the honest form is to show
# the token discount only and label the rest.
say("With the Batch API's 50%% discount applied to TOKENS ONLY (search billing")
say("at list -- the batch discount on per-use server tools is not established")
say("in this repo and is not assumed here):")
arms[, batch := tok / 2 + srch]
print(arms[, .(tier, arm, synchronous = usd(total), batch_tokens = usd(batch))],
      row.names = FALSE)

## ---- the MAYBE cascade -----------------------------------------------------
# dev/ADJUDICATION-EXPERIMENT.md Q2 + the ablation. Escalate on the LIGHT arm's
# own stated confidence: high 12/12, medium 10/11, low 0/4 against known
# answers, so the 18% it calls `low` is where the errors are.
ESC <- 0.18
hr(); say("MAYBE CASCADE: light everywhere, escalate the light arm's own `low`"); hr()
nm <- n_tier[["MAYBE"]]
casc <- rbindlist(list(
  data.table(policy = "light only",
             tok = 0.000674 * nm, srch_n = 0, acc = "81.5% (22/27)"),
  data.table(policy = "escalate low -> deep- (no search)",
             tok = 0.000674 * nm + 0.030265 * nm * ESC, srch_n = 0,
             acc = "96.3% (26/27)"),
  data.table(policy = "escalate low -> deep+ (search)",
             tok = 0.000674 * nm + 0.067765 * nm * ESC, srch_n = 2.2 * nm * ESC,
             acc = "96.3% (26/27)"),
  data.table(policy = "deep+ everywhere",
             tok = 0.067765 * nm, srch_n = 2.2 * nm, acc = "92.6% (25/27)")))
casc[, total := tok + srch_n * SEARCH_USD]
print(casc[, .(policy, tokens = usd(tok), searches = nf(srch_n),
               TOTAL = usd(total), acc)], row.names = FALSE)
say("")
say("Escalating to the NO-SEARCH deep arm reaches the same 26/27 as the search")
say("arm for %s instead of %s. The +3.7 points search adds on the 27 is one",
    usd(casc$total[2]), usd(casc$total[3]))
say("case (McNemar exact p = 1.000) -- not distinguishable from zero, and not")
say("ruled out either. What search measurably buys is CONFIDENCE (high 51%% ->")
say("73%%), which is not the thing being paid for.")

## ---- layer 0, which costs nothing ------------------------------------------
# dev/NO-EXP-16-fuzzy.log, cutoff 0.90, on the 4,868-identity in-scope run
# against the matchdb active-observed tier.
hr(); say("LAYER 0 -- deterministic character recovery, no API at all"); hr()
FZ_SEC <- 521; MATCH_SEC <- 5830
say("pf_fuzzy_recover() at the 0.90 default: %d s, %.1f%% of the %d s match",
    FZ_SEC, 100 * FZ_SEC / MATCH_SEC, MATCH_SEC)
say("  +24 identities to YES on 2,009 residual; 0 YES identities broken")
say("  reaches 3 of the 33 web-established EINs, agrees on 2, contradicts 1")
say("  marginal cost per corpus run: %s", usd(0))
say("")
say("Projected to %s identities the scan is ~%.0f core-hours, which is",
    nf(IDENT), FZ_SEC / 3600 * IDENT / BENCH_IN)
say("compute, not billing. Against %s for the cheapest LLM layer on MAYBE",
    usd(casc$total[1]))
say("alone, it is the only layer whose cost does not scale with the corpus.")
hr()
