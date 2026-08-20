#!/usr/bin/env Rscript
# Render the enriched candidate view for reading.
# Usage: Rscript dev/show-enriched.R <from> <to> [hard|correct|all]
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
a  <- commandArgs(TRUE)
from <- as.integer(a[1]); to <- as.integer(a[2])
grp  <- if (length(a) >= 3) a[3] else "hard"

d <- fread(file.path(PF, "data-dev", "HARD-ENRICHED.csv"), colClasses = "character")
keep <- switch(grp,
  hard    = d$verdict %in% c("WRONG", "AMBIGUOUS"),
  correct = d$verdict == "CORRECT",
  rep(TRUE, nrow(d)))
d <- d[keep]
ids <- unique(d$idx)
ids <- ids[from:min(to, length(ids))]

tr <- function(x, n) { x[is.na(x)] <- ""; x <- gsub("[[:space:]]+", " ", x); substr(x, 1, n) }
for (id in ids) {
  s <- d[idx == id]
  h <- s[1]
  cat(sprintf("\n=== #%s  [%s] %s\n", id, h$verdict, tr(h$note, 70)))
  cat(sprintf("  GRANT: %s | %s %s %s | $%s\n", tr(h$recip_name, 46),
              tr(h$recip_city, 18), h$recip_state, h$recip_zip5, h$amount))
  if (nzchar(tr(h$purpose, 1))) cat(sprintf("  PURPOSE: %s\n", tr(h$purpose, 150)))
  for (i in seq_len(nrow(s))) {
    x <- s[i]
    cat(sprintf("  %s%s %-44s | %-16s %s %s | ntee=%s sub=%s %s prog=%s\n",
                if (x$is_pick == "TRUE") "*" else " ", x$rank,
                tr(x$cand_name, 44), tr(x$cand_city, 16), x$cand_state, x$cand_zip,
                ifelse(nzchar(x$ntee), x$ntee, "-"), x$subsection,
                ifelse(nzchar(x$return_type), x$return_type, "no990"), x$n_prog))
    if (nzchar(tr(x$ntee_text, 1)))
      cat(sprintf("       NTEE: %s\n", tr(x$ntee_text, 130)))
    if (nzchar(tr(x$mission, 1)))
      cat(sprintf("       MISS: %s\n", tr(x$mission, 230)))
    if (nzchar(tr(x$prog, 1)))
      cat(sprintf("       PROG: %s\n", tr(x$prog, 230)))
  }
}
