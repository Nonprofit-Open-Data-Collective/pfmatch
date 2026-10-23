#' 990-PF Part XV grants paid, direct from the NCCS e-file extracts
#'
#' The grant file this project has matched against since the beginning is a
#' GTDC Data Mart extract (`2025_08_29_All_Years_990PFPart14Grants3A.csv`,
#' 12,559,051 rows, tax years 2008-2024). This module rebuilds the same table
#' from the NCCS e-file extracts instead, which is the upstream source and is
#' both larger and fresher.
#'
#' @section Why rebuild:
#' Measured against the inventory the bucket publishes alongside the data:
#' \tabular{lrl}{
#'   source \tab rows \tab tax years \cr
#'   GTDC `Part14Grants3A` \tab 12,559,051 \tab 2008-2024 \cr
#'   **e-file `PF-P15-T01`** \tab **17,560,767** \tab **2009-2025**
#' }
#' That is 5.0M more grant rows (+40%) and an additional year. The e-file
#' extract is also regenerated continuously, so a rebuild is reproducible on
#' demand rather than pinned to whenever the Data Mart extract was cut.
#'
#' @section Which version, and the trap:
#' **Use `efilepf_v3_1`.** `efilepf_v2_3` exists in the same bucket and carries
#' the same `PF-*` table family, but its published row inventory reports **zero**
#' rows for `PF-P15-T01` in every year — the grants-paid table is not populated
#' there. This is the same shape of trap as `efile_v2_1` vs `efile_v2_2` for
#' Schedule I (see [pf_schedi_url()]), where the superseded extract carried the
#' right schema and a tenth of the rows. Always check
#' `COUNT-OF-ROWS-BY-TABLE-AND-FORMTYPE-*.CSV` before trusting a version.
#'
#' @section Part XIV or Part XV:
#' The GTDC file is named "Part14" and this table "P15". They are the same
#' schedule: grants and contributions **paid** during the year. The IRS
#' renumbered the 990-PF supplementary-information part, and the e-file
#' extracts follow the current numbering. `PF-P15-T01` is the repeating
#' grant-level table; `PF-P15-T00` is the one-row-per-return parent;
#' `PF-P15-T02` is grants *approved for future payment*, which is a different
#' population and is **not** what this project matches.
#'
#' @section 2025 drops the recipient-status column:
#' `PF_15_G_PAID_RECIP_STAT` -- the GTDC `SIGOCPYRFSTA`, "foundation status of
#' recipient" -- is present every year 2009-2024 and **absent from 2025**. One
#' column removed; the other 29 are identical. The IRS revised Form 990-PF and
#' dropped that box from Part XV line 3, so this is permanent and 2026 onward
#' will not have it either.
#'
#' It matters more than a missing field normally would, because
#' [pf_standardize_status()] reads it and it is the only input to the scope
#' decision. Measured rather than assumed: with the column absent every row
#' classifies as `other_unknown` and **`in_scope` stays `TRUE`**, because the
#' recipient-type filter flags individuals and government bodies rather than
#' dropping them and only a foreign address removes a row. So 2025 grants are
#' matched normally; what is lost is the ability to *crosstab* them by
#' recipient type, and any such breakdown must exclude 2025 or report it
#' separately rather than showing a year that is 100% `other_unknown` and
#' letting a reader conclude the data is broken.
#'
#' @section Column naming:
#' [pf_efilepf_build()] emits the **GTDC column names**, not the e-file ones.
#' That is deliberate: [pf_prepare_grants()] reads `SIGOCPYRBNBN1`,
#' `SIGOCPYRFSTA` and friends by name, as do the recipient-type and scope
#' rules, so emitting the historical schema means the entire downstream
#' pipeline, every benchmark and every frozen artifact keeps working untouched.
#' [pf_efilepf_map()] is the mapping, exported so the translation is auditable
#' rather than buried.
#'
#' @name pf_efilepf
NULL

#' @rdname pf_efilepf
#' @export
pf_efilepf_years <- function() 2009:2025

#' @rdname pf_efilepf
#' @export
pf_efilepf_table <- function() "PF-P15-T01-SUPPLEMENTARY-INFO-GRANT-PAID"

