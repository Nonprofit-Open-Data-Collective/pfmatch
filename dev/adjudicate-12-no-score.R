#!/usr/bin/env Rscript
# ============================================================================
# adjudicate-12-no-score.R -- what the NO tier actually contains.
#
# Four questions, in the order their answers depend on each other:
#
#   1 RECOVERABLE   How many NO cases turn out to have an EIN that is in the
#                   reference after all? This is the clearance figure, and it
#                   is a MECHANICAL lookup -- the model reports an EIN, code
#                   tests set membership. Nothing here rests on the model's
#                   opinion about the reference, because the model was never
#                   shown it.
#
#   2 WHY MISSED    For those, was the EIN ever offered to the scorer? The
#                   scored pairs are cached, so this separates "blocking never
#                   retrieved it" from "the comparator had it and ranked it
#                   below the floor" by lookup rather than by replaying the
#                   blocker, which dev/replay-no-residual-blocking.R had to do.
#
#   3 OUTSIDE       For the rest, what kind of thing is the payee and why is
#                   there no record? This is the taxonomy and it is the model's
#                   judgement, so it is reported as such and calibrated in 4.
#
#   4 CALIBRATION   NOT done in this script. The human head-to-head needs a
#                   packet built from the prior audit's own cases, which is
#                   PF_NO_SET=cal and dev/adjudicate-14-no-calib.R. Section 4
#                   below records why the obvious shortcut is wrong.
#
# THE CIRCULARITY GUARD IS THE WHOLE BALLGAME IN QUESTION 1.
#
# An EIN read off a rejected near-miss row is in the reference BY CONSTRUCTION:
# it got there because the blocker retrieved it from the reference. Counting
# such a case as evidence that "the reference holds the answer" is circular, and
# dev/NO-RESIDUAL-AUDIT.md excluded four EINs on exactly this ground to protect
# its headline. Stage 11 records ein_source on every verdict so the exclusion
# is a filter here rather than a hand-maintained list. The headline rate is
# computed on WEB-sourced EINs only; the candidate-sourced ones are reported
# beside it, labelled, because they are a real recovery route -- just not
# evidence about reference coverage.
#
# WHAT "CLEARS" MEANS HERE, AND WHAT IT DOES NOT.
#
# In the MAYBE experiment a case cleared when a reviewer returned MATCH on one
# of five offered candidates, and precision on those was measurable because the
# answer was in the packet 71% of the time. Here there is no candidate set, so
# "clears" means: the investigation established an EIN and that EIN is in the
# reference. That is RECOVERABILITY, not a verified match. Whether the EIN is
# the right one is attested by the model's own confidence and by the separate
# human head-to-head in dev/adjudicate-14-no-calib.R, and the vignette says so
# rather than quietly promoting recoverability to accuracy.
#
# OUTPUT  data-dev/ADJ-NO-SCORED.rds / .csv, plus the read-out below.
#
# USAGE  Rscript dev/adjudicate-12-no-score.R
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
PF <- Sys.getenv("PFMATCH_DIR", ".")
DD <- file.path(PF, "data-dev")
TAG <- Sys.getenv("PF_NO_TAG", "")

say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() cat(strrep("=", 78), "\n")
sub_hr <- function() cat(strrep("-", 78), "\n")
nf  <- function(x) format(x, big.mark = ",")
pct <- function(a, b) if (b == 0) "n/a" else sprintf("%.1f%%", 100 * a / b)

# Wilson score interval. Used rather than the normal approximation because the
# cells here are small and several are near 0 or 1, where the normal interval
# runs outside [0,1] and is simply wrong.
wilson <- function(k, n, z = 1.96) {
  if (n == 0) return(c(NA, NA))
  p <- k / n; d <- 1 + z^2 / n
  c <- (p + z^2 / (2 * n)) / d
  h <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / d
  c(max(0, c - h), min(1, c + h))
}
ci <- function(k, n) { w <- wilson(k, n); sprintf("[%.1f%%, %.1f%%]", 100 * w[1], 100 * w[2]) }

# BASELINE-2026-10C augmented, as published in its MANIFEST.md. These four are
# literals because they are the figures this experiment is reported against and
# they must not drift silently with a re-run.
BASE_IDENT <- 4748L; BASE_YES <- 2979L; BASE_MAYBE <- 1044L; BASE_NO_TIER <- 725L

