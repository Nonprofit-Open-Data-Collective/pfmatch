#!/usr/bin/env Rscript
# ============================================================================
# adjudicate-05-calib-packet.R -- a ~200-case calibration packet out of labels
# this project already holds.
#
# WHY. The ablation's conclusion rests on 27 hand-adjudicated cases, where one
# case is 3.7 points and none of the three McNemar tests reaches significance
# (dev/ADJ-EXP-ABLATION.log). The direction was consistent across accuracy,
# clearance and cost, which is why it was actionable -- but it is not settled.
# More PAIRED cases is the only thing that settles it.
#
# No new labelling is needed. Three labelled sets exist, and together they
# resolve to ~276 cases with a determinable correct answer:
#
#   dev/maybe-verdicts.csv       100 MAYBE cases, 87 scorable
#                                  CORRECT_TOP 53 + CORRECT_DEEPER 10 -> MATCH
#                                  NO_CORRECT 24 -> NONE;  AMBIGUOUS 13 dropped
#                                Candidates already in data-dev/AUDIT-MAYBE-100.csv,
#                                which is pf_candidate_frame() output -- the exact
#                                schema the renderer wants.
#
#   dev/autoaccept-verdicts.csv  200 cases where the ZIP5+margin rule fired
#                                  CORRECT 144 -> MATCH on the rule's own pick
#                                  WRONG 37 + AMBIGUOUS 19 -> refined below
#
#   dev/enrichment-verdicts.csv  the 56 autoaccept failures, re-adjudicated
#                                with the enriched packet
#                                  RESOLVED_PICK 8 + RESOLVED_ALT 14 -> MATCH
#                                  RESOLVED_NONE 23 -> NONE
#                                  HELPS 9 + SILENT 2 -> unresolved, dropped
#
# THREE THINGS THAT ARE NOT CLEAN ABOUT THIS, stated here because the scoring
# stage cannot infer them and a pooled accuracy figure would hide them.
#
# 1. THE STRATA ARE NOT ONE SAMPLE. maybe-verdicts was drawn from the 1k
#    population (dev/build-audit-samples.R, PF-MATCH-RESULT-1k.rds); the
#    autoaccept 200 from the 50k one (dev/build-autoaccept-sample.R). grant_id
#    is only unique WITHIN a file, so the two sets are prefixed here (`M-`,
#    `A-`) and never joined on the raw id. A collision would silently pair a
#    case with another case's label.
#
# 2. THE EASY STRATUM IS OVER-REPRESENTED. The 144 autoaccept CORRECTs are
#    cases where a geographic rule fired AND its top pick was right. That is
#    ~13% of the MAYBE tier (the rule fires on ~18%, and 72% of those are
#    correct), but it would be 52% of a pooled 276. It is therefore SUBSAMPLED
#    to PF_ADJ_CALIB_EASY (default 68) to land near 200 with a less lopsided
#    mix, and the stratum is labelled so accuracy is always reported within it.
#    **No pooled accuracy from this packet is a tier-level estimate.** The
#    stratum-A figure in dev/ADJ-EXP-RESULTS.log remains the only unbiased one.
#
# 3. THE PAIRED TESTS ARE UNAFFECTED BY 1 AND 2. McNemar uses only the cases
#    where two arms disagree, and asks which is right more often on those.
#    Heterogeneous strata add concordant pairs, which the test discards. So the
#    power gain for "is the search effect real" is real even though the pooled
#    accuracy is not interpretable. That asymmetry is the whole reason this
#    packet is worth building.
#
# One more mismatch, recorded: the main 100-case run took BMF context from the
# AUGMENTED reference; these cases were produced against the ACTIVE one, and
# are contexted from it here, consistently with how they were originally built.
# Context is descriptive, not a candidate source, so it does not change which
# EINs are on offer -- but it is a difference between strata.
#
# OUTPUTS (data-dev/)
#   ADJ-CAL-PACKET.rds / .csv   candidate-level, renderer-ready
#   ADJ-CAL-CASES.rds           case-level, with `stratum` and batch_order
#   ADJ-CAL-TRUTH.rds           target, correct_ein, truth_in_packet
#
# USAGE
#   PFMATCH_DIR=. Rscript dev/adjudicate-05-calib-packet.R
#   PF_ADJ_CALIB_EASY=0 ...   drop the easy stratum entirely (132 cases)
#   PF_ADJ_CALIB_EASY=144 ... keep all of it (276 cases)
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(library(npmatch)))
setDTthreads(0)
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
DD  <- file.path(PF, "data-dev")
NPM <- Sys.getenv("NPMATCH_DIR", file.path(PF, "..", "npmatch"))
BMF <- file.path(NPM, "data-raw", "bmf_2026_01_processed.csv")

