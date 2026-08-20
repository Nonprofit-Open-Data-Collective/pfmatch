#!/usr/bin/env Rscript
# ============================================================================
# build-schedi-db.R -- load the 990 Schedule I grant tables into DuckDB and
# reduce them to a recipient alias table.
#
# Schedule I Part II is where a non-PF 990 filer lists every grant it made to a
# US organization or government -- recipient NAME, ADDRESS, and **EIN**. That
# last field is what makes this different from every other source we have: it is
# a large set of (name variant, address variant) -> EIN observations, written by
# grantmakers, in exactly the register 990-PF filers use when they write Part XIV.
#
# The BMF gives one legal name per EIN. This gives many *observed* names per EIN.
# `dev/AUDIT-FINDINGS.md` named "an alias source the BMF does not carry" as the
# blocker for brand-vs-legal-name matching; this is a candidate for that source.
#
#   PF_GRANTS_DIR=<dir>   raw CSVs        (default ~/Documents/grants)
#   PF_SCHEDI_DB=<path>   duckdb file     (default <dir>/schedi.duckdb)
#
# Safe to re-run: the load is idempotent per year.
# ============================================================================
suppressWarnings(suppressMessages({ library(DBI); library(duckdb) }))

DIR <- Sys.getenv("PF_GRANTS_DIR", file.path(path.expand("~"), "Documents", "grants"))
DB  <- Sys.getenv("PF_SCHEDI_DB",  file.path(DIR, "schedi.duckdb"))
say <- function(...) cat(sprintf(...), "\n")

files <- list.files(DIR, pattern = "^SI-P02-T01-GRANTS-US-ORGS-GOVTS-[0-9]{4}[.]CSV$",
                    full.names = TRUE)
if (!length(files)) stop("no Schedule I CSVs in ", DIR)
say("%d yearly files in %s", length(files), DIR)

con <- dbConnect(duckdb::duckdb(), DB)
on.exit(dbDisconnect(con, shutdown = TRUE))
dbExecute(con, "PRAGMA threads=4")

## ---- 1. raw load -----------------------------------------------------------
# union_by_name because the 2009-2018 files predate the RecipientTable column.
have <- if ("grants_raw" %in% dbListTables(con))
  dbGetQuery(con, "SELECT DISTINCT TAX_YEAR FROM grants_raw")$TAX_YEAR else character()
if (!length(have)) {
  say("loading all years into grants_raw ...")
  dbExecute(con, sprintf("
    CREATE OR REPLACE TABLE grants_raw AS
    SELECT * FROM read_csv([%s],
      union_by_name = true, header = true, all_varchar = true,
      ignore_errors = true, sample_size = -1)",
    paste(sprintf("'%s'", gsub("\\\\", "/", files)), collapse = ", ")))
} else say("grants_raw already holds %d years -- skipping load", length(have))

