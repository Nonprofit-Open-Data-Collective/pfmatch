#!/usr/bin/env Rscript
# ============================================================================
# adjudicate-16-fuzzy-regress.R -- what pf_fuzzy_recover() does to a full run.
#
# The fuzzy pass was designed from 91 cases the cascade had already failed, so
# the one thing those 91 cases cannot tell us is what it does to everything
# else. This runs the production configuration end to end and measures the
# whole file: how many pairs the pass adds, how many identities move tier, and
# whether the 2,979 that already cleared YES are touched.
#
# The YES set is protected by construction -- np_cascade() drops an identity
# from `pending` the moment a pass clears it to YES, and pf_fuzzy_recover()
# takes its residual by the same rule -- so the interesting question is not
# whether YES breaks but what happens to MAYBE. The pass adds rows to the
# adjudication queue and can change which row a MAYBE identity is holding, and
# neither of those shows up in a clear-rate delta.
#
# Three things are measured, in descending order of how much they matter:
#
#   1. Does any identity that had cleared YES change tier? (The function stops
#      if one does. This script re-checks it independently rather than trusting
#      the function to police itself.)
#   2. How many identities move NO -> MAYBE or NO -> YES, at each cutoff?
#   3. Of the EINs the LLM arms established by search, how many does the fuzzy
#      pass reach on its own? This is the number that says whether the cheap
#      deterministic fix substitutes for the expensive one or merely overlaps
#      with it.
#
# USAGE
#   Rscript dev/adjudicate-16-fuzzy-regress.R
#   PF_FZ_CUTOFFS=0.95,0.90,0.85 Rscript dev/adjudicate-16-fuzzy-regress.R
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
DD <- file.path(PF, "data-dev")
suppressWarnings(suppressMessages(library(pfmatch)))
suppressWarnings(suppressMessages(library(stringdist)))
source(file.path(PF, "dev", "assert-lib.R"))

# The same default as dev/adjudicate-10-no-packet.R's PF_ADJ_GRANTS. A
# regression has to run on the file the baseline was measured on; a different
# grant file would make every delta below uninterpretable.
GRANTS  <- Sys.getenv("PF_FZ_GRANTS", "^efv2_1k_grants_.*\\.csv$")
CUTOFFS <- as.numeric(strsplit(Sys.getenv("PF_FZ_CUTOFFS", "0.95,0.90,0.85"), ",")[[1]])
OUT     <- file.path(DD, "ADJ-FUZZY-REGRESS.rds")

say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() cat(strrep("=", 78), "\n")
nf  <- function(x) format(x, big.mark = ",")

hr(); say("FUZZY PASS regression: cutoffs %s", paste(CUTOFFS, collapse = ", ")); hr()

## ---- 1. a reference the installed normalizer will accept ------------------
# This was written to load REF-augmented.rds, the reference BASELINE-2026-10C
# and the NO sample were measured on. It cannot: npmatch was reinstalled on
# 2026-10-31 at 13:11, after that reference was built, and
# pf_check_reference() correctly refuses it --
#
#   bundle v1-3e7b9f9d59bbb19e, installed v1-592912060053c4c3
#
# Every cached bundle in data-dev predates that reinstall, so all of them are
# refused. The guard is right and is not worked around here: npmatch measured
# street_key changing on 34,280 BMF rows in one release, so matching a
# freshly-normalized query against stale keys resolves fewer rows with nothing
# saying why. `check_reference = "warn"` would produce exactly the plausible,
# wrong number this experiment has already been burned by twice.
#
# So the reference is rebuilt from the CURRENT default tier's CSV, which costs
# about 30 minutes. THE CONSEQUENCE, which every figure below inherits: this is
# the matchdb active-observed tier (6.67M rows), not the baseline's augmented
# reference (3.88M rows). The before/after tier counts are therefore NOT the
# published baseline's, and no delta against the baseline's match rate can be
# read off them. What they do measure is what the fuzzy pass does to a full run
# on the reference the pipeline now uses by default.
REFCSV <- Sys.getenv("PF_FZ_REFCSV", file.path(DD, "REF-MATCHDB.csv"))
REFBND <- Sys.getenv("PF_FZ_REF", file.path(DD, "REF-FZ-BUNDLE.rds"))
ref <- NULL
if (file.exists(REFBND)) {
  say("loading cached bundle %s ...", basename(REFBND))
  cand <- readRDS(REFBND)
  ok <- tryCatch({ pf_check_reference(cand, "stop"); TRUE },
                 error = function(e) { say("  refused: %s", conditionMessage(e)); FALSE })
  if (ok) ref <- cand else rm(cand)
  invisible(gc())
}
if (is.null(ref)) {
  say("building a reference from %s (~30 min) ...", basename(REFCSV))
  t0 <- proc.time()[["elapsed"]]
  ref <- pf_build_reference(REFCSV)
  say("  built in %.0f min", (proc.time()[["elapsed"]] - t0) / 60)
  saveRDS(ref, REFBND)
  say("  cached as %s", basename(REFBND))
}
pf_check_reference(ref, "stop")
say("  %s reference rows, normalizer %s", nf(nrow(ref$reference)), ref$normalizer)