N_EASY <- as.integer(Sys.getenv("PF_ADJ_CALIB_EASY", "68"))
SEED   <- as.integer(Sys.getenv("PF_ADJ_SEED", "20261031"))
K      <- as.integer(Sys.getenv("PF_ADJ_K", "5"))

say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() cat(strrep("=", 78), "\n")
sq  <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; trimws(x) }

hr(); say("CALIBRATION PACKET  (target ~200 scorable cases)"); hr()
say("easy stratum capped at %d; seed %d; k %d", N_EASY, SEED, K)

## ---- stratum M: the MAYBE-100, already in packet form ----------------------
say("\n[M] data-dev/AUDIT-MAYBE-100.csv")
am <- fread(file.path(DD, "AUDIT-MAYBE-100.csv"), colClasses = "character")
mv <- fread(file.path(DD, "..", "dev", "maybe-verdicts.csv"), colClasses = "character")
am[, `:=`(rank = as.integer(rank), is_top_pick = as.integer(is_top_pick))]
say("  %d candidate rows over %d grants", nrow(am), uniqueN(am$grant_id))
say("  verdicts: %s", paste(sprintf("%s=%d", names(table(mv$verdict)),
                                    table(mv$verdict)), collapse = " "))
# correct_ein from the rank the adjudicator named
mv[, correct_rank := suppressWarnings(as.integer(correct_rank))]
key <- am[, .(grant_id, rank, ein)]
mv <- merge(mv, key, by.x = c("grant_id", "correct_rank"),
            by.y = c("grant_id", "rank"), all.x = TRUE)
setnames(mv, "ein", "correct_ein_resolved")
mv[, target := fifelse(verdict %in% c("CORRECT_TOP", "CORRECT_DEEPER"), "MATCH",
              fifelse(verdict == "NO_CORRECT", "NONE", NA_character_))]
say("  resolved: %d MATCH (ein found for %d), %d NONE, %d dropped (AMBIGUOUS)",
    sum(mv$target == "MATCH", na.rm = TRUE),
    sum(mv$target == "MATCH" & !is.na(mv$correct_ein_resolved), na.rm = TRUE),
    sum(mv$target == "NONE", na.rm = TRUE), sum(is.na(mv$target)))

## ---- stratum A/H/E: the autoaccept 200, rebuilt at full schema -------------
# HARD-ENRICHED.csv already covers these 200 cases, but with a thinner column
# set than pf_candidate_frame() produces. Running the arms on a thinner packet
# would confound field-set with stratum, so the candidates are rebuilt from the
# 50k result instead, through the same function that built stratum M.
say("\n[A] rebuilding the autoaccept 200 at full schema")
aa <- fread(file.path(DD, "AUTOACCEPT-SAMPLE-200.csv"), colClasses = "character")
av <- fread(file.path(DD, "..", "dev", "autoaccept-verdicts.csv"), colClasses = "character")
ev <- fread(file.path(DD, "..", "dev", "enrichment-verdicts.csv"), colClasses = "character")
aa[, idx := as.character(.I)]
av[, idx := as.character(idx)]; ev[, idx := as.character(idx)]
aa <- merge(aa, av[, .(idx, aa_verdict = verdict)], by = "idx", all.x = TRUE)
aa <- merge(aa, ev[, .(idx, en_outcome = outcome,
                       en_rank = suppressWarnings(as.integer(pick_ein_rank)))],
            by = "idx", all.x = TRUE)
