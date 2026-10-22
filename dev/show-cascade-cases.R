#!/usr/bin/env Rscript
# Render disputed cascade cases for adjudication.
# Usage: Rscript dev/show-cascade-cases.R <cell-substring> <from> <to>
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
a <- commandArgs(TRUE)
pat <- a[1]; from <- as.integer(a[2]); to <- as.integer(a[3])
d <- fread(file.path(PF, "data-dev", "CASCADE-ADJUDICATION.csv"), colClasses = "character")
d <- d[grepl(pat, cell, fixed = TRUE)]
tr <- function(x, n) { x[is.na(x)] <- ""; substr(gsub("[[:space:]]+", " ", x), 1, n) }
set.seed(42)
if (nrow(d) > 1) d <- d[sample(.N)]          # stable shuffle so a slice is a sample
for (i in from:min(to, nrow(d))) {
  x <- d[i]
  cat(sprintf("\n=== %d/%d  %s  [%s]\n", i, nrow(d), x$id, x$cell))
  cat(sprintf("  FILED : %-42s | %s %s %s | %s | $%s\n", tr(x$recip_name, 42),
              tr(x$recip_city, 16), x$recip_state, x$recip_zip5, x$taxyear, x$amount))
  if (nzchar(tr(x$purpose, 1))) cat(sprintf("  PURPOSE: %s\n", tr(x$purpose, 110)))
  for (p in list(c("bmf", "A/BMF", "ein_a", "score_a"),
                 c("mdb", "B/matchdb", "ein_b", "score_b"))) {
    pre <- p[1]
    cat(sprintf("  %-10s %-9s %-40s | %s %s %s | sc=%s\n", p[2],
                x[[p[3]]], tr(x[[paste0(pre, "_name")]], 40),
                tr(x[[paste0(pre, "_city")]], 14), x[[paste0(pre, "_state")]],
                x[[paste0(pre, "_zip")]], substr(x[[p[4]]], 1, 5)))
    if (nzchar(tr(x[[paste0(pre, "_ntee")]], 1)))
      cat(sprintf("             NTEE: %s\n", tr(x[[paste0(pre, "_ntee")]], 95)))
    if (nzchar(tr(x[[paste0(pre, "_mission")]], 1)))
      cat(sprintf("             MISS: %s\n", tr(x[[paste0(pre, "_mission")]], 165)))
  }
}
