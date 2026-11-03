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

# Columns the IRS genuinely stopped publishing, and the first tax year they
# are absent from. An empty column in those years is correct data, not a build
# fault, and the per-year check below would otherwise fail on every sound file.
#
# PF_15_G_PAID_RECIP_STAT -- the GTDC SIGOCPYRFSTA, "foundation status of
# recipient" -- was dropped from Form 990-PF Part XV line 3. It is present
# every year 2009-2024 and absent from 2025 onward, permanently; see the
# "2025 drops the recipient-status column" section of R/efilepf.R for what
# that costs downstream.
.pf_discontinued <- function() list(PF_15_G_PAID_RECIP_STAT = 2025L)

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
    yn  <- suppressWarnings(as.integer(as.character(yr)))
    gone <- .pf_discontinued()
    bad <- character(0); noted <- character(0)
    for (c0 in needed) {
      v <- .pf_col(g, c0)
      if (all(is.na(v))) next
      ok <- !is.na(v) & nzchar(as.character(v))
      overall <- mean(ok)
      if (overall < 0.5) next          # sparse everywhere: nothing to compare to
      byyr <- tapply(ok, yr, mean)
      off  <- names(byyr)[!is.na(byyr) & byyr < 0.10]
      if (!length(off)) next
      # An empty year is EXPECTED where the IRS stopped publishing the column.
      # Without this the check fails on every well-formed file from 2025 on,
      # and a check that always fails is one nobody reads.
      from <- gone[[c0]]
      if (!is.null(from)) {
        exp <- off[suppressWarnings(as.integer(off)) >= from]
        off <- setdiff(off, exp)
        if (length(exp))
          noted <- c(noted, sprintf("%s absent from %d (expected)", c0, from))
      }
      if (length(off))
        bad <- c(bad, sprintf("%s empty in %s (corpus %.0f%%)", c0,
                              paste(off, collapse = "/"), 100 * overall))
    }
    add("per-year column coverage", if (!length(bad)) "PASS" else "FAIL",
        if (length(bad)) paste(bad, collapse = "; ")
        else paste(c(sprintf("no unexplained empty year over %d years",
                             length(unique(yr[!is.na(yr)]))), noted),
                   collapse = "; "))
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

# ============================================================================
# Does this frame carry the columns the cascade is about to block on?
#
# pf_check_reference() refuses a reference whose normalizer disagrees with the
# installed one, which catches keys that MOVED. It says nothing about keys that
# are ABSENT, and from the outside the two failures look nothing alike: a moved
# key stops matching, a missing key stops the pass.
#
# That gap cost a run. REF-augmented.rds was rebuilt on 2026-11-02 by a script
# that called pf_build_reference() and saveRDS() directly rather than going
# through pf_reference(), which adds the stage-4 recovery keys on the line
# before it saves. The bundle lost name_acro, name_pre and name_is_acro and
# nothing said so: pf_run_batches() rebuilt them in flight and charged the run
# 197.5 s (dev/REF-REBUILD-20261103.log). Any caller that reads that bundle
# WITHOUT going through pf_run_batches() or pf_match_grants(recover = TRUE)
# blocks D1-acronym and D2-prefix on columns that are not there, and gets an
# empty pass rather than an error.
#
# The required columns are read out of the pass specifications themselves, not
# from a list maintained by hand here, so a pass cannot be added without this
# check learning what it blocks on.
# ============================================================================

# Which columns does each pass block on, for one side of the join? `by` is
# shared, so it counts on both sides. A token pass blocks on its `token_col`,
# which defaults to `name_key` because that is np_block()'s own default.
.pf_pass_columns <- function(passes, side = c("y", "x")) {
  side <- match.arg(side)
  nm <- vapply(passes, function(p) as.character(p$name %||% "")[1], character(1))
  out <- lapply(passes, function(p) {
    a <- if (is.list(p$args)) p$args else list()
    cols <- c(a$by, if (identical(side, "x")) a$by_x else a$by_y)
    if (isTRUE(a$token)) cols <- c(cols, a$token_col %||% "name_key")
    cols <- as.character(unique(cols))
    cols[!is.na(cols) & nzchar(cols)]
  })
  names(out) <- nm
  out
}

# The only reference columns a run can supply for itself: pf_add_recovery_keys()
# derives all three from name_key. That is why their absence is a warning when
# the run is going to call it anyway, and a failure when it is not.
.pf_derivable_cols <- function() c("name_acro", "name_pre", "name_is_acro")