say("  autoaccept verdicts: %s", paste(sprintf("%s=%d",
    names(table(aa$aa_verdict)), table(aa$aa_verdict)), collapse = " "))
say("  enrichment outcomes: %s", paste(sprintf("%s=%d",
    names(table(aa$en_outcome)), table(aa$en_outcome)), collapse = " "))

say("  loading PF-MATCH-RESULT-50k.rds (2.4 GB) ...")
t0 <- proc.time()[["elapsed"]]
m50 <- readRDS(file.path(DD, "PF-MATCH-RESULT-50k.rds"))
say("    loaded in %.0f s", proc.time()[["elapsed"]] - t0)
# Rescored with the CURRENT config, exactly as dev/build-autoaccept-sample.R
# did, so the candidate ordering the packet shows is the shipped one.
pr  <- attr(m50$result, "pairs")
cfg <- npmatch::np_config()
p   <- npmatch::np_veto(npmatch::np_score(pr, cfg, method = "hier"), cfg)
res <- npmatch::np_tier(npmatch::np_select(p, cfg), cfg)
x50 <- m50; x50$result <- res
attr(x50$result, "pairs")  <- p
attr(x50$result, "config") <- cfg
rm(pr, m50); invisible(gc())
say("  rescored; building BMF context from %s ...", basename(BMF))
ctx <- pf_bmf_context(BMF)
say("    %d EINs with context", nrow(ctx))
ap <- as.data.table(pf_candidate_frame(x50, ids = aa$grant_id, k = K,
                                       bmf_context = ctx))
say("  %d candidate rows over %d grants", nrow(ap), uniqueN(ap$grant_id))
rm(x50, p, res); invisible(gc())

## ---- resolve the targets AGAINST THE ARTEFACTS THE ADJUDICATOR SAW --------
# NOT against the frame just rebuilt. A verdict of "CORRECT" attaches to one
# specific EIN -- the pick as it stood when a human looked at it -- and a
# pick_ein_rank attaches to a rank in the packet that human was shown. The
# rebuild above rescores with TODAY's npmatch config, and the normalizer has
# moved since these were labelled (npmatch PR #18). If the ordering shifted at
# all, "rank 1 of the rebuild" is a different organisation from the one judged
# correct, and the calibration set would be quietly scoring the arms against
# the wrong answers. There is no way to detect that downstream.
#
# So: the easy stratum's EIN comes from AUTOACCEPT-SAMPLE-200.csv's own `ein`
# column, and the hard stratum's from HARD-ENRICHED.csv's (grant_id, rank) ->
# cand_ein map, which IS the packet the enrichment adjudicator read.
he <- fread(file.path(DD, "HARD-ENRICHED.csv"), colClasses = "character")
he[, rank := as.integer(rank)]
aa <- merge(aa, he[, .(grant_id, en_rank = rank, ein_en_rank = cand_ein)],
            by = c("grant_id", "en_rank"), all.x = TRUE)
aa[, target := NA_character_]
# `ein` is the rule's pick as recorded in the sample file, which is what the
# CORRECT verdict refers to.
aa[aa_verdict == "CORRECT", `:=`(target = "MATCH", correct_ein_resolved = ein)]
aa[en_outcome %in% c("RESOLVED_PICK", "RESOLVED_ALT"),
   `:=`(target = "MATCH", correct_ein_resolved = ein_en_rank)]
aa[en_outcome == "RESOLVED_NONE", `:=`(target = "NONE", correct_ein_resolved = NA_character_)]
# How far the rebuild drifted from what was adjudicated. A high rate here means
# the rebuilt packet is not the one the labels describe, and the stratum should
# be dropped rather than scored.
r1 <- ap[rank == 1L, .(grant_id, ein_rank1_now = .pf_ein(ein))]
chk <- merge(aa[aa_verdict == "CORRECT", .(grant_id, ein_recorded = .pf_ein(ein))],
             r1, by = "grant_id", all.x = TRUE)