# The population actually sampled, measured rather than assumed. It is NOT
# BASE_NO_TIER, and getting this wrong would project a rate onto the wrong
# denominator.
#
# pf_status() runs over every identity in the file; x$result runs only over the
# identities that got at least one scored candidate. The baseline's 4,748
# identities and 725 NO are the result frame. The status frame's NO tier is
# larger, because it also contains the in-scope identities for which no
# blocking pass produced any pair at all -- the cascade's hardest retrieval
# failures, which the published denominator drops precisely because they
# failed. Those cases are the sampled population here and they are central to
# the question, so the arithmetic below reports BOTH denominators and never
# mixes them.
stf <- file.path(DD, "ADJ-NO-STATUS.rds")
if (!file.exists(stf))
  stop(paste0("ADJ-NO-STATUS.rds absent. Re-run dev/adjudicate-10-no-packet.R;\n",
       "  without it the NO population size is unknown and every projection\n",
       "  below would be against a guessed denominator."), call. = FALSE)
st <- as.data.table(readRDS(stf))
st <- as.data.table(st)
NO_ALL      <- sum(st$status == "NO")
IDENT_ALL   <- nrow(st)
IDENT_SCOPE <- sum(st$status != "OOS")
N_OOS       <- sum(st$status == "OOS")
# The scored/unscored split of the NO tier: the baseline's published 725 IS the
# result frame's tier=="NO", so whatever the status frame holds beyond that
# never reached the result frame at all. Derived this way rather than from
# ADJ-NO-PAIRS.rds, which covers only the 100 sampled ids and so cannot speak
# to the tier as a whole.
NO_SCORED   <- BASE_NO_TIER
NO_UNSCORED <- NO_ALL - NO_SCORED
if (NO_UNSCORED < 0L)
  stop(sprintf(paste0("the status frame's NO tier (%d) is smaller than the ",
       "baseline's published NO (%d).\n  These should differ only by the ",
       "never-scored identities, so a negative\n  remainder means the run and ",
       "the baseline are not describing the same file."),
       NO_ALL, BASE_NO_TIER), call. = FALSE)

hr(); say("NO-TIER EXPERIMENT  stage 12: score"); hr()

v     <- as.data.table(readRDS(file.path(DD, sprintf("ADJ-NO-SEARCH%s.rds", TAG))))
cases <- as.data.table(readRDS(file.path(DD, "ADJ-NO-CASES.rds")))
pairs <- as.data.table(readRDS(file.path(DD, "ADJ-NO-PAIRS.rds")))
refein <- readRDS(file.path(DD, "ADJ-NO-REFEIN.rds"))
truth <- as.data.table(readRDS(file.path(DD, "ADJ-NO-TRUTH.rds")))
say("verdicts %d, cases %d, scored pairs %s, reference EINs %s, prior verdicts %d",
    nrow(v), nrow(cases), nf(nrow(pairs)), nf(length(refein)), nrow(truth))

d <- merge(cases, v[, setdiff(names(v), c("stratum", "batch_order", "recip_name",
                                          "n_cand")), with = FALSE],
           by = "grant_id")
setorder(d, batch_order)
d <- d[api_ok == TRUE]
say("usable verdicts: %d", nrow(d))

## ---- 1. the mechanical lookups ---------------------------------------------
d[, ein_in_ref := ifelse(is.na(ein), NA, ein %in% refein)]
# Was that EIN ever put in front of the scorer? Every scored pair for these
# ids is cached, so this is a join, not a replay.
pset <- pairs[, .(eins = list(unique(.ein))), by = .id]
d[, ein_offered := {
  idx <- match(grant_id, pset$.id)
  mapply(function(e, i) if (is.na(e) || is.na(i)) NA else e %in% pset$eins[[i]],
         ein, idx)
}]
# The score the comparator gave the correct row, where it had it. This is the
# number that says how far off the floor the right answer sat.
#
# Ordered by descending score FIRST, because several passes can retrieve the
# same (id, ein) and match() returns the first hit. Unordered, the reported
# score would be whichever pass happened to be stored first -- so a row the
# comparator scored 0.60 on its best pass could be reported at 0.22, making the
# scoring failure look far worse than it was.
pj <- pairs[order(.id, -score), .(.id, .ein, score, pass)]
d[, found_score := pj$score[match(paste(grant_id, ein), paste(pj$.id, pj$.ein))]]
d[, found_pass  := pj$pass[match(paste(grant_id, ein), paste(pj$.id, pj$.ein))]]

