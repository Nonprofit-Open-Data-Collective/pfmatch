#!/usr/bin/env Rscript
# ============================================================================
# adjudicate-14-no-calib.R -- the model against the human, on the same cases.
#
# dev/adjudicate-12-no-score.R reports what the NO tier contains, and almost
# all of it rests on the model's taxonomy being trustworthy. This is the only
# script that tests that against anything other than the model's own
# confidence.
#
# THE CASES. dev/no-residual-verdicts.csv holds 67 verdicts from the 2026-10-22
# hand audit. Re-keyed on the FILED RECIPIENT NAME -- not grant_id, which is
# positional and not stable across runs -- 63 of them are still NO identities
# in this arm. PF_NO_SET=cal builds a packet from exactly those, and stage 11
# runs the same single search arm over it with the same instructions. So both
# sides judged the same organisations from the same filed record, and the only
# difference is who did the judging.
#
# WHAT AGREEMENT HERE DOES AND DOES NOT MEAN.
#
# The human audit was a single adjudicator with no blind second pass, and its
# own write-up says so: "treat the 32/59/6 split as having a few points of
# slack". So a disagreement is not automatically the model's error, and this
# script does not call it one. What it can establish:
#
#   high agreement  the taxonomy in stage 12 is reproducing a human's reading
#                   of the same cases, which is the claim being made for it
#   low agreement   one of the two is wrong and the vignette cannot lean on the
#                   taxonomy without saying which cases are in dispute
#
# The EIN comparison is sharper than the class comparison, because it needs no
# vocabulary mapping: where both sides name an EIN, they either name the same
# nine digits or they do not.
#
# THE ONE ASYMMETRY TO RESPECT. 17 of the 67 human verdicts carry
# basis = "reference", meaning the EIN was read off a reference near-miss rather
# than established independently. Those are in the reference by construction,
# exactly like a model verdict with ein_source = CANDIDATE, so they cannot
# corroborate reference coverage and are reported separately wherever that
# matters.
#
# OUTPUT  data-dev/ADJ-NOCAL-SCORED.{rds,csv}
#
# USAGE  Rscript dev/adjudicate-14-no-calib.R
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
PF <- Sys.getenv("PFMATCH_DIR", ".")
DD <- file.path(PF, "data-dev")

say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() cat(strrep("=", 78), "\n")
sub_hr <- function() cat(strrep("-", 78), "\n")
pct <- function(a, b) if (b == 0) "n/a" else sprintf("%.1f%%", 100 * a / b)
wilson <- function(k, n, z = 1.96) {
  if (n == 0) return(c(NA, NA))
  p <- k / n; d <- 1 + z^2 / n
  c0 <- (p + z^2 / (2 * n)) / d
  h <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / d
  c(max(0, c0 - h), min(1, c0 + h))
}
ci <- function(k, n) { w <- wilson(k, n); sprintf("[%.1f%%, %.1f%%]", 100*w[1], 100*w[2]) }

hr(); say("NO-TIER EXPERIMENT  stage 14: model vs human on the same cases"); hr()

for (f in c("ADJ-NOCAL-SEARCH.rds", "ADJ-NOCAL-CASES.rds", "ADJ-NOCAL-TRUTH.rds",
            "ADJ-NOCAL-PAIRS.rds", "ADJ-NO-REFEIN.rds"))
  if (!file.exists(file.path(DD, f)))
    stop(sprintf("%s absent. Run:\n  PF_NO_SET=cal Rscript dev/adjudicate-10-no-packet.R\n  PF_NO_SET=cal Rscript dev/adjudicate-11-no-search.R", f),
         call. = FALSE)

v     <- as.data.table(readRDS(file.path(DD, "ADJ-NOCAL-SEARCH.rds")))
cases <- as.data.table(readRDS(file.path(DD, "ADJ-NOCAL-CASES.rds")))
truth <- as.data.table(readRDS(file.path(DD, "ADJ-NOCAL-TRUTH.rds")))
pairs <- as.data.table(readRDS(file.path(DD, "ADJ-NOCAL-PAIRS.rds")))
refein <- readRDS(file.path(DD, "ADJ-NO-REFEIN.rds"))

d <- merge(cases[, .(grant_id, n_cand, best_score, looks_personal, recipient_type)],
           v[, setdiff(names(v), c("stratum", "batch_order", "n_cand")), with = FALSE],
           by = "grant_id")
d <- merge(d, truth, by = "grant_id")
d <- d[api_ok == TRUE]
say("cases with both a model verdict and a human verdict: %d", nrow(d))

# The filed name is re-checked here even though stage 10 joined on it. The
# whole reason this script exists is that a key which looked fine produced a
# silent mis-join, so the key is verified at the point of use rather than
# trusted from upstream.
nzkey <- function(x) gsub("[^A-Z0-9]", "", toupper(trimws(x)))
bad <- d[nzkey(recip_name) != nzkey(truth_filed)]
if (nrow(bad))
  stop(sprintf("%d of %d rows pair a model verdict with a human verdict about a\n  DIFFERENT filed name. The join is broken; do not read the numbers below.",
       nrow(bad), nrow(d)), call. = FALSE)
