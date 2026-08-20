#!/usr/bin/env Rscript
# Build the non-itemizing-returns report over the available grant files.
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")

g <- pf_read_grants(file.path(PF, "inputs"), pattern = "^(50k|100k)_grants\\.csv$")
say("grant rows read: %s", format(nrow(g), big.mark = ","))
r <- pf_attached_report(g)
fwrite(r, file.path(PF, "data-dev", "ATTACHED-SCHEDULE-REPORT.csv"))
say("\nwrote data-dev/ATTACHED-SCHEDULE-REPORT.csv (%d returns)", nrow(r))

d <- as.data.table(r)
say("\ntop 12 returns by un-itemized dollars:")
print(head(d[, .(filer = substr(filer_name, 1, 30), taxyear,
                 rows = n_placeholder_rows,
                 hidden = paste0("$", formatC(placeholder_amount, format = "f",
                                              digits = 0, big.mark = ",")),
                 pct = pct_dollars_hidden,
                 text = substr(placeholder_text, 1, 24))], 12), row.names = FALSE)

say("\nhow much of each return is hidden:")
print(d[, .N, by = .(bucket = cut(pct_dollars_hidden, c(-1, 25, 50, 75, 99.9, 100),
                                  labels = c("<25%", "25-50%", "50-75%", "75-99%", "100%")))][order(bucket)],
      row.names = FALSE)
say("\nthe wording filers use:")
print(head(d[, .N, by = .(text = toupper(substr(placeholder_text, 1, 30)))][order(-N)], 10),
      row.names = FALSE)
