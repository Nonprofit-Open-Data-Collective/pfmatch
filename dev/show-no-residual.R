#!/usr/bin/env Rscript
# Render the NO-residual audit cases. Usage: Rscript dev/show-no-residual.R <from> <to> [stratum]
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
a <- commandArgs(TRUE)
d <- fread(file.path(PF, "data-dev", "AUDIT-NO-RESIDUAL-100.csv"), colClasses = "character")
if (length(a) >= 3) d <- d[prior == a[3]]
setorder(d, id)
tr <- function(x, n) { x[is.na(x)] <- ""; substr(gsub("[[:space:]]+", " ", x), 1, n) }
for (i in as.integer(a[1]):min(as.integer(a[2]), nrow(d))) {
  x <- d[i]
  cat(sprintf("\n%3d %s  %s | %s %s %s | %s\n", i, x$id, tr(x$recip_name, 46),
              tr(x$recip_city, 16), x$recip_state, x$recip_zip5, x$taxyear))
  if (nzchar(tr(x$recip_street, 1)))
    cat(sprintf("        st: %s\n", tr(x$recip_street, 50)))
  if (nzchar(tr(x$purpose, 1)))  cat(sprintf("        pu: %s\n", tr(x$purpose, 88)))
  cat(sprintf("        near: BMF %-34s sc=%s | MDB %-34s sc=%s\n",
              tr(x$bmf_near, 34), substr(x$score_a, 1, 5),
              tr(x$mdb_near, 34), substr(x$score_b, 1, 5)))
}
