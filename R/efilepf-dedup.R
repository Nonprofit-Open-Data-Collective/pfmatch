# ============================================================================
# Filing-level deduplication for the 990-PF grants-paid table.
#
# WHY NOT panel990::panel_deduplicate(). That function keeps exactly one filing
# per organization-year, preferring non-group, then non-partial, then amended,
# then the newest timestamp. That is right for its job -- assembling
# organization-by-year financial panels, where one row per org-year is the
# point and a short-period return is noise.
#
# It is wrong for this table, and the reason is cardinality. PF-P15-T01 is a
# 1:M table: many grant rows per filing, which is why it carries TABLE_ID at
# all. Measured over all 17,560,767 grant rows, 310 organization-years hold a
# short-period filing alongside a full-year one, and in 97 of those the
# PARTIAL return reports MORE grants than the full-year return. Preferring
# non-partial would silently delete real grants from a grant-recovery pipeline.
#
# THE RULE HERE. A filing can only supersede another filing of the same
# reporting context, so the unit is
#
#     (EIN2, TAX_YEAR, group flag, partial flag)
#
# EIN2 rather than ORG_EIN because it is the stable form: it preserves leading
# zeros and survives numeric casting. Distinct reporting contexts are never
# compared, so a short-period return is never dropped for sharing a tax year
# with a full-year return, and a group return is never dropped for sharing one
# with a primary return. (990-PF filers do not file group returns -- measured
# RETURN_GROUP_X is FALSE on every row -- but the flag stays in the key so the
# behaviour is correct if that ever changes.)
#
# Within one context:
#
#   identical grant content   -> keep one copy, lowest OBJECTID for
#                                determinism. Dropping a copy loses nothing.
#                                8,277 of 10,073 multi-filing units.
#   an amended filing exists  -> keep the amended one, newest timestamp first.
#                                The original is superseded. 1,481 units.
#   no amendment, content
#   differs                   -> KEEP EVERYTHING and flag. Supersession cannot
#                                be established from the metadata, and the
#                                brief is to keep every grant reported.
#
# Content is compared on the grant fields, not on TABLE_ID: row order within a
# filing carries no meaning, so the comparison is over the sorted row set.
# ============================================================================

# Flag and timestamp encodings follow panel990's, so the two packages read the
# same files the same way: X / TRUE / T / 1 / Y / YES, and three timestamp
# layouts. Reimplemented rather than imported to avoid a dependency on
# panel990 internals, which are not exported.
.pf_flagged <- function(x) {
  if (is.logical(x)) return(!is.na(x) & x)
  if (is.numeric(x)) return(!is.na(x) & x == 1)
  v <- toupper(trimws(as.character(x)))
  !is.na(v) & v %in% c("X", "TRUE", "T", "1", "Y", "YES")
}

.pf_stamp <- function(x) {
  v <- trimws(as.character(x))
  v[is.na(v) | v == ""] <- NA_character_
  v <- sub(" (UTC|GMT)$", "", v, ignore.case = TRUE)
  out <- as.POSIXct(rep(NA_real_, length(v)), origin = "1970-01-01", tz = "UTC")
  for (fmt in c("%Y-%m-%d %H:%M:%OS", "%Y-%m-%dT%H:%M:%OS", "%Y-%m-%d")) {
    miss <- is.na(out) & !is.na(v)
    if (!any(miss)) break
    out[miss] <- suppressWarnings(as.POSIXct(v[miss], format = fmt, tz = "UTC"))
  }
  out
}

#' Grant fields compared when deciding whether two filings are the same
#'
#' Concordance990 v2 names. TABLE_ID is deliberately excluded: it is a row
#' counter within a filing, so two identical filings would differ on it.
#'
#' @return A character vector of column names.
#' @export
pf_grant_content_cols <- function() {
  c("PF_15_G_PAID_RECIP_NAME_ORG_L1", "PF_15_G_PAID_RECIP_NAME_ORG_L2",
    "PF_15_G_PAID_RECIP_NAME_PERS",   "PF_15_G_PAID_RECIP_ADDR_L1",
    "PF_15_G_PAID_RECIP_ADDR_L2",     "PF_15_G_PAID_RECIP_ADDR_CITY",
    "PF_15_G_PAID_RECIP_ADDR_STATE",  "PF_15_G_PAID_RECIP_ADDR_ZIP",
    "PF_15_G_PAID_RECIP_ADDR_CNTR",   "PF_15_G_PAID_AMT",
    "PF_15_G_PAID_PURPOSE",           "PF_15_G_PAID_RECIP_STAT",
    "PF_15_G_PAID_RELATIONSHIP")
}

