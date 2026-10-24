#!/usr/bin/env Rscript
# Two years, 2024 and 2025, is the minimal case that reproduces the shift:
# 2025 is the only year missing PF_15_G_PAID_RECIP_STAT. Build them together
# and check the 2025 block lands in register.
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("-", 78))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))

tmp <- file.path(tempdir(), "pf-colorder-test.csv")
hr(); say("building 2024 + 2025 -> %s", basename(tmp))
pf_efilepf_build(out = tmp, years = 2024:2025, schema = "v2", dedup = FALSE,
                 verbose = TRUE)

d <- fread(tmp, colClasses = "character", na.strings = NULL, showProgress = FALSE)
hr(); say("built %s rows, %d columns", format(nrow(d), big.mark = ","), ncol(d))

chk <- function(yr) {
  x <- d[TAX_YEAR == yr]
  nz <- function(col) 100 * mean(nzchar(x[[col]]))
  say("  %s  n=%-9s AMT %5.1f%%  STATE %5.1f%%  CITY %5.1f%%  NAME %5.1f%%  STAT %5.1f%%",
      yr, format(nrow(x), big.mark = ","),
      nz("PF_15_G_PAID_AMT"), nz("PF_15_G_PAID_RECIP_ADDR_STATE"),
      nz("PF_15_G_PAID_RECIP_ADDR_CITY"), nz("PF_15_G_PAID_RECIP_NAME_ORG_L1"),
      nz("PF_15_G_PAID_RECIP_STAT"))
  invisible(c(amt = nz("PF_15_G_PAID_AMT"), stat = nz("PF_15_G_PAID_RECIP_STAT")))
}
hr(); say("non-empty rate by year (the shift showed as AMT 0%% and STAT ~100%%)")
a <- chk("2024"); b <- chk("2025")

hr()
say("2025 amount populated   %s   (was 0%% before the fix)",
    if (b[["amt"]] > 50) "PASS" else "FAIL")
say("2025 status empty       %s   (the column genuinely does not exist in 2025)",
    if (b[["stat"]] < 1)  "PASS" else "FAIL")

## numeric sanity: an amount column holding purpose text would not parse
num <- suppressWarnings(as.numeric(d[TAX_YEAR == "2025" & nzchar(PF_15_G_PAID_AMT),
                                     PF_15_G_PAID_AMT]))
say("2025 amounts numeric    %s   (%.2f%% parse)",
    if (mean(!is.na(num)) > 0.99) "PASS" else "FAIL", 100 * mean(!is.na(num)))
say("  median 2025 grant $%s", format(round(median(num, na.rm = TRUE)), big.mark = ","))
unlink(tmp)
hr()