#' URL for one year of the e-file 990-PF grants-paid extract
#'
#' @param year Tax year.
#' @param version NCCS extract version. **Use `efilepf_v3_1`** — see the
#'   version trap in [pf_efilepf].
#' @param table Table stem; defaults to [pf_efilepf_table()].
#' @param format `"csv"` or `"parquet"`. Both are published per year.
#' @return A single URL string.
#' @export
pf_efilepf_url <- function(year, version = "efilepf_v3_1",
                           table = pf_efilepf_table(),
                           format = c("csv", "parquet")) {
  format <- match.arg(format)
  ext <- if (format == "csv") "CSV" else "parquet"
  sprintf("https://nccs-efile.s3.us-east-1.amazonaws.com/public/%s/%s-%d.%s",
          version, table, year, ext)
}

#' Download the e-file 990-PF grants-paid extracts
#'
#' Downloads to a staging name and renames on success, so an interrupted run
#' never leaves a truncated file that a later run would treat as complete —
#' the same discipline [pf_schedi_download()] uses.
#'
#' @param dir Destination directory. Defaults to `~/Documents/grants/efilepf`,
#'   deliberately outside the package and outside any synced folder: the full
#'   set is several GB.
#' @param years,version,table Passed to [pf_efilepf_url()].
#' @param overwrite Re-download files that already exist.
#' @param verbose Print progress.
#' @return Character vector of local paths, invisibly.
#' @export
pf_efilepf_download <- function(dir = pf_efilepf_dir(),
                                years = pf_efilepf_years(),
                                version = "efilepf_v3_1",
                                table = pf_efilepf_table(),
                                overwrite = FALSE, verbose = TRUE) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  out <- character(0)
  for (y in years) {
    url  <- pf_efilepf_url(y, version, table)
    dest <- file.path(dir, basename(url))
    if (file.exists(dest) && !overwrite) {
      if (verbose) message(sprintf("  %d  have it (%.0f MB)", y,
                                   file.size(dest) / 1e6))
      out <- c(out, dest); next
    }
    tmp <- paste0(dest, ".part")
    if (verbose) message(sprintf("  %d  downloading ...", y))
    ok <- tryCatch({
      utils::download.file(url, tmp, mode = "wb", quiet = TRUE); TRUE
    }, error = function(e) { message("    failed: ", conditionMessage(e)); FALSE })
    if (!ok) { unlink(tmp); next }
    file.rename(tmp, dest)
    if (verbose) message(sprintf("    %.0f MB", file.size(dest) / 1e6))
    out <- c(out, dest)
  }
  invisible(out)
}

#' @rdname pf_efilepf
#' @export
pf_efilepf_dir <- function()
  file.path(path.expand("~"), "Documents", "grants", "efilepf")

#' The e-file to GTDC column mapping
#'
#' Named character vector: names are the **GTDC** columns the pipeline reads,
#' values are the **e-file** columns they come from. Exported so the rebuild is
#' auditable — every column in the output traces to exactly one source column.
#'
#' One field changes meaning for the better. `SIGOCAFFRFACO` (recipient
#' country) is present in the GTDC schema but empty throughout it, which is why
#' [pf_prepare_grants()] detects foreign recipients from the address text
#' instead. The e-file source populates `PF_15_G_PAID_RECIP_ADDR_CNTR`, so the
#' rebuilt file can carry a real country and foreign detection can be revisited
#' — measure before changing the rule.
#'
#' @return Named character vector, GTDC name -> e-file name.
#' @export
pf_efilepf_map <- function() {
  c(# --- return / filer identity -------------------------------------------
    TAXPEREND     = "TAX_PERIOD_END_DATE",
    TAXPERBEGIN   = "TAX_PERIOD_BEGIN_DATE",
    FILEREIN      = "ORG_EIN",
    FILERNAME1    = "ORG_NAME_L1",
    FILERNAME2    = "ORG_NAME_L2",
    TAXYEAR       = "TAX_YEAR",
    URL           = "URL",
    # --- recipient name ----------------------------------------------------
    SIGOCPYRPNAM  = "PF_15_G_PAID_RECIP_NAME_PERS",
    SIGOCPYRBNBN1 = "PF_15_G_PAID_RECIP_NAME_ORG_L1",
    SIGOCPYRBNBN2 = "PF_15_G_PAID_RECIP_NAME_ORG_L2",
    # --- recipient address -------------------------------------------------
    SIGOCPYRFAAL1 = "PF_15_G_PAID_RECIP_ADDR_L1",
    SIGOCPYRFAAL2 = "PF_15_G_PAID_RECIP_ADDR_L2",
    SIGOCPYRFACI  = "PF_15_G_PAID_RECIP_ADDR_CITY",
    SIGOCPYRFAPO  = "PF_15_G_PAID_RECIP_ADDR_STATE",
    SIGOCPYRFAPC  = "PF_15_G_PAID_RECIP_ADDR_ZIP",
    SIGOCAFFRFACO = "PF_15_G_PAID_RECIP_ADDR_CNTR",
    # --- the grant ---------------------------------------------------------
    SIGOCPYAMOUN  = "PF_15_G_PAID_AMT",
    SIGOCPYPOGOC  = "PF_15_G_PAID_PURPOSE",
    SIGOCPYRFSTA  = "PF_15_G_PAID_RECIP_STAT",
    SIGOCPYRRELA  = "PF_15_G_PAID_RELATIONSHIP")
}