# Name the release a signature belongs to rather than printing a bare hash. A
# hash is a good fingerprint and a poor label, and npnormalize 0.1.9 can date
# one. Degrades to the hash alone wherever it cannot.
#
# "introduced by", not "is": a signature does not determine a release. A
# release that changes no rule reports its predecessor's value, so 0.1.9
# reports 0.1.8's and np_signature_history() answers which release PRODUCED a
# value -- the earliest that could have -- not which one is installed.
# npnormalize documents this and says what a consumer should do about it:
# record the signature AND packageVersion(), because neither determines the
# other. A previous consumer of that table read it as a one-to-one map and had
# to correct a caption.
#
# So `installed` is named alongside wherever the caller knows it, which is
# wherever the signature being labelled is the live one. For a signature read
# off an artifact it is left out: which release wrote that bundle is not
# something the installed version can answer.
.pf_sig_label <- function(sig, installed = NULL) {
  sig <- as.character(sig)[1]
  if (is.na(sig) || !nzchar(sig)) return("(none recorded)")
  also <- ""
  if (!is.null(installed)) {
    iv <- as.character(installed)[1]
    if (!is.na(iv) && nzchar(iv)) also <- sprintf("; installed %s", iv)
  }
  h <- tryCatch(npnormalize::np_signature_history(sig), error = function(e) NULL)
  if (!is.data.frame(h) || !nrow(h))
    return(if (nzchar(also)) sprintf("%s (unrecognized%s)", sig, also) else sig)
  v <- as.character(h$version[1])
  pkg <- as.character(h$package[1])
  if (is.na(v) || !nzchar(v))
    sprintf("%s (introduced by %s, version not recorded%s)", sig, pkg, also)
  else sprintf("%s (introduced by %s %s%s)", sig, pkg, v, also)
}

# The installed normalizer's own version, for the `installed` argument above.
# npnormalize is the normalizer; npmatch re-exports its signature function.
.pf_installed_normalizer <- function() {
  tryCatch(as.character(utils::packageVersion("npnormalize")),
           error = function(e) NULL)
}

