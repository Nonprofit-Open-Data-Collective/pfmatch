#!/usr/bin/env Rscript
# ============================================================================
# A/B the name comparator: plain Jaro (what production does) vs Jaro-Winkler
# (what it is documented to do). See dev/JARO-NOT-JAROWINKLER.md.
#
# reclin2::cmp_jarowinkler() calls stringdist(method = "jw") with no `p`, so the
# name/geo path has always been plain Jaro, while the DBA cross-products in
# np_compare() used p = 0.1. npmatch now exposes config$jw_p: NULL reproduces
# that split exactly, a number applies one value to both paths.
#
# The 21-case name test set said the prefix boost helps true pairs (+0.075) more
# than false ones (+0.044) and lifts prec@1 from 62% to 67%. That cannot be
# extrapolated: every threshold was tuned against Jaro behaviour, and raising
# all name similarities by 0.04-0.08 moves pairs across the 0.65 and 0.78 lines
# at once. This measures it on the real cascade.
#
# Mirrors dev/bench-efilepf.R exactly -- same grant files, same passes, same
# direct pf_match_grants() call with no dedup -- so grant_id lines up with every
# adjudicated verdict in dev/ and the audit cells are directly comparable.
#
# NO TIMINGS. An unrelated 15-worker job held the machine throughout this
# session (dev/BENCHMARK-NOTES.md). Tier counts and EINs are deterministic.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(devtools::load_all(
  Sys.getenv("NPMATCH_DIR", "../npmatch"), quiet = TRUE)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
setDTthreads(4L)
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("=", 86))
sb  <- function() message(strrep("-", 86))
e9  <- function(z) { z <- gsub("[^0-9]", "", as.character(z))
                     fifelse(nchar(z) == 9L, z, NA_character_) }

CACHE <- file.path(PF, "data-dev", "BMF-REF-AUG-2026-08-20.rds")
grants <- pf_recover_name_from_street(
  pf_read_grants(file.path(PF, "inputs"), pattern = "^ef1k_grants_.*\\.csv$"))
hr(); say("JARO vs JARO-WINKLER  --  %s grant rows", format(nrow(grants), big.mark = ",")); hr()
ref <- readRDS(CACHE)
say("reference: %s rows", format(nrow(ref$reference), big.mark = ","))
PASSES <- c(pf_staged_passes("lean", concat = TRUE), pf_recovery_passes(state = TRUE))

run <- function(jp, tag) {
  sb(); say("RUN: %s", tag); sb()
  m <- pf_match_grants(grants, ref, config = np_config(jw_p = jp),
                       passes = PASSES, recover = TRUE, verbose = FALSE)
  r <- as.data.table(m$result)
  r[, ein9 := e9(overall_ein)]
  tb <- table(factor(r$tier, levels = c("YES", "MAYBE", "NO", "OOS")))
  say("  %s", paste(sprintf("%s=%d", names(tb), as.integer(tb)), collapse = "  "))
  setnames(r[, .(.id, tier, ein9, overall_score)], c(".id","overall_score"), c("grant_id","score"))[]
}

A <- run(NULL, "jw_p = NULL  (plain Jaro -- current production)")
B <- run(0.1,  "jw_p = 0.1   (true Jaro-Winkler)")

cl <- function(x) 100 * mean(x$tier == "YES")
ym <- function(x) 100 * mean(x$tier %in% c("YES", "MAYBE"))
hr(); say("HEADLINE"); hr()
say("  %-16s %8s %10s", "", "YES", "YES+MAYBE")
say("  %-16s %7.1f%% %9.1f%%", "Jaro (current)", cl(A), ym(A))
say("  %-16s %7.1f%% %9.1f%%", "Jaro-Winkler",   cl(B), ym(B))
say("  %-16s %+7.1f %+10.1f", "change (pts)",    cl(B) - cl(A), ym(B) - ym(A))