# %in% rather than == on every comparison: a verdict missing ein_source would
# make == return NA, cleared_web would be NA rather than FALSE, and sum() over
# the column would return NA -- voiding the headline figure rather than
# reporting it as a zero. %in% returns FALSE on NA, which is the right reading:
# a verdict that does not state where its EIN came from has not cleared the
# circularity bar.
d[, cleared_web  := !is.na(ein) & ein_source %in% "WEB" & ein_in_ref %in% TRUE]
d[, cleared_cand := !is.na(ein) & ein_source %in% "CANDIDATE" & ein_in_ref %in% TRUE]
d[, cleared_any  := cleared_web | cleared_cand]

A <- d[stratum == "A-estimation"]
B <- d[stratum == "B-calibration"]

hr(); say("1. RECOVERABLE -- how much of the NO tier has an EIN after all"); hr()
say("Stratum A (%d cases, simple random from the %d-case NO tier) is the only",
    nrow(A), NO_ALL)
say("stratum that estimates a rate. It is a simple random draw from %d of the",
    NO_ALL - nrow(B))
say("%d NO identities; the %d held back were held back by an id join later found",
    NO_ALL, nrow(B))
say("invalid, for reasons unrelated to their content, so the draw stays")
say("unbiased for the tier. The other %d cases are labelled B-calibration but", nrow(B))
say("calibrate nothing -- see section 4 -- and are excluded from every rate.\n")

nA <- nrow(A)
say("  EIN reported at all        : %3d of %d  %s", sum(!is.na(A$ein)), nA,
    pct(sum(!is.na(A$ein)), nA))
say("    of which WEB-sourced     : %3d", sum(!is.na(A$ein) & A$ein_source %in% "WEB"))
say("    of which off a candidate : %3d", sum(!is.na(A$ein) & A$ein_source %in% "CANDIDATE"))
sub_hr()
kw <- sum(A$cleared_web)
say("  RECOVERABLE, non-circular  : %3d of %d  %s  %s", kw, nA, pct(kw, nA), ci(kw, nA))
say("    -> projected over %d NO : %.0f identities [%.0f, %.0f]", NO_ALL,
    NO_ALL * kw / nA, NO_ALL * wilson(kw, nA)[1], NO_ALL * wilson(kw, nA)[2])
ka <- sum(A$cleared_any)
say("  RECOVERABLE, incl. candidate-sourced EINs: %3d of %d  %s  %s",
    ka, nA, pct(ka, nA), ci(ka, nA))
say("    -> projected over %d NO : %.0f identities", NO_ALL, NO_ALL * ka / nA)
say("\n  The first figure is the headline. The second counts cases whose EIN was")
say("  read off a rejected near-miss row, which is in the reference BY")
say("  CONSTRUCTION -- a real recovery route, but not evidence that the")
say("  reference covers the tier. Both are reported so neither is mistaken for")
say("  the other.")

sub_hr()
say("THE NON-CIRCULAR COVERAGE TEST")
say("Of the WEB-sourced EINs -- established from a source outside the packet --")
say("how many are already in the reference? dev/NO-RESIDUAL-AUDIT.md found 21 of")
say("21 and called it the robust result, because it is a set-membership test.\n")
for (s in c("A-estimation", "B-calibration")) {
  w <- d[stratum == s & !is.na(ein) & ein_source %in% "WEB"]
  if (!nrow(w)) { say("  %-14s no WEB-sourced EINs", s); next }
  say("  %-14s %d of %d in the reference  %s  %s", s,
      sum(w$ein_in_ref), nrow(w), pct(sum(w$ein_in_ref), nrow(w)),
      ci(sum(w$ein_in_ref), nrow(w)))
}
wall <- d[!is.na(ein) & ein_source %in% "WEB"]
say("  %-14s %d of %d in the reference  %s  %s", "both strata",
    sum(wall$ein_in_ref), nrow(wall), pct(sum(wall$ein_in_ref), nrow(wall)),
    ci(sum(wall$ein_in_ref), nrow(wall)))
miss <- wall[ein_in_ref == FALSE]
if (nrow(miss)) {
  say("\n  WEB-established EINs that are NOT in the reference -- the only cases")
  say("  that are a reference COVERAGE gap rather than a name-resolution gap:")
  for (k in seq_len(nrow(miss)))
    say("    %s  %-34s ein %s  %s", miss$grant_id[k],
        substr(miss$recip_name[k], 1, 34), miss$ein[k], miss$entity_class[k])
}

