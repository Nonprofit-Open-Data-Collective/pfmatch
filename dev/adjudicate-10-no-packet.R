#!/usr/bin/env Rscript
# ============================================================================
# adjudicate-10-no-packet.R -- freeze a 100-case batch from the NO tier.
#
# The MAYBE experiment (dev/ADJUDICATION-EXPERIMENT.md) asked which of five
# offered candidates is right. This asks a different question, and the
# difference is the whole point: a NO case has no candidate worth offering, so
# the reviewer is not choosing between rows. It is being asked whether the
# organisation the foundation paid exists in the IRS Business Master File at
# all -- and if it does, what its EIN is, given that the cascade never found it.
#
# WHICH NO, AND WHY THIS ONE.
#
# BASELINE-2026-10C augmented leaves 725 NO identities of 4,748 (15.27%).
# That is the tier this samples, because it is the tier the published match
# rate is computed against: 2,979 YES + 1,044 MAYBE + 725 NO = 4,748, and a
# clearance from this tier adds to the same numerator the MAYBE clearances do.
#
# dev/NO-RESIDUAL-AUDIT.md sampled a DIFFERENT population -- the 592 identities
# that are NO under *both* references -- so its figures are not interchangeable
# with these. That audit is the prior here, not the comparison: 35 of 100
# recoverable, 59 a genuine floor, 37 individual payees, and the robust
# mechanical result that all 21 independently-established EINs were already in
# both references. This run tests whether an LLM with search reproduces that
# composition on the production tier, and extends it with a taxonomy of what
# "outside the BMF" actually consists of.
#
# TWO STRATA, for the same reason stage 00 has two.
#
#   A  estimation   (default 75)  simple random from the NO identities with NO
#        prior human verdict. Unbiased, so the share that clears is an estimate
#        for the whole 725-case tier with a Wilson interval.
#
#   B  calibration  (default 25)  drawn from the NO identities that
#        dev/no-residual-verdicts.csv already adjudicates by hand. These give
#        agreement against a human rather than against another model. They are
#        NOT random -- an earlier stratified audit drew them -- so they must
#        never enter the clearance numerator. Stage 12 keeps them apart.
#
# WHAT A CASE CARRIES. Everything a NO case has, which is less than a MAYBE
# case has: the filed record, the filing foundation, and the cascade's best
# near-misses where any were scored at all. The near-misses are included
# deliberately -- pf_status() keeps them for exactly this reason, and the prior
# audit found that in 18 of 25 recoverable cases the correct row HAD been
# offered and scored too low. Hiding them would hide the dominant mechanism.
#
# They also create a trap, and stage 11's schema is built around it: an EIN the
# reviewer reads off a near-miss row is in the reference BY CONSTRUCTION, so
# counting it as evidence that the reference holds the answer is circular. The
# prior audit excluded four such EINs from its headline for this reason. The
# verdict schema therefore records ein_source (WEB vs CANDIDATE), and stage 12
# reports the reference-presence rate on WEB-sourced EINs only.
#
# OUTPUTS (data-dev/)
#   ADJ-NO-CASES.rds    one row per sampled identity, with batch_order
#   ADJ-NO-PACKET.rds   near-miss candidate rows, where any exist
#   ADJ-NO-PAIRS.rds    EVERY scored candidate for the sampled ids, not just
#                         the top k. Stage 12 needs this to separate "never
#                         retrieved" from "retrieved and underscored".
#   ADJ-NO-REFEIN.rds    the reference's unique EIN set, for the mechanical
#                         in-reference lookup without reloading 2.8 GB
#   (no trimmed reference: see the note at the load, it was 124 MB of nothing)
#   ADJ-NO-TRUTH.rds     stratum B only: the prior human verdict. Never read
#                         by a tier.
#
# USAGE
#   PFMATCH_DIR=. Rscript dev/adjudicate-10-no-packet.R
#   PF_NO_N=100 PF_NO_NTRUTH=25 PF_NO_SEED=20261101 Rscript dev/adjudicate-10-no-packet.R
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(library(npmatch)))
setDTthreads(0)

PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
DD <- file.path(PF, "data-dev")

N       <- as.integer(Sys.getenv("PF_NO_N", "100"))
N_TRUTH <- as.integer(Sys.getenv("PF_NO_NTRUTH", "25"))
SEED    <- as.integer(Sys.getenv("PF_NO_SEED", "20261101"))
K       <- as.integer(Sys.getenv("PF_NO_K", "5"))
GRANTS  <- Sys.getenv("PF_ADJ_GRANTS", "^efv2_1k_grants_.*\\.csv$")
BASE    <- file.path(PF, "dev", "BASELINE-2026-10C", "benchmark-1k-augmented.rds")
stopifnot(N_TRUTH <= N)

# SET=exp  the 100-case random sample (default)
# SET=cal  every NO identity the prior audit already adjudicated, re-keyed by
#          FILED NAME rather than by grant_id -- see the note in section 3.
SET <- tolower(Sys.getenv("PF_NO_SET", "exp"))
stopifnot(SET %in% c("exp", "cal"))
PFX <- if (SET == "cal") "ADJ-NOCAL" else "ADJ-NO"

# Normalised filed-name key. grant_id is NOT usable as a join key across runs
# (section 3 explains), so the join is on the filed recipient name stripped to
# alphanumerics and upper-cased. That is lossy -- two different grants can
# share a filed name -- so the collisions are counted and resolved
# deterministically rather than left to whichever row merge() returns first.
nzkey <- function(x) gsub("[^A-Z0-9]", "", toupper(trimws(x)))

say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() cat(strrep("=", 78), "\n")
nf  <- function(x) format(x, big.mark = ",")

hr(); say("NO-TIER EXPERIMENT  stage 10: packet"); hr()
say("N=%d  (calibration=%d, estimation=%d)  seed=%d  k=%d", N, N_TRUTH, N - N_TRUTH,
    SEED, K)

## ---- 1. the match, with `pairs` kept ---------------------------------------
# Byte-for-byte dev/adjudicate-00-packet.R's call, which is itself byte-for-byte
# the augmented arm of dev/build-baseline.R. The NO tier this samples has to be
# the same NO tier the baseline publishes or the clearance cannot be added to
# the baseline's match rate.
refpath <- file.path(DD, "REF-augmented.rds")
say("\nloading %s ...", basename(refpath))
ref <- readRDS(refpath)
say("  %s reference rows", nf(nrow(ref$reference)))

# Taken BEFORE the reference is dropped: the mechanical "is this EIN in the
# reference" test is the one result in the prior audit that does not depend on
# any normalisation choice, and it needs the EIN set. Saved rather than held so
# stage 12 never has to load 2.8 GB to answer a set-membership question.
refdt   <- as.data.table(ref$reference)
ref_ein <- sort(unique(.pf_ein(refdt$.ein)))
saveRDS(ref_ein, file.path(DD, "ADJ-NO-REFEIN.rds"))
say("  %s unique EINs in the reference", nf(length(ref_ein)))
# A trimmed copy of the reference (.ein/name/city/state/zip5) was saved here at
# first, to diagnose HOW far the filed name sat from the reference row for a
# recovered EIN. It is not saved any more: the diagnosis that earned its place
# -- was the correct EIN ever offered to the scorer, and what did it score --
# is answered by ADJ-NO-PAIRS.rds and ADJ-NO-REFEIN.rds, which are 0.5 MB and
# 10 MB. The trimmed reference was 124 MB, was rewritten on every packet build,
# and no stage ever read it. Inside a Dropbox folder that is not free: the sync
# it provoked held a lock on a pkgdown temp file and broke the site build.
rm(refdt); invisible(gc())

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
       "  A NO sample drawn from a drifted run does not describe the baseline's\n",
       "  NO tier, and its clearance cannot be added to the baseline's match\n",
       "  rate. Resolve before sampling."), nrow(drift)), call. = FALSE)
