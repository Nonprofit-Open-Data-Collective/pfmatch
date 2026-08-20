#!/usr/bin/env Rscript
# Render the MAYBE adjudication frame as compact human-readable blocks.
# Usage: Rscript dev/show-maybe.R <from> <to>
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
a  <- commandArgs(TRUE); from <- as.integer(a[1]); to <- as.integer(a[2])

d <- fread(file.path(PF, "data-dev", "AUDIT-MAYBE-100.csv"), colClasses = "character")
ids <- unique(d$grant_id)[from:to]
tr <- function(x, n) { x[is.na(x)] <- ""; substr(x, 1, n) }

for (id in ids) {
  x <- d[grant_id == id]
  cat(sprintf("\n== %s  [%s] ================================================\n",
              id, x$recipient_type[1]))
  cat(sprintf("  FILED : %s%s\n", x$recip_name[1],
              ifelse(nzchar(tr(x$recip_name_alt[1], 99)), paste0("  /alt: ", x$recip_name_alt[1]), "")))
  cat(sprintf("          %s, %s %s   %s\n", tr(x$recip_city[1], 24), x$recip_state[1],
              tr(x$recip_zip5[1], 5), tr(x$recip_street[1], 34)))
  cat(sprintf("  PURPOSE: %s\n", tr(x$grant_purpose[1], 96)))
  cat(sprintf("  FDN   : %s [%s] ntee=%s %s\n", tr(x$fdn_name[1], 40),
              x$FDN_org_addr_state[1], x$FDN_ntee_code_clean[1],
              tr(x$FDN_ntee_code_definition[1], 30)))
  for (i in seq_len(nrow(x))) {
    cat(sprintf("   %s%d) %-44s %-16s %-2s %-5s sc=%-5s z=%s c=%s s=%s\n",
                ifelse(x$is_top_pick[i] == "1", "*", " "), i,
                tr(x$cand_name[i], 44), tr(x$cand_city[i], 16), x$cand_state[i],
                tr(x$cand_zip5[i], 5), x$score[i], x$geo_zip5[i], x$geo_city[i], x$geo_state[i]))
    cat(sprintf("        ein=%s  ntee=%-6s %-34s | %s\n", x$ein[i],
                x$CAND_ntee_code_clean[i], tr(x$CAND_ntee_code_definition[i], 34),
                tr(x$CAND_activity_code_definitions[i], 46)))
  }
}
