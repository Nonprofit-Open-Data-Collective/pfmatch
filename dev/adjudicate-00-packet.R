#!/usr/bin/env Rscript
# ============================================================================
# adjudicate-00-packet.R -- freeze the 100-case adjudication batch.
#
# Stage 0 of the two-tier MAYBE adjudication experiment
# (dev/ADJUDICATION-EXPERIMENT.md). Builds the review packet ONCE and caches
# it, so the two LLM tiers and the scoring pass all read identical bytes and
# can be re-run without touching the matcher.
#
# WHY THIS SCRIPT EXISTS AT ALL -- the baseline cannot be adjudicated.
#
# dev/BASELINE-2026-10C/benchmark-1k-augmented.rds is the tiered decision, one
# row per identity: the winning EIN and its score, and nothing else.
# dev/build-baseline.R strips the `pairs` attribute deliberately (it is 194 MB
# of a 198 MB object). Adjudication needs the LOSERS -- the four other
# candidates npmatch could not separate the winner from -- so the match has to
# be re-run with `pairs` retained. Everything else here is downstream of that.
#
# The re-run reproduces the augmented arm exactly: same grants, same 11 passes,
# same recover flag, same reference bundle. If `tier` disagrees with the frozen
# baseline on any identity, that is a determinism failure and the script stops,
# because a packet drawn from a different MAYBE set answers a different
# question than the one the baseline poses.
#
# THE SAMPLE IS TWO STRATA, AND THEY ARE NOT INTERCHANGEABLE.
#
#   A  estimation   (default 68)  simple random from the MAYBEs that have NO
#        adjudicated truth. Unbiased, so the share of these that clear to YES
#        is a legitimate estimate for the whole 1,044-case tier, with a
#        Wilson interval the scoring stage reports.
#
#   B  calibration  (default 32)  EVERY MAYBE that PF-TRUTH-V2.csv already
#        adjudicates by hand. These give ABSOLUTE accuracy -- against a human
#        verdict, not against the other model -- which inter-model agreement
#        cannot supply. They are NOT random: they were drawn by earlier
#        stratified audits, so they must never enter the clearance-rate
#        numerator. The scoring stage keeps them apart; nothing here mixes them.
#
# The two strata are shuffled into one batch under `batch_order` and the truth
# columns are written to a SEPARATE file. Neither tier is told which stratum a
# case belongs to, or that strata exist -- dev/LLM-REVIEW-INSTRUCTIONS.md's
# calibration section depends on the reviewer not being able to tell.
#
# WHAT A CASE CARRIES is dev/ADJUDICATION-PLAN.md section 5 as amended: the
# candidate's own 990 mission and program text and the NTEEv2 description for
# EVERY candidate, not just the top pick. That addition resolved 45 of 56 hard
# cases (dev/ENRICHMENT-FINDINGS.md); a packet without it measures a different
# and much weaker reviewer.
#
# OUTPUTS (data-dev/)
#   ADJ-EXP-PACKET.rds    candidate-level, one row per (grant, candidate)
#   ADJ-EXP-CASES.rds     case-level, one row per grant, with batch_order
#   ADJ-EXP-TRUTH.rds     stratum B only: truth verdict, correct_ein,
#                           truth_in_packet. Read by stage 03, never by a tier.
#   ADJ-EXP-PACKET.csv    the same candidate rows, for reading by eye
#
# USAGE
#   PFMATCH_DIR=. Rscript dev/adjudicate-00-packet.R
#   PF_ADJ_N=100 PF_ADJ_NTRUTH=32 PF_ADJ_SEED=20261031 Rscript dev/adjudicate-00-packet.R
#   PF_ADJ_BMF=active   use the smaller active BMF for context (faster, but
#                       augmented-only candidate EINs lose their context)
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(library(npmatch)))
setDTthreads(0)

PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
DD <- file.path(PF, "data-dev")

N       <- as.integer(Sys.getenv("PF_ADJ_N", "100"))
N_TRUTH <- as.integer(Sys.getenv("PF_ADJ_NTRUTH", "32"))
SEED    <- as.integer(Sys.getenv("PF_ADJ_SEED", "20261031"))
K       <- as.integer(Sys.getenv("PF_ADJ_K", "5"))
BMFARM  <- tolower(Sys.getenv("PF_ADJ_BMF", "augmented"))
GRANTS  <- Sys.getenv("PF_ADJ_GRANTS", "^efv2_1k_grants_.*\\.csv$")
BASE    <- file.path(PF, "dev", "BASELINE-2026-10C", "benchmark-1k-augmented.rds")
stopifnot(BMFARM %in% c("augmented", "active"), N_TRUTH <= N)