say("\ngate: %s identities, tier identical to BASELINE-2026-10C", nf(nrow(cmp)))
print(table(cmp$tier_new))

st <- as.data.table(pf_status(m))
no <- st[status == "NO"]

# THE DENOMINATOR IS NOT THE BASELINE'S DENOMINATOR, AND THE DIFFERENCE IS THE
# POPULATION THIS EXPERIMENT IS ABOUT.
#
# pf_status() runs over x$grants -- every identity in the file. x$result runs
# over the identities that got at least one scored candidate. Those are not the
# same set, and the gap is entirely inside the NO tier:
#
#   tier == "NO" in the result      the cascade retrieved something and the
#                                   best of it scored below the review floor
#   not in the result at all        no blocking pass produced any pair, so no
#                                   comparator ever ran
#
# BASELINE-2026-10C reports 4,748 identities and 725 NO. Those 4,748 are the
# result frame, so the published clear rate of 2,979/4,748 = 62.74% has a
# denominator that EXCLUDES the in-scope identities which surfaced nothing. A
# match rate cannot legitimately drop the cases its retrieval step failed on
# hardest, so the full status table is printed and saved here, and stage 12
# reports against both denominators rather than inheriting one silently.
say("\nfull status table over all %s identities:", nf(nrow(st)))
print(table(st$status, useNA = "ifany"))
n_scored <- sum(st$grant_id %in% res$.id)
say("  in the result frame (>=1 scored candidate): %s", nf(n_scored))
say("  never scored at all                       : %s", nf(nrow(st) - n_scored))
say("  in scope (status != OOS)                  : %s", nf(sum(st$status != "OOS")))
saveRDS(st, file.path(DD, "ADJ-NO-STATUS.rds"))

say("\nNO tier: %s identities (%.2f%% of %s)", nf(nrow(no)),
    100 * nrow(no) / nrow(st), nf(nrow(st)))
say("  of which tier==NO in the result frame: %s", nf(sum(no$grant_id %in% res$.id)))
say("  of which never scored at all         : %s", nf(sum(!no$grant_id %in% res$.id)))
say("  BASELINE-2026-10C's published NO is the first of those two.")

# The two shapes of NO are not the same case and must not be reported as one.
# `scored` means the cascade found something and rejected it, so a near-miss
# exists and the reviewer can see what was considered. `unscored` means no
# blocking pass produced any pair at all -- there is nothing to show, and the
# reviewer works from the filed record alone.
no[, has_cand := grant_id %in% res$.id]
say("  with a scored near-miss : %d", sum(no$has_cand))
say("  no candidate at all     : %d", sum(!no$has_cand))
say("\nfiled-record signals across the NO tier:")
print(table(recipient_type = no$recipient_type, useNA = "ifany"))
say("  looks_personal: %d of %d", sum(no$looks_personal, na.rm = TRUE), nrow(no))