## ---- 2. why the recoverable ones were missed -------------------------------
hr(); say("2. WHY -- retrieval or scoring"); hr()
rec <- d[cleared_any == TRUE]
say("For the %d recoverable cases across both strata, was the correct EIN ever", nrow(rec))
say("offered to the scorer? The scored pairs are cached, so this is a lookup.\n")
if (nrow(rec)) {
  off <- sum(rec$ein_offered %in% TRUE)
  say("  offered and REJECTED (a scoring/threshold failure) : %3d  %s",
      off, pct(off, nrow(rec)))
  say("  never offered        (a blocking/retrieval failure): %3d  %s",
      nrow(rec) - off, pct(nrow(rec) - off, nrow(rec)))
  so <- rec[ein_offered %in% TRUE & !is.na(found_score)]
  if (nrow(so)) {
    say("\n  Where it was offered, the score it got (floor for review is 0.65):")
    say("    median %.3f, range %.3f to %.3f; %d of %d scored at or above 0.60",
        median(so$found_score), min(so$found_score), max(so$found_score),
        sum(so$found_score >= 0.60), nrow(so))
    say("    passes that found it: %s",
        paste(sort(unique(na.omit(so$found_pass))), collapse = ", "))
  }
  say("\n  The model's own hypothesis for why it was missed:")
  print(table(miss_hypothesis = rec$miss_hypothesis, useNA = "ifany"))
  say("\n  Cross-tabulated against what actually happened:")
  print(table(miss_hypothesis = rec$miss_hypothesis,
              offered = ifelse(rec$ein_offered %in% TRUE, "offered", "never offered"),
              useNA = "ifany"))
}

## ---- 3. what lives outside the BMF ----------------------------------------
hr(); say("3. OUTSIDE -- what the unrecoverable part of the tier is"); hr()
say("Stratum A only (%d cases), so these shares estimate the %d-case tier.", nA, NO_ALL)
say("These are the model's judgements, calibrated in section 4.\n")

tabA <- function(col) {
  t <- sort(table(A[[col]], useNA = "ifany"), decreasing = TRUE)
  for (nm in names(t))
    say("  %-24s %3d  %6s   -> ~%4.0f of %d", nm, t[[nm]], pct(t[[nm]], nA),
        NO_ALL * t[[nm]] / nA, NO_ALL)
  invisible(t)
}
say("entity_class -- WHAT THE PAYEE IS")
tabA("entity_class")
say("\nbmf_expectation -- SHOULD AN EXEMPT-ORGANISATION RECORD EXIST")
tabA("bmf_expectation")
say("\noutside_reason -- WHY NOT, where it should not")
tabA("outside_reason")

sub_hr()
# The payees that are not organisations at all do not belong in a match-rate
# denominator: there is nothing in the BMF for them to match, which is what OOS
# exists to express. dev/NO-RESIDUAL-AUDIT.md put this at 37 of 100 on its
# population and called the denominator "contested" on that basis. Quantified
# here against the production tier.
NOTORG <- c("INDIVIDUAL", "FOR_PROFIT", "GOVERNMENT", "FOREIGN", "AGGREGATE")
nno <- sum(A$entity_class %in% NOTORG)
say("NOT AN ORGANISATION THE BMF COULD EVER HOLD")
say("  %d of %d  %s  %s -- individuals, businesses, government bodies,",
    nno, nA, pct(nno, nA), ci(nno, nA))
say("  foreign organisations and aggregate placeholders.")
say("  -> ~%.0f of the %d NO identities, i.e. ~%.1f%% of the whole %s-identity file.",
    NO_ALL * nno / nA, NO_ALL, 100 * (NO_ALL * nno / nA) / BASE_IDENT, nf(BASE_IDENT))
print(table(A$entity_class[A$entity_class %in% NOTORG]))
say("\n  What the pipeline's own flags said about these %d cases:", nno)
print(table(flagged_personal = A$looks_personal[A$entity_class %in% NOTORG],
            useNA = "ifany"))
print(table(recipient_type = A$recipient_type[A$entity_class %in% NOTORG],
            useNA = "ifany"))
say("  These reached the matching path, where they can only fail or match")
say("  something wrong. They are a denominator problem, not a matching problem.")

