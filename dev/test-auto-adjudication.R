#!/usr/bin/env Rscript
# ============================================================================
# Can MAYBE be adjudicated automatically, and at what false-positive rate?
#
# Ground truth: dev/maybe-verdicts.csv, 100 hand-adjudicated MAYBE grants. For
# each, whether a correct EIN exists among the surfaced candidates and which
# rank it sits at. That supports a real precision/recall measurement of
# candidate auto-accept rules.
#
# The question is NOT "what is the best rule" -- it is "is there a rule whose
# precision is high enough to accept without review, and how much of the tier
# does it cover". Everything it does not cover is the LLM/human batch.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 78), "\n")

cand <- fread(file.path(PF, "data-dev", "AUDIT-MAYBE-100.csv"), colClasses = "character")
# the audit sheet ships empty verdict columns for human use; drop them so the
# merge with the filled-in verdicts does not collide
drop <- intersect(c("verdict", "verdict_note"), names(cand))
if (length(drop)) cand[, (drop) := NULL]
v    <- fread(file.path(PF, "dev", "maybe-verdicts.csv"), colClasses = "character")
v[, correct_rank := as.integer(correct_rank)]
v[verdict == "CORRECT_TOP" & is.na(correct_rank), correct_rank := 1L]
num <- function(x) suppressWarnings(as.numeric(x))
cand[, `:=`(rank = as.integer(rank), score = num(score), name_sim = num(name_sim),
            geo_zip5 = num(geo_zip5), geo_state = num(geo_state),
            is_top_pick = as.integer(is_top_pick))]

# per-grant features of the TOP PICK, plus the runner-up margin
top <- cand[is_top_pick == 1L]
setorder(cand, grant_id, -score)
runner <- cand[, .(top_score = score[1],
                   runner = if (.N > 1) score[2] else 0,
                   n_cand = .N,
                   n_within_05 = sum(score >= score[1] - 0.05)), by = grant_id]
f <- merge(top, runner, by = "grant_id")
f[, margin := top_score - runner]
f <- merge(f, v[, .(grant_id, verdict, correct_rank)], by = "grant_id")
f[, resolvable := verdict %in% c("CORRECT_TOP", "CORRECT_DEEPER")]
f[, top_is_right := verdict == "CORRECT_TOP"]

say("adjudicated grants with a top pick: %d", nrow(f))
say("  top pick correct           : %d", sum(f$top_is_right))
say("  correct but ranked lower   : %d", sum(f$verdict == "CORRECT_DEEPER"))
say("  no correct candidate       : %d", sum(f$verdict == "NO_CORRECT"))
say("  ambiguous (related EINs)   : %d", sum(f$verdict == "AMBIGUOUS"))

hr(); say("AUTO-ACCEPT RULES -- accept the top pick when the rule fires"); hr()
say("%-40s %7s %8s %10s %9s", "rule", "fires", "correct", "precision", "coverage")
rules <- list(
  "always (accept every top pick)"     = quote(rep(TRUE, .N)),
  "ZIP5 agrees"                        = quote(geo_zip5 == 1),
  "ZIP5 agrees & margin >= 0.05"       = quote(geo_zip5 == 1 & margin >= 0.05),
  "ZIP5 agrees & only 1 in tie band"   = quote(geo_zip5 == 1 & n_within_05 == 1),
  "ZIP5 & name_sim >= 0.95"            = quote(geo_zip5 == 1 & name_sim >= 0.95),
  "ZIP5 & name_sim = 1.0"              = quote(geo_zip5 == 1 & name_sim >= 0.999),
  "name_sim = 1.0 & only 1 in band"    = quote(name_sim >= 0.999 & n_within_05 == 1),
  "margin >= 0.10"                     = quote(margin >= 0.10),
  "margin >= 0.10 & state agrees"      = quote(margin >= 0.10 & geo_state == 1),
  "only 1 candidate at all"            = quote(n_cand == 1)
)
res <- rbindlist(lapply(names(rules), function(nm) {
  fire <- f[, eval(rules[[nm]])]
  fire[is.na(fire)] <- FALSE
  n <- sum(fire); ok <- sum(fire & f$top_is_right)
  data.table(rule = nm, fires = n, correct = ok,
             precision = if (n) ok / n else NA_real_,
             coverage = n / nrow(f))
}))
for (i in seq_len(nrow(res))) with(res[i], say("%-40s %7d %8d %9s %8.0f%%",
    rule, fires, correct, if (is.na(precision)) "-" else sprintf("%.1f%%", 100 * precision),
    100 * coverage))

hr(); say("WHAT AUTO-ACCEPT COSTS AND BUYS"); hr()
say("A rule accepting N cases at precision p adds ~N*p correct matches and")
say("~N*(1-p) false positives that nobody will ever look at again.")
say("")
best <- res[fires >= 10][order(-precision)][1]
say("highest-precision rule with >=10 firings: %s", best$rule)
say("  precision %.1f%% over %d cases (%.0f%% of the tier)",
    100 * best$precision, best$fires, 100 * best$coverage)
n_maybe <- 1006
say("\nprojected over the %d-case MAYBE tier at that coverage/precision:", n_maybe)
say("  auto-accepted    : ~%.0f cases", n_maybe * best$coverage)
say("  of them correct  : ~%.0f", n_maybe * best$coverage * best$precision)
say("  false positives  : ~%.0f", n_maybe * best$coverage * (1 - best$precision))
say("  left for review  : ~%.0f", n_maybe * (1 - best$coverage))

hr(); say("THE RESIDUAL -- what the LLM/human batch would contain"); hr()
fire <- f[, eval(rules[[best$rule]])]; fire[is.na(fire)] <- FALSE
say("cases NOT auto-accepted: %d", sum(!fire))
print(f[!fire, .N, by = verdict][order(-N)], row.names = FALSE)
say("\nof those, how many are resolvable at all (correct EIN is present): %d of %d (%.0f%%)",
    sum(!fire & f$resolvable), sum(!fire), 100 * mean(f$resolvable[!fire]))
fwrite(res, file.path(PF, "data-dev", "AUTO-ADJUDICATION-RULES.csv"))
say("\nCAVEAT: 100 labelled grants. A rule at 95%% precision here has a 95%% CI")
say("of roughly +/- 5 points. Treat these as ranking the rules, not as final")
say("precision estimates; confirm the chosen rule on a fresh labelled sample.")