## ---- 3. the sample ---------------------------------------------------------
# dev/no-residual-verdicts.csv holds 67 hand verdicts from the 2026-10-22 audit.
#
# GRANT_ID IS NOT A VALID JOIN KEY HERE, AND JOINING ON IT PRODUCES A RESULT
# THAT LOOKS LIKE A FINDING.
#
# The first version of this script matched the verdict file to the NO tier on
# grant_id. It appeared to work: 9 ids landed in the tier and 58 did not, which
# read as "58 cases have since moved tier" -- a plausible story, since tier 2
# recovers a quarter of tier-1 NO. It was wrong. Checking the FILED NAME on
# those 9 showed 0 of 9 agreeing: grant_id G003722 is `EASTER SEAL SOCIETY OF
# DEL-MAR` in the audit and `JAMIE DANIELS FOUNDATION` here. The ids are
# positional and are not stable across runs, so the join silently paired
# unrelated grants and the downstream calibration compared verdicts about
# different organisations -- reporting 4/8 agreement and kappa 0.26, i.e. the
# model looking unreliable, when nothing had been compared at all.
#
# Re-keyed on the filed recipient name, 63 of the 67 verdicts match a NO
# identity in this arm. So the prior audit's population IS essentially this
# tier, and the "58 moved tier" reading was an artefact end to end.
#
# dev/adjudicate-05-calib-packet.R hit the same hazard and prefixed its ids by
# population for exactly this reason. The lesson did not transfer because this
# script joins to a different file; it is written down here so it does not have
# to be learned a third time.
vpath <- file.path(PF, "dev", "no-residual-verdicts.csv")
vd <- if (file.exists(vpath)) fread(vpath, colClasses = "character") else
  data.table(id = character(0), filed = character(0))
if (nrow(vd)) {
  vd <- vd[!duplicated(id)]
  vd[, k := nzkey(filed)]
  say("\nprior verdicts: %d rows in %s", nrow(vd), basename(vpath))
  print(table(vd$verdict))
}
no[, k := nzkey(recip_name)]
vd_no <- if (nrow(vd)) vd[k %in% no$k] else vd
say("  matching a NO identity in this arm BY FILED NAME: %d of %d",
    nrow(vd_no), nrow(vd))
say("  (joining on grant_id instead gives a different and WRONG answer --")
say("   the ids are positional and not stable across runs. See the note above.)")

set.seed(SEED)
if (SET == "cal") {
  # THE CALIBRATION SET: every NO identity the prior audit adjudicated, matched
  # by filed name. Not a sample of anything and never used to estimate a rate --
  # its only job is a head-to-head against a human on the SAME organisations.
  #
  # A filed name can belong to more than one identity (the same charity named by
  # two foundations), so the key is not unique. Resolved to the lowest grant_id
  # per key, deterministically, and the collisions are counted: taking whichever
  # row a merge returned first would make the set depend on row order.
  mt <- merge(no[, .(k, grant_id)], vd_no[, .(k, id, filed, verdict, basis,
                                              web_ein, web_name, note)], by = "k")
  setorder(mt, k, grant_id)
  ncol_before <- nrow(mt)
  mt <- mt[!duplicated(k)]
  say("\ncalibration set: %d identities over %d verdict keys (%d name collisions",
      nrow(mt), uniqueN(mt$k), ncol_before - nrow(mt))
  say("  resolved to the lowest grant_id)")
  ids   <- mt$grant_id
  cases <- data.table(grant_id = ids, stratum = "C-calibration")
  cases[, batch_order := seq_len(.N)]      # no shuffling needed: one arm, one set
  print(table(mt$verdict))
} else {
  nB  <- min(N_TRUTH, nrow(vd_no))
  # NOTE ON STRATUM B, WHICH TURNED OUT NOT TO BE A CALIBRATION STRATUM.
  #
  # This draw and the pool exclusion below both key on grant_id, which the note
  # in section 3 shows is not a valid join key. They are left EXACTLY as first
  # run rather than corrected in place, because the 100-case packet and its
  # verdicts were already built from them and the determinism check below has to
  # keep passing. The consequence is recorded instead:
  #
  #   stratum B is 9 arbitrary identities, not 9 adjudicated ones, so it
  #   calibrates nothing. SET=cal exists to do that job properly.
  #
  #   stratum A is unaffected as an estimator. It is a simple random draw from
  #   836 of the 845 NO identities; the 9 excluded were excluded for a reason
  #   unrelated to their content, so the draw stays unbiased for the tier. Rates
  #   are therefore reported on stratum A alone, which is what stage 12 does.
  idB <- if (nB == 0L) character(0) else sample(vd_no$id, nB)
  pool <- setdiff(no$grant_id, vd$id)
  nA   <- min(N - length(idB), length(pool))
  idA  <- sample(pool, nA)
  say("\nstratum A estimation : %d drawn simple-random from %s eligible",
      length(idA), nf(length(pool)))
  say("stratum B (see note) : %d; these are NOT adjudicated cases -- the id join",
      length(idB))
  say("                       that selected them is invalid. Use PF_NO_SET=cal.")
  ids   <- c(idA, idB)
  cases <- data.table(
    grant_id = ids,
    stratum  = c(rep("A-estimation", length(idA)), rep("B-calibration", length(idB))))
  cases[, batch_order := sample.int(.N)]
}
setorder(cases, batch_order)