sub_hr()
say("THE STRUCTURAL FLOOR -- real bodies with no exemption of their own")
FLOOR <- c("GROUP_RULING", "CHURCH_EXEMPT", "NO_SEPARATE_EXEMPTION")
nfl <- sum(A$outside_reason %in% FLOOR)
say("  %d of %d  %s  %s", nfl, nA, pct(nfl, nA), ci(nfl, nA))
say("  A subordinate under a group ruling, a church, or a programme inside")
say("  another organisation. There is no EIN to find, so no amount of matching")
say("  recovers these. This is the honest floor.")
print(table(A$entity_class[A$outside_reason %in% FLOOR], useNA = "ifany"))

nut <- sum(A$outside_reason %in% "NOT_TRACEABLE")
say("\nUNTRACEABLE -- no organisation of this description found at all: %d of %d  %s",
    nut, nA, pct(nut, nA))

## ---- 4. calibration lives in its own run -----------------------------------
hr(); say("4. CALIBRATION -- deliberately NOT done here"); hr()
# THIS SECTION USED TO COMPARE THE MODEL TO THE HUMAN AUDIT AND IT WAS WRONG.
#
# It joined dev/no-residual-verdicts.csv to this sample on grant_id, reported
# 4 of 8 agreement and Cohen's kappa 0.26, and read as evidence that the
# model's taxonomy was unreliable. The join was invalid: grant_id is positional
# and not stable across runs, so the two sides described DIFFERENT GRANTS.
# Checked on the filed name, 0 of those 9 pairs referred to the same
# organisation -- G003722 is `EASTER SEAL SOCIETY OF DEL-MAR` in the audit and
# `JAMIE DANIELS FOUNDATION` here.
#
# The failure mode is worth naming: a bad join does not error, it produces a
# plausible-looking disagreement. Low agreement between a model and a human is
# exactly what one half-expects, so the number passed the sniff test and would
# have been published.
#
# Re-keyed on filed name, 63 of the 67 verdicts DO match a NO identity in this
# arm, so the comparison is available -- just not on this sample, which only
# overlaps 5 of them. It is done properly in dev/adjudicate-14-no-calib.R on a
# packet built from those 63 cases (PF_NO_SET=cal).
say("The 100-case sample overlaps the prior audit on only a handful of cases,")
say("and the grant_id join that appeared to give more is invalid -- it pairs")
say("unrelated grants. See the note in this script and in stage 10 section 3.")
say("")
say("The human head-to-head is run separately, on a packet built from the 63")
say("prior-audit cases that are still NO in this arm:")
say("  PF_NO_SET=cal Rscript dev/adjudicate-10-no-packet.R")
say("  PF_NO_SET=cal Rscript dev/adjudicate-11-no-search.R")
say("  Rscript dev/adjudicate-14-no-calib.R")
if (nrow(truth))
  say("\n(%d truth rows are present in this packet and are IGNORED here.)", nrow(truth))

## ---- 5. what this does to the match rate -----------------------------------
hr(); say("5. THE MATCH RATE"); hr()
rw <- kw / nA
MAYBE_CLEAR <- 0.742   # vignettes/adjudicating-maybe.Rmd, deep arm, 1,044 MAYBEs

# THREE DENOMINATORS, NAMED, AND NEVER MIXED.
#
# The temptation is to add recovered NO identities to the baseline's numerator
# and divide by the baseline's 4,748. That is wrong, and wrong in the flattering
# direction: 4,748 is the RESULT frame, which excludes the never-scored
# identities, so the recovery would be credited against a denominator that
# never contained the cases being recovered.
say("The denominators are not interchangeable, so all three are named.\n")
say("  result frame  %s  identities with >=1 scored candidate. This is the",
    nf(BASE_IDENT))
say("                       baseline's denominator and the source of 62.74%%.")
say("  in scope      %s  every identity the cascade should have resolved,", nf(IDENT_SCOPE))
say("                       i.e. all %s less %d flagged OOS. %d identities sit",
    nf(IDENT_ALL), N_OOS, IDENT_SCOPE - BASE_IDENT)
say("                       here but not in the result frame: nothing was ever")
say("                       retrieved for them.")
say("  all           %s  every identity in the file.", nf(IDENT_ALL))
sub_hr()
say("BASELINE-2026-10C augmented, on its own denominator:")
say("  %s identities, %s YES = %.2f%%; %s MAYBE; %s NO (tier==NO in the result).",
    nf(BASE_IDENT), nf(BASE_YES), 100 * BASE_YES / BASE_IDENT, nf(BASE_MAYBE),
    nf(NO_SCORED))
