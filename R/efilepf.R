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
pf_efilepf_dir <- function() {
  d <- Sys.getenv("PF_EFILEPF_DIR")
  if (nzchar(d)) return(d)
  # path.expand("~") is NOT the user's home on Windows: R sets it to the
  # Documents folder, so file.path(path.expand("~"), "Documents", ...) resolved
  # to C:/Users/<u>/Documents/Documents/grants/efilepf and every year was
  # reported MISSING. Use USERPROFILE there, which is the actual home.
  home <- if (.Platform$OS.type == "windows" && nzchar(Sys.getenv("USERPROFILE")))
    Sys.getenv("USERPROFILE") else path.expand("~")
  file.path(home, "Documents", "grants", "efilepf")
}

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
#' @section Schema:
#' `schema = "v2"` (the default) keeps the ef2 columns **as published**, with
#' their concordance990 v2 names (`PF_15_G_PAID_*`) and the full filing
#' metadata. `schema = "gtdc"` reproduces the legacy behaviour: rename to the
#' v1 GTDC names via [pf_efilepf_map()] and keep only those columns.
#'
#' The legacy path exists to reproduce artifacts built before the migration. It
#' is a **downgrade**: the published files already carry the current names, and
#' renaming them to v1 also discarded ten standardized columns. Two of those
#' matter beyond tidiness — `TABLE_ID`, the within-filing row counter that makes
#' `OBJECTID + TABLE_ID` a unique row key, and `RETURN_AMENDED_X` /
#' `RETURN_PARTIAL_X`, without which superseded filings cannot be identified.
#' Dropping `TABLE_ID` is why a content hash once had to be invented for a key
#' the data already published.
#'
#' @param dir Directory holding the downloaded CSVs.
#' @param out Output CSV path.
#' @param years Years to include.
#' @param schema `"v2"` for the published concordance990 names and full
#'   metadata, `"gtdc"` for the legacy v1 names.
#' @param dedup Drop superseded and duplicate filings with
#'   [pf_efilepf_dedup()]. Requires `schema = "v2"`, since the legacy schema
#'   discards the flags the rule needs.
#' @param verbose Print progress.
#' @return A one-row-per-year `data.frame` of counts, invisibly.
#' @export
pf_efilepf_build <- function(dir = pf_efilepf_dir(), out, years = pf_efilepf_years(),
                             schema = c("v2", "gtdc"), dedup = NULL,
                             verbose = TRUE) {
  schema <- match.arg(schema)
  if (is.null(dedup)) dedup <- identical(schema, "v2")
  if (isTRUE(dedup) && !identical(schema, "v2"))
    stop("dedup = TRUE needs schema = \"v2\": the legacy schema drops ",
         "RETURN_AMENDED_X and RETURN_PARTIAL_X, so supersession cannot be ",
         "determined.", call. = FALSE)
  map <- pf_efilepf_map()
  if (file.exists(out)) unlink(out)
  log <- list()
  first <- TRUE
  canon <- NULL   # column order of the first year written; see the v2 branch
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
    if (identical(schema, "v2")) {
      # keep the file as published: current names, full filing metadata
      o <- d
      # ... but NOT in whatever order this year happens to publish them.
      # fwrite(append = TRUE) writes POSITIONALLY, against the header the first
      # year wrote. The blank column added above lands at the END of the frame,
      # whereas every other year carries it in its published position, so
      # appending 2025 -- the one year missing PF_15_G_PAID_RECIP_STAT -- shifted
      # all 658,811 of its rows two columns out of register: the amount came out
      # empty and the purpose text landed in the status column. The gtdc path
      # never had this problem because it selects columns by name into a fixed
      # order. Pin the order here so the v2 path cannot drift either.
      if (is.null(canon)) {
        canon <- names(o)
      } else {
        extra <- setdiff(names(o), canon)
        if (length(extra))
          stop("the ", y, " extract publishes column(s) no earlier year had: ",
               paste(extra, collapse = ", "),
               ".\n  Appending it would write every later row out of register. ",
               "Rebuild from the first year, or restrict `years` to one schema.",
               call. = FALSE)
        for (cc in setdiff(canon, names(o))) o[, (cc) := ""]
        data.table::setcolorder(o, canon)
      }
    } else {
      keep <- c(map, OBJECTID = "OBJECTID")
      o <- d[, keep, with = FALSE]
      data.table::setnames(o, unname(keep), names(keep))
    }
    o[, efile_year := as.character(y)]
    if (isTRUE(dedup)) {
      # Per year, not corpus-wide. A filing can only supersede another in the
      # same (EIN2, TAX_YEAR, group, partial) context, and TAX_YEAR is inside
      # the context, so no supersession pair can straddle two extract files.
      # Doing it per year keeps peak memory at one year.
      n_in <- nrow(o)
      o <- data.table::as.data.table(pf_efilepf_dedup(o, verbose = FALSE))
      if (verbose && nrow(o) < n_in)
        message(sprintf("  %d  dedup: %s -> %s rows", y,
                        format(n_in, big.mark = ","),
                        format(nrow(o), big.mark = ",")))
    }
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
  # A build that found no source files used to report "total: 0 rows", write
  # nothing, and return invisibly with no error -- so a wrong `dir` looked like
  # a successful empty build and only surfaced downstream as a missing file.
  # Not finding the data is a failure, and it says so here.
  if (is.null(res))
    stop("pf_efilepf_build() found no source extracts in ", dir,
         ".\n  Expected files named ", pf_efilepf_table(), "-<year>.CSV for ",
         "years ", min(years), "-", max(years), ".\n  Download them with ",
         "pf_efilepf_download(), or set PF_EFILEPF_DIR / pass `dir` to point ",
         "at an existing cache.", call. = FALSE)
  if (verbose)
    message(sprintf("total: %s rows -> %s",
                    format(sum(res$rows), big.mark = ","), out))
  invisible(res)
}
