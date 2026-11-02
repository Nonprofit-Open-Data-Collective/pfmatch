#!/usr/bin/env Rscript
# Clean A/B for distinct_name_min_idf: same pairs, same everything, only the
# gate varies. Rescoring the stored pairs avoids re-blocking, so nothing else
# can move.
#
# The gate's job is to demote, so "demoted: N" is the number it was built to
# produce and cannot argue against it. Two columns are printed beside it:
# `gained` (stated as should-be-zero, so a non-zero reads as a defect rather
# than as a result), and EIN churn -- identities YES under both settings but on
# a different EIN, which a status-only comparison records as no change. The
# CORRECTION in dev/PROMOTION-FLOOR-FINDINGS.md turned on this script moving
# "2 cases, net zero"; net zero over a status comparison is not net zero over
# the EINs, and that distinction was not measured.
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
gained <- sum(off$status != "YES" & on_al$status == "YES")
say("\nYES gained (should be 0): %d", gained)
if (gained > 0) {
  say("*** non-zero: the gate is a veto and cannot promote a pair, so this is")
  say("*** a selection move or a defect. Investigate before reading the above.")
}

# EIN churn: YES both ways, different EIN. "net zero" measured on status alone
# counts these as unchanged, and they are not -- one of the two EINs is wrong.
both  <- which(off$status == "YES" & on_al$status == "YES")
e_off <- off$ein[both]; e_on <- on_al$ein[both]
churn <- both[!is.na(e_off) & !is.na(e_on) & e_off != e_on]
say("\nYES both ways on a DIFFERENT EIN: %d of %d", length(churn), length(both))
say("  net zero on the status comparison is not net zero on the EINs.")
if (length(churn))
  print(head(data.table(name = substr(off$recip_name[churn], 1, 30),
                        ein_off = off$ein[churn],
                        bmf_off = substr(off$bmf_name[churn], 1, 26),
                        ein_on = on_al$ein[churn],
                        bmf_on = substr(on_al$bmf_name[churn], 1, 26)), 20),
        row.names = FALSE)