say("")
say("The same run on the in-scope denominator, which is the honest one for a")
say("match rate because it keeps the retrieval failures in:")
say("  %s identities, %s YES = %.2f%%  (%.2f points lower)",
    nf(IDENT_SCOPE), nf(BASE_YES), 100 * BASE_YES / IDENT_SCOPE,
    100 * BASE_YES / BASE_IDENT - 100 * BASE_YES / IDENT_SCOPE)
say("  NO tier is %d, not %d: %d scored-and-rejected plus %d never scored.",
    NO_ALL, NO_SCORED, NO_SCORED, NO_UNSCORED)
sub_hr()
say("ADDING THE MEASURED RECOVERY (%s of the %d-case NO tier, stratum A)",
    pct(kw, nA), NO_ALL)
rec_n <- NO_ALL * rw
say("  recovers ~%.0f identities.\n", rec_n)
say("  on the in-scope denominator of %s:", nf(IDENT_SCOPE))
say("    YES alone                          : %.2f%%", 100 * BASE_YES / IDENT_SCOPE)
say("    YES + recovered NO                 : %.2f%%  (+%.2f points)",
    100 * (BASE_YES + rec_n) / IDENT_SCOPE, 100 * rec_n / IDENT_SCOPE)
say("    YES + cleared MAYBE                : %.2f%%",
    100 * (BASE_YES + BASE_MAYBE * MAYBE_CLEAR) / IDENT_SCOPE)
say("    YES + cleared MAYBE + recovered NO : %.2f%%",
    100 * (BASE_YES + BASE_MAYBE * MAYBE_CLEAR + rec_n) / IDENT_SCOPE)
sub_hr()
say("AND ON A CLEANED DENOMINATOR")
say("Dropping the NO-tier payees that are not organisations the BMF could ever")
say("hold (%s of stratum A), because there is nothing for them to match:", pct(nno, nA))
drop <- NO_ALL * nno / nA
den  <- IDENT_SCOPE - drop
say("  removes ~%.0f identities: %s -> %.0f", drop, nf(IDENT_SCOPE), den)
say("    YES alone                          : %.2f%%  (+%.2f points, from scope",
    100 * BASE_YES / den, 100 * BASE_YES / den - 100 * BASE_YES / IDENT_SCOPE)
say("                                                   alone, matching nothing)")
say("    YES + cleared MAYBE + recovered NO : %.2f%%",
    100 * (BASE_YES + BASE_MAYBE * MAYBE_CLEAR + rec_n) / den)
say("")
say("Compare the two levers on the NO tier: recovery is worth %.2f points and",
    100 * rec_n / IDENT_SCOPE)
say("the scope correction %.2f. Only one of them is a matching improvement; the",
    100 * BASE_YES / den - 100 * BASE_YES / IDENT_SCOPE)
say("other is a statement about which grants were ever answerable.")

## ---- 6. cost ---------------------------------------------------------------
hr(); say("6. COST"); hr()
say("searches: %d over %d cases, %.1f/case", sum(d$searches), nrow(d),
    mean(d$searches))
say("tokens: %s in, %s out, %s cache read, %s cache written",
    nf(sum(d$in_tokens)), nf(sum(d$out_tokens)), nf(sum(d$cache_read)),
    nf(sum(d$cache_write)))
say("confidence x search outcome:")
print(table(confidence = d$confidence, search_confirmed = d$search_confirmed))
say("\norg_found x bmf_expectation:")
print(table(org_found = d$org_found, bmf_expectation = d$bmf_expectation))

## ---- write -----------------------------------------------------------------
keep <- intersect(c("grant_id", "stratum", "batch_order", "recip_name",
  "recip_city", "recip_state", "recip_zip5", "recipient_type", "looks_personal",
  "n_cand", "n_pairs", "best_score", "best_name", "org_found", "org_name",
  "ein", "ein_source", "ein_in_ref", "ein_offered", "found_score", "found_pass",
  "entity_class", "bmf_expectation", "outside_reason", "miss_hypothesis",
  "confidence", "evidence", "search_findings", "search_confirmed",
  "cleared_web", "cleared_cand", "cleared_any", "searches"), names(d))
saveRDS(d[, keep, with = FALSE], file.path(DD, sprintf("ADJ-NO-SCORED%s.rds", TAG)))
fwrite(d[, keep, with = FALSE], file.path(DD, sprintf("ADJ-NO-SCORED%s.csv", TAG)))
hr()
say("wrote data-dev/ADJ-NO-SCORED%s.{rds,csv}", TAG)
hr()