# The sample must be reproducible, and that is checked rather than asserted.
# Everything upstream of the draw is deterministic -- the match is gated against
# the baseline, `no` comes out of it in a fixed order, and the seed is set
# immediately before the first sample() -- so a re-run should produce the same
# 100 ids in the same batch_order. If it does not, verdicts collected against
# the earlier packet no longer describe these cases, and silently overwriting
# the packet would leave a verdict file keyed to ids that are still present but
# now carry different case text. Stop instead.
prev <- file.path(DD, sprintf("%s-CASES.rds", PFX))
if (file.exists(prev)) {
  pv <- as.data.table(readRDS(prev))
  if (!identical(sort(pv$grant_id), sort(cases$grant_id)) ||
      !identical(pv[order(grant_id)]$batch_order, cases[order(grant_id)]$batch_order))
    stop(paste0("this run drew a DIFFERENT sample than the existing ",
      basename(prev), ".\n  Any verdicts already collected are keyed to the old",
      " packet. Move the old\n  ADJ-NO-* files aside deliberately before",
      " rebuilding."), call. = FALSE)
  say("\ndeterminism: sample reproduces the existing packet exactly (%d ids)",
      nrow(cases))
}

## ---- 4. the filed record and the foundation --------------------------------
# Built onto `cases` directly rather than taken from the candidate frame's
# first row, because a NO case may have NO candidate rows -- and stage 00's
# renderer, which reads grant_purpose off cand_rows[1], would silently emit an
# empty grant for every unscored case.
bmfpath <- file.path(DD, "BMF-AUGMENTED-unified-fixed.csv")
say("\nBMF context from %s ...", basename(bmfpath))
t0  <- proc.time()[["elapsed"]]
ctx <- pf_bmf_context(bmfpath)
say("  %s context rows in %.1f s", nf(nrow(ctx)), proc.time()[["elapsed"]] - t0)

g  <- as.data.table(m$grants)
gi <- match(cases$grant_id, g$grant_id)
gv <- function(col) if (!is.null(g[[col]])) as.character(g[[col]])[gi] else NA_character_
cases[, `:=`(
  recip_name       = gv("recip_name"),
  recip_name_alt   = gv("recip_name_alt"),
  recip_street     = gv("recip_street"),
  recip_city       = gv("recip_city"),
  recip_state      = gv("recip_state_raw"),
  recip_zip5       = gv("recip_zip5"),
  grant_purpose    = gv("PF_15_G_PAID_PURPOSE"),
  grant_amount     = gv("PF_15_G_PAID_AMT"),
  grant_year       = gv("TAX_YEAR"),
  recip_status_raw = gv("PF_15_G_PAID_RECIP_STAT"),
  recipient_type   = as.character(g$recipient_type)[gi],
  recipient_type_detail = gv("recipient_type_detail"),
  looks_personal   = g$looks_personal[gi],
  filer_ein        = .pf_ein(gv("ORG_EIN")))]