#' Check a frame against the columns its passes block on
#'
#' Reports, one row per check, whether a reference bundle or a query frame
#' carries every column the given cascade passes need -- and for a bundle, also
#' whether it is stamped with the installed normalizer and whether it ships the
#' precomputed companions ([npmatch::np_cascade()] recomputes those on every
#' call when they are absent).
#'
#' @section Why absence is not the same failure as drift:
#' [pf_check_reference()] compares the bundle's `np_normalize_signature()` to
#' the installed one, which catches keys that moved under a reference built
#' earlier. A column that was never written is invisible to that check, and the
#' symptom is different in kind: the pass blocks on a column that does not
#' exist, produces no candidates, and the cascade carries on. A pass that finds
#' nothing is indistinguishable from a pass that had nothing to find.
#'
#' @section Severity:
#' `name_acro`, `name_pre` and `name_is_acro` are derived from `name_key` by
#' [pf_add_recovery_keys()], so a run that is going to call it can repair them
#' itself: absent, they are a `WARN` saying the saved bundle is incomplete.
#' With `recover = FALSE` nothing will repair them and the same absence is a
#' `FAIL`. Every other column comes out of normalization and cannot be rebuilt
#' here, so its absence is always a `FAIL`.
#'
#' A frame with no `name_key` has not been normalized at all, which is not a
#' defect: [npmatch::np_cascade()] normalizes a reference whose `name_key` is
#' `NULL`, and normalizes the query on every call. Such a frame gets one `WARN`
#' saying its blocking columns could not be checked, and the per-pass rows are
#' skipped rather than reported as failures.
#'
#' @param x A reference bundle (a list with a `reference` element), a reference
#'   frame, or a query frame.
#' @param passes Pass specifications, as [pf_staged_passes()] and
#'   [pf_recovery_passes()] return them. The default is the cascade
#'   [pf_run_batches()] runs.
#' @param side Which side of the join `x` is. `"auto"` reads a bundle as the
#'   reference side and a bare frame as the query side.
#' @param recover Will the caller add the recovery keys itself? See Severity.
#' @param strict When `TRUE`, any `FAIL` raises an error instead of returning.
#' @param verbose Print the report.
#' @return A `data.frame` with columns `check`, `status`
#'   (`PASS` / `WARN` / `FAIL` / `INFO`) and `detail`, invisibly.
#' @seealso [pf_check_reference()] for the normalizer stamp,
#'   [pf_validate_grants()] for the grant file.
#' @export
pf_check_schema <- function(x, passes = c(pf_staged_passes("lean"),
                                          pf_recovery_passes(state = TRUE)),
                            side = c("auto", "reference", "query"),
                            recover = TRUE, strict = FALSE, verbose = TRUE) {
  side <- match.arg(side)
  bundle <- is.list(x) && !is.data.frame(x) && !is.null(x$reference)
  if (identical(side, "auto")) side <- if (bundle) "reference" else "query"
  d <- if (bundle) x$reference else x
  if (is.null(d) || !length(names(d)))
    stop("pf_check_schema(): `x` has no columns to check.", call. = FALSE)
  have <- names(d)

  res <- list()
  add <- function(check, status, detail)
    res[[length(res) + 1L]] <<- data.frame(check = check, status = status,
                                           detail = detail,
                                           stringsAsFactors = FALSE)
  fmt <- function(v) format(v, big.mark = ",")

  add("side", "INFO", side)
  add("rows", "INFO", fmt(nrow(d)))
  add("columns", "INFO", fmt(length(have)))

  if (bundle) {
    sig  <- .pf_ref_signature(x)
    live <- tryCatch(npmatch::np_normalize_signature(),
                     error = function(e) NA_character_)
    add("normalizer stamp",
        if (is.null(sig)) "WARN"
        else if (identical(as.character(sig)[1], live)) "PASS" else "FAIL",
        if (is.null(sig))
          "absent -- the bundle cannot be shown to match the installed normalizer"
        else if (identical(as.character(sig)[1], live))
          .pf_sig_label(sig, .pf_installed_normalizer())
        # The bundle's own signature gets no `installed`: which release wrote
        # it is not something this machine's library can answer.
        else paste0("bundle ", .pf_sig_label(sig), ", installed ",
                    .pf_sig_label(live, .pf_installed_normalizer())))
    # Absent, each of these is recomputed by np_cascade() on EVERY call -- the
    # reason a bundle carries them at all is that the whole reference has to be
    # read to build one.
    for (el in c("name_freq", "token_idf", "ref_index"))
      add(paste("bundle", el), if (is.null(x[[el]])) "WARN" else "PASS",
          if (is.null(x[[el]]))
            "absent -- np_cascade() will recompute it on every call"
          else "present")
    tc <- x$ref_index$token_col
    if (!is.null(tc)) add("ref_index token_col", "INFO", as.character(tc)[1])
  }

  # An un-normalized frame has none of the keys yet and that is not a defect:
  # np_cascade() normalizes a reference whose name_key is NULL, and normalizes
  # the query every time. `is.null(name_key)` is npmatch's own test for it
  # (npmatch R/cascade.R), so it is the one used here. Checking blocking columns
  # against such a frame would report every pass as broken, so the per-pass
  # check is skipped and said to be skipped.
  if (!("name_key" %in% have)) {
    add("normalized", "WARN",
        paste0("no name_key -- np_cascade() will normalize this frame at run ",
               "time, so its blocking columns cannot be checked here"))
  } else {
    need <- .pf_pass_columns(passes,
                             side = if (identical(side, "query")) "x" else "y")
    derivable <- .pf_derivable_cols()
    for (i in seq_along(need)) {
      cols <- need[[i]]
      nm <- names(need)[i]
      if (!nzchar(nm)) nm <- sprintf("pass %d", i)
      if (!length(cols)) {
        add(nm, "INFO", "blocks on no named column")
        next
      }
      miss <- setdiff(cols, have)
      if (!length(miss)) {
        add(nm, "PASS", paste(cols, collapse = ", "))
        next
      }
      only_derived <- all(miss %in% derivable)
      add(nm, if (only_derived && isTRUE(recover)) "WARN" else "FAIL",
          if (only_derived && isTRUE(recover))
            paste0(paste(miss, collapse = ", "),
                   " absent -- pf_add_recovery_keys() will rebuild it in flight;",
                   " the saved bundle is incomplete")
          else paste0(paste(miss, collapse = ", "), " absent",
                      if (only_derived) " and recover = FALSE" else "",
                      " -- this pass would return no candidates"))
    }
  }

  out <- do.call(rbind, res)
  if (verbose) {
    message(strrep("-", 76))
    message("pf_check_schema")
    message(strrep("-", 76))
    for (i in seq_len(nrow(out)))
      message(sprintf("  %-5s %-22s %s", out$status[i], out$check[i], out$detail[i]))
    message(strrep("-", 76))
    message(sprintf("  %d FAIL | %d WARN", sum(out$status == "FAIL"),
                    sum(out$status == "WARN")))
  }
  fails <- out[out$status == "FAIL", , drop = FALSE]
  if (isTRUE(strict) && nrow(fails))
    stop("pf_check_schema() found ", nrow(fails), " failure(s): ",
         paste(fails$check, collapse = "; "), call. = FALSE)
  invisible(out)
}
