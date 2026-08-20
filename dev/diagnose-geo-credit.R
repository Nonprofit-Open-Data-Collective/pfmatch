#!/usr/bin/env Rscript
# name_sim favours the correct candidate, yet the score inverts. So the geo term
# decided it. Which geo signal fired, and on what?
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 74), "\n")

a <- fread(file.path(PF, "data-dev", "AUDIT-MAYBE-100.csv"), colClasses = "character")
for (gid in c("G002178", "G004775", "G001981")) {
  x <- a[grant_id == gid]
  hr(); say("%s  filed: %s", gid, x$recip_name[1])
  say("  filed address: %s | %s, %s %s", x$recip_street[1], x$recip_city[1],
      x$recip_state[1], x$recip_zip5[1])
  print(x[, .(rank, cand = substr(cand_name, 1, 34), cand_city, cand_state, cand_zip5,
              name_sim, geo_zip5, geo_city, geo_state, geo_stnum, score)],
        row.names = FALSE)
  # reconstruct the implied geo sub-score from score = 0.6*name + 0.4*geo
  ns <- as.numeric(x$name_sim); sc <- as.numeric(x$score)
  say("  implied geo sub-score per candidate: %s",
      paste(sprintf("%.2f", (sc - 0.6 * ns) / 0.4), collapse = "  "))
}
