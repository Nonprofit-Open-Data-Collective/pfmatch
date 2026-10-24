#!/usr/bin/env Rscript
# ============================================================================
# bench-fresh-control.R -- is the lifted sample still representative?
#
# The headline recalibration is measured on inputs/efv2_1k_grants_0*.csv, which
# is the old evaluation sample carried onto the deduplicated corpus. That keeps
# the 172 adjudications, but it leaves one thing unverified: those 4,903 grants
# were drawn at random from the UNDEDUPED population, which contains superseded
# filings, so the draw over-weights filers who amended. Pruning the superseded
# rows afterwards does not undo that -- the survivors are still a draw from the
# wrong frame.
#
# dev/cut-fresh-v2-sample.R draws cleanly from the deduplicated corpus. This
# runs the SAME arm, the SAME reference and the SAME configuration over it. If
# the two clear rates agree within sampling error the lifted sample is fine and
# the headline stands on it. If they do not, the gap is the correction, and it
# has to be reported rather than averaged away.
#
# Sampling error on n = 5,000 at p = 0.63 is about +/- 1.3 points at 95%, so
# only a gap materially larger than that means anything.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(devtools::load_all(
  Sys.getenv("NPMATCH_DIR", "../npmatch"), quiet = TRUE)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
setDTthreads(4L)
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("=", 86))

REF    <- file.path(PF, "data-dev", "BMF-REF-AUG-2026-08-20.rds")
PASSES <- c(pf_staged_passes("lean", concat = TRUE), pf_recovery_passes(state = TRUE))

hr(); say("bench-fresh-control  %s", format(Sys.time())); hr()
say("reference %s", basename(REF))
ref <- readRDS(REF)
say("  %s rows", format(nrow(ref$reference), big.mark = ","))

run <- function(pat, label) {
  g <- pf_recover_name_from_street(pf_read_grants(file.path(PF, "inputs"), pattern = pat))
  t0 <- proc.time()[["elapsed"]]
  m <- pf_match_grants(g, ref, passes = PASSES, recover = TRUE, verbose = FALSE)
  r <- as.data.table(m$result)
  el <- proc.time()[["elapsed"]] - t0
  say("  %-10s %5s identities | YES %5.2f%% | Y+M %5.2f%% | %5.1f s", label,
      format(nrow(r), big.mark = ","),
      100 * mean(r$tier == "YES"), 100 * mean(r$tier %chin% c("YES", "MAYBE")), el)
  data.table(arm = label, population = pf_population_id(g), n = nrow(r),
             yes = 100 * mean(r$tier == "YES"),
             ym  = 100 * mean(r$tier %chin% c("YES", "MAYBE")))
}

hr(); say("ARM A (current config) on both v2 populations")
z <- rbindlist(list(
  run("^efv2_1k_grants_[0-9]+\\.csv$",    "lifted"),
  run("^effresh_1k_grants_[0-9]+\\.csv$", "fresh")))

d  <- z$yes[2] - z$yes[1]
# 95% CI on a difference of two independent proportions
se <- sqrt(sum((z$yes / 100) * (1 - z$yes / 100) / z$n)) * 100
hr(); say("CONTROL")
say("  lifted  %5.2f%%  (n = %s)", z$yes[1], format(z$n[1], big.mark = ","))
say("  fresh   %5.2f%%  (n = %s)", z$yes[2], format(z$n[2], big.mark = ","))
say("  diff    %+5.2f points   95%% CI +/- %.2f", d, 1.96 * se)
say("")
say("  %s", if (abs(d) <= 1.96 * se)
  "WITHIN sampling error: the lifted sample represents the deduplicated population."
  else "OUTSIDE sampling error: the lifted sample is biased; report the gap.")
fwrite(z, file.path(PF, "data-dev", "FRESH-CONTROL.csv"))
hr(); say("wrote data-dev/FRESH-CONTROL.csv")