#' Drop superseded and duplicate 990-PF filings, keeping every grant reported
#'
#' Deduplicates at the level of the **filing**, never the grant row, and only
#' within one reporting context — see the file header for why this differs
#' deliberately from [panel990::panel_deduplicate()].
#'
#' @param d A grants-paid frame carrying the ef2 filing metadata: `EIN2`,
#'   `TAX_YEAR`, `OBJECTID`, and where available `RETURN_GROUP_X`,
#'   `RETURN_PARTIAL_X`, `RETURN_AMENDED_X`, `RETURN_TIME_STAMP`.
#' @param content_cols Grant fields used to decide whether two filings report
#'   the same thing. Defaults to [pf_grant_content_cols()].
#' @param verbose Print the tally.
#' @return `d` with superseded and duplicate filings removed, carrying two new
#'   columns: `dedup_action` (`kept`, `kept_amended`, `kept_flagged`) and
#'   `dedup_flag` — `TRUE` where several filings of one context disagree and
#'   no amendment settles it, so **all** of them were kept. An attribute
#'   `"pf_dedup"` holds the per-context audit table.
#' @export
pf_efilepf_dedup <- function(d, content_cols = pf_grant_content_cols(),
                             verbose = TRUE) {
  stopifnot(is.data.frame(d))
  need <- c("EIN2", "TAX_YEAR", "OBJECTID")
  miss <- setdiff(need, names(d))
  if (length(miss))
    stop("pf_efilepf_dedup() needs the ef2 filing metadata; missing: ",
         paste(miss, collapse = ", "),
         ". Build the grant file with pf_efilepf_build(schema = \"v2\"); the ",
         "legacy gtdc schema discards these columns.", call. = FALSE)
  D <- data.table::as.data.table(d)
  n0 <- nrow(D)
  sq <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; x }

  grp <- if ("RETURN_GROUP_X"   %in% names(D)) .pf_flagged(D$RETURN_GROUP_X)   else rep(FALSE, n0)
  par <- if ("RETURN_PARTIAL_X" %in% names(D)) .pf_flagged(D$RETURN_PARTIAL_X) else rep(FALSE, n0)
  amd <- if ("RETURN_AMENDED_X" %in% names(D)) .pf_flagged(D$RETURN_AMENDED_X) else rep(FALSE, n0)
  ts  <- if ("RETURN_TIME_STAMP" %in% names(D)) as.numeric(.pf_stamp(D$RETURN_TIME_STAMP))
         else rep(NA_real_, n0)

  # the reporting context: a filing can only supersede another in the same one
  D[, `:=`(.ctx = paste(sq(EIN2), sq(TAX_YEAR), grp, par, sep = "\r"),
           .amd = amd, .ts = ts)]

  cc <- intersect(content_cols, names(D))
  if (!length(cc))
    stop("none of `content_cols` are present; cannot compare filings.", call. = FALSE)
  D[, .rowkey := do.call(paste, c(lapply(cc, function(k) sq(D[[k]])), sep = "\r"))]

  # one row per filing: its content fingerprint, flags and timestamp
  fil <- D[, .(.n_rows = .N,
               .fp = .pf_fingerprint(.rowkey),
               .amd = .amd[1], .ts = .ts[1]), by = .(.ctx, OBJECTID)]

  ctx <- fil[, .(n_filings = .N, n_amended = sum(.amd),
                 identical_content = data.table::uniqueN(.fp) == 1L), by = .ctx]

  # choose which OBJECTIDs survive in each context
  fil <- merge(fil, ctx, by = ".ctx", all.x = TRUE)
  data.table::setorder(fil, .ctx, -.amd, -.ts, OBJECTID, na.last = TRUE)
  fil[, action := data.table::fcase(
    n_filings == 1L,                     "kept",
    identical_content == TRUE,           "kept",          # redundant copies
    n_amended > 0L,                      "kept_amended",  # amendment supersedes
    default                            = "kept_flagged")] # cannot establish; keep all
  fil[, rank := seq_len(.N), by = .ctx]
  fil[, keep := action == "kept_flagged" | rank == 1L]

  keep_ids <- fil[keep == TRUE, .(OBJECTID, .ctx, action)]
  out <- merge(D, keep_ids, by = c("OBJECTID", ".ctx"))
  out[, dedup_action := action]
  out[, dedup_flag := action == "kept_flagged"]
  out[, c(".ctx", ".amd", ".ts", ".rowkey", "action") := NULL]

  if (verbose) {
    fmt <- function(x) format(x, big.mark = ",")
    drop_f <- nrow(fil) - sum(fil$keep)
    message(sprintf("pf_efilepf_dedup: %s -> %s grant rows", fmt(n0), fmt(nrow(out))))
    message(sprintf("  filings: %s -> %s (%s dropped)",
                    fmt(nrow(fil)), fmt(sum(fil$keep)), fmt(drop_f)))
    message(sprintf("  contexts: %s | multi-filing: %s",
                    fmt(nrow(ctx)), fmt(sum(ctx$n_filings > 1L))))
    # tally KEPT and DROPPED separately. An earlier version counted `action`
    # over every filing, so dropped filings were reported under "kept" and the
    # column summed to the input count -- which read as though nothing was
    # dropped.
    tb <- fil[, .(filings = .N), by = .(action, keep)]
    data.table::setorder(tb, action, -keep)
    for (i in seq_len(nrow(tb)))
      message(sprintf("  %-14s %-8s %s", tb$action[i],
                      if (tb$keep[i]) "kept" else "dropped", fmt(tb$filings[i])))
    nfl <- sum(out$dedup_flag)
    message(sprintf("  FLAGGED: %s grant rows across %s contexts where filings %s",
                    fmt(nfl), fmt(data.table::uniqueN(out$OBJECTID[out$dedup_flag])),
                    "disagree and no amendment settles it -- all kept."))
  }
  data.table::setattr(out, "pf_dedup", as.data.frame(ctx))
  as.data.frame(out)
}

# Order-insensitive fingerprint of a filing's grant rows.
.pf_fingerprint <- function(rowkey) {
  s <- paste(sort(rowkey), collapse = "\n")
  if (requireNamespace("digest", quietly = TRUE))
    return(digest::digest(s, algo = "xxhash64"))
  # digest is only Suggested; fall back to the string itself
  s
}