say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() cat(strrep("=", 78), "\n")
nf  <- function(x) format(x, big.mark = ",")

hr(); say("ADJUDICATION EXPERIMENT  stage 0: packet"); hr()
say("N=%d  (calibration=%d, estimation=%d)  seed=%d  k=%d  bmf=%s",
    N, N_TRUTH, N - N_TRUTH, SEED, K, BMFARM)

## ---- 1. the match, with `pairs` kept ---------------------------------------
# Byte-for-byte the augmented arm of dev/build-baseline.R. Do not "improve"
# any argument here: the packet's claim to describe BASELINE-2026-10C's MAYBE
# tier rests entirely on this call matching that one.
refpath <- file.path(DD, "REF-augmented.rds")
say("\nloading %s ...", basename(refpath))
ref <- readRDS(refpath)
say("  %s reference rows", nf(nrow(ref$reference)))

grants <- pf_read_grants(file.path(PF, "inputs"), pattern = GRANTS)
grants <- pf_recover_name_from_street(grants)
say("  %s grants", nf(nrow(grants)))

passes <- c(pf_staged_passes("lean", concat = TRUE), pf_recovery_passes(state = TRUE))
say("matching (%d passes, pairs retained) ...", length(passes))
t0 <- proc.time()[["elapsed"]]
m  <- pf_match_grants(grants, ref, passes = passes, recover = TRUE, verbose = FALSE)
say("  matched in %.1f s", proc.time()[["elapsed"]] - t0)
rm(ref); invisible(gc())

## ---- 2. gate against the frozen baseline -----------------------------------
# A packet built on a MAYBE set that is not the baseline's MAYBE set cannot be
# reported against the baseline's figures. Checked, not assumed.
res  <- as.data.table(as.data.frame(m$result))
base <- as.data.table(readRDS(BASE))
cmp  <- merge(res[, .(.id, tier_new = as.character(tier))],
              base[, .(.id, tier_old = as.character(tier))], by = ".id")
if (nrow(cmp) != nrow(base))
  stop(sprintf("identity count moved: %d re-run vs %d baseline.", nrow(cmp), nrow(base)),
       call. = FALSE)
drift <- cmp[tier_new != tier_old]
if (nrow(drift))
  stop(sprintf(paste0("%d identities changed tier against BASELINE-2026-10C.\n",
       "  The re-run is not reproducing the baseline, so a packet drawn from it\n",
       "  does not describe the baseline's MAYBE tier. Resolve before sampling."),
       nrow(drift)), call. = FALSE)
say("\ngate: %s identities, tier identical to BASELINE-2026-10C", nf(nrow(cmp)))
print(table(cmp$tier_new))

st    <- as.data.table(pf_status(m))
maybe <- st[status == "MAYBE"]
say("\nMAYBE tier: %s identities", nf(nrow(maybe)))

## ---- 3. the two strata -----------------------------------------------------
tr <- fread(file.path(DD, "PF-TRUTH-V2.csv"), colClasses = "character")
say("truth file: %d rows, population %s", nrow(tr),
    paste(unique(tr$population), collapse = ","))

# One truth row per grant, preferring an adjudication that names an EIN: a
# grant with both an ORG_FOUND and an UNRESOLVED row is more informative as the
# former. UNRESOLVED carries no answer and is kept only so the scoring stage
# can exclude it explicitly rather than silently.
tr[, has_ein := nzchar(correct_ein)]
setorderv(tr, c("grant_id", "has_ein"), c(1L, -1L))
tr <- tr[!duplicated(grant_id)]
tr_maybe <- tr[grant_id %in% maybe$grant_id]
say("truth rows that are MAYBE here: %d (%d naming an EIN)",
    nrow(tr_maybe), sum(tr_maybe$has_ein))
if (nrow(tr_maybe) < N_TRUTH)
  say("  NOTE: only %d available, calibration stratum shrinks to that.", nrow(tr_maybe))

