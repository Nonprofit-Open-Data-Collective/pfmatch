# ============================================================================
# Retrieval delegated to panel990.
#
# pfmatch used to build the S3 URL itself:
#
#   https://nccs-efile.s3.us-east-1.amazonaws.com/public/efilepf_v3_1/
#     PF-P15-T01-SUPPLEMENTARY-INFO-GRANT-PAID-{year}.CSV
#
# which was the right location -- byte-identical to what panel990 resolves --
# but it pinned the release in a string literal inside this package. A new
# published release then needed a pfmatch edit, and the version pfmatch used
# could silently diverge from the one the rest of the stack was reading.
#
# panel990 owns that resolution: data_source() defaults to the current release
# and to parquet, which is faster and stores every column as a string with
# leading zeros intact -- convenient here, since pfmatch reads everything as
# character anyway. The columns are the same in either format; only the types
# differ (panel990's "Source format" section).
#
# panel990 is Suggested rather than Imported: pfmatch runs perfectly well
# against files already on disk, so the dependency is only needed to fetch.
# ============================================================================

#' Fetch the 990-PF grants-paid extracts via panel990
#'
#' Downloads the published ef2 tables for the requested years. Supersedes
#' [pf_efilepf_download()], which built the S3 URL from a release pinned inside
#' this package.
#'
#' @param years Tax years to fetch. Defaults to [pf_efilepf_years()].
#' @param dir Destination directory. Defaults to [pf_efilepf_dir()].
#' @param version Published release such as `"v3_1"`. `NULL` (default) takes
#'   panel990's current default, which is the point of delegating.
#' @param format `"parquet"` (panel990's default) or `"csv"`.
#' @param verbose Print progress.
#' @return Whatever [panel990::download_tables()] returns, invisibly: a frame
#'   describing what was fetched.
#' @export
pf_efilepf_fetch <- function(years = pf_efilepf_years(), dir = pf_efilepf_dir(),
                             version = NULL, format = NULL, verbose = TRUE) {
  if (!requireNamespace("panel990", quietly = TRUE))
    stop("pf_efilepf_fetch() needs panel990:\n",
         "  remotes::install_github(\"Nonprofit-Open-Data-Collective/panel990\")\n",
         "Already-downloaded files can be built without it via ",
         "pf_efilepf_build().", call. = FALSE)
  args <- list(form = "990PF")
  if (!is.null(version)) args$version <- version
  if (!is.null(format))  args$format  <- format
  src <- do.call(panel990::data_source, args)
  if (verbose)
    message(sprintf("panel990 source: %s (release %s, %s)",
                    src$root, src$version, src$format))
  res <- panel990::download_tables(
    years = years, tables = pf_efilepf_table(), source = src,
    path = dir, verbose = verbose)
  invisible(res)
}

#' The release pfmatch would read, as panel990 resolves it
#'
#' Recorded in run provenance so an artifact says which published release and
#' which concordance it was built against, rather than leaving it implied.
#'
#' @return A named list: `efile_version`, `efile_root`, `efile_format`,
#'   `concordance_version`, and `grants_table`. Entries are `NA` when the
#'   relevant package is not installed.
#' @export
pf_source_provenance <- function() {
  out <- list(grants_table = pf_efilepf_table(),
              efile_version = NA_character_, efile_root = NA_character_,
              efile_format = NA_character_, concordance_version = NA_character_)
  if (requireNamespace("panel990", quietly = TRUE)) {
    s <- panel990::data_source(form = "990PF")
    out$efile_version <- as.character(s$version)
    out$efile_root    <- as.character(s$root)
    out$efile_format  <- as.character(s$format)
  }
  if (requireNamespace("concordance990", quietly = TRUE)) {
    v <- concordance990::concordance_version()
    out$concordance_version <- as.character(v$package)
  }
  out
}

#' The grants-paid variables, taken from concordance990
#'
#' Reads the variable names from the installed concordance rather than
#' hardcoding them, so a concordance rename surfaces here instead of silently
#' producing all-missing columns. Falls back to the names baked into
#' [pf_efilepf_map()] when concordance990 is not installed.
#'
#' @param check When `TRUE` and concordance990 is installed, warn about any
#'   name pfmatch expects that the concordance no longer lists.
#' @return A character vector of concordance990 v2 variable names.
#' @export
pf_concordance_vars <- function(check = TRUE) {
  baked <- unname(pf_efilepf_map())
  baked <- baked[startsWith(baked, "PF_15_G_PAID")]
  if (!requireNamespace("concordance990", quietly = TRUE)) return(baked)
  v <- as.data.frame(concordance990::cc_variables())
  live <- v$variable_name[startsWith(v$variable_name, "PF_15_G_PAID")]
  if (isTRUE(check)) {
    gone <- setdiff(baked, live)
    if (length(gone))
      warning("pfmatch expects variable(s) the installed concordance990 (",
              as.character(concordance990::concordance_version()$package),
              ") no longer lists: ", paste(gone, collapse = ", "),
              ". Check reports/issues-resolved.csv for a rename.", call. = FALSE)
  }
  sort(unique(live))
}