say("join verified: filed name identical on all %d rows", nrow(d))

d[, ein_in_ref := ifelse(is.na(ein), NA, ein %in% refein)]
pset <- pairs[, .(eins = list(unique(.ein))), by = .id]
d[, ein_offered := { idx <- match(grant_id, pset$.id)
  mapply(function(e, i) if (is.na(e) || is.na(i)) NA else e %in% pset$eins[[i]],
         ein, idx) }]

## ---- 1. the four-class comparison ------------------------------------------
hr(); say("1. DO THEY AGREE ON WHAT THE CASE IS"); hr()
# The vocabularies differ, so the mapping is written out rather than buried in
# a nested ifelse. UNCLEAR is excluded explicitly: the human declined to call
# those, and folding them into any class would manufacture agreement or
# disagreement out of a non-answer.
NOTORG <- c("INDIVIDUAL", "FOR_PROFIT", "GOVERNMENT", "FOREIGN", "AGGREGATE")
FLOOR  <- c("GROUP_RULING", "CHURCH_EXEMPT", "NO_SEPARATE_EXEMPTION")
say("human vocabulary -> four comparable classes:")
say("  REAL-ORG, UNCLEAR-GEO     -> RECOVERABLE   a real body with its own EIN")
say("  INDIVIDUAL, NOT-A-CHARITY -> NOT_AN_ORG    nothing the BMF could hold")
say("  NO-OWN-EIN                -> NO_EXEMPTION  real, but no exemption of its own")
say("  UNFINDABLE                -> UNTRACEABLE   could not be identified")
say("  UNCLEAR                   -> excluded, it carries no answer\n")
d[, h := fcase(
  truth_verdict %in% c("REAL-ORG", "UNCLEAR-GEO"), "RECOVERABLE",
  truth_verdict %in% c("INDIVIDUAL", "NOT-A-CHARITY"), "NOT_AN_ORG",
  truth_verdict %in% "NO-OWN-EIN", "NO_EXEMPTION",
  truth_verdict %in% "UNFINDABLE", "UNTRACEABLE",
  default = NA_character_)]
d[, mm := fcase(
  bmf_expectation %in% "LISTED", "RECOVERABLE",
  entity_class %in% NOTORG, "NOT_AN_ORG",
  outside_reason %in% FLOOR, "NO_EXEMPTION",
  outside_reason %in% "NOT_TRACEABLE", "UNTRACEABLE",
  default = NA_character_)]
cmp <- d[!is.na(h) & !is.na(mm)]
say("comparable: %d of %d (%d excluded: %d human UNCLEAR, %d unmapped model)",
    nrow(cmp), nrow(d), nrow(d) - nrow(cmp),
    sum(d$truth_verdict == "UNCLEAR"), sum(!is.na(d$h) & is.na(d$mm)))
print(table(human = cmp$h, model = cmp$mm))
ag <- sum(cmp$h == cmp$mm)
say("\nagreement: %d of %d  %s  %s", ag, nrow(cmp), pct(ag, nrow(cmp)), ci(ag, nrow(cmp)))
lv <- sort(union(cmp$h, cmp$mm))
tb <- table(factor(cmp$h, lv), factor(cmp$mm, lv))
po <- sum(diag(tb)) / sum(tb)
pe <- sum(rowSums(tb) * colSums(tb)) / sum(tb)^2
say("Cohen's kappa: %.3f (observed %.3f, chance %.3f)", (po - pe) / (1 - pe), po, pe)
say("\nper-class recall against the human:")
for (k in lv) {
  n <- sum(cmp$h == k)
  if (n) say("  %-13s %d of %d  %s", k, sum(cmp$h == k & cmp$mm == k), n,
             pct(sum(cmp$h == k & cmp$mm == k), n))
}

sub_hr()
say("WHERE THEY DISAGREE, case by case. The human audit was a single")
say("adjudicator with no blind second pass, so these are disputes, not errors.")
dis <- cmp[h != mm]
for (k in seq_len(nrow(dis))) with(dis[k], say(
  "\n  %s  %s\n    human %-12s (%s)\n    model %-12s (%s / %s / %s)\n    model org: %s\n    model says: %s",
  grant_id, substr(recip_name, 1, 44), h, truth_verdict, mm, entity_class,
  bmf_expectation, outside_reason, substr(org_name, 1, 52),
  substr(evidence, 1, 150)))