grants <- pf_recover_name_from_street(pf_read_grants(file.path(PF, "inputs"), pattern = GRANTS))
say("  %s grants", nf(nrow(grants)))
passes <- c(pf_staged_passes("lean", concat = TRUE), pf_recovery_passes(state = TRUE))

# The match is cached. It costs two hours on the 6.67M-row reference, and the
# first attempt at this script spent them and then died in the tail of
# pf_fuzzy_recover(), throwing the match away with the process. The cache is
# keyed on the three things that would make a stored match the wrong baseline
# -- the normalizer the reference was built with, the grant file, and the pass
# list -- and re-matches rather than reusing when any of them has moved. It is
# NOT keyed on the fuzzy cutoffs, which are applied after the match and do not
# touch it.
MCACHE <- file.path(DD, "ADJ-FUZZY-MATCH.rds")
key <- list(normalizer = ref$normalizer, n_grants = nrow(grants),
            grant_hash = sum(nchar(grants$recip_name), na.rm = TRUE),
            passes = passes)
m <- NULL; t_match <- NA_real_
if (file.exists(MCACHE)) {
  cm <- readRDS(MCACHE)
  if (identical(cm$key, key)) {
    m <- cm$m; t_match <- cm$t_match
    say("reusing the cached match (%.0f s when it was run)", t_match)
  } else {
    say("cached match does not fit this run; re-matching")
  }
}
if (is.null(m)) {
  say("matching (%d passes, pairs retained) ...", length(passes))
  t0 <- proc.time()[["elapsed"]]
  m  <- pf_match_grants(grants, ref, passes = passes, recover = TRUE, verbose = FALSE)
  t_match <- proc.time()[["elapsed"]] - t0
  say("  matched in %.0f s", t_match)
  saveRDS(list(key = key, m = m, t_match = t_match), MCACHE)
  say("  cached as %s", basename(MCACHE))
}

st0 <- as.data.table(pf_status(m))
say("")
print(table(st0$status, useNA = "ifany"))

# The baseline is taken from the RESULT FRAME, not from pf_status(). The first
# run of this script took it from pf_status() and the movement table came back
# with "NO -> ABSENT 97" and "OOS -> ABSENT 35": 132 identities that had not
# moved at all. pf_status() labels an identity with no pair anywhere as NO and
# an out-of-scope one as OOS, because that is what a reader of a status report
# wants; the result frame simply omits both. Comparing one convention against
# the other counts the difference between them as movement, and `moved` came
# out at 159 when 27 identities had changed tier.
#
# So both sides of every comparison below read the result frame, where ABSENT
# means absent before and after, and out-of-scope identities are excluded
# rather than relabelled. pf_status() is still printed, because the tier counts
# a reader will recognize are the ones above.
#
# pf_result_tiers() is that choice made out loud, and it is why this line no
# longer spells the convention out by hand: two calls to the same accessor say
# at the call site that both sides agree on what absence means. It asserts
# `.id` and `tier` itself, so the column guard lives there now.
base_tier <- pf_result_tiers(m)
# Every movement count below names its tiers literally. A tier the result frame
# gains and this script does not mention would be excluded from all of them at
# once, leaving a movement table that still adds up over a smaller universe.
need_vocab(base_tier, c("YES", "MAYBE", "NO"), what = "result-frame tier")
scope <- as.character(m$in_scope)
yes0 <- names(base_tier)[base_tier == "YES"]
say("\nbaseline: %s YES, %s in-scope identities not YES (of which %s have no pair at all)",
    nf(length(yes0)), nf(length(scope) - length(yes0)),
    nf(sum(!scope %in% names(base_tier))))

## ---- 2. the LLM arms' established EINs, as a target set -------------------
# Only WEB-sourced EINs, and only those already shown to be in the reference.
# A candidate-sourced EIN is in the reference by construction and would flatter
# the fuzzy pass for the same circular reason it would flatter the model.
target <- NULL
for (f in c("ADJ-NO-SCORED.rds", "ADJ-NO-SCORED-haiku.rds")) {
  p <- file.path(DD, f)
  if (!file.exists(p)) next
  v <- as.data.table(readRDS(p))
  # Three clauses, each one a label this script spells out by hand, and a
  # target set that silently empties if any of the three is misremembered --
  # which would report the fuzzy pass as reaching none of the LLM's EINs.
  need_cols(v, "ein_in_ref", "ein_source", "stratum", what = sprintf("target set from %s", f))
  need_levels(v$ein_source, "WEB", what = sprintf("WEB-sourced EINs in %s", f))
  need_levels(v$stratum, "A-estimation", what = sprintf("estimation stratum in %s", f))
  v <- v[ein_in_ref %in% TRUE & ein_source %in% "WEB" & stratum == "A-estimation",
         .(grant_id, ein, arm = if (grepl("haiku", f)) "haiku" else "opus")]
  target <- rbind(target, v)
}
if (!is.null(target)) {
  target <- unique(target, by = c("grant_id", "ein"))
  say("LLM-established EINs to aim at: %s over %s identities",
      nf(nrow(target)), nf(uniqueN(target$grant_id)))
}

