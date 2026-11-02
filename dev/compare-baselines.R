#!/usr/bin/env Rscript
# BASELINE-2026-10 (v1 ef1k) against BASELINE-2026-10B (v2 lifted, deduplicated).
# Same references, same passes, same normalizer signature: the population is the
# only thing that moved, so every difference here is attributable to it.
suppressWarnings(suppressMessages(library(data.table)))
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("=", 84))
PF <- Sys.getenv("PFMATCH_DIR", ".")
source(file.path(PF, "dev", "assert-lib.R"))

grab <- function(dir, arm) {
  f <- file.path(PF, "dev", dir, sprintf("benchmark-1k-%s.rds", arm))
  if (!file.exists(f)) return(NULL)
  r <- as.data.table(readRDS(f))
  need_cols(r, "tier", what = sprintf("%s %s tiers", dir, arm))
  need_rows(r, min = 1L, what = sprintf("%s %s identities, this arm's denominator", dir, arm))
  need_vocab(r$tier, c("YES", "MAYBE", "NO"),
             what = sprintf("%s %s tier vocabulary", dir, arm))
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
# The two clear rates stand on DIFFERENT denominators -- the identity count is
# the thing that moved between these baselines -- so their difference is not a
# measurement of matching. It is the sum of two effects, and dropping fewer
# identities would raise it just as readily as matching more of them:
#
#   clear2 - clear1  =  dYES / n2        <- the matching term
#                    +  YES1 * (n1 - n2) / (n1 * n2)   <- the denominator term
#
# Identity, not approximation: the two terms sum to the headline exactly. The
# second is positive whenever the population shrank, which it did here, so a
# headline "clear rate up" is reported WITHOUT knowing whether anything was
# matched better. Printing both lets the decomposition say the gain was all
# denominator -- the finding the single difference could not produce.
for (a in unique(z$arm)) {
  s <- z[arm == a]
  if (nrow(s) != 2L) next
  n1 <- s$n[1]; n2 <- s$n[2]
  num <- 100 * (s$YES[2] - s$YES[1]) / n2
  den <- 100 * s$YES[1] * (n1 - n2) / (n1 * n2)
  tot <- s$clear[2] - s$clear[1]
  stopifnot(abs((num + den) - tot) < 1e-9)   # practice 6: check the identity
  say("  %-10s identities %+5d   clear %+.2f points   Y+M %+.2f points", a,
      n2 - n1, tot, s$surf[2] - s$surf[1])
  say("    of which matching %+.2f pt (YES %+d on %s) and denominator %+.2f pt",
      num, s$YES[2] - s$YES[1], format(n2, big.mark = ","), den)
  # Three cases worth shouting about, and the third is the one the first
  # version of this block missed. On the committed run the headline is -0.17
  # while matching is -1.30 and the denominator gives back +1.13: the
  # population shrinking MASKED 87% of a real recall loss. Neither "headline
  # rose" nor "denominator term is larger" catches that, because the headline
  # moved the same way as the matching and the denominator term is smaller.
  # What matters is that the two terms OPPOSE and the offset is large.
  if (tot > 0 && num < 0) {
    say("    *** the headline ROSE while matching got worse: every point of it")
    say("    *** is the population shrinking. Do not read it as an improvement.")
  } else if (num * den < 0 && abs(den) > 0.5 * abs(num)) {
    say("    *** MASKED: the two terms oppose, and the denominator offsets")
    say("    *** %.0f%% of the matching move. The headline (%+.2f) is %.1fx",
        100 * abs(den) / abs(num), tot, abs(num) / max(abs(tot), 1e-9))
    say("    *** smaller than the matching change (%+.2f) underneath it.", num)
  } else if (tot != 0 && abs(den) > abs(num)) {
    say("    *** the denominator term is the larger of the two: most of this")
    say("    *** arm's headline is the population moving, not the matching.")
  }
}
hr()
say("The identity count falls because deduplication removed 97 of the 5,000")
say("sampled grants as superseded filings, and because identities are grants")
say("collapsed on normalized name+address, so the two do not fall in step.")
say("")
say("Both `clear` columns above are YES over the RESULT FRAME -- these are")
say("saved benchmark frames and the in-scope identity count is not in them, so")
say("identities no pass retrieved for are missing from both numerator and")
say("denominator. The decomposition separates the population move from the")
say("matching move; it cannot recover the retrieval failures neither base")
say("counts. For that, read a run through pf_result_tiers() against x$in_scope")
say("(dev/bench-md-reference.R, dev/adjudicate-16-fuzzy-regress.R).")
fwrite(z, file.path(PF, "data-dev", "BASELINE-COMPARISON.csv"))
say("wrote data-dev/BASELINE-COMPARISON.csv")