set.seed(SEED)
# Calibration: prefer the rows that name an EIN, since those discriminate a
# right EIN from a merely plausible one. Fill from the NONE-shaped verdicts
# after, which are equally real answers and the tier most likely to be faked.
nB  <- min(N_TRUTH, nrow(tr_maybe))
idB <- if (nB == 0L) character(0) else {
  withein <- tr_maybe[has_ein == TRUE]$grant_id
  noein   <- tr_maybe[has_ein == FALSE]$grant_id
  c(if (length(withein)) sample(withein, min(nB, length(withein))) else character(0),
    if (nB > length(withein) && length(noein))
      sample(noein, min(nB - length(withein), length(noein))) else character(0))
}
pool <- setdiff(maybe$grant_id, tr$grant_id)   # every truth row out of the pool
nA   <- min(N - length(idB), length(pool))
idA  <- sample(pool, nA)
say("\nstratum A estimation : %d drawn simple-random from %s eligible",
    length(idA), nf(length(pool)))
say("stratum B calibration: %d drawn from %d adjudicated", length(idB), nrow(tr_maybe))

ids   <- c(idA, idB)
cases <- data.table(
  grant_id = ids,
  stratum  = c(rep("A-estimation", length(idA)), rep("B-calibration", length(idB))))
cases[, batch_order := sample.int(.N)]          # the order both tiers see
setorder(cases, batch_order)

## ---- 4. candidate frame + BMF context --------------------------------------
bmfpath <- if (BMFARM == "augmented")
  file.path(DD, "BMF-AUGMENTED-unified-fixed.csv") else
  file.path(PF, "..", "npmatch", "data-raw", "bmf_2026_01_processed.csv")
say("\nBMF context from %s ...", basename(bmfpath))
t0 <- proc.time()[["elapsed"]]
pk <- as.data.table(pf_adjudicate(m, bmf = bmfpath, ids = ids, k = K, verbose = FALSE))
say("  %d candidate rows over %d grants in %.1f s",
    nrow(pk), uniqueN(pk$grant_id), proc.time()[["elapsed"]] - t0)

## ---- 5. the candidates' own words ------------------------------------------
# dev/ADJUDICATION-PLAN.md 5, amended: mission and program text for EVERY
# candidate. Absent text is left empty, which is not evidence either way, and
# the coverage read-out below is the honest statement of how often the packet
# actually carries this.
txtpath <- file.path(DD, "ORG-TEXT-BUNDLE.rds")
pk[, `:=`(cand_mission = "", cand_prog = "", cand_ntee_text = "")]
if (file.exists(txtpath)) {
  say("\n990 text from %s ...", basename(txtpath))
  tx <- as.data.table(readRDS(txtpath))
  tx[, ein := .pf_ein(ein)]
  tx <- tx[!duplicated(ein)]
  g <- function(col) {
    if (!col %in% names(tx)) return("")
    v <- tx[[col]][match(pk$ein, tx$ein)]
    v[is.na(v)] <- ""
    v
  }
  pk[, `:=`(cand_mission   = g("mission"),
            cand_prog      = g("prog_all"),
            cand_ntee_text = g("ntee_text"))]
  say("  mission %.1f%%  programs %.1f%%  ntee_text %.1f%% of candidate rows",
      100 * mean(nzchar(pk$cand_mission)), 100 * mean(nzchar(pk$cand_prog)),
      100 * mean(nzchar(pk$cand_ntee_text)))
  rm(tx); invisible(gc())
} else {
  say("\nWARNING: %s absent. The packet is name+geography+NTEE only, which is",
      basename(txtpath))
  say("         the weaker reviewer ENRICHMENT-FINDINGS.md measured at 11/56.")
}

## ---- 6. case-level signals -------------------------------------------------
# Carried so the scoring stage can report reliability BY the structural
# features the auto-accept rule failed on (ties, thin margins, the
# TOKEN_OVERLAP passes) rather than as one undifferentiated rate.
cases <- merge(cases, res[, .(grant_id = .id, n_close, tie, overall_margin,
                              overall_score, overall_ein, views_agree, pass,
                              overall_veto_soft, overall_veto_reason)],
               by = "grant_id", all.x = TRUE)
cases <- merge(cases, st[, .(grant_id, recip_name, recip_city, recip_state,
                             recip_zip5, filer_ein, filer_name,
                             recipient_type, looks_personal)],
               by = "grant_id", all.x = TRUE)