# pf_status()/pf_candidate_frame() both read the filer name from FILERNAME1,
# which the efv2 files do not carry -- they name the filer in ORG_NAME_L1/L2.
# Same recovery as dev/adjudicate-00b-patch-fdn.R, done inline here so the
# packet is right on the first pass rather than patched afterwards.
fn <- data.table(
  ein = .pf_ein(g$ORG_EIN),
  nm  = trimws(paste(ifelse(is.na(g$ORG_NAME_L1), "", g$ORG_NAME_L1),
                     if (!is.null(g$ORG_NAME_L2))
                       ifelse(is.na(g$ORG_NAME_L2), "", g$ORG_NAME_L2) else "")))
fn <- fn[!is.na(ein) & nzchar(nm)][!duplicated(ein)]
cases[, filer_name := fn$nm[match(filer_ein, fn$ein)]]
say("  foundation name resolved for %d of %d cases",
    sum(!is.na(cases$filer_name)), nrow(cases))

fi <- match(cases$filer_ein, ctx$ein)
for (nm in c("BMF_org_addr_state", "BMF_org_addr_city", "BMF_ntee_code_clean",
             "BMF_ntee_code_definition", "BMF_nteev2_subsector"))
  if (nm %in% names(ctx)) cases[[sub("^BMF_", "FDN_", nm)]] <- ctx[[nm]][fi]

## ---- 5. the near-misses, where there are any -------------------------------
with_cand <- cases$grant_id[cases$grant_id %in% res$.id]
pk <- if (length(with_cand))
  as.data.table(pf_candidate_frame(m, ids = with_cand, k = K, bmf_context = ctx)) else
  data.table()
say("\nnear-miss rows: %d over %d of %d cases",
    nrow(pk), uniqueN(pk$grant_id), nrow(cases))

# Attach the candidates' own 990 words, as stage 00 does. A near-miss is being
# shown so the reviewer can judge whether the cascade was close; that judgement
# needs the same evidence the MAYBE packet carries.
txtpath <- file.path(DD, "ORG-TEXT-BUNDLE.rds")
if (nrow(pk)) {
  pk[, `:=`(cand_mission = "", cand_prog = "", cand_ntee_text = "")]
  if (file.exists(txtpath)) {
    tx <- as.data.table(readRDS(txtpath))
    tx[, ein := .pf_ein(ein)]
    tx <- tx[!duplicated(ein)]
    gt <- function(col) {
      if (!col %in% names(tx)) return("")
      v <- tx[[col]][match(pk$ein, tx$ein)]; v[is.na(v)] <- ""; v
    }
    pk[, `:=`(cand_mission = gt("mission"), cand_prog = gt("prog_all"),
              cand_ntee_text = gt("ntee_text"))]
    say("  990 text: mission %.1f%%  programs %.1f%%  ntee %.1f%% of near-miss rows",
        100 * mean(nzchar(pk$cand_mission)), 100 * mean(nzchar(pk$cand_prog)),
        100 * mean(nzchar(pk$cand_ntee_text)))
    rm(tx); invisible(gc())
  }
}

# EVERY scored pair for these ids, not the top K. Stage 12 asks whether a
# web-found EIN was ever offered to the scorer at all -- the retrieval-versus-
# scoring split that dev/replay-no-residual-blocking.R had to re-run the whole
# blocker to answer. Keeping the pairs here answers it by lookup instead.
pr    <- as.data.table(attr(m$result, "pairs"))
pairs <- pr[.id %in% cases$grant_id, ]
pairs[, .ein := .pf_ein(.ein)]
say("  all scored pairs for these ids: %s rows (median %.0f per scored case)",
    nf(nrow(pairs)), median(pairs[, .N, by = .id]$N))

nc <- if (nrow(pk)) pk[, .N, by = grant_id] else data.table(grant_id = character(0), N = integer(0))
ri <- match(cases$grant_id, res$.id)
cases[, `:=`(
  n_cand        = { v <- nc$N[match(grant_id, nc$grant_id)]; v[is.na(v)] <- 0L; v },
  n_pairs       = { v <- pairs[, .N, by = .id]$N[match(grant_id, pairs[, .N, by = .id]$.id)]
                    v[is.na(v)] <- 0L; v },
  best_score    = round(res$overall_score[ri], 3),
  best_ein      = .pf_ein(res$overall_ein[ri]),
  best_name     = res$overall_name_y[ri],
  best_name_sim = round(res$overall_name_sim[ri], 3),
  best_pass     = if (!is.null(res$pass)) res$pass[ri] else NA_character_)]