## ---- 3. the pass, at each cutoff ------------------------------------------
rows <- list()
for (cut in CUTOFFS) {
  hr(); say("CUTOFF %.2f", cut); hr()
  t0 <- proc.time()[["elapsed"]]
  fr <- pf_fuzzy_recover(m, ref, cutoff = cut, verbose = TRUE)
  el <- proc.time()[["elapsed"]] - t0
  say("  %.1f s  (%.2f%% of the %.0f s match it supplements)", el, 100 * el / t_match, t_match)

  new_tier <- pf_result_tiers(fr)
  # The universe is the in-scope identities, so an identity with no pair before
  # AND no pair after appears as ABSENT -> ABSENT and is visible as a
  # non-movement rather than invisible. Out-of-scope identities are not here at
  # all: the pass never sees them and cannot move them.
  ids <- scope
  bt  <- ifelse(is.na(base_tier[ids]), "ABSENT", base_tier[ids])
  at  <- ifelse(is.na(new_tier[ids]),  "ABSENT", new_tier[ids])
  need_vocab(c(bt, at), c("YES", "MAYBE", "NO", "ABSENT"),
             what = "tier vocabulary, ABSENT injected for no-pair identities")

  # The independent re-check. pf_fuzzy_recover() stops on this itself; a guard
  # that only the guarded code tests is not a guard.
  broke <- sum(bt == "YES" & at != "YES")
  say("\n  YES identities that changed tier: %d  %s", broke,
      if (broke == 0L) "(as the residual rule requires)" else "*** REGRESSION ***")

  say("\n  tier movement:")
  mv <- table(from = bt, to = at)
  print(mv[rowSums(mv) > 0, colSums(mv) > 0, drop = FALSE])

  hit <- NA_integer_; hit_n <- NA_integer_
  if (!is.null(target) && nrow(fr$moved)) {
    md <- as.data.table(fr$moved)[, .(grant_id = as.character(.id),
                                      fz_ein = pfmatch:::.pf_ein(overall_ein),
                                      tier = as.character(tier),
                                      score = overall_score, sim = fuzzy_sim)]
    j <- merge(target, md, by = "grant_id")
    hit <- sum(j$ein == j$fz_ein, na.rm = TRUE); hit_n <- nrow(j)
    say("\n  of the LLM-established EINs, the fuzzy pass moved %d identities and",
        uniqueN(j$grant_id))
    say("  landed the SAME EIN on %d of them:", hit)
    if (nrow(j)) print(j[order(-sim)][1:min(12L, nrow(j))], row.names = FALSE)
    # A row where the pass cleared an identity to YES on a DIFFERENT EIN than
    # the one web search established is the costly outcome, not a near miss:
    # one of the two is wrong and the pipeline has no way to tell which. Name
    # them so they can be checked by hand rather than averaged away.
    bad <- j[ein != fz_ein & tier == "YES"]
    if (nrow(bad)) {
      say("\n  *** %d cleared to YES on an EIN the LLM arm contradicts:", nrow(bad))
      print(bad, row.names = FALSE)
    }
  }
  rows[[sprintf("%.2f", cut)]] <- data.table(
    cutoff = cut, seconds = el, residual = fr$n[["residual"]],
    pairs = fr$n[["pairs"]], moved = sum(bt != at),
    to_yes = sum(bt != "YES" & at == "YES"),
    to_maybe = sum(bt %in% c("NO", "ABSENT") & at == "MAYBE"),
    yes_broken = broke, llm_ein_matched = hit, llm_overlap = hit_n,
    llm_contradicted = if (is.null(target) || !nrow(fr$moved)) NA_integer_
                       else nrow(j[ein != fz_ein & tier == "YES"]),
    yes_before = sum(bt == "YES"), yes_after = sum(at == "YES"))
}

hr(); say("SUMMARY"); hr()
sm <- rbindlist(rows)
print(sm, row.names = FALSE)
say("")
say("clear rate on the %s in-scope identities OF THIS RUN. Not comparable to",
    nf(length(scope)))
say("BASELINE-2026-10C: different reference (see the note at the top).")
for (i in seq_len(nrow(sm)))
  say("  cutoff %.2f : %.2f%% -> %.2f%%  (%+.2f points)", sm$cutoff[i],
      100 * sm$yes_before[i] / length(scope),
      100 * sm$yes_after[i] / length(scope),
      100 * (sm$yes_after[i] - sm$yes_before[i]) / length(scope))
saveRDS(sm, OUT)
say("\nwrote %s", OUT)
hr()
