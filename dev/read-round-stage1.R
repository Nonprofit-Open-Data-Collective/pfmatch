#!/usr/bin/env Rscript
# ============================================================================
# read-round-stage1.R -- read stage 1 back, and say what it measures.
#
# All 400 cases now carry truth: shard 1 from claude-fable-5-1 on every case,
# shards 2-5 from the high-only gate (dev/gate-shard-truth.R). This reads the
# five shards through pf_read_truth(), takes the blinded overlap through
# pf_labeler_agreement(), and derives the one figure the round was built for --
# how often the cascade's MAYBE pick is the right EIN.
#
# THE OVERLAP IS NOT ONE COMPARISON, AND IS NOT REPORTED AS ONE. Shard 1 is
# all-fable; shards 2-5 are a two-model pipeline. So a case shared between
# shard 1 and shard 3 is fable-vs-fable where shard 3 escalated it and
# fable-vs-haiku where shard 3 accepted haiku's `high` row -- two different
# measurements that pf_labeler_agreement() would pool into one rate. The
# `model` column exists so they can be separated, and they are separated here,
# because a blended rate over a heterogeneous denominator is exactly the defect
# dev/PLAUSIBLE-WRONG-NUMBERS.md catalogues. Each subset is small; that is
# reported rather than hidden by pooling.
#
# USAGE  Rscript dev/read-round-stage1.R
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
DD  <- file.path(PF, "data-dev")
DIR <- file.path(DD, "round-stage1-labelled")

say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() cat(strrep("=", 78), "\n")
hr(); say("ADJUDICATION ROUND, STAGE 1 -- READ-OUT"); hr()

## ---- the five shards -------------------------------------------------------
f1 <- file.path(DIR, "shard-01-truth-claude-fable-5-1-truth-01.csv")
rd <- function(p, m) {
  d <- as.data.table(utils::read.csv(p, colClasses = "character"))
  if (is.null(d$model)) d[, model := m]
  d
}
parts <- c(list(rd(f1, "pass2")),
           lapply(2:5, function(s)
             rd(file.path(DIR, sprintf("shard-%02d-truth-GATED.csv", s)), NA)))
all <- rbindlist(parts, fill = TRUE)
say("%d label-rows over %d cases", nrow(all), uniqueN(all$grant_id))

key <- as.data.table(utils::read.csv(
  file.path(DD, "round-stage1-key", "SHARD-KEY.csv"), colClasses = "character"))
cols <- pf_shard_schema()
say("")
v <- pf_read_truth(as.data.frame(all[, ..cols]), key = key,
                   population = unique(all$population)[1L], verbose = TRUE)

## ---- the blinded overlap ---------------------------------------------------
say("")
hr(); say("THE BLINDED OVERLAP"); hr()
ag <- pf_labeler_agreement(v)
print(ag)

## ---- and what it is actually made of --------------------------------------
# The pooled rate above spans two comparisons. Split them.
ov <- all[, .N, by = grant_id][N > 1L, grant_id]
o  <- all[grant_id %in% ov]
setorder(o, grant_id, shard)
pair <- o[, .(models = paste(sort(model), collapse = "-vs-"),
              agree = uniqueN(paste(verdict, correct_ein)) == 1L,
              n_lab = uniqueN(labeler)), by = grant_id]
say("\nthe %d overlap cases, by which models actually produced the two rows:",
    nrow(pair))
sub <- pair[, .(n = .N, agree = sum(agree)), by = models][order(-n)]
sub[, rate := sprintf("%.0f%%", 100 * agree / n)]
sub[, usable := ifelse(n >= 20L, "yes", "no (n<20)")]
print(sub)
say("\nEach subset is a different question. pass2-vs-pass2 is two runs of ONE")
say("procedure (fable twice, once as shard 1 and once as an escalation), which")
say("is run-to-run stability. Anything involving pass1 is cross-model. Neither")
say("is accuracy.")

## ---- the figure the round exists for ---------------------------------------
say("")
hr(); say("MAYBE-TIER PICK PRECISION, ALL 400 CASES"); hr()
cas <- rbindlist(lapply(1:5, function(s) as.data.table(utils::read.csv(
  file.path(DD, "round-stage1", sprintf("shard-%02d-cases.csv", s)),
  colClasses = "character"))), fill = TRUE)
cas <- unique(cas, by = "grant_id")

# One row per CASE, not per label-row: an overlap case would otherwise count
# twice, and its two labels can disagree. Prefer the all-fable reading where
# both exist, so the precision figure rests on one procedure rather than on
# whichever shard happened to sort first.
lab <- unique(all[order(model != "pass2")], by = "grant_id")
d <- merge(lab[, .(grant_id, verdict, correct_ein, wrong_ein, confidence, model)],
           cas[, .(grant_id, cascade_ein, cascade_pass, purpose_band)],
           by = "grant_id")
nz <- function(x) gsub("[^0-9]", "", ifelse(is.na(x), "", x))
d[, `:=`(pick = nz(cascade_ein), got = nz(correct_ein))]
say("%d cases, deduplicated to one label each", nrow(d))

say("\nverdicts:")
print(table(verdict = d$verdict))

sc <- d[verdict != "UNRESOLVED"]
sc[, right := verdict == "ORG_FOUND" & nzchar(got) & got == pick]
w <- pf_wilson(sum(sc$right), nrow(sc))
say("\nscoreable %d (dropped %d UNRESOLVED)", nrow(sc), nrow(d) - nrow(sc))
say("pick precision: %d/%d = %.1f%% [%.1f, %.1f]",
    sum(sc$right), nrow(sc), 100 * mean(sc$right),
    100 * w[1, "lo"], 100 * w[1, "hi"])
say("  ADJUDICATION-PLAN section 1 published 72%% [65, 78] on 200 hand-labelled")
say("  cases of the UNENRICHED packet, a different population.")

of <- sc[verdict == "ORG_FOUND"]
w2 <- pf_wilson(sum(of$right), nrow(of))
say("\non the looser denominator -- only cases where an org was found at all:")
say("  %d/%d = %.1f%% [%.1f, %.1f]", sum(of$right), nrow(of),
    100 * mean(of$right), 100 * w2[1, "lo"], 100 * w2[1, "hi"])

say("\nby blocking pass (the cascade's own, so these are ITS cells):")
bp <- sc[, .(n = .N, right = sum(right)), by = cascade_pass][order(-n)]
bp[, `:=`(rate = sprintf("%.0f%%", 100 * right / n),
          usable = ifelse(n >= 20L, "yes", "no (n<20)"))]
print(bp)

say("\nby which model produced the label, as a check that the gate did not")
say("bend the figure:")
bm <- sc[, .(n = .N, right = sum(right)), by = model]
bm[, rate := sprintf("%.0f%%", 100 * right / n)]
print(bm)

hr()
say("TRUTH HERE IS MODEL-PRODUCED. Every figure above is measured against")
say("labels two Claude models wrote, and where they agree they can be wrong")
say("together. TRUTH-LABELING-PROTOCOL.md section 6 step 4 -- a hand-labelled")
say("slice scored with pf_grade_verdicts() -- is still the only thing that")
say("turns any of this into an error rate.")
hr()