# pf_status() populates filer_name from FILERNAME1, which the efv2 grant files
# do not carry -- they name the filer in ORG_NAME_L1/L2. Left alone, the
# foundation's name is NA on every case in this population and the packet's
# FILING FOUNDATION block loses it. Recovered here by EIN rather than by
# patching R/report.R, which is out of this experiment's scope.
if (all(is.na(cases$filer_name)) && !is.null(grants$ORG_NAME_L1)) {
  fn <- data.table(ein = .pf_ein(grants$ORG_EIN),
                   nm  = trimws(paste(ifelse(is.na(grants$ORG_NAME_L1), "", grants$ORG_NAME_L1),
                                      if (!is.null(grants$ORG_NAME_L2))
                                        ifelse(is.na(grants$ORG_NAME_L2), "", grants$ORG_NAME_L2)
                                      else "")))
  fn <- fn[!is.na(ein) & nzchar(nm)][!duplicated(ein)]
  cases[, filer_name := fn$nm[match(filer_ein, fn$ein)]]
  say("  foundation name recovered from ORG_NAME_L1/L2 for %d of %d cases",
      sum(!is.na(cases$filer_name)), nrow(cases))
}
nc <- pk[, .N, by = grant_id]
cases[, n_cand := nc$N[match(grant_id, nc$grant_id)]]
setorder(cases, batch_order)

## ---- 7. truth, kept apart --------------------------------------------------
# `truth_in_packet` is the column that keeps the scoring honest. ORG_FOUND
# means a human found the organisation -- NOT that its EIN is among the five
# candidates. Where it is absent, NONE is the correct answer for a
# candidate-only reviewer and a MATCH on any candidate is wrong. Scoring a
# reviewer as if an answer were always present manufactures the exact error
# dev/LLM-REVIEW-INSTRUCTIONS.md opens by warning about.
truth <- tr_maybe[grant_id %in% idB,
                  .(grant_id, truth_id, truth_verdict = verdict,
                    correct_ein = .pf_ein(correct_ein), wrong_ein,
                    truth_basis = basis, truth_confidence = confidence,
                    truth_source = source, truth_note = note)]
inpk <- pk[, .(eins = paste(ein, collapse = " ")), by = grant_id]
truth[, truth_in_packet := {
  p <- inpk$eins[match(grant_id, inpk$grant_id)]
  ifelse(is.na(correct_ein) | !nzchar(correct_ein) | is.na(p), NA,
         mapply(grepl, correct_ein, p, fixed = TRUE))
}]
truth[, adjudicable := truth_verdict != "UNRESOLVED"]
say("\ncalibration stratum: %d cases", nrow(truth))
print(table(truth$truth_verdict))
# !is.na(), NOT nzchar(): nzchar(NA_character_) returns TRUE, so nzchar() on
# this column (where .pf_ein() has already turned the blanks into NA) counts
# the EIN-less UNRESOLVED rows as "naming one" and overstates the denominator.
say("  correct EIN present among the %d candidates: %d of %d naming one",
    K, sum(truth$truth_in_packet, na.rm = TRUE), sum(!is.na(truth$correct_ein)))
say("  scorable: %d (%d target MATCH, %d target NONE); %d UNRESOLVED excluded",
    sum(truth$adjudicable), sum(truth$truth_in_packet, na.rm = TRUE),
    sum(truth$truth_in_packet == FALSE, na.rm = TRUE), sum(!truth$adjudicable))

## ---- 8. write --------------------------------------------------------------
saveRDS(pk,    file.path(DD, "ADJ-EXP-PACKET.rds"))
saveRDS(cases, file.path(DD, "ADJ-EXP-CASES.rds"))
saveRDS(truth, file.path(DD, "ADJ-EXP-TRUTH.rds"))
fwrite(pk,     file.path(DD, "ADJ-EXP-PACKET.csv"))
hr()
say("wrote data-dev/ADJ-EXP-PACKET.rds   %d candidate rows", nrow(pk))
say("wrote data-dev/ADJ-EXP-CASES.rds    %d cases", nrow(cases))
say("wrote data-dev/ADJ-EXP-TRUTH.rds    %d with adjudicated truth", nrow(truth))
say("\ncase mix: ties %d/%d, median margin %.3f, %d distinct passes",
    sum(cases$tie, na.rm = TRUE), nrow(cases),
    median(cases$overall_margin, na.rm = TRUE), uniqueN(cases$pass))
say("\nnext: Rscript dev/adjudicate-01-light.R")
hr()
