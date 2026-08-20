#!/usr/bin/env Rscript
# Compact render of the auto-accept validation sample for labelling.
# Usage: Rscript dev/show-autoaccept.R <from> <to>
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
a  <- commandArgs(TRUE); from <- as.integer(a[1]); to <- as.integer(a[2])
d  <- fread(file.path(PF, "data-dev", "AUTOACCEPT-SAMPLE-200.csv"), colClasses = "character")
tr <- function(x, n) { x[is.na(x)] <- ""; substr(x, 1, n) }
for (i in from:min(to, nrow(d))) {
  x <- d[i]
  cat(sprintf("%3d %-38s | %-16s %s %s\n", i, tr(x$recip_name, 38),
              tr(x$recip_city, 16), x$recip_state, x$recip_zip5))
  cat(sprintf("    -> %-38s | %-16s %s %s  [%s]\n", tr(x$bmf_name, 38),
              tr(x$cand_city, 16), x$cand_state, x$cand_zip, x$name_ver))
  cat(sprintf("       sc=%s nm=%s mg=%s band=%s | runner: %s (%s)\n",
              x$score, x$name_sim, x$margin, x$n_band,
              tr(x$ru_name, 30), ifelse(is.na(x$ru_score) | x$ru_score == "", "-", x$ru_score)))
}
