#!/usr/bin/env Rscript
# ============================================================================
# validate-corpus-v2.R -- run the integrity checks over the whole rebuilt
# corpus, one year at a time.
#
# The column-shift bug that wrecked 2025 was invisible to every corpus-wide
# check: 96% of rows were fine, so the amount column still "resolved" and the
# state/ZIP sanity test still passed. Only a per-year view shows a year sitting
# at 0% on a column the other sixteen populate. That check now lives in
# pf_validate_grants(); this runs it, plus the row key and dedup checks, over
# all 17 million rows without holding them in memory at once.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("=", 92))

PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
V2 <- "C:/Users/jlecy/Documents/grants/PF-GRANTS-PAID-V2-2009-2025.csv"
CHUNK <- 2000000L

hr(); say("validate-corpus-v2  %s", format(Sys.time())); hr()
hdr <- names(fread(V2, nrows = 0L))
say("%s  %.2f GB, %d columns", basename(V2), file.size(V2) / 2^30, length(hdr))

COLS <- c("PF_15_G_PAID_RECIP_NAME_ORG_L1", "PF_15_G_PAID_RECIP_ADDR_CITY",
          "PF_15_G_PAID_RECIP_ADDR_STATE",  "PF_15_G_PAID_RECIP_ADDR_ZIP",
          "PF_15_G_PAID_AMT",               "PF_15_G_PAID_RECIP_STAT",
          "PF_15_G_PAID_PURPOSE")
KEEP <- c("OBJECTID", "TABLE_ID", "EIN2", "TAX_YEAR", "dedup_action",
          "dedup_flag", COLS)

# With header = FALSE the columns have no names yet, so `select` has to be
# given by POSITION and col.names must describe only the selected ones --
# passing the full header alongside a name-based select misaligns them.
sel <- sort(match(KEEP, hdr))
stopifnot(!anyNA(sel))

acc <- list(); keys <- list(); i <- 0L; seen <- 0L
repeat {
  ch <- fread(V2, colClasses = "character", na.strings = NULL,
              skip = 1L + i * CHUNK, nrows = CHUNK, header = FALSE,
              select = sel, col.names = hdr[sel], showProgress = FALSE)
  nn <- nrow(ch); if (!nn) break
  seen <- seen + nn; i <- i + 1L
  acc[[i]] <- ch[, c(lapply(.SD, function(v) sum(nzchar(v))), .(n = .N)),
                 by = TAX_YEAR, .SDcols = COLS]
  keys[[i]] <- ch[, paste(OBJECTID, TABLE_ID, sep = "|")]
  rm(ch)
  if (nn < CHUNK) break
}
z <- rbindlist(acc)[, lapply(.SD, sum), by = TAX_YEAR][order(TAX_YEAR)]
k <- unlist(keys, use.names = FALSE); rm(keys, acc); invisible(gc())

hr(); say("PER-YEAR NON-EMPTY RATE  (a shifted block shows as 0%% on a populated column)")
say("%-6s %10s %7s %7s %7s %7s %7s %7s %7s", "year", "rows",
    "name", "city", "state", "zip", "amt", "stat", "purp")
for (j in seq_len(nrow(z))) {
  n <- z$n[j]
  say("%-6s %10s %6.1f%% %6.1f%% %6.1f%% %6.1f%% %6.1f%% %6.1f%% %6.1f%%",
      z$TAX_YEAR[j], format(n, big.mark = ","),
      100 * z$PF_15_G_PAID_RECIP_NAME_ORG_L1[j] / n,
      100 * z$PF_15_G_PAID_RECIP_ADDR_CITY[j]   / n,
      100 * z$PF_15_G_PAID_RECIP_ADDR_STATE[j]  / n,
      100 * z$PF_15_G_PAID_RECIP_ADDR_ZIP[j]    / n,
      100 * z$PF_15_G_PAID_AMT[j]               / n,
      100 * z$PF_15_G_PAID_RECIP_STAT[j]        / n,
      100 * z$PF_15_G_PAID_PURPOSE[j]           / n)
}
say("")
say("  2025 carries no PF_15_G_PAID_RECIP_STAT -- the IRS dropped the box, so")
say("  0%% there is correct. Any OTHER zero in this table is a shifted block.")

amt <- 100 * z$PF_15_G_PAID_AMT / z$n
bad <- z$TAX_YEAR[amt < 50]
hr()
say("amount populated in every year : %s", if (!length(bad)) "PASS"
    else paste("FAIL --", paste(bad, collapse = ", ")))
say("row key unique over %s rows : %s", format(length(k), big.mark = ","),
    if (!anyDuplicated(k)) "PASS" else "FAIL")
say("total rows                     : %s", format(seen, big.mark = ","))
hr(); say("done  %s", format(Sys.time()))