moved <- chk[!is.na(ein_recorded) & !is.na(ein_rank1_now) &
             ein_recorded != ein_rank1_now, .N]
say("  rebuild drift: the recorded pick is no longer rank 1 on %d of %d CORRECT cases",
    moved, nrow(chk))
if (nrow(chk) > 0 && moved / nrow(chk) > 0.10)
  say("  WARNING: >10%% drift -- the rebuilt candidate order differs materially from
           the one these labels describe; treat the E stratum with suspicion.")
aa[, stratum := fifelse(aa_verdict == "CORRECT", "E-easy-rule-correct",
                 fifelse(!is.na(en_outcome) & en_outcome %in%
                         c("RESOLVED_PICK", "RESOLVED_ALT", "RESOLVED_NONE"),
                         "H-hard-rule-failed", NA_character_))]
say("  resolved: %d MATCH, %d NONE, %d unresolved",
    sum(aa$target == "MATCH", na.rm = TRUE), sum(aa$target == "NONE", na.rm = TRUE),
    sum(is.na(aa$target)))

## ---- subsample the easy stratum --------------------------------------------
set.seed(SEED)
easy <- aa[stratum == "E-easy-rule-correct" & !is.na(target)]
hard <- aa[stratum == "H-hard-rule-failed"  & !is.na(target)]
if (N_EASY < nrow(easy)) {
  keep <- sample(easy$grant_id, N_EASY)
  say("\n  easy stratum subsampled %d of %d (see header, note 2)", N_EASY, nrow(easy))
  easy <- easy[grant_id %in% keep]
}
aa_keep <- rbind(easy, hard)

## ---- assemble, with ids prefixed per stratum -------------------------------
# M- and A- prefixes: grant_id is unique only within a population file, so an
# unprefixed join across these two sets would pair a case with a stranger's
# label. Cheap to prevent, impossible to detect afterwards.
mkeep <- mv[!is.na(target)]
say("\nassembling: %d from M, %d from E, %d from H = %d cases",
    nrow(mkeep), nrow(easy), nrow(hard), nrow(mkeep) + nrow(aa_keep))

common <- c("grant_id", "rank", "is_top_pick", "ein", "cand_name", "cand_city",
            "cand_state", "cand_zip5", "score", "name_sim", "geo_zip5",
            "geo_state", "pass", "recip_name", "recip_city", "recip_state",
            "recip_zip5", "grant_purpose", "grant_amount", "grant_year",
            "recip_status_raw", "recipient_type", "fdn_name",
            grep("^(CAND|FDN)_", names(am), value = TRUE))
take <- function(d, pfx) {
  d <- copy(d)
  for (nm in setdiff(common, names(d))) d[[nm]] <- NA_character_
  d <- d[, ..common]
  d[, grant_id := paste0(pfx, grant_id)]
  d
}
pk <- rbind(take(am[grant_id %in% mkeep$grant_id], "M-"),
            take(ap[grant_id %in% aa_keep$grant_id], "A-"), fill = TRUE)
pk[, rank := as.integer(rank)]
setorder(pk, grant_id, rank)

## ---- the candidates' own words ---------------------------------------------
txtf <- file.path(DD, "ORG-TEXT-BUNDLE.rds")
pk[, `:=`(cand_mission = "", cand_prog = "", cand_ntee_text = "")]
if (file.exists(txtf)) {
  say("\n990 text from %s ...", basename(txtf))
  tx <- as.data.table(readRDS(txtf))
  tx[, ein := .pf_ein(ein)]
  tx <- tx[!duplicated(ein)]
  g <- function(col) { if (!col %in% names(tx)) return("")
    v <- tx[[col]][match(.pf_ein(pk$ein), tx$ein)]; v[is.na(v)] <- ""; v }
  pk[, `:=`(cand_mission = g("mission"), cand_prog = g("prog_all"),
            cand_ntee_text = g("ntee_text"))]
  say("  mission %.1f%%  programs %.1f%%  ntee_text %.1f%%",
      100 * mean(nzchar(pk$cand_mission)), 100 * mean(nzchar(pk$cand_prog)),
      100 * mean(nzchar(pk$cand_ntee_text)))
  rm(tx); invisible(gc())
} else say("\nWARNING: %s absent -- packet is name+geography+NTEE only", basename(txtf))

## ---- cases and truth -------------------------------------------------------
# grant_id and stratum only. The recipient fields come from the PACKET, not
# from the label files -- mkeep is maybe-verdicts (no recipient columns at all)
# and aa_keep is the autoaccept sample (which has its own, differently derived).
# Taking them from one place means the case list and the rendered packet cannot
# disagree about what was filed.
cases <- rbind(
  mkeep[,   .(grant_id = paste0("M-", grant_id), stratum = "M-maybe-random")],
  aa_keep[, .(grant_id = paste0("A-", grant_id), stratum)])
rc <- pk[rank == 1L, .(grant_id, recip_name, recip_city, recip_state, recip_zip5,
                       recipient_type, filer_name = fdn_name)]
cases <- merge(cases, rc, by = "grant_id", all.x = TRUE)
nc <- pk[, .N, by = grant_id]
cases[, n_cand := nc$N[match(grant_id, nc$grant_id)]]
cases[, `:=`(tie = NA, overall_margin = NA_real_)]
set.seed(SEED + 1L)
cases[, batch_order := sample.int(.N)]
setorder(cases, batch_order)

truth <- rbind(
  mkeep[, .(grant_id = paste0("M-", grant_id), target,
            correct_ein = .pf_ein(correct_ein_resolved),
            label_source = "maybe-verdicts.csv", label_detail = verdict)],
  aa_keep[, .(grant_id = paste0("A-", grant_id), target,
              correct_ein = .pf_ein(correct_ein_resolved),
              label_source = fifelse(stratum == "E-easy-rule-correct",
                                     "autoaccept-verdicts.csv",
                                     "enrichment-verdicts.csv"),
              label_detail = fifelse(is.na(en_outcome), aa_verdict, en_outcome))])
inpk <- pk[, .(eins = paste(.pf_ein(ein), collapse = " ")), by = grant_id]
truth[, truth_in_packet := {
  p <- inpk$eins[match(grant_id, inpk$grant_id)]
  ifelse(is.na(correct_ein) | is.na(p), NA,
         mapply(grepl, correct_ein, p, fixed = TRUE))
}]
# A MATCH target whose EIN is not in the packet is not scorable as MATCH: the
# right answer for a candidate-only reviewer is NONE. Same rule as stage 00.
n_fix <- truth[target == "MATCH" & truth_in_packet == FALSE, .N]
if (n_fix) {
  say("\n%d MATCH target(s) whose EIN is not among the %d candidates -> target NONE",
      n_fix, K)
  truth[target == "MATCH" & truth_in_packet == FALSE, target := "NONE"]
}
truth[, adjudicable := !is.na(target)]

hr()
say("cases     : %d", nrow(cases))
print(table(cases$stratum))
say("\ntargets   : %d MATCH, %d NONE", sum(truth$target == "MATCH"),
    sum(truth$target == "NONE"))
print(table(stratum = cases$stratum[match(truth$grant_id, cases$grant_id)],
            target = truth$target))
say("\ncandidate rows: %d  (median %d per case)", nrow(pk), median(nc$N))

saveRDS(pk,    file.path(DD, "ADJ-CAL-PACKET.rds"))
saveRDS(cases, file.path(DD, "ADJ-CAL-CASES.rds"))
saveRDS(truth, file.path(DD, "ADJ-CAL-TRUTH.rds"))
fwrite(pk,     file.path(DD, "ADJ-CAL-PACKET.csv"))
say("\nwrote data-dev/ADJ-CAL-{PACKET,CASES,TRUTH}.rds")
say("next: PF_ADJ_SET=cal Rscript dev/adjudicate-01-light.R")
hr()