## ---- 2. the EIN comparison -------------------------------------------------
hr(); say("2. DO THEY AGREE ON THE EIN"); hr()
say("This needs no vocabulary mapping. Where both name an EIN they either name")
say("the same nine digits or they do not.\n")
both <- d[!is.na(ein) & !is.na(truth_ein)]
say("  both name an EIN            : %d", nrow(both))
if (nrow(both)) {
  same <- sum(both$ein == both$truth_ein)
  say("    identical                : %d of %d  %s  %s", same, nrow(both),
      pct(same, nrow(both)), ci(same, nrow(both)))
  for (k in which(both$ein != both$truth_ein)) with(both[k], say(
    "    DIFFER %s  %-30s\n      model %s  %s\n      human %s  %s  (basis %s)",
    grant_id, substr(recip_name, 1, 30), ein, substr(org_name, 1, 40),
    truth_ein, substr(truth_name, 1, 40), truth_basis))
}
say("  human only                 : %d", nrow(d[is.na(ein) & !is.na(truth_ein)]))
for (k in seq_len(nrow(d[is.na(ein) & !is.na(truth_ein)])))
  with(d[is.na(ein) & !is.na(truth_ein)][k], say(
    "    %s  %-32s human %s (basis %s); model said %s/%s",
    grant_id, substr(recip_name, 1, 32), truth_ein, truth_basis,
    entity_class, bmf_expectation))
say("  model only                 : %d", nrow(d[!is.na(ein) & is.na(truth_ein)]))
for (k in seq_len(nrow(d[!is.na(ein) & is.na(truth_ein)])))
  with(d[!is.na(ein) & is.na(truth_ein)][k], say(
    "    %s  %-32s model %s %s (human verdict %s)",
    grant_id, substr(recip_name, 1, 32), ein,
    ifelse(ein_in_ref %in% TRUE, "[in ref]", "[NOT in ref]"), truth_verdict))
say("  neither                    : %d", nrow(d[is.na(ein) & is.na(truth_ein)]))

sub_hr()
say("RECOVERY RATE, both sides, on the same %d cases", nrow(d))
# The human audit's own headline was 32 REAL-ORG of 67. Recomputed here on the
# subset that is still NO in this arm so the two sides share a denominator.
hrec <- sum(d$h %in% "RECOVERABLE")
mrec <- sum(d$mm %in% "RECOVERABLE")
say("  human calls recoverable : %d  %s", hrec, pct(hrec, nrow(d)))
say("  model calls recoverable : %d  %s", mrec, pct(mrec, nrow(d)))
say("  model names an EIN that is in the reference: %d  %s",
    sum(d$ein_in_ref %in% TRUE), pct(sum(d$ein_in_ref %in% TRUE), nrow(d)))
say("  human named an EIN independently (basis=web): %d",
    sum(!is.na(d$truth_ein) & d$truth_basis == "web"))

## ---- 3. the coverage test, both sides --------------------------------------
hr(); say("3. IS THE CORRECT EIN IN THE REFERENCE -- both sides' answer"); hr()
say("The prior audit's robust result was 21 of 21 independently established")
say("EINs present in the reference. Re-tested on these cases, from both sides.\n")
hw <- d[!is.na(truth_ein) & truth_basis == "web"]
hw[, in_ref := truth_ein %in% refein]
say("  human EINs, independently established: %d of %d in the reference  %s",
    sum(hw$in_ref), nrow(hw), pct(sum(hw$in_ref), nrow(hw)))
mw <- d[!is.na(ein) & ein_source %in% "WEB"]
say("  model EINs, WEB-sourced              : %d of %d in the reference  %s",
    sum(mw$ein_in_ref %in% TRUE), nrow(mw), pct(sum(mw$ein_in_ref %in% TRUE), nrow(mw)))
for (k in which(!mw$ein_in_ref %in% TRUE)) with(mw[k], say(
  "    model EIN not in reference: %s %s %s (%s)", grant_id,
  substr(recip_name, 1, 28), ein, entity_class))

## ---- 4. retrieval vs scoring, on this set ----------------------------------
hr(); say("4. RETRIEVAL OR SCORING, on the cases both sides call recoverable"); hr()
rec <- d[ein_in_ref %in% TRUE]
if (nrow(rec)) {
  off <- sum(rec$ein_offered %in% TRUE)
  say("  %d recoverable cases: %d were offered to the scorer and rejected,",
      nrow(rec), off)
  say("  %d were never offered at all.", nrow(rec) - off)
  say("\n  dev/replay-no-residual-blocking.R answered this for 25 cases by")
  say("  replaying the whole blocker and got 18 retrieved of 25. This is the")
  say("  same question answered by lookup against the cached pairs.")
  print(table(miss_hypothesis = rec$miss_hypothesis,
              offered = ifelse(rec$ein_offered %in% TRUE, "offered", "never")))
}

## ---- write -----------------------------------------------------------------
keep <- intersect(c("grant_id", "recip_name", "truth_filed", "n_cand", "best_score",
  "org_found", "org_name", "ein", "ein_source", "ein_in_ref", "ein_offered",
  "entity_class", "bmf_expectation", "outside_reason", "miss_hypothesis",
  "confidence", "evidence", "search_findings", "search_confirmed",
  "truth_verdict", "truth_ein", "truth_name", "truth_basis", "truth_note",
  "h", "mm", "searches"), names(d))
saveRDS(d[, keep, with = FALSE], file.path(DD, "ADJ-NOCAL-SCORED.rds"))
fwrite(d[, keep, with = FALSE], file.path(DD, "ADJ-NOCAL-SCORED.csv"))
hr(); say("wrote data-dev/ADJ-NOCAL-SCORED.{rds,csv}"); hr()