setorder(cases, batch_order)

## ---- 6. truth, kept apart --------------------------------------------------
# Keyed on the filed-name key for SET=cal, which is the only valid join. The
# SET=exp branch keeps its (invalid) id join so the existing packet reproduces;
# stage 12 is told which set it is reading and refuses to calibrate on `exp`.
truth <- if (SET == "cal")
  merge(cases[, .(grant_id)], mt[, .(grant_id, truth_filed = filed,
          truth_basis = basis, truth_verdict = verdict,
          truth_ein = .pf_ein(web_ein), truth_name = web_name,
          truth_note = note)], by = "grant_id") else
  vd_no[id %in% idB, .(grant_id = id, truth_filed = filed,
                       truth_basis = basis, truth_verdict = verdict,
                       truth_ein = .pf_ein(web_ein),
                       truth_name = web_name, truth_note = note)]
truth <- as.data.table(truth)
truth[, truth_ein_in_ref := ifelse(is.na(truth_ein), NA, truth_ein %in% ref_ein)]
say("\ntruth rows carried: %d", nrow(truth))
if (nrow(truth)) {
  print(table(truth$truth_verdict))
  say("  naming an EIN: %d; of those in the reference: %d",
      sum(!is.na(truth$truth_ein)), sum(truth$truth_ein_in_ref, na.rm = TRUE))
  # basis == "reference" means the audit read the EIN off a reference near-miss
  # rather than establishing it independently, so those are in the reference by
  # construction and cannot corroborate coverage -- the same guard ein_source
  # applies to the model's own answers.
  say("  of which established independently of the reference (basis=web): %d",
      sum(truth$truth_basis == "web", na.rm = TRUE))
  if (SET == "exp")
    say("  WARNING: on SET=exp these rows are keyed by an INVALID id join and")
  if (SET == "exp")
    say("  describe different grants. Do not calibrate on them.")
}

## ---- 7. write --------------------------------------------------------------
saveRDS(cases, file.path(DD, sprintf("%s-CASES.rds", PFX)))
saveRDS(pk,    file.path(DD, sprintf("%s-PACKET.rds", PFX)))
saveRDS(pairs, file.path(DD, sprintf("%s-PAIRS.rds", PFX)))
saveRDS(truth, file.path(DD, sprintf("%s-TRUTH.rds", PFX)))
if (nrow(pk)) fwrite(pk, file.path(DD, sprintf("%s-PACKET.csv", PFX)))
fwrite(cases, file.path(DD, sprintf("%s-CASES.csv", PFX)))
hr()
say("set=%s, file prefix %s", SET, PFX)
say("wrote data-dev/%s-CASES.rds   %d cases", PFX, nrow(cases))
say("wrote data-dev/%s-PACKET.rds  %d near-miss rows", PFX, nrow(pk))
say("wrote data-dev/%s-PAIRS.rds   %s scored pairs", PFX, nf(nrow(pairs)))
say("wrote data-dev/ADJ-NO-REFEIN.rds  %s unique reference EINs", nf(length(ref_ein)))
say("wrote data-dev/%s-TRUTH.rds   %d with a prior human verdict", PFX, nrow(truth))
say("\nsample mix: %d with a near-miss, %d without; %d looks_personal; %d distinct types",
    sum(cases$n_cand > 0), sum(cases$n_cand == 0),
    sum(cases$looks_personal, na.rm = TRUE), uniqueN(cases$recipient_type))
say("\nnext: Rscript dev/adjudicate-11-no-search.R")
hr()
