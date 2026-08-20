#!/usr/bin/env Rscript
# ============================================================================
# probe-schedi-ein-quality.R -- 35.2% of Schedule I alias EINs are in neither
# BMF vintage. Why?
#
# Three competing explanations, and they imply completely different handling:
#
#   TYPO       the filer mistyped the EIN. The organization is real and IS in the
#              BMF, under a different number. Recoverable, and a reason to trust
#              name+geo over the filed EIN.
#   OUT OF     Schedule I covers grants to organizations AND GOVERNMENTS. School
#   SCOPE      districts, municipalities and state universities have EINs but no
#              exempt-organization BMF row. Not an error at all.
#   GONE       revoked or merged before even the unified file's coverage.
#
# Tests:
#   A  length of the RAW EIN field -- too short / too long / non-numeric
#   B  government-name heuristic on the not-in-BMF set
#   C  1,000 sampled cases: block the BMF on ZIP3, fuzzy-match the name, and
#      where a strong name match exists under a DIFFERENT EIN, measure the digit
#      distance between the filed EIN and the matched one. A distance of 1-2 is a
#      transposition or a slip; a distance of 8-9 is a different organization.
# ============================================================================
suppressWarnings(suppressMessages({
  library(data.table); library(DBI); library(duckdb); library(stringdist) }))
setDTthreads(0)
set.seed(2026)

NPM <- Sys.getenv("NPMATCH_DIR", "../npmatch")
DIR <- Sys.getenv("PF_GRANTS_DIR", file.path(path.expand("~"), "Documents", "grants"))
DB  <- file.path(DIR, "schedi_grants.duckdb")
UNI <- file.path(NPM, "data-raw", "bmf_unified_geocoded.csv")
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 72), "\n")
key <- function(x) { x <- toupper(as.character(x)); x[is.na(x)] <- ""
                     gsub(" +", " ", trimws(gsub("[^A-Z0-9 ]", "", x))) }

con <- DBI::dbConnect(duckdb::duckdb(), DB, read_only = TRUE)