j <- merge(A, B, by = "grant_id", suffixes = c("_a", "_b"))
hr(); say("TIER MOVEMENT (rows = Jaro, cols = Jaro-Winkler)"); hr()
print(dcast(j[, .N, by = .(tier_a, tier_b)], tier_a ~ tier_b,
            value.var = "N", fill = 0), row.names = FALSE)

hr(); say("EIN CHURN among rows YES under BOTH"); hr()
yy <- j[tier_a == "YES" & tier_b == "YES"]
same <- sum(!is.na(yy$ein9_a) & yy$ein9_a == yy$ein9_b)
chg  <- sum(!is.na(yy$ein9_a) & !is.na(yy$ein9_b) & yy$ein9_a != yy$ein9_b)
say("  YES in both : %s", format(nrow(yy), big.mark = ","))
say("  same EIN    : %s (%.1f%%)", format(same, big.mark = ","), 100 * same / max(1, nrow(yy)))
say("  EIN CHANGED : %s (%.1f%%)", format(chg, big.mark = ","), 100 * chg / max(1, nrow(yy)))

## ---- recovery on hand-adjudicated answers ----------------------------------
# BIASED on purpose and must be read that way: these 25 were drawn from what the
# CURRENT pipeline failed on, so they measure recovery of known failures, not
# precision. Precision would need adjudicated YES cells, which do not exist for
# this grant file.
hr(); say("RECOVERY ON THE 25 ADJUDICATED NO-RESIDUAL CASES (biased sample)"); hr()
v <- fread(file.path(PF, "dev", "no-residual-verdicts.csv"), colClasses = "character")
v <- v[verdict == "REAL-ORG" & nzchar(web_ein), .(grant_id = id, tgt = e9(web_ein))]
jj <- merge(j, v, by = "grant_id")
say("  joined: %d of %d", nrow(jj), nrow(v))
if (nrow(jj)) {
  okA <- !is.na(jj$ein9_a) & jj$ein9_a == jj$tgt
  okB <- !is.na(jj$ein9_b) & jj$ein9_b == jj$tgt
  say("  correct EIN as top pick -- Jaro         : %d", sum(okA))
  say("  correct EIN as top pick -- Jaro-Winkler : %d", sum(okB))
  say("  of those, tiered YES or MAYBE -- Jaro   : %d",
      sum(okA & jj$tier_a %in% c("YES", "MAYBE")))
  say("  of those, tiered YES or MAYBE -- JW     : %d",
      sum(okB & jj$tier_b %in% c("YES", "MAYBE")))
  say("")
  say("  %-9s %-28s %-6s %-6s %-9s %-9s", "id", "filed", "tierA", "tierB", "einA_ok", "einB_ok")
  g2 <- as.data.table(pf_prepare_grants(grants))[, .(grant_id, recip_name)]
  jj <- merge(jj, g2, by = "grant_id", all.x = TRUE)
  setorder(jj, grant_id)
  for (i in seq_len(nrow(jj)))
    say("  %-9s %-28s %-6s %-6s %-9s %-9s", jj$grant_id[i],
        substr(sq <- ifelse(is.na(jj$recip_name[i]), "", jj$recip_name[i]), 1, 28),
        jj$tier_a[i], jj$tier_b[i],
        ifelse(!is.na(jj$ein9_a[i]) & jj$ein9_a[i] == jj$tgt[i], "yes", "-"),
        ifelse(!is.na(jj$ein9_b[i]) & jj$ein9_b[i] == jj$tgt[i], "yes", "-"))
}

fwrite(j, file.path(PF, "data-dev", "BENCH-JW-AB.csv"))
hr(); say("wrote data-dev/BENCH-JW-AB.csv")
say("")
say("READ THIS BEFORE ACTING: a clear-rate gain here is NOT evidence of")
say("correctness. The adjudicated sample is biased toward current failures, and")
say("the YES cells are unadjudicated for this file, so a rise in YES could be")
say("recall or could be false accepts. Deciding needs the newly-promoted cells")
say("sampled and judged, as was done for the cascade in CASCADE-STRATEGY.md.")
