#!/usr/bin/env Rscript
# BASELINE-2026-10 (v1 ef1k) against BASELINE-2026-10B (v2 lifted, deduplicated).
# Same references, same passes, same normalizer signature: the population is the
# only thing that moved, so every difference here is attributable to it.
suppressWarnings(suppressMessages(library(data.table)))
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("=", 84))
PF <- Sys.getenv("PFMATCH_DIR", ".")

grab <- function(dir, arm) {
  f <- file.path(PF, "dev", dir, sprintf("benchmark-1k-%s.rds", arm))
  if (!file.exists(f)) return(NULL)
  r <- as.data.table(readRDS(f))
  t <- table(factor(r$tier, levels = c("YES", "MAYBE", "NO")))
  data.table(baseline = dir, arm = arm, n = nrow(r),
             YES = as.integer(t[["YES"]]), MAYBE = as.integer(t[["MAYBE"]]),
             NO = as.integer(t[["NO"]]),
             clear = 100 * t[["YES"]] / nrow(r),
             surf  = 100 * (t[["YES"]] + t[["MAYBE"]]) / nrow(r))
}
z <- rbindlist(Filter(Negate(is.null), list(
  grab("BASELINE-2026-10",  "active"),    grab("BASELINE-2026-10B", "active"),
  grab("BASELINE-2026-10",  "augmented"), grab("BASELINE-2026-10B", "augmented"))))

hr(); say("BASELINE-2026-10 (v1, undeduplicated)  vs  -10B (v2, deduplicated)"); hr()
say("%-10s %-18s %7s %6s %6s %6s %8s %8s", "arm", "baseline", "ids",
    "YES", "MAYBE", "NO", "clear", "Y+M")
for (i in seq_len(nrow(z)))
  say("%-10s %-18s %7s %6d %6d %6d %7.2f%% %7.2f%%", z$arm[i], z$baseline[i],
      format(z$n[i], big.mark = ","), z$YES[i], z$MAYBE[i], z$NO[i],
      z$clear[i], z$surf[i])

hr(); say("DELTA, v2 minus v1")
for (a in unique(z$arm)) {
  s <- z[arm == a]
  if (nrow(s) != 2L) next
  say("  %-10s identities %+5d   clear %+.2f points   Y+M %+.2f points", a,
      s$n[2] - s$n[1], s$clear[2] - s$clear[1], s$surf[2] - s$surf[1])
}
hr()
say("The identity count falls because deduplication removed 97 of the 5,000")
say("sampled grants as superseded filings, and because identities are grants")
say("collapsed on normalized name+address, so the two do not fall in step.")
fwrite(z, file.path(PF, "data-dev", "BASELINE-COMPARISON.csv"))
say("wrote data-dev/BASELINE-COMPARISON.csv")
