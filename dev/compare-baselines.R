#!/usr/bin/env Rscript
# BASELINE-2026-10 (v1 ef1k) against BASELINE-2026-10B (v2 lifted, deduplicated).
# Same references, same passes, same normalizer signature: the population is the
# only thing that moved, so every difference here is attributable to it.
#
# HOW THE MATCHING MOVE IS ISOLATED, and a withdrawn claim.
#
# An earlier version of this script decomposed the clear-rate delta as
#
#   clear2 - clear1  =  dYES / n2                     <- labelled "matching"
#                    +  YES1 * (n1 - n2) / (n1 * n2)  <- labelled "denominator"
#
# The identity is exact. The LABEL on the first term is wrong, and the wrong
# label produced a published false alarm: it read -1.30 and -1.45 points and
# the script shouted that the population shrinking had MASKED 87% of a recall
# loss. There was no recall loss. dYES is the change in the YES COUNT, which
# mixes matching with WHICH IDENTITIES ARE PRESENT, so when the population
# changes that term absorbs the composition effect and reports it as matching.
#
# These frames carry `.id`, so the matching move is directly measurable: hold
# the identity set fixed and compare the SAME identities in both baselines.
# That is what the script now does. On the committed run it gives -0.20 points
# for `active` and **+0.04** for `augmented` -- against the -1.30 and -1.45 the
# mislabelled term reported. BASELINE-2026-10B/MANIFEST.md's published -0.17 /
# -0.21 and its sentence "the direction is the expected one rather than a
# regression" are both correct, and the alarm this script raised against them
# was not.
#
# The population change is also not the clean removal the old comment assumed.
# 299 identities leave and 206 arrive in `active`, 244 and 150 in `augmented`,
# because the v2 lift re-keys some of them -- so "97 superseded filings were
# removed" does not describe the id set either.
#
# The lesson is the one dev/ab-idf-gate.R already carries, which this script
# had not learnt: a metric that raises a FALSE alarm is as bad as one that
# cannot alarm. Practice 7 asks for a measurement that can come out wrong; it
# does not excuse the alarming direction from needing a second instrument.
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


hr(); say("DELTA, v2 minus v1"); hr()
# The matching move, measured on the identities both baselines hold. This is
# the term the old decomposition mislabelled; see the header. Composition is
# reported beside it as who left and who arrived, with their clear rates, so
# the net is attributable without inferring anything.
tiers <- function(dir, arm) {
  r <- as.data.table(readRDS(file.path(PF, "dev", dir,
         sprintf("benchmark-1k-%s.rds", arm))))
  need_cols(r, ".id", "tier", what = sprintf("%s %s, keyed comparison", dir, arm))
  stopifnot(!anyDuplicated(as.character(r$.id)))
  setNames(r$tier == "YES", as.character(r$.id))
}
for (a in unique(z$arm)) {
  s <- z[arm == a]
  if (nrow(s) != 2L) next
  y1 <- tiers("BASELINE-2026-10", a); y2 <- tiers("BASELINE-2026-10B", a)
  sh <- intersect(names(y1), names(y2))
  gone <- setdiff(names(y1), names(y2)); new <- setdiff(names(y2), names(y1))
  need_rows(length(sh), min = 1L, what = "identities both baselines hold")
  m1 <- 100 * mean(y1[sh]); m2 <- 100 * mean(y2[sh])
  tot <- s$clear[2] - s$clear[1]
  say("  %-10s identities %+5d   clear %+.2f points   Y+M %+.2f points", a,
      s$n[2] - s$n[1], tot, s$surf[2] - s$surf[1])
  say("    MATCHING, on the %s identities both hold : %.2f%% -> %.2f%%  %+.2f pt",
      format(length(sh), big.mark = ","), m1, m2, m2 - m1)
  say("    COMPOSITION: %d left (cleared %.1f%%), %d arrived (cleared %.1f%%)",
      length(gone), 100 * mean(y1[gone]), length(new), 100 * mean(y2[new]))
  # Fire only on a real divergence between the matching move and the headline,
  # measured rather than inferred from a mislabelled term. The old condition
  # fired on both arms and was wrong on both.
  if (abs(m2 - m1) > 0.25 && abs(m2 - m1) > 2 * abs(tot))
    say("    *** the headline (%+.2f) understates the matching move (%+.2f) by %.1fx",
        tot, m2 - m1, abs(m2 - m1) / max(abs(tot), 1e-9))
  else
    say("    (headline and matching move agree in sign and size; no masking)")
}
hr()
say("The identity set changes in both directions -- identities leave AND arrive")
say("-- because v2 re-keys some of them, so the net identity count understates")
say("how much of the population moved. That is why matching is measured on the")
say("intersection rather than inferred from the counts.")
say("")
say("Both `clear` columns above are YES over the RESULT FRAME -- these are")
say("saved benchmark frames and the in-scope identity count is not in them, so")
say("identities no pass retrieved for are missing from both numerator and")
say("denominator. Holding the identity set fixed removes the composition")
say("effect; it cannot recover the retrieval failures neither base counts. For")
say("that, read a run through pf_result_tiers() against x$in_scope")
say("(dev/bench-md-reference.R, dev/adjudicate-16-fuzzy-regress.R).")
fwrite(z, file.path(PF, "data-dev", "BASELINE-COMPARISON.csv"))
say("wrote data-dev/BASELINE-COMPARISON.csv")
