#' Report on a grant-recipient match run
#'
#' Turns a [pf_match_grants()] result into the four-way outcome every grant
#' lands in, and crosstabs it against the standardized recipient type.
#'
#' @section Outcome levels:
#' * `YES`   — one candidate cleared the auto-accept threshold with a clear lead
#' * `MAYBE` — candidates surfaced but need adjudication (below threshold, a
#'   near-tie with the runner-up, or a soft veto)
#' * `NO`    — no candidate surfaced, or the best one scored below the review floor
#' * `OOS`   — out of sample: the recipient is not the kind of entity the BMF
#'   contains (a natural person, a government unit, a foreign organization), so
#'   there is nothing to find and the grant is not counted as a miss
#'
#' @name pf_report
NULL
#' @rdname pf_report
#' @return `pf_status_levels()`: the outcome levels in report order.
#' @keywords internal
#' @export
pf_status_levels <- function() c("YES", "MAYBE", "NO", "OOS")
#' Per-grant outcome frame
#'
#' @param x A `pf_match` from [pf_match_grants()].
#' @return One row per grant: identity, recipient type, outcome, the chosen EIN
#'   and BMF name, the score and margin, the pass that found it, and the
#'   query/reference geography for the geographic-agreement diagnostics.
#' @export
pf_status <- function(x) {
  stopifnot(inherits(x, "pf_match"))
  g   <- x$grants
  res <- as.data.frame(x$result)
  pr  <- as.data.frame(attr(x$result, "pairs"))
  i <- match(g$grant_id, res$.id)
  status <- rep("NO", nrow(g))                       # no candidate surfaced at all
  status[!is.na(i)] <- as.character(res$tier[i[!is.na(i)]])
  status[!g$in_scope] <- "OOS"
  # geography of the winning pair, pulled from the scored candidate union
  ein <- res$overall_ein[i]
  j <- match(paste(g$grant_id, ein), paste(pr$.id, pr$.ein))
  out <- data.frame(
    grant_id       = g$grant_id,
    filer_ein      = .pf_col(g, "ORG_EIN"),
    filer_name     = if (!is.null(g$FILERNAME1)) g$FILERNAME1 else NA_character_,
    recip_name     = g$recip_name,
    recip_name_alt = g$recip_name_alt,
    recip_city     = g$recip_city,
    recip_state    = g$recip_state_raw,
    recip_zip5     = g$recip_zip5,
    status_raw     = .pf_col(g, "PF_15_G_PAID_RECIP_STAT"),
    recipient_type = factor(as.character(g$recipient_type), pf_type_levels()),
    recipient_type_detail = g$recipient_type_detail,
    looks_personal = g$looks_personal,
    status         = factor(status, pf_status_levels()),
    oos_reason     = g$oos_reason,
    ein            = ein,
    bmf_name       = res$overall_name_y[i],
    score          = round(res$overall_score[i], 3),
    name_sim       = round(res$overall_name_sim[i], 3),
    margin         = round(res$overall_margin[i], 3),
    n_close        = res$n_close[i],
    match_pass     = if (!is.null(res$pass)) res$pass[i] else NA_character_,
    bmf_state      = if (!is.null(pr$state_y)) pr$state_y[j] else NA_character_,
    bmf_city       = if (!is.null(pr$city_y)) pr$city_y[j] else NA_character_,
    bmf_zip5       = if (!is.null(pr$zip5_y)) pr$zip5_y[j] else NA_character_,
    geo_state      = if (!is.null(pr$geo_state)) pr$geo_state[j] else NA_real_,
    geo_zip5       = if (!is.null(pr$geo_zip5)) pr$geo_zip5[j] else NA_real_,
    stringsAsFactors = FALSE
  )
  # Out-of-sample grants were never put through the cascade, so blank any match
  # columns. NO rows deliberately KEEP their best near-miss: it is the reference
  # a reviewer needs to see why nothing was accepted.
  oos <- out$status == "OOS"
  for (col in c("ein", "bmf_name", "bmf_state", "bmf_city", "bmf_zip5"))
    out[[col]][oos] <- NA_character_
  out$state_agree <- ifelse(is.na(out$ein) | is.na(out$recip_state) | is.na(out$bmf_state),
                            NA, out$recip_state == out$bmf_state)
  out
}
#' Outcome x recipient-type crosstab
#'
#' @param status A frame from [pf_status()], or a `pf_match`.
#' @param pct If `TRUE`, add row-percentage columns.
#' @return A data frame: one row per recipient type, one column per outcome.
#' @export
pf_crosstab <- function(status, pct = TRUE) {
  if (inherits(status, "pf_match")) status <- pf_status(status)
  tb <- table(recipient_type = status$recipient_type, status = status$status)
  m <- as.data.frame.matrix(tb)
  out <- data.frame(recipient_type = rownames(m),
                    label = unname(pf_type_labels()[rownames(m)]),
                    m, n = rowSums(m), stringsAsFactors = FALSE)
  if (pct) {
    for (s in pf_status_levels())
      out[[paste0("pct_", s)]] <- ifelse(out$n > 0, round(100 * out[[s]] / out$n, 1), NA_real_)
    # match rate over the grants that were actually attempted (excludes OOS)
    att <- out$n - out$OOS
    out$pct_YES_of_attempted   <- ifelse(att > 0, round(100 * out$YES / att, 1), NA_real_)
    out$pct_YESMAYBE_attempted <- ifelse(att > 0, round(100 * (out$YES + out$MAYBE) / att, 1), NA_real_)
  }
  rownames(out) <- NULL
  tot <- data.frame(recipient_type = "TOTAL", label = "all recipients")
  for (s in pf_status_levels()) tot[[s]] <- sum(out[[s]])
  tot$n <- sum(out$n)
  if (pct) {
    for (s in pf_status_levels()) tot[[paste0("pct_", s)]] <- round(100 * tot[[s]] / tot$n, 1)
    att <- tot$n - tot$OOS
    tot$pct_YES_of_attempted   <- round(100 * tot$YES / att, 1)
    tot$pct_YESMAYBE_attempted <- round(100 * (tot$YES + tot$MAYBE) / att, 1)
  }
  rbind(out, tot[, names(out)])
}
#' Geographic-agreement diagnostics
#'
#' How often the address the foundation typed agrees with the BMF address of the
#' organization it matched to. The point of running the cascade state-free is to
#' measure this before deciding whether a geographic block is safe.
#'
#' @param status A frame from [pf_status()], or a `pf_match`.
#' @return A one-row-per-outcome data frame of state / ZIP agreement rates.
pf_geo_agreement <- function(status) {
  if (inherits(status, "pf_match")) status <- pf_status(status)
  m <- status[status$status %in% c("YES", "MAYBE") & !is.na(status$ein), , drop = FALSE]
  by <- factor(as.character(m$status), c("YES", "MAYBE"))
  agg <- function(f) tapply(f, by, function(v) round(100 * mean(v, na.rm = TRUE), 1))
  data.frame(
    status        = levels(by),
    n             = as.integer(table(by)),
    n_comparable  = as.integer(tapply(!is.na(m$state_agree), by, sum)),
    pct_state_agree = as.numeric(agg(m$state_agree)),
    pct_zip5_agree  = as.numeric(agg(m$geo_zip5 == 1)),
    row.names = NULL, stringsAsFactors = FALSE)
}
#' Print the full test report
#'
#' @param x A `pf_match`.
#' @param file Optional path; when given, the outcome frame and crosstab are
#'   also written as CSVs next to it.
#' @return Invisibly, a list of the report tables.
#' @export
pf_report <- function(x, file = NULL) {
  st <- pf_status(x)
  ct <- pf_crosstab(st)
  geo <- pf_geo_agreement(st)
  hr <- function() cat(strrep("-", 78), "\n")
  cat("\n"); hr()
  cat("990-PF GRANT RECIPIENT -> BMF MATCH REPORT\n"); hr()
  cat(sprintf("grants ..................... %s\n", format(x$n[["grants"]], big.mark = ",")))
  cat(sprintf("in scope (matched) ......... %s\n", format(x$n[["in_scope"]], big.mark = ",")))
  cat(sprintf("out of sample (not matched)  %s\n", format(x$n[["out_of_scope"]], big.mark = ",")))
  cat(sprintf("BMF reference records ...... %s\n", format(x$n[["reference"]], big.mark = ",")))
  cat("\nOUTCOMES\n")
  tb <- table(st$status)
  for (s in pf_status_levels())
    cat(sprintf("  %-6s %6d  (%4.1f%%)\n", s, tb[[s]], 100 * tb[[s]] / nrow(st)))
  att <- nrow(st) - tb[["OOS"]]
  cat(sprintf("  match rate on attempted: %.1f%% YES, %.1f%% YES+MAYBE\n",
              100 * tb[["YES"]] / att, 100 * (tb[["YES"]] + tb[["MAYBE"]]) / att))
  cat("\nOUT-OF-SAMPLE REASONS\n")
  orr <- sort(table(st$oos_reason[st$status == "OOS"]), decreasing = TRUE)
  for (nm in names(orr)) cat(sprintf("  %-20s %5d\n", nm, orr[[nm]]))
  cat("\nOUTCOME BY RECIPIENT TYPE\n")
  print(ct[, c("label", pf_status_levels(), "n",
               "pct_YES_of_attempted", "pct_YESMAYBE_attempted")],
        row.names = FALSE, right = FALSE)
  cat("\nGEOGRAPHIC AGREEMENT OF MATCHED PAIRS\n")
  print(geo, row.names = FALSE, right = FALSE)
  cat("\nBLOCKING CASCADE STAGES\n")
  print(x$stages, row.names = FALSE, right = FALSE)
  cat("\nRUNTIME (match only; BMF and grant preprocessing excluded)\n")
  cat(sprintf("  cascade ............ %8.1f s\n", x$timing[["match"]]))
  cat(sprintf("  per 1,000 grants ... %8.1f s\n", x$timing[["match_per_1k"]]))
  cat(sprintf("  query canonicalize . %8.2f s  (preprocessing, not counted)\n",
              x$timing[["query_prep"]]))
  hr(); cat("\n")
  if (!is.null(file)) {
    utils::write.csv(st, file, row.names = FALSE, na = "")
    ctf <- sub("\\.csv$", "-CROSSTAB.csv", file)
    utils::write.csv(ct, ctf, row.names = FALSE, na = "")
    cat(sprintf("wrote %s\n      %s\n", file, ctf))
  }
  invisible(list(status = st, crosstab = ct, geo = geo, stages = x$stages))
}