n <- dbGetQuery(con, "SELECT COUNT(*) n FROM grants_raw")$n
say("grants_raw: %s rows", format(n, big.mark = ","))
print(dbGetQuery(con, "SELECT TAX_YEAR, COUNT(*) grants,
                              COUNT(DISTINCT ORG_EIN) filers
                       FROM grants_raw GROUP BY 1 ORDER BY 1"))

## ---- 2. normalized recipient observations ----------------------------------
# One row per grant, with the recipient reduced to the fields a linkage needs.
# EIN is kept as filed AND as 9 digits; the two differ more than you would like.
say("building recipient observations ...")
dbExecute(con, "
CREATE OR REPLACE TABLE recip_obs AS
SELECT
  TAX_YEAR                                                    AS tax_year,
  ORG_EIN                                                     AS filer_ein,
  regexp_replace(SI_02_GRANT_US_ORG_EIN, '[^0-9]', '', 'g')   AS recip_ein_raw,
  trim(SI_02_GRANT_US_ORG_NAME_L1)                            AS name_l1,
  trim(SI_02_GRANT_US_ORG_NAME_L2)                            AS name_l2,
  trim(SI_02_GRANT_US_ORG_ADDR_L1)                            AS street,
  trim(SI_02_GRANT_US_ORG_ADDR_CITY)                          AS city,
  upper(trim(SI_02_GRANT_US_ORG_ADDR_STATE))                  AS state,
  regexp_replace(SI_02_GRANT_US_ORG_ADDR_ZIP, '[^0-9]', '', 'g') AS zip_raw,
  SI_02_GRANT_US_ORG_IRC_SECTION                              AS irc_section,
  TRY_CAST(SI_02_GRANT_US_ORG_AMT_CASH AS DOUBLE)             AS amt_cash,
  SI_02_GRANT_US_ORG_PURPOSE                                  AS purpose
FROM grants_raw")

dbExecute(con, "
CREATE OR REPLACE TABLE recip AS
SELECT *,
  CASE WHEN length(recip_ein_raw) = 9 THEN recip_ein_raw END      AS ein,
  CASE WHEN length(zip_raw) >= 5 THEN substr(zip_raw, 1, 5) END   AS zip5,
  -- the same normalization npmatch applies: upper, strip punctuation, squeeze
  regexp_replace(regexp_replace(upper(
     CASE WHEN name_l2 IS NOT NULL AND name_l2 <> ''
          THEN name_l1 || ' ' || name_l2 ELSE name_l1 END),
     '[^A-Z0-9 ]', '', 'g'), ' +', ' ', 'g')                      AS name_norm
FROM recip_obs")

say("recip: %s rows", format(dbGetQuery(con, "SELECT COUNT(*) n FROM recip")$n, big.mark = ","))

## ---- 3. the alias table ----------------------------------------------------
# One row per distinct (ein, name_norm, city, state, zip5), with how often it was
# observed and how many DISTINCT FILERS wrote it that way. The filer count is the
# trust signal: a spelling used by 40 different grantmakers is a real alias; one
# used once may be a typo.
say("deduplicating to alias table ...")
dbExecute(con, "
CREATE OR REPLACE TABLE alias AS
SELECT ein, name_norm, city, state, zip5,
       COUNT(*)                     AS n_obs,
       COUNT(DISTINCT filer_ein)    AS n_filers,
       MIN(tax_year)                AS first_year,
       MAX(tax_year)                AS last_year,
       SUM(amt_cash)                AS total_cash,
       any_value(name_l1)           AS name_display,
       any_value(street)            AS street
FROM recip
WHERE ein IS NOT NULL AND name_norm <> ''
GROUP BY 1,2,3,4,5")
say("alias: %s rows", format(dbGetQuery(con, "SELECT COUNT(*) n FROM alias")$n, big.mark = ","))

## ---- 4. read-out -----------------------------------------------------------
q <- function(sql) dbGetQuery(con, sql)
say(""); say("=== coverage ===")
print(q("SELECT
   COUNT(*)                                  AS alias_rows,
   COUNT(DISTINCT ein)                       AS distinct_eins,
   COUNT(DISTINCT name_norm)                 AS distinct_names,
   COUNT(DISTINCT (ein || '|' || name_norm)) AS distinct_ein_name
 FROM alias"))

say(""); say("=== EIN quality on the raw grant rows ===")
print(q("SELECT
   COUNT(*) AS rows,
   SUM(CASE WHEN recip_ein_raw = '' OR recip_ein_raw IS NULL THEN 1 ELSE 0 END) AS ein_blank,
   SUM(CASE WHEN ein IS NULL AND recip_ein_raw <> '' THEN 1 ELSE 0 END)         AS ein_malformed,
   SUM(CASE WHEN ein IS NOT NULL THEN 1 ELSE 0 END)                             AS ein_ok
 FROM recip"))

say(""); say("=== name variants per EIN ===")
print(q("SELECT n_variants, COUNT(*) AS eins FROM (
           SELECT ein, COUNT(DISTINCT name_norm) AS n_variants FROM alias GROUP BY 1)
         GROUP BY 1 ORDER BY 1 LIMIT 15"))

say(""); say("=== is a name+geo key ambiguous across EINs? ===")
print(q("SELECT n_eins, COUNT(*) AS keys FROM (
           SELECT name_norm, state, zip5, COUNT(DISTINCT ein) AS n_eins
           FROM alias WHERE zip5 IS NOT NULL GROUP BY 1,2,3)
         GROUP BY 1 ORDER BY 1 LIMIT 10"))

say(""); say("=== trust: how many aliases are corroborated by several filers? ===")
print(q("SELECT CASE WHEN n_filers = 1 THEN '1 filer'
                     WHEN n_filers < 5 THEN '2-4'
                     WHEN n_filers < 20 THEN '5-19'
                     ELSE '20+' END AS filers,
                COUNT(*) AS aliases
         FROM alias GROUP BY 1 ORDER BY 1"))

say(""); say("wrote %s", DB)
