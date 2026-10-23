# ============================================================================
# Validate a grant file before anything is measured on it.
#
# Several problems this session were silent rather than loud, and each would
# have been caught here:
#
#   * two grant vintages concatenated by a loose file pattern -- 422,806 rows
#     where either population alone is a fraction of that, double-counting
#     filings present in both
#   * TABLE_ID discarded by the build, so the published row key was unavailable
#     and a content hash had to be invented to replace it
#   * a column read as all-NA because a schema changed under a reader, with the
#     pipeline carrying on rather than failing
#   * superseded filings left in place, double-counting 1.75% of grant rows
#
# None of these throw. They produce plausible numbers that are wrong, which is
# the worst failure mode for a measurement pipeline. This function makes the
# checks explicit and cheap enough to run before every benchmark.
# ============================================================================

#' Validate a grant file
#'
#' Checks schema consistency, key uniqueness, deduplication status and column
#' coverage, and reports what it finds rather than guessing at a repair.
#'
#' @param grants A grant frame, or a path passed to [pf_read_grants()].
#' @param strict When `TRUE`, any FAIL raises an error instead of returning.
#' @param verbose Print the report.
#' @return A `data.frame` of checks, one row per check, with columns `check`,
#'   `status` (`PASS` / `WARN` / `FAIL` / `INFO`) and `detail`, invisibly.
#' @export
pf_validate_grants <- function(grants, strict = FALSE, verbose = TRUE) {
  g <- if (is.character(grants) && length(grants) == 1L)
    pf_read_grants(grants) else as.data.frame(grants)
  n <- nrow(g)
  res <- list()
  add <- function(check, status, detail)
    res[[length(res) + 1L]] <<- data.frame(check = check, status = status,
                                           detail = detail,
                                           stringsAsFactors = FALSE)
  fmt <- function(x) format(x, big.mark = ",")

  add("rows", "INFO", fmt(n))

  ## ---- one schema, not two -------------------------------------------------
  sch <- .pf_schema_of(g)
  add("schema", if (sch == "mixed") "FAIL" else if (sch == "unknown") "WARN" else "PASS",
      switch(sch,
             v2      = "concordance990 v2 names",
             gtdc    = "legacy v1/GTDC names -- readable, but superseded; rebuild with schema = \"v2\"",
             mixed   = "BOTH vintages present: two populations were concatenated, which double-counts filings",
             unknown = "no recognised grant columns"))

  ## ---- the published row key ----------------------------------------------
  if (all(c("OBJECTID", "TABLE_ID") %in% names(g))) {
    k <- paste(g$OBJECTID, g$TABLE_ID, sep = "|")
    dup <- sum(duplicated(k))
    add("row key OBJECTID|TABLE_ID", if (dup == 0L) "PASS" else "FAIL",
        if (dup == 0L) "unique" else paste(fmt(dup), "duplicate row keys"))
  } else {
    add("row key OBJECTID|TABLE_ID", "WARN",
        "TABLE_ID absent -- the published row key is unavailable, so rows cannot be addressed stably across rebuilds")
  }

  ## ---- superseded filings --------------------------------------------------
  meta <- c("EIN2", "TAX_YEAR", "RETURN_AMENDED_X", "RETURN_PARTIAL_X")
  if (all(meta %in% names(g))) {
    sq <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; x }
    ctx <- paste(sq(g$EIN2), sq(g$TAX_YEAR), .pf_flagged(g$RETURN_GROUP_X),
                 .pf_flagged(g$RETURN_PARTIAL_X), sep = "\r")
    per_ctx <- tapply(g$OBJECTID, ctx, function(x) length(unique(x)))
    multi <- sum(per_ctx > 1L)
    flagged <- if ("dedup_flag" %in% names(g)) sum(as.logical(g$dedup_flag), na.rm = TRUE) else NA
    add("superseded filings", if (multi == 0L) "PASS" else "WARN",
        if (multi == 0L) "no reporting context holds more than one filing"
        else paste(fmt(multi), "context(s) hold several filings;",
                   "run pf_efilepf_dedup() or build with dedup = TRUE"))
    if (!is.na(flagged) && flagged > 0L)
      add("dedup flags", "INFO",
          paste(fmt(flagged), "row(s) in contexts that disagree with no amendment to settle them -- kept deliberately"))
  } else {
    add("superseded filings", "WARN",
        paste("cannot check: missing", paste(setdiff(meta, names(g)), collapse = ", ")))
  }

  ## ---- the columns the matcher needs, in either schema ---------------------
  needed <- c("PF_15_G_PAID_RECIP_NAME_ORG_L1", "PF_15_G_PAID_RECIP_ADDR_CITY",
              "PF_15_G_PAID_RECIP_ADDR_STATE",  "PF_15_G_PAID_RECIP_ADDR_ZIP",
              "PF_15_G_PAID_AMT",               "PF_15_G_PAID_RECIP_STAT")
  resolved <- vapply(needed, function(c0) !all(is.na(.pf_col(g, c0))), logical(1))
  add("matcher columns resolve", if (all(resolved)) "PASS" else "FAIL",
      if (all(resolved)) paste(length(needed), "of", length(needed), "resolve and are non-empty")
      else paste("all-missing:", paste(needed[!resolved], collapse = ", ")))

  ## ---- per-year coverage, which a column shift breaks in ONE year ---------
  # The corpus-wide check above passes while a single year is wrecked: when the
  # v2 build wrote 2025 two columns out of register, every one of its 658,811
  # rows had an empty amount, but 96% of the corpus was fine so the column
  # still "resolved". A shift shows up as a year at ~0% on a column the other
  # years populate, which is what this looks for.
  yr <- .pf_col(g, "TAX_YEAR")
  if (!all(is.na(yr)) && length(unique(yr[!is.na(yr)])) > 1L) {
    bad <- character(0)
    for (c0 in needed) {
      v <- .pf_col(g, c0)
      if (all(is.na(v))) next
      ok <- !is.na(v) & nzchar(as.character(v))
      overall <- mean(ok)
      if (overall < 0.5) next          # sparse everywhere: nothing to compare to
      byyr <- tapply(ok, yr, mean)
      off  <- names(byyr)[!is.na(byyr) & byyr < 0.10]
      if (length(off))
        bad <- c(bad, sprintf("%s empty in %s (corpus %.0f%%)", c0,
                              paste(off, collapse = "/"), 100 * overall))
    }
    add("per-year column coverage", if (!length(bad)) "PASS" else "FAIL",
        if (!length(bad))
          sprintf("no year is empty on a column the others populate (%d years)",
                  length(unique(yr[!is.na(yr)])))
        else paste(bad, collapse = "; "))
  }

  ## ---- state / ZIP sanity, which a transposition would break --------------
  st <- .pf_col(g, "PF_15_G_PAID_RECIP_ADDR_STATE")
  zp <- .pf_col(g, "PF_15_G_PAID_RECIP_ADDR_ZIP")
  pct <- function(x, p) {
    x <- x[!is.na(x) & nzchar(x)]
    if (!length(x)) return(NA_real_)
    100 * mean(grepl(p, x))
  }
  s2 <- pct(st, "^[A-Za-z]{2}$"); z5 <- pct(zp, "^[0-9]{5}")
  ok <- !is.na(s2) && !is.na(z5) && s2 > 90 && z5 > 85
  add("state/ZIP not transposed", if (ok) "PASS" else "WARN",
      sprintf("state %.1f%% two-letter, ZIP %.1f%% numeric", s2, z5))

  ## ---- provenance ----------------------------------------------------------
  pr <- pf_source_provenance()
  add("source provenance", "INFO",
      sprintf("efile %s (%s), concordance990 %s", pr$efile_version,
              pr$efile_format, pr$concordance_version))

  out <- do.call(rbind, res)
  if (verbose) {
    message(strrep("-", 76))
    message("pf_validate_grants")
    message(strrep("-", 76))
    for (i in seq_len(nrow(out)))
      message(sprintf("  %-5s %-28s %s", out$status[i], out$check[i], out$detail[i]))
    nf <- sum(out$status == "FAIL"); nw <- sum(out$status == "WARN")
    message(strrep("-", 76))
    message(sprintf("  %d FAIL | %d WARN", nf, nw))
  }
  fails <- out[out$status == "FAIL", ]
  if (isTRUE(strict) && nrow(fails))
    stop("pf_validate_grants() found ", nrow(fails), " failure(s): ",
         paste(fails$check, collapse = "; "), call. = FALSE)
  invisible(out)
}
