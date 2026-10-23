#!/usr/bin/env Rscript
# Validate the rebuilt grant file before it is published.
#
# Three questions, in order of how badly a wrong answer would hurt:
#   1. Does the existing pipeline read it? A file that matches the schema on
#      paper but breaks pf_prepare_grants() is worse than no file.
#   2. Is the +40% real? More rows than the GTDC extract is only good news if
#      they are additional grants and not duplication.
#   3. Does 2025 behave as measured -- in scope, typed other_unknown?
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
suppressWarnings(suppressMessages(devtools::load_all(
  Sys.getenv("PFMATCH_DIR", "."), quiet = TRUE)))
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("-", 78))

NEW <- "C:/Users/jlecy/Documents/grants/PF-GRANTS-PAID-2009-2025.csv"
GT  <- "C:/Users/jlecy/Documents/grants/2025_08_29_All_Years_990PFPart14Grants3A.csv"

hr(); say("1. DOES THE PIPELINE READ IT?"); hr()
d <- fread(NEW, colClasses = "character", showProgress = FALSE, nrows = 200000,
           na.strings = NULL)
say("read %s rows x %d cols", format(nrow(d), big.mark = ","), ncol(d))
p <- as.data.table(pf_prepare_grants(d))
say("pf_prepare_grants() returned %s rows", format(nrow(p), big.mark = ","))
say("  in_scope      : %.1f%%", 100 * mean(p$in_scope))
say("  has a name    : %.1f%%", 100 * mean(!is.na(p$recip_name)))
say("  has a state   : %.1f%%", 100 * mean(!is.na(p$recip_state)))
say("  has a ZIP5    : %.1f%%", 100 * mean(!is.na(p$recip_zip5)))
say("recipient types:")
print(p[, .N, by = recipient_type][order(-N)], row.names = FALSE)

hr(); say("2. IS THE EXTRA VOLUME REAL?  per-year, new vs GTDC"); hr()
ny <- fread(NEW, select = "TAXYEAR", colClasses = "character", showProgress = FALSE)
gy <- fread(GT,  select = "TAXYEAR", colClasses = "character", showProgress = FALSE)
a <- ny[, .(efile = .N), by = TAXYEAR]
b <- gy[, .(gtdc  = .N), by = TAXYEAR]
m <- merge(a, b, by = "TAXYEAR", all = TRUE)
m[is.na(efile), efile := 0L][is.na(gtdc), gtdc := 0L]
setorder(m, TAXYEAR)
m[, delta := efile - gtdc]
print(m, row.names = FALSE)
say("")
say("totals: efile %s | gtdc %s | delta %+d",
    format(sum(m$efile), big.mark = ","), format(sum(m$gtdc), big.mark = ","),
    sum(m$efile) - sum(m$gtdc))

hr(); say("3. DOES 2025 BEHAVE AS MEASURED?"); hr()
d25 <- fread(NEW, colClasses = "character", showProgress = FALSE, na.strings = NULL)[
  TAXYEAR == "2025"][seq_len(min(100000, .N))]
if (nrow(d25)) {
  p25 <- as.data.table(pf_prepare_grants(d25))
  say("2025 sample: %s rows", format(nrow(p25), big.mark = ","))
  say("  in_scope    : %.1f%%  (expected ~ the same as other years)", 100 * mean(p25$in_scope))
  say("  SIGOCPYRFSTA non-blank: %.1f%% (expected 0)",
      100 * mean(nzchar(ifelse(is.na(d25$SIGOCPYRFSTA), "", d25$SIGOCPYRFSTA))))
  print(p25[, .N, by = recipient_type][order(-N)], row.names = FALSE)
} else say("no 2025 rows found")

hr(); say("4. THE COUNTRY FIELD THE GTDC FILE NEVER POPULATED"); hr()
cn <- fread(NEW, select = c("TAXYEAR", "SIGOCAFFRFACO"), colClasses = "character",
            showProgress = FALSE, na.strings = NULL)
cn[, has := nzchar(ifelse(is.na(SIGOCAFFRFACO), "", SIGOCAFFRFACO))]
say("rows with a country value: %s of %s (%.2f%%)",
    format(sum(cn$has), big.mark = ","), format(nrow(cn), big.mark = ","),
    100 * mean(cn$has))
if (sum(cn$has)) {
  say("commonest values:")
  print(head(cn[has == TRUE, .N, by = SIGOCAFFRFACO][order(-N)], 8), row.names = FALSE)
}
say("")
say("GTDC had this column present but empty throughout, which is why")
say("pf_prepare_grants() detects foreign recipients from address text.")