## ---- A. raw EIN length -----------------------------------------------------
hr(); say("A. LENGTH OF THE RAW EIN FIELD (all 8.99M grant rows)"); hr()
len <- as.data.table(DBI::dbGetQuery(con, "
  SELECT
    CASE WHEN SI_02_GRANT_US_ORG_EIN IS NULL OR trim(SI_02_GRANT_US_ORG_EIN) = ''
         THEN -1
         ELSE length(regexp_replace(SI_02_GRANT_US_ORG_EIN, '[^0-9]', '', 'g')) END AS n_digits,
    COUNT(*) AS rows
  FROM grants_raw GROUP BY 1 ORDER BY 1"))
len[, label := fifelse(n_digits < 0, "blank",
              fifelse(n_digits == 9, "9 (valid)",
              fifelse(n_digits <  9, sprintf("%d (SHORT)", n_digits),
                                     sprintf("%d (LONG)", n_digits))))]
len[, pct := round(100 * rows / sum(rows), 3)]
print(len[, .(label, rows, pct)])
say("")
say("non-numeric characters present in the raw field:")
print(DBI::dbGetQuery(con, "
  SELECT COUNT(*) AS rows_with_non_numeric FROM grants_raw
  WHERE SI_02_GRANT_US_ORG_EIN IS NOT NULL
    AND trim(SI_02_GRANT_US_ORG_EIN) <> ''
    AND regexp_matches(SI_02_GRANT_US_ORG_EIN, '[^0-9]')"))

## ---- the not-in-BMF alias set ---------------------------------------------
al <- as.data.table(DBI::dbGetQuery(con, "
  SELECT ein, name_norm, name_display, street, city, state, zip5,
         n_obs, n_filers, last_year
  FROM alias WHERE ein IS NOT NULL"))
DBI::dbDisconnect(con, shutdown = TRUE)

say(""); say("reading unified BMF ...")
b <- fread(UNI, select = c("ein", "org_name_join", "org_addr_city",
                           "org_addr_state", "org_addr_zip5"),
           colClasses = "character", showProgress = FALSE)
b[, e := gsub("[^0-9]", "", ein)]
bset <- unique(b$e)

al[, in_bmf := ein %in% bset]
say("alias rows: %s | distinct EINs: %s | EIN not in unified BMF: %.1f%% of EINs",
    format(nrow(al), big.mark = ","), format(uniqueN(al$ein), big.mark = ","),
    100 * mean(!unique(al, by = "ein")$in_bmf))

miss <- al[in_bmf == FALSE]

## ---- B. is it governments? -------------------------------------------------
hr(); say("B. GOVERNMENT / OUT-OF-SCOPE HEURISTIC on the not-in-BMF set"); hr()
GOV <- paste0("\\b(CITY OF|TOWN OF|TOWNSHIP|COUNTY OF|STATE OF|COMMONWEALTH|",
              "SCHOOL DISTRICT|PUBLIC SCHOOL|UNIFIED SCHOOL|BOARD OF EDUCATION|",
              "DEPARTMENT OF|DEPT OF|BUREAU OF|OFFICE OF|MUNICIPAL|VILLAGE OF|",
              "PARISH OF|BOROUGH|HOUSING AUTHORITY|POLICE|FIRE DISTRICT|",
              "PUBLIC LIBRARY|UNIVERSITY OF|STATE UNIVERSITY|COMMUNITY COLLEGE|",
              "TRIBE|TRIBAL|NATION OF|PUEBLO|BAND OF)\\b")
miss[, looks_gov := grepl(GOV, name_norm)]
al[, looks_gov := grepl(GOV, name_norm)]
say("not-in-BMF aliases matching a government pattern : %5.1f%%", 100 * mean(miss$looks_gov))
say("in-BMF aliases matching the same pattern (base)  : %5.1f%%",
    100 * mean(al[in_bmf == TRUE]$looks_gov))
say("")
say("most common not-in-BMF names (by filer corroboration):")
print(head(miss[order(-n_filers), .(name = substr(name_display, 1, 44),
                                    state, filers = n_filers, gov = looks_gov)], 20))

## ---- C. zip3 block + fuzzy name, then EIN digit distance -------------------
hr(); say("C. 1,000 SAMPLED CASES: is there a strong name match under a");
say("   DIFFERENT EIN in the same ZIP3?"); hr()
cand <- miss[nzchar(name_norm) & nzchar(city) & nzchar(state) & !is.na(zip5) &
             nchar(zip5) == 5 & n_filers >= 1]
say("eligible (complete name + address): %s alias rows", format(nrow(cand), big.mark = ","))
s <- cand[sample(.N, min(1000L, .N))]

b <- b[!is.na(org_addr_zip5) & nchar(org_addr_zip5) == 5]
b[, zip3 := substr(org_addr_zip5, 1, 3)]
b[, nkey := key(org_name_join)]
setkey(b, zip3)
s[, zip3 := substr(zip5, 1, 3)]

res <- rbindlist(lapply(seq_len(nrow(s)), function(i) {
  blk <- b[.(s$zip3[i]), nomatch = 0L]
  if (!nrow(blk)) return(data.table(i = i, n_block = 0L, best_sim = NA_real_))
  d <- stringdist::stringsim(s$name_norm[i], blk$nkey, method = "jw", p = 0.1)
  j <- which.max(d)
  data.table(i = i, n_block = nrow(blk), best_sim = d[j],
             bmf_ein = blk$e[j], bmf_name = blk$org_name_join[j],
             bmf_zip5 = blk$org_addr_zip5[j])
}), fill = TRUE)
s <- cbind(s, res[, -"i"])

say("median ZIP3 block size: %s", format(median(s$n_block), big.mark = ","))
say("")
say("distribution of best name similarity within the ZIP3 block:")
print(s[, .(cases = .N), by = .(sim = cut(best_sim, c(-Inf,.80,.90,.95,.99,1),
        labels = c("<0.80","0.80-0.90","0.90-0.95","0.95-0.99","0.99-1.00")))][order(sim)])

## digit distance between the filed EIN and the EIN of the best name match
strong <- s[!is.na(best_sim) & best_sim >= 0.95]
say("")
say("cases with a >=0.95 name match under a different EIN: %d of %d (%.1f%%)",
    nrow(strong), nrow(s), 100 * nrow(strong) / nrow(s))
if (nrow(strong)) {
  strong[, ein_dist := stringdist::stringdist(ein, bmf_ein, method = "hamming")]
  strong[is.infinite(ein_dist) | is.na(ein_dist),
         ein_dist := stringdist::stringdist(ein, bmf_ein, method = "lv")]
  strong[, ein_lv := stringdist::stringdist(ein, bmf_ein, method = "lv")]
  say("digit distance between the FILED EIN and the matched BMF EIN:")
  print(strong[, .(cases = .N), by = .(digits_differing = ein_lv)][order(digits_differing)])
  say("")
  say("  <=2 digits differ (a slip or transposition): %d (%.1f%% of strong matches)",
      strong[ein_lv <= 2, .N], 100 * strong[ein_lv <= 2, .N] / nrow(strong))
  say("")
  say("examples where the EIN is 1-2 digits off -- these are typos:")
  print(head(strong[ein_lv <= 2, .(filed_name = substr(name_display, 1, 30),
                                   filed_ein = ein, bmf_ein,
                                   bmf_name = substr(bmf_name, 1, 30),
                                   sim = round(best_sim, 3), d = ein_lv)], 20))
  say("")
  say("examples with a strong name match but a completely different EIN:")
  print(head(strong[ein_lv >= 6, .(filed_name = substr(name_display, 1, 30),
                                   filed_ein = ein, bmf_ein,
                                   bmf_name = substr(bmf_name, 1, 30),
                                   sim = round(best_sim, 3), d = ein_lv,
                                   gov = looks_gov)], 15))
}
