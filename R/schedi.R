#' Form 990 Schedule I as an alias source for the BMF
#'
#' Schedule I Part II is where a non-PF 990 filer lists every grant it made to a
#' US organization or government: recipient **name**, **address**, and **EIN**.
#' That is the same speech act as 990-PF Part XIV — a grantmaker writing down who
#' it paid — so the name representations come from the same distribution as the
#' queries we are trying to match. The BMF gives one *legal* name per EIN; this
#' gives many *observed* names.
#'
#' @section Why it earns its place:
#' Measured on the 50k benchmark (`dev/SCHEDI-ALIAS-FINDINGS.md`):
#' \itemize{
#'   \item 95.6% agreement with the accepted EIN on grants the cascade already
#'     resolved confidently — and the error rate is a clean function of
#'     `n_filers`, the number of *distinct grantmakers* who wrote that spelling:
#'     86.1% at one filer, 95.4% at 2-4, 98.0% at 5-19, 99.0% at 20+.
#'   \item 18.1% of the NO tier gets a hit; roughly half of those are both
#'     BMF-present and multi-filer, worth about +2.2 points.
#'   \item It resolves rebrands (`Lakeview Pantry` -> Nourishing Hope), mergers
#'     (`Foundation for National Progress` -> Center for Investigative
#'     Reporting), and brand-vs-legal names (`USA FOR UNHCR`, `VOTEORG`) — none
#'     of which any string metric can reach.
#' }
#'
#' @section The trap this design avoids:
#' Do **not** use the alias to assign an EIN, and do not block on it. If the
#' alias merely surfaces the BMF row for `Nourishing Hope` as a candidate for the
#' query `Lakeview Pantry`, the comparison step scores those two names against
#' each other, gets ~0, and the veto layer discards the correct answer. The match
#' is justified by the alias *observation*, not by name similarity. So the alias
#' name is written into the reference as a row in its own right, and the existing
#' `exact-name` pass resolves it with no new comparison logic.
#'
#' @name pf_schedi
NULL

PF_SCHEDI_BASE <- "https://nccs-efile.s3.us-east-1.amazonaws.com/public"

#' Default Schedule I years
#' @keywords internal
#' @export
pf_schedi_years <- function() 2009:2024

#' URL for one Schedule I extract
#'
#' @param year Tax year.
#' @param version NCCS extract version. **Use `efile_v2_2`**: `efile_v2_1` has
#'   the same schema but roughly a tenth of the rows at identical bytes-per-row
#'   (641k vs 66k grants in 2024), i.e. it is a partial or superseded extract.
#' @keywords internal
#' @export
pf_schedi_url <- function(year, version = "efile_v2_2")
  sprintf("%s/%s/SI-P02-T01-GRANTS-US-ORGS-GOVTS-%d.CSV", PF_SCHEDI_BASE, version, year)

#' Download the Schedule I extracts
#'
#' Downloads to a staging name and renames on success, so an interrupted run
#' never leaves a truncated file that a later run would treat as complete.
#'
#' @param dir Destination directory. Defaults to `~/Documents/grants` —
#'   deliberately outside the package and outside any synced folder, because the
#'   raw set is ~3.5 GB.
#' @param years,version Passed to [pf_schedi_url()].
#' @param overwrite Re-download files that already exist.
#' @param verbose Print progress.
#' @return Character vector of local paths, invisibly.
#' @export
pf_schedi_download <- function(dir = pf_schedi_dir(), years = pf_schedi_years(),
                               version = "efile_v2_2", overwrite = FALSE,
                               verbose = TRUE) {
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
  out <- character()
  for (y in years) {
    url <- pf_schedi_url(y, version)
    dest <- file.path(dir, basename(url))
    if (!overwrite && file.exists(dest) && file.size(dest) > 0) {
      if (verbose) message(sprintf("  have %d (%.0f MB)", y, file.size(dest) / 1e6))
      out <- c(out, dest); next
    }
    tmp <- paste0(dest, ".part")
    if (verbose) message(sprintf("  downloading %d ...", y))
    ok <- tryCatch({ utils::download.file(url, tmp, mode = "wb", quiet = TRUE); TRUE },
                   error = function(e) FALSE)
    if (!ok || !file.exists(tmp) || file.size(tmp) == 0) {
      unlink(tmp); warning("failed: ", url, call. = FALSE); next
    }
    file.rename(tmp, dest)
    out <- c(out, dest)
    if (verbose) message(sprintf("    %d done (%.0f MB)", y, file.size(dest) / 1e6))
  }
  invisible(out)
}