#' Build the rebuilt grant file from the downloaded extracts
#'
#' Reads one year at a time and appends, so peak memory is one year (~2M rows)
#' rather than the whole 17.5M-row table.
#'
#' Two e-file columns are carried through in addition to the GTDC schema, because
#' they are free here and the GTDC file had no equivalent: `OBJECTID`, which
#' identifies the source return, and `efile_year`, the extract the row came from
#' (distinct from `TAXYEAR` when a return is filed late or amended).
#'
#' @param dir Directory holding the downloaded CSVs.
#' @param out Output CSV path.
#' @param years Years to include.
#' @param verbose Print progress.
#' @return A one-row-per-year `data.frame` of counts, invisibly.
#' @export
pf_efilepf_build <- function(dir = pf_efilepf_dir(), out, years = pf_efilepf_years(),
                             verbose = TRUE) {
  map <- pf_efilepf_map()
  if (file.exists(out)) unlink(out)
  log <- list()
  first <- TRUE
  for (y in years) {
    f <- file.path(dir, sprintf("%s-%d.CSV", pf_efilepf_table(), y))
    if (!file.exists(f)) { if (verbose) message(sprintf("  %d  MISSING, skipped", y)); next }
    d <- data.table::fread(f, colClasses = "character", showProgress = FALSE,
                           na.strings = NULL)
    # A mapped column absent from a year is emitted blank rather than fatal:
    # 2025 genuinely has no PF_15_G_PAID_RECIP_STAT (see the section above) and
    # refusing to build the year would be worse than building it with the gap
    # recorded. What must never happen is emitting it silently, so every
    # absence is returned and lands in the manifest.
    miss <- setdiff(unname(map), names(d))
    if (length(miss)) {
      if (verbose) message(sprintf("  %d  NOTE: absent, emitted blank -- %s",
                                   y, paste(miss, collapse = ", ")))
      for (cc in miss) d[, (cc) := ""]
    }
    keep <- c(map, OBJECTID = "OBJECTID")
    o <- d[, keep, with = FALSE]
    data.table::setnames(o, unname(keep), names(keep))
    o[, efile_year := as.character(y)]
    data.table::fwrite(o, out, append = !first)
    first <- FALSE
    log[[as.character(y)]] <- data.frame(
      year = y, rows = nrow(o),
      missing_cols = if (length(miss)) paste(miss, collapse = ";") else "",
      stringsAsFactors = FALSE)
    if (verbose) message(sprintf("  %d  %s rows", y, format(nrow(o), big.mark = ",")))
    rm(d, o); invisible(gc())
  }
  res <- do.call(rbind, log)
  if (verbose && !is.null(res))
    message(sprintf("total: %s rows -> %s",
                    format(sum(res$rows), big.mark = ","), out))
  invisible(res)
}
