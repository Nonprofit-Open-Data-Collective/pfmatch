#!/usr/bin/env Rscript
# ============================================================================
# The 45.6% of multi-filing units the simple rule cannot resolve.
#
# dev/probe-amended-returns.R found 10,073 units (ORG_EIN, TAX_YEAR) with more
# than one filing, and that in 4,592 of them the NEWEST filing is not the
# amended one. Almost all of those -- 4,588 -- have no amended filing at all:
# two ORIGINAL returns for the same EIN-year. And 4,302 units have tied
# RETURN_TIME_STAMP values, so they cannot be ordered by time either.
#
# So "keep the most recent, flag if it is not the amended one" resolves roughly
# half the duplicates and leaves the rest undecided. This measures what those
# undecided units actually look like, which decides whether they can be deduped
# safely or must go to review:
#
#   identical row sets      a true duplicate filing -- safe to drop one
#   different row sets      two substantively different returns -- not safe
#
# Comparison is on the grant content (recipient, amount, purpose, address),
# NOT on TABLE_ID, since row ordering within a filing carries no meaning.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(library(digest)))
setDTthreads(0)
PF  <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("-", 86))
sq  <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; x }

GRANT <- c("PF_15_G_PAID_RECIP_NAME_ORG_L1", "PF_15_G_PAID_RECIP_NAME_ORG_L2",
           "PF_15_G_PAID_RECIP_NAME_PERS", "PF_15_G_PAID_RECIP_ADDR_L1",
           "PF_15_G_PAID_RECIP_ADDR_CITY", "PF_15_G_PAID_RECIP_ADDR_STATE",
           "PF_15_G_PAID_RECIP_ADDR_ZIP", "PF_15_G_PAID_AMT",
           "PF_15_G_PAID_PURPOSE", "PF_15_G_PAID_RECIP_STAT")
META <- c("OBJECTID", "ORG_EIN", "TAX_YEAR", "RETURN_AMENDED_X",
          "RETURN_TIME_STAMP")

dir <- pf_efilepf_dir()
fs  <- list.files(dir, pattern = "GRANT-PAID.*CSV$", full.names = TRUE)
d <- rbindlist(lapply(fs, function(f) {
  h <- names(fread(f, nrows = 0, showProgress = FALSE))
  fread(f, colClasses = "character", showProgress = FALSE,
        select = intersect(c(META, GRANT), h))
}), fill = TRUE)
say("rows: %s", format(nrow(d), big.mark = ","))

d[, amended := sq(RETURN_AMENDED_X) %in% c("X", "x", "1", "TRUE", "Y")]
d[, unit := paste(ORG_EIN, TAX_YEAR, sep = "|")]
nf <- unique(d[, .(unit, OBJECTID)])[, .(n = .N), by = unit]
multi <- nf[n > 1L]$unit
dm <- d[unit %in% multi]
say("multi-filing units: %s  (%s grant rows)",
    format(length(multi), big.mark = ","), format(nrow(dm), big.mark = ","))

## ---- content fingerprint per filing ---------------------------------------
gcols <- intersect(GRANT, names(dm))
dm[, rowkey := do.call(paste, c(lapply(gcols, function(k) sq(dm[[k]])), sep = "\r"))]
fil <- dm[, .(n_rows = .N,
              fp = digest::digest(sort(rowkey), algo = "xxhash64"),
              amended = amended[1], ts = sq(RETURN_TIME_STAMP)[1]),
          by = .(unit, OBJECTID)]

u <- fil[, .(n_filings = .N,
             n_amended = sum(amended),
             identical_content = uniqueN(fp) == 1L,
             ts_distinct = uniqueN(ts) == .N,
             rows_min = min(n_rows), rows_max = max(n_rows)), by = unit]

hr(); say("WHAT THE DUPLICATE UNITS LOOK LIKE")
u[, cls := fcase(
  n_amended > 0L & identical_content, "amended present, content identical",
  n_amended > 0L,                     "amended present, content DIFFERS",
  identical_content,                  "no amended, content identical",
  default                           = "no amended, content DIFFERS")]
print(u[, .(units = .N), by = cls][order(-units)], row.names = FALSE)

hr(); say("CAN THEY BE ORDERED IN TIME?")
print(u[, .(units = .N), by = .(cls, ts_distinct)][order(cls, -units)], row.names = FALSE)

hr(); say("ROW-COUNT SPREAD WITHIN A UNIT (max - min)")
u[, spread := rows_max - rows_min]
print(u[, .(units = .N), by = .(cls, same_rowcount = spread == 0L)][order(cls)],
      row.names = FALSE)

hr(); say("SAFE-TO-DEDUP TALLY")
safe <- u[identical_content == TRUE]
say("  content identical -> dropping a copy loses nothing : %s (%.1f%%)",
    format(nrow(safe), big.mark = ","), 100 * nrow(safe) / nrow(u))
say("  content differs   -> needs a rule or review        : %s (%.1f%%)",
    format(nrow(u) - nrow(safe), big.mark = ","),
    100 * (nrow(u) - nrow(safe)) / nrow(u))
say("")
say("  of the differing ones, an amended filing exists in : %s",
    format(nrow(u[identical_content == FALSE & n_amended > 0L]), big.mark = ","))
say("  ... and no amended filing exists in                : %s",
    format(nrow(u[identical_content == FALSE & n_amended == 0L]), big.mark = ","))

ex <- u[cls == "no amended, content DIFFERS"][order(-spread)]
if (nrow(ex)) {
  hr(); say("EXAMPLES: two ORIGINAL filings, different content")
  say("  %-24s %9s %9s %9s", "unit (EIN|year)", "filings", "rows_min", "rows_max")
  for (i in seq_len(min(10L, nrow(ex))))
    say("  %-24s %9d %9d %9d", ex$unit[i], ex$n_filings[i], ex$rows_min[i], ex$rows_max[i])
}
fwrite(u, file.path(PF, "data-dev", "AMENDED-UNIT-DETAIL.csv"))
hr(); say("wrote data-dev/AMENDED-UNIT-DETAIL.csv")