#' Default Schedule I data directory
#' @keywords internal
#' @export
pf_schedi_dir <- function()
  Sys.getenv("PF_GRANTS_DIR", file.path(path.expand("~"), "Documents", "grants"))

#' Load the extracts into DuckDB and reduce them to an alias table
#'
#' Three tables are created. `grants_raw` is the union of the yearly CSVs
#' (`union_by_name`, because the pre-2019 files predate the `RecipientTable`
#' column). `recip` is one normalized row per grant. `alias` is the payload: one
#' row per distinct `(ein, name_norm, city, state, zip5)` with `n_obs` and
#' `n_filers`.
#'
#' `n_filers` is the trust signal and the reason this works — it counts
#' *independent* observations, so it separates a real alias from one filer's
#' typo. See the precision table in [pf_schedi].
#'
#' @param dir Directory holding the CSVs.
#' @param db Path to the DuckDB file.
#' @param rebuild Reload even if `grants_raw` already exists.
#' @param threads DuckDB thread count.
#' @return `db`, invisibly.
#' @export
pf_schedi_build <- function(dir = pf_schedi_dir(),
                            db = file.path(dir, "schedi_grants.duckdb"),
                            rebuild = FALSE, threads = 4L) {
  files <- list.files(dir, pattern = "^SI-P02-T01-GRANTS-US-ORGS-GOVTS-[0-9]{4}[.]CSV$",
                      full.names = TRUE)
  if (!length(files)) stop("no Schedule I CSVs in ", dir, call. = FALSE)

  con <- DBI::dbConnect(duckdb::duckdb(), db)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  DBI::dbExecute(con, sprintf("PRAGMA threads=%d", threads))

  if (rebuild || !"grants_raw" %in% DBI::dbListTables(con)) {
    message("loading ", length(files), " yearly files ...")
    DBI::dbExecute(con, sprintf("
      CREATE OR REPLACE TABLE grants_raw AS
      SELECT * FROM read_csv([%s], union_by_name = true, header = true,
                             all_varchar = true, ignore_errors = true,
                             sample_size = -1)",
      paste(sprintf("'%s'", gsub("\\\\", "/", files)), collapse = ", ")))
  }

  message("normalizing recipients ...")
  DBI::dbExecute(con, "
  CREATE OR REPLACE TABLE recip AS
  SELECT
    TAX_YEAR AS tax_year,
    ORG_EIN  AS filer_ein,
    CASE WHEN length(regexp_replace(SI_02_GRANT_US_ORG_EIN,'[^0-9]','','g')) = 9
         THEN regexp_replace(SI_02_GRANT_US_ORG_EIN,'[^0-9]','','g') END AS ein,
    trim(SI_02_GRANT_US_ORG_NAME_L1) AS name_l1,
    trim(SI_02_GRANT_US_ORG_NAME_L2) AS name_l2,
    trim(SI_02_GRANT_US_ORG_ADDR_L1) AS street,
    trim(SI_02_GRANT_US_ORG_ADDR_CITY) AS city,
    upper(trim(SI_02_GRANT_US_ORG_ADDR_STATE)) AS state,
    CASE WHEN length(regexp_replace(SI_02_GRANT_US_ORG_ADDR_ZIP,'[^0-9]','','g')) >= 5
         THEN substr(regexp_replace(SI_02_GRANT_US_ORG_ADDR_ZIP,'[^0-9]','','g'),1,5) END AS zip5,
    TRY_CAST(SI_02_GRANT_US_ORG_AMT_CASH AS DOUBLE) AS amt_cash,
    regexp_replace(regexp_replace(upper(
      CASE WHEN SI_02_GRANT_US_ORG_NAME_L2 IS NOT NULL
            AND trim(SI_02_GRANT_US_ORG_NAME_L2) <> ''
           THEN SI_02_GRANT_US_ORG_NAME_L1 || ' ' || SI_02_GRANT_US_ORG_NAME_L2
           ELSE SI_02_GRANT_US_ORG_NAME_L1 END),
      '[^A-Z0-9 ]','','g'), ' +',' ','g') AS name_norm
  FROM grants_raw")

  message("deduplicating to the alias table ...")
  DBI::dbExecute(con, "
  CREATE OR REPLACE TABLE alias AS
  SELECT ein, name_norm, city, state, zip5,
         COUNT(*) AS n_obs, COUNT(DISTINCT filer_ein) AS n_filers,
         MIN(tax_year) AS first_year, MAX(tax_year) AS last_year,
         SUM(amt_cash) AS total_cash,
         any_value(name_l1) AS name_display, any_value(street) AS street
  FROM recip
  WHERE ein IS NOT NULL AND name_norm <> '' AND length(trim(name_norm)) > 1
  GROUP BY 1,2,3,4,5")

  n <- DBI::dbGetQuery(con, "SELECT COUNT(*) n FROM alias")$n
  message(sprintf("alias: %s rows over %s EINs", format(n, big.mark = ","),
    format(DBI::dbGetQuery(con, "SELECT COUNT(DISTINCT ein) n FROM alias")$n,
           big.mark = ",")))
  invisible(db)
}

#' Read the alias table, one row per (EIN, name)
#'
#' Collapses the `(ein, name, city, state, zip5)` grain to `(ein, name)`, keeping
#' the best-corroborated address for each pairing, and drops names that are
#' ambiguous across EINs — a name used for two different organizations cannot
#' identify one of them.
#'
#' @param db Path to the DuckDB file.
#' @param min_filers Minimum distinct grantmakers. `1` admits everything
#'   (86% precision), `2` is the sensible floor (95%), `5` is auto-accept grade
#'   (98%).
#' @param drop_ambiguous Drop names that map to more than one EIN.
#' @return A `data.table`, one row per `(ein, name_norm)`.
#' @export
pf_schedi_alias <- function(db = file.path(pf_schedi_dir(), "schedi_grants.duckdb"),
                            min_filers = 2L, drop_ambiguous = TRUE) {
  con <- DBI::dbConnect(duckdb::duckdb(), db, read_only = TRUE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  a <- data.table::as.data.table(DBI::dbGetQuery(con, "
    SELECT ein, name_norm, city, state, zip5, street, name_display,
           n_obs, n_filers, first_year, last_year
    FROM alias"))
  # collapse to (ein, name): keep the address the most filers agreed on
  data.table::setorder(a, ein, name_norm, -n_filers, -n_obs)
  out <- a[, .(city = city[1], state = state[1], zip5 = zip5[1], street = street[1],
               name_display = name_display[1],
               n_obs = sum(n_obs), n_filers = sum(n_filers),
               first_year = min(first_year), last_year = max(last_year)),
           by = .(ein, name_norm)]
  if (drop_ambiguous) {
    amb <- out[, .(k = data.table::uniqueN(ein)), by = name_norm][k > 1L]$name_norm
    out <- out[!name_norm %in% amb]
  }
  out[n_filers >= min_filers]
}

#' Append Schedule I alias rows to the BMF
#'
#' Emits one extra reference row per `(ein, alias name)` that the BMF does not
#' already carry, copying every other field — NTEE, subsection, foundation code,
#' filing requirement — from that EIN's own BMF row, so the augmented file is a
#' drop-in for the plain one.
#'
#' Only the **name** varies by default. The alias address is used because that is
#' how grantmakers write it, which is the premise of the whole source; pass
#' `address = "bmf"` to keep the BMF's own address instead.
#'
#' @param bmf The BMF: a path or a data frame. Works with either the active file
#'   or the unified (active + inactive) one — the unified file attaches 8.4
#'   points more of the alias table (64.8% of alias EINs vs 56.4%).
#' @param alias Output of [pf_schedi_alias()].
#' @param address `"alias"` or `"bmf"`.
#' @param name_col,display_col,ein_col BMF column names.
#' @param verbose Print the difference report.
#' @return The BMF with alias rows appended and three provenance columns:
#'   `row_source` (`"bmf"` / `"schedi"`), `alias_n_filers`, `alias_last_year`.
#' @export
pf_bmf_augment <- function(bmf, alias, address = c("alias", "bmf"),
                           name_col = "org_name_join",
                           display_col = "org_name_display",
                           ein_col = "ein", verbose = TRUE) {
  address <- match.arg(address)
  say <- function(...) if (verbose) cat(sprintf(...), "\n")

  if (is.character(bmf) && length(bmf) == 1L)
    bmf <- data.table::fread(bmf, colClasses = "character", showProgress = FALSE)
  b <- data.table::as.data.table(bmf)
  say("BMF: %s rows", format(nrow(b), big.mark = ","))

  key <- function(x) {
    x <- toupper(as.character(x)); x[is.na(x)] <- ""
    gsub(" +", " ", trimws(gsub("[^A-Z0-9 ]", "", x)))
  }
  e9 <- function(x) { x <- gsub("[^0-9]", "", as.character(x))
                      x[nchar(x) != 9] <- NA_character_; x }

  b[, .e := e9(get(ein_col))]
  a <- data.table::copy(data.table::as.data.table(alias))
  a[, .e := e9(ein)]
  a <- a[!is.na(.e)]
  say("alias rows in: %s over %s EINs", format(nrow(a), big.mark = ","),
      format(data.table::uniqueN(a$.e), big.mark = ","))

  # 1. the EIN must exist in this BMF, or there is nothing to copy from
  first <- b[!duplicated(.e) & !is.na(.e)]
  i <- match(a$.e, first$.e)
  a[, .row := i]
  n_orphan <- sum(is.na(i))
  a <- a[!is.na(.row)]
  say("  dropped %s with no BMF row for the EIN", format(n_orphan, big.mark = ","))

  # 2. the name must be new -- an alias equal to the BMF name or DBA adds nothing
  have <- unique(rbind(
    b[, .(.e, k = key(get(name_col)))],
    if (!is.null(b$dba_name)) b[, .(.e, k = key(dba_name))] else NULL))
  have <- have[nzchar(k)]
  dup <- paste0(a$.e, "|", a$name_norm) %in% paste0(have$.e, "|", have$k)
  say("  dropped %s already present as the BMF name or DBA", format(sum(dup), big.mark = ","))
  a <- a[!dup]
  say("  net new alias rows: %s", format(nrow(a), big.mark = ","))
  if (!nrow(a)) { b[, `:=`(row_source = "bmf", alias_n_filers = NA_integer_,
                           alias_last_year = NA_character_)][, .e := NULL]; return(b[]) }

  # 3. clone the EIN's BMF row, then overwrite name (and address)
  new <- first[a$.row]
  data.table::set(new, j = name_col,    value = a$name_norm)
  data.table::set(new, j = display_col, value = a$name_display)
  if (address == "alias") {
    if ("org_addr_street" %in% names(new)) data.table::set(new, j = "org_addr_street", value = a$street)
    if ("org_addr_city"   %in% names(new)) data.table::set(new, j = "org_addr_city",   value = a$city)
    if ("org_addr_state"  %in% names(new)) data.table::set(new, j = "org_addr_state",  value = a$state)
    if ("org_addr_zip5"   %in% names(new)) data.table::set(new, j = "org_addr_zip5",   value = a$zip5)
    if ("org_addr_zip4"   %in% names(new)) data.table::set(new, j = "org_addr_zip4",   value = NA_character_)
  }
  new[, `:=`(row_source = "schedi",
             alias_n_filers = as.integer(a$n_filers),
             alias_last_year = as.character(a$last_year))]
  b[, `:=`(row_source = "bmf", alias_n_filers = NA_integer_,
           alias_last_year = NA_character_)]

  out <- rbind(b, new, fill = TRUE)
  out[, .e := NULL]
  if (".row" %in% names(out)) out[, .row := NULL]
  say("augmented BMF: %s rows (+%.1f%%)", format(nrow(out), big.mark = ","),
      100 * nrow(new) / nrow(b))
  out[]
}
