#!/usr/bin/env Rscript
# ============================================================================
# Measure the amended / group filing structure before writing any dedup rule.
#
# The ef2 v3_1 tables carry standardized filing metadata that pf_efilepf_build()
# currently DISCARDS: TABLE_ID, RETURN_AMENDED_X, RETURN_GROUP_X,
# RETURN_TIME_STAMP, RETURN_TYPE, VERSION, EIN2. Dropping TABLE_ID is why a
# content hash had to be invented for a row key when OBJECTID + TABLE_ID was
# already the published one.
#
# THE RULE TO IMPLEMENT (per the data owner):
#   * the dedup unit is (ORG_EIN, TAX_YEAR, group-flag) -- a group return and a
#     primary return for one EIN-year are DIFFERENT filings, not duplicates, so
#     there are four combinations of {group, primary} x {amended, original}
#   * where several filings share that unit, keep the most recent
#   * the most recent SHOULD be the amended one -- flag it when it is not
#   * where only an amended filing exists, keep it
#
# This script measures, it does not change anything. The questions that decide
# the implementation:
#   1. how often does one (EIN, year, group) unit have several OBJECTIDs?
#   2. is the most recent always the amended one? (if not, how often not?)
#   3. do group and primary returns genuinely coexist for one EIN-year?
#   4. when a unit has several filings, how much do their grant rows differ?
#      An amendment often exists BECAUSE a grant changed, so exact row-set
#      equality is the wrong test for "the same filing".
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
PF  <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("-", 86))
sq  <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; x }

META <- c("OBJECTID", "TABLE_ID", "ORG_EIN", "TAX_YEAR", "RETURN_AMENDED_X",
          "RETURN_GROUP_X", "RETURN_TIME_STAMP", "RETURN_TYPE", "VERSION")
dir <- pf_efilepf_dir()
fs  <- list.files(dir, pattern = "GRANT-PAID.*CSV$", full.names = TRUE)
say("raw ef2 files: %d in %s", length(fs), dir)

d <- rbindlist(lapply(fs, function(f) {
  h <- names(fread(f, nrows = 0, showProgress = FALSE))
  fread(f, colClasses = "character", showProgress = FALSE,
        select = intersect(META, h))
}), fill = TRUE)
say("grant rows: %s", format(nrow(d), big.mark = ","))

## ---- the metadata columns the build currently drops -----------------------
hr(); say("FLAG DISTRIBUTIONS")
for (k in c("RETURN_AMENDED_X", "RETURN_GROUP_X", "RETURN_TYPE")) {
  if (!k %in% names(d)) { say("  %s absent", k); next }
  t <- sort(table(sq(d[[k]])), decreasing = TRUE)
  say("  %-18s %s", k, paste(sprintf("[%s]=%s", ifelse(names(t) == "", "blank", names(t)),
      format(as.integer(t), big.mark = ",")), collapse = "  "))
}
say("  TABLE_ID non-blank : %.1f%%", 100 * mean(nzchar(sq(d$TABLE_ID))))
say("  OBJECTID+TABLE_ID unique over all rows: %s",
    ifelse(!anyDuplicated(paste(d$OBJECTID, d$TABLE_ID)), "YES", "NO"))

## ---- filing-level view -----------------------------------------------------
d[, amended := sq(RETURN_AMENDED_X) %in% c("X", "x", "1", "TRUE", "Y")]
d[, grp     := sq(RETURN_GROUP_X)   %in% c("X", "x", "1", "TRUE", "Y")]
fil <- unique(d[, .(OBJECTID, ORG_EIN, TAX_YEAR, amended, grp,
                    ts = sq(RETURN_TIME_STAMP))])
say("")
say("distinct filings (OBJECTID): %s", format(nrow(fil), big.mark = ","))
hr(); say("THE FOUR COMBINATIONS")
print(fil[, .(filings = .N), by = .(grp, amended)][order(-filings)], row.names = FALSE)

## ---- duplicate units -------------------------------------------------------
fil[, unit := paste(ORG_EIN, TAX_YEAR, grp, sep = "|")]
u <- fil[, .(n_filings = .N, n_amended = sum(amended),
             n_orig = sum(!amended)), by = unit]
hr(); say("DEDUP UNIT = (ORG_EIN, TAX_YEAR, group flag)")
say("  units total                       : %s", format(nrow(u), big.mark = ","))
say("  units with ONE filing             : %s (%.1f%%)",
    format(sum(u$n_filings == 1L), big.mark = ","), 100 * mean(u$n_filings == 1L))
say("  units with SEVERAL filings        : %s (%.1f%%)",
    format(sum(u$n_filings > 1L), big.mark = ","), 100 * mean(u$n_filings > 1L))
print(u[n_filings > 1L, .(units = .N), by = .(n_filings = pmin(n_filings, 5L))][
        order(n_filings)], row.names = FALSE)

## ---- is the most recent always the amended one? ---------------------------
dup <- fil[unit %in% u[n_filings > 1L]$unit]
setorder(dup, unit, -ts)
chk <- dup[, .(n = .N, n_amended = sum(amended),
               newest_is_amended = amended[1],
               ts_all_distinct = uniqueN(ts) == .N), by = unit]
hr(); say("WITHIN MULTI-FILING UNITS")
say("  newest filing IS the amended one  : %s (%.1f%%)",
    format(sum(chk$newest_is_amended), big.mark = ","),
    100 * mean(chk$newest_is_amended))
say("  newest is NOT amended      [FLAG] : %s (%.1f%%)",
    format(sum(!chk$newest_is_amended), big.mark = ","),
    100 * mean(!chk$newest_is_amended))
say("  no amended filing at all in unit  : %s", format(sum(chk$n_amended == 0L), big.mark = ","))
say("  timestamps tied (cannot order)    : %s", format(sum(!chk$ts_all_distinct), big.mark = ","))

## ---- do group and primary coexist for one EIN-year? ----------------------
ey <- fil[, .(has_grp = any(grp), has_pri = any(!grp)), by = .(ORG_EIN, TAX_YEAR)]
hr(); say("GROUP vs PRIMARY FOR ONE EIN-YEAR")
say("  primary only : %s", format(sum(ey$has_pri & !ey$has_grp), big.mark = ","))
say("  group only   : %s", format(sum(ey$has_grp & !ey$has_pri), big.mark = ","))
say("  BOTH         : %s  <- legitimately distinct filings, must NOT be merged",
    format(sum(ey$has_grp & ey$has_pri), big.mark = ","))

## ---- how much do grant rows differ between filings of one unit? ----------
hr(); say("HOW MUCH DO THE GRANT ROWS DIFFER WITHIN A UNIT?")
say("  (an amendment often exists BECAUSE a grant changed, so exact row-set")
say("   equality is the wrong test for 'the same filing')")
say("")
say("  rows per filing, multi-filing units only:")
rp <- d[OBJECTID %in% dup$OBJECTID, .N, by = OBJECTID]$N
print(summary(rp))
fwrite(u, file.path(PF, "data-dev", "AMENDED-UNITS.csv"))
fwrite(chk, file.path(PF, "data-dev", "AMENDED-UNIT-CHECKS.csv"))
hr(); say("wrote data-dev/AMENDED-UNITS.csv and AMENDED-UNIT-CHECKS.csv")
