#!/usr/bin/env Rscript
# Render the cleared cell by stratum. The cell is not homogeneous: 54% of it is
# matchdb confirming tier 1's own top pick and clearing a tie, 46% is matchdb
# naming a different organisation. Those carry different risk and a blended
# sample would average them into a number that describes neither.
# Usage: Rscript dev/show-cleared-stratum.R <same|diff> <from> <to>
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
a <- commandArgs(TRUE)
d <- fread(file.path(PF, "data-dev", "CASCADE-ADJUDICATION.csv"), colClasses = "character")
d <- d[grepl("cleared", cell)]
d <- if (a[1] == "same") d[ein_a == ein_b] else d[ein_a != ein_b]
set.seed(7); d <- d[sample(.N)]
from <- as.integer(a[2]); to <- min(as.integer(a[3]), nrow(d))
tr <- function(x, n) { x[is.na(x)] <- ""; substr(gsub("[[:space:]]+", " ", x), 1, n) }
for (i in from:to) {
  x <- d[i]
  cat(sprintf("\n=== %d/%d  %s\n", i, nrow(d), x$id))
  cat(sprintf("  FILED: %-40s | %s %s %s | %s\n", tr(x$recip_name, 40),
              tr(x$recip_city, 15), x$recip_state, x$recip_zip5, x$taxyear))
  if (nzchar(tr(x$purpose, 1))) cat(sprintf("  PURP : %s\n", tr(x$purpose, 95)))
  if (a[1] != "same")
    cat(sprintf("  tier1: %-40s | %s %s   sc=%s\n", tr(x$bmf_name, 40),
                tr(x$bmf_city, 15), x$bmf_state, substr(x$score_a, 1, 5)))
  cat(sprintf("  CHOSE: %-40s | %s %s %s  sc=%s\n", tr(x$mdb_name, 40),
              tr(x$mdb_city, 15), x$mdb_state, x$mdb_zip, substr(x$score_b, 1, 5)))
  if (nzchar(tr(x$mdb_ntee, 1))) cat(sprintf("         NTEE: %s\n", tr(x$mdb_ntee, 85)))
  if (nzchar(tr(x$mdb_mission, 1))) cat(sprintf("         MISS: %s\n", tr(x$mdb_mission, 150)))
}
