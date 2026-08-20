#!/usr/bin/env Rscript
# ============================================================================
# probe-schedi-vs-efilers.R -- 35.2% of Schedule I alias EINs (279,845) are in
# neither BMF vintage, and name patterns do not explain them:
#
#   churches     11.6% of the missing vs 12.8% of the present -- NOT enriched
#   governments   9.6% vs 5.8% -- mildly enriched, explains ~10%
#   unexplained  76.5%
#
# Jesse's test: organizations that need not register with the IRS to be exempt
# can still be required to file a 990. So the e-file HEADER tables -- every EIN
# that actually filed -- should catch some of the missing set that the BMF never
# will. The size of that overlap is the interesting number: it separates
#
#   FILED BUT UNREGISTERED  a real, verifiable filer the BMF simply lacks. These
#                           are matchable if we add them as reference rows.
#   NEVER FILED             no 990 anywhere. Either out of scope entirely
#                           (governments, small churches) or a bad EIN.
#
# Loads F9-P00-T00-HEADER-<year>.CSV for 2009-2024 into the same DuckDB.
# ============================================================================
suppressWarnings(suppressMessages({
  library(data.table); library(DBI); library(duckdb) }))
setDTthreads(0)

NPM <- Sys.getenv("NPMATCH_DIR", "../npmatch")
DIR <- Sys.getenv("PF_GRANTS_DIR", file.path(path.expand("~"), "Documents", "grants"))
DB  <- file.path(DIR, "schedi_grants.duckdb")
UNI <- file.path(NPM, "data-raw", "bmf_unified_geocoded.csv")
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 72), "\n")

hdr <- list.files(DIR, pattern = "^F9-P00-T00-HEADER-[0-9]{4}[.]CSV$", full.names = TRUE)
if (!length(hdr)) stop("no header CSVs in ", DIR)
say("%d header files", length(hdr))

con <- DBI::dbConnect(duckdb::duckdb(), DB)
DBI::dbExecute(con, "PRAGMA threads=4")

if (!"efilers" %in% DBI::dbListTables(con)) {
  say("loading header tables ...")
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TABLE efiler_raw AS
    SELECT ORG_EIN, ORG_NAME_L1, TAX_YEAR, RETURN_TYPE,
           F9_00_ORG_ADDR_STATE, F9_00_ORG_ADDR_ZIP
    FROM read_csv([%s], union_by_name = true, header = true, all_varchar = true,
                  ignore_errors = true, sample_size = -1)",
    paste(sprintf("'%s'", gsub("\\\\", "/", hdr)), collapse = ", ")))
  DBI::dbExecute(con, "
    CREATE OR REPLACE TABLE efilers AS
    SELECT
      CASE WHEN length(regexp_replace(ORG_EIN,'[^0-9]','','g')) = 9
           THEN regexp_replace(ORG_EIN,'[^0-9]','','g') END AS ein,
      COUNT(*) AS n_returns, MIN(TAX_YEAR) AS first_year, MAX(TAX_YEAR) AS last_year,
      any_value(ORG_NAME_L1) AS name_display,
      any_value(F9_00_ORG_ADDR_STATE) AS state,
      string_agg(DISTINCT RETURN_TYPE, '/') AS return_types
    FROM efiler_raw WHERE ORG_EIN IS NOT NULL GROUP BY 1")
  DBI::dbExecute(con, "DROP TABLE IF EXISTS efiler_raw")
}

say("e-filer returns : %s",
    format(DBI::dbGetQuery(con, "SELECT SUM(n_returns) n FROM efilers")$n, big.mark = ","))
ef <- as.data.table(DBI::dbGetQuery(con,
  "SELECT ein, n_returns, first_year, last_year, name_display, state, return_types
   FROM efilers WHERE ein IS NOT NULL"))
say("distinct e-filer EINs (2009-2024): %s", format(nrow(ef), big.mark = ","))

al <- as.data.table(DBI::dbGetQuery(con,
  "SELECT ein, name_display, state, n_filers FROM alias WHERE ein IS NOT NULL"))
DBI::dbDisconnect(con, shutdown = TRUE)

b <- fread(UNI, select = "ein", colClasses = "character", showProgress = FALSE)
bset <- unique(gsub("[^0-9]", "", b$ein))

u <- unique(al, by = "ein")
u[, in_bmf := ein %in% bset]
u[, in_efile := ein %in% ef$ein]
miss <- u[in_bmf == FALSE]

hr(); say("THE MISSING 35.2%%, SPLIT BY WHETHER THEY EVER FILED A 990"); hr()
say("alias EINs not in the unified BMF : %s", format(nrow(miss), big.mark = ","))
say("")
say("  ... that DID file a 990 (2009-2024) : %s (%.1f%%)",
    format(sum(miss$in_efile), big.mark = ","), 100 * mean(miss$in_efile))
say("  ... that NEVER filed                : %s (%.1f%%)",
    format(sum(!miss$in_efile), big.mark = ","), 100 * mean(!miss$in_efile))
say("")
say("weighted by filer corroboration (how much each matters):")
say("  DID file   : %.1f%% of missing-EIN filer-observations",
    100 * sum(miss[in_efile == TRUE]$n_filers) / sum(miss$n_filers))
say("  NEVER filed: %.1f%%",
    100 * sum(miss[in_efile == FALSE]$n_filers) / sum(miss$n_filers))

hr(); say("CONTEXT: the e-file and BMF universes"); hr()
say("distinct e-filer EINs      : %s", format(nrow(ef), big.mark = ","))
say("  ... in the unified BMF   : %5.1f%%", 100 * mean(ef$ein %in% bset))
say("  ... NOT in the BMF       : %s (%.1f%%)",
    format(sum(!ef$ein %in% bset), big.mark = ","), 100 * mean(!ef$ein %in% bset))
say("unified BMF EINs           : %s", format(length(bset), big.mark = ","))

hr(); say("THE RECOVERABLE SET: missing from BMF, but a real 990 filer"); hr()
rec <- miss[in_efile == TRUE]
i <- match(rec$ein, ef$ein)
rec[, `:=`(efile_name = ef$name_display[i], efile_last = ef$last_year[i],
           efile_returns = ef$n_returns[i], efile_types = ef$return_types[i])]
say("recoverable EINs: %s", format(nrow(rec), big.mark = ","))
say("")
say("what forms do they file?")
print(head(rec[, .N, by = efile_types][order(-N)], 10))
say("")
say("top recoverable organizations by corroboration:")
print(head(rec[order(-n_filers), .(schedi_name = substr(name_display, 1, 34),
                                   efile_name = substr(efile_name, 1, 30),
                                   st = state, filers = n_filers,
                                   returns = efile_returns, last = efile_last)], 25))
