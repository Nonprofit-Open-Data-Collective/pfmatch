#!/usr/bin/env Rscript
# Clean A/B for distinct_name_min_idf: same pairs, same everything, only the
# gate varies. Rescoring the stored pairs avoids re-blocking, so nothing else
# can move.
#
# The gate's job is to demote, so "demoted: N" is the number it was built to
# produce and cannot argue against it. Three things print beside it: the YES it
# gains, the net it has to reconcile with, and EIN churn.
#
# WHAT A RUN AT npmatch 0.1.1.9000 FOUND, and it is not what was expected here:
#
#   min_idf 0  : YES 2821  MAYBE 1006  NO 1093
#   min_idf 10 : YES 2822  MAYBE  986  NO 1112
#   demoted 1 (THE CENTER FOR MICHIGAN, YPSILANTI against DETROIT -> MAYBE)
#   gained 2    net +1 YES    EIN churn 0 of 2820
#
# So dev/PROMOTION-FLOOR-FINDINGS.md's CORRECTION -- "moves 2 cases, net zero",
# the figure that shipped distinct_name_min_idf = 0 -- does not reproduce. The
# net is +1, not zero.
#
# EIN CHURN WAS THE WRONG HYPOTHESIS. This script was changed on the reasoning
# that "net zero" on a status comparison might hide identities re-pointed to a
# different EIN. Measured: zero of 2,820. The column stays because zero
# measured is a different statement from nothing measured, but it is not where
# the discrepancy lives -- the status comparison itself does not balance, and
# the gross-against-net line below is what shows it.
#
# (Figures above are from another session's run and were not re-derived here;
# re-run to confirm before quoting them.)
suppressWarnings(suppressMessages(library(data.table)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
source(file.path(PF, "dev", "assert-lib.R"))
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 74), "\n")

m <- readRDS(file.path(PF, "data-dev", "PF-MATCH-RESULT-1k.rds"))
pairs <- attr(m$result, "pairs")
if (is.null(pairs$name_idf)) {
  say("stored pairs predate the name_idf column -- rerun PF_SET=1k first"); quit(save = "no")
}
say("pairs carry name_idf: %s non-missing of %s",
    format(sum(!is.na(pairs$name_idf)), big.mark = ","), format(nrow(pairs), big.mark = ","))

run <- function(thr) {
  cfg <- npmatch::np_config(distinct_name_min_idf = thr)
  p <- npmatch::np_veto(npmatch::np_score(pairs, cfg, method = "hier"), cfg)
  res <- npmatch::np_tier(npmatch::np_select(p, cfg), cfg)
  x <- m; x$result <- res
  attr(x$result, "pairs") <- p; attr(x$result, "config") <- cfg
  pf_status(x)
}
off <- run(0); on <- run(10)

hr(); say("A/B: distinct_name_min_idf 0 vs 10 (identical pairs)"); hr()
for (nm in c("off", "on")) {
  s <- get(nm); t <- table(factor(s$status, pf_status_levels()))
  say("min_idf = %-3s  YES %5d  MAYBE %5d  NO %5d", if (nm == "off") "0" else "10",
      t[["YES"]], t[["MAYBE"]], t[["NO"]])
}
k <- match(off$grant_id, on$grant_id)
# NA from match() would drop an identity out of every count below rather than
# register it as a change; both arms rescore the same stored pairs, so assert it.
stopifnot(!anyNA(k), setequal(off$grant_id, on$grant_id))
need_rows(nrow(off), n = nrow(on), what = "identities in both arms")
need_vocab(c(off$status, on$status), pf_status_levels(),
           what = "pf_status() vocabulary, both arms")
on_al <- on[k, , drop = FALSE]              # on, aligned to off, row for row
moved <- which(off$status == "YES" & on_al$status != "YES")
say("\nYES -> demoted by the gate: %d", length(moved))
if (length(moved))
  print(data.table(name = substr(off$recip_name[moved], 1, 32),
                   bmf = substr(off$bmf_name[moved], 1, 32),
                   qcity = substr(off$recip_city[moved], 1, 14),
                   bcity = substr(on_al$bmf_city[moved], 1, 14),
                   now = as.character(on_al$status[moved])), row.names = FALSE)
# "YES gained (should be 0)" was the wrong invariant, and a run of this script
# at npmatch 0.1.1.9000 reports 2. The gate cannot RAISE a pair's score -- but
# np_tier() demotes on the margin to the runner-up (R/dyads.R's "collapse
# before selection" section), so removing a runner-up RAISES the winner's
# margin and can carry it MAYBE -> YES. A gain is therefore expected
# behaviour, not a defect, and an assertion that calls it one trains the reader
# to ignore the line.
#
# The invariant that IS true: no gained identity's score went up. That is what
# is asserted, and the margin is printed beside it so the mechanism is visible
# rather than inferred.
gain_set <- which(off$status != "YES" & on_al$status == "YES")
say("\nYES gained by the gate: %d", length(gain_set))
say("  Expected, not a defect: the gate removes pairs, and np_tier() demotes on")
say("  margin to the runner-up, so removing a runner-up can promote the winner.")
if (length(gain_set)) {
  up <- gain_set[!is.na(off$score[gain_set]) & !is.na(on_al$score[gain_set]) &
                 on_al$score[gain_set] > off$score[gain_set]]
  say("  of the %d, %d had their SCORE rise -- that one would be a defect, since",
      length(gain_set), length(up))
  say("  a veto cannot raise a score. Anything above 0 stops the run.")
  print(data.table(name = substr(off$recip_name[gain_set], 1, 30),
                   was = as.character(off$status[gain_set]),
                   score_off = off$score[gain_set],
                   score_on = on_al$score[gain_set],
                   margin_off = off$margin[gain_set],
                   margin_on = on_al$margin[gain_set]), row.names = FALSE)
  stopifnot(length(up) == 0L)
}

# Gross against net, the check that caught this. A gate that only demotes would
# have net == -demoted; with the margin route open, net == gained - demoted.
# Printed because the two disagreeing is how the margin mechanism surfaced at
# all: the run reports demoted 1, gained 2, net +1 YES.
net <- sum(on_al$status == "YES") - sum(off$status == "YES")
say("\nreconciliation: net YES %+d = gained %d - demoted %d = %+d",
    net, length(gain_set), length(moved), length(gain_set) - length(moved))
stopifnot(net == length(gain_set) - length(moved))

# EIN churn: YES both ways, different EIN. Measured at zero here (see the
# header), so this is a negative result rather than the explanation it was
# added to test. It stays because a zero that was measured and a quantity that
# was never looked at print the same way in a note and not in a log.
both  <- which(off$status == "YES" & on_al$status == "YES")
e_off <- off$ein[both]; e_on <- on_al$ein[both]
churn <- both[!is.na(e_off) & !is.na(e_on) & e_off != e_on]
say("\nYES both ways on a DIFFERENT EIN: %d of %d", length(churn), length(both))
say("  Measured at 0 at npmatch 0.1.1.9000. Printed anyway: a zero that was")
say("  measured is a different claim from a quantity nobody looked at.")
if (length(churn))
  print(head(data.table(name = substr(off$recip_name[churn], 1, 30),
                        ein_off = off$ein[churn],
                        bmf_off = substr(off$bmf_name[churn], 1, 26),
                        ein_on = on_al$ein[churn],
                        bmf_on = substr(on_al$bmf_name[churn], 1, 26)), 20),
        row.names = FALSE)
