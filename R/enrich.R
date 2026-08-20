#' Enrich match results with BMF context for adjudication
#'
#' A reviewer deciding between two candidate EINs needs more than a name and a
#' score. This module attaches, for every candidate, what the BMF says the
#' organization *does*, and, for every grant, what the *foundation* does and what
#' the grant was *for*. Purpose-to-mission agreement is then usable as evidence.
#'
#' @section On "mission":
#' The BMF carries **no mission statement** — that text lives on Form 990 Part I
#' / Part III, not in the master file. The BMF's mission proxies, best to worst:
#' \itemize{
#'   \item `ntee_code_definition` — the NTEE classification in words
#'     ("Cemeteries", "Elementary & Secondary Schools"). Always populated, but
#'     ~1 in 4 records reads `UNDEFINED`.
#'   \item `nteev2_subsector` — the coarse sector (ART, EDU, HEL, HMS, REL ...).
#'     Useful for a same-sector / different-sector test even when the detailed
#'     code is undefined.
#'   \item `activity_code_definitions` — legacy IRS activity codes rendered as
#'     text ("Association or convention of churches; Other religious
#'     activities"). Genuinely mission-like, but only ~44% populated and frozen
#'     in the 1970s vocabulary.
#' }
#' Where a real mission statement is available from an e-file extract it can be
#' joined on `ein` via `mission` — see [pf_attach_missions()].
#'
#' @name pf_enrich
NULL
#' BMF fields used for adjudication
#'
#' The subset of BMF columns worth carrying into a review sheet: classification,
#' mission proxies, size, filing status, and address.
#'
#' @return A character vector of BMF column names.
#' @keywords internal
#' @export
pf_bmf_context_cols <- function() {
  c("ein", "org_name_join", "org_name_display",
    "org_addr_city", "org_addr_state", "org_addr_zip5",
    "ntee_code_clean", "ntee_code_definition", "ntee_code_major_group",
    "ntee_common_code_definition", "nteev2", "nteev2_subsector", "nteev2_org_type",
    "activity_code_definitions", "activity_code_categories",
    "subsection_code", "foundation_code_definition", "status_code_definition",
    "ruling_date", "asset_amount", "revenue_amount",
    "filing_requirement_code_definition", "pf_filing_requirement_code")
}
#' Build a compact BMF context table keyed by EIN
#'
#' @param bmf The raw processed BMF (data frame or CSV path).
#' @param prefix Column prefix for the returned fields.
#' @return A `data.table` keyed by `ein`.
#' @export
pf_bmf_context <- function(bmf, prefix = "BMF_") {
  if (is.character(bmf) && length(bmf) == 1L) {
    have <- names(data.table::fread(bmf, nrows = 0L))
    bmf <- data.table::fread(bmf, select = intersect(pf_bmf_context_cols(), have),
                             colClasses = "character", showProgress = FALSE)
  }
  d <- data.table::as.data.table(bmf)
  keep <- intersect(pf_bmf_context_cols(), names(d))
  d <- d[, keep, with = FALSE]
  d[, ein := .pf_ein(ein)]
  d <- d[!duplicated(ein)]
  nm <- setdiff(names(d), "ein")
  data.table::setnames(d, nm, paste0(prefix, nm))
  data.table::setkey(d, ein)
  d
}
# EINs arrive with and without dashes and with dropped leading zeros.
.pf_ein <- function(x) {
  v <- gsub("[^0-9]", "", as.character(x))
  v[is.na(v) | !nzchar(v)] <- NA_character_
  ok <- !is.na(v) & nchar(v) <= 9L
  v[ok] <- formatC(v[ok], width = 9, flag = "0")
  v
}
#' Attach an external mission table
#'
#' Joins mission text onto a frame by EIN. Supply any table with an EIN column
#' and a mission-text column — e.g. an e-file Form 990 Part III extract. Where
#' several filings exist per EIN the most recent tax year is kept.
#'
#' @param x A data frame with an EIN column.
#' @param missions A data frame with EIN, mission text, and optionally a year.
#' @param ein_col,mission_col,year_col Column names in `missions`.
#' @param on The EIN column in `x`.
#' @param into Name of the mission column added to `x`.
#' @return `x` with the mission column added.
pf_attach_missions <- function(x, missions, ein_col = "ORG_EIN",
                               mission_col = "F9_03_ORG_MISSION_PURPOSE",
                               year_col = "TAX_YEAR", on = "ein",
                               into = "mission") {
  m <- data.table::as.data.table(missions)
  m <- m[, c(ein_col, mission_col, year_col), with = FALSE]
  data.table::setnames(m, c("ein", "mission", "year"))
  m <- m[!is.na(mission) & nzchar(mission)]
  m[, ein := .pf_ein(ein)]
  data.table::setorderv(m, c("ein", "year"), c(1L, -1L))
  m <- m[!duplicated(ein)]
  x[[into]] <- m$mission[match(.pf_ein(x[[on]]), m$ein)]
  x
}
#' Candidate-level adjudication frame
#'
#' One row per (grant, candidate EIN) for the requested grants, carrying the
#' comparison signals, the BMF context for the candidate, the BMF context for
#' the *filing foundation*, and the grant purpose. This is the sheet a human or
#' an LLM adjudicates from.
#'
#' @param x A `pf_match` from [pf_match_grants()].
#' @param ids Grant ids to include. Defaults to every MAYBE.
#' @param k Maximum candidates per grant, by score.
#' @param bmf_context A table from [pf_bmf_context()].
#' @return A data frame, one row per candidate, ordered by grant then rank.
#' @export
pf_candidate_frame <- function(x, ids = NULL, k = 5, bmf_context = NULL) {
  stopifnot(inherits(x, "pf_match"))
  st <- pf_status(x)
  if (is.null(ids)) ids <- st$grant_id[st$status == "MAYBE"]
  g  <- x$grants
  pr <- data.table::as.data.table(attr(x$result, "pairs"))
  res <- as.data.frame(x$result)
  p <- pr[.id %in% ids]
  if (!nrow(p)) stop("no scored candidates for the requested ids.", call. = FALSE)
  data.table::setorder(p, .id, -score)
  p[, rank := seq_len(.N), by = .id]
  p <- p[rank <= k]
  gi <- match(p$.id, g$grant_id)
  ri <- match(p$.id, res$.id)
  gv <- function(col) if (!is.null(g[[col]])) as.character(g[[col]])[gi] else NA_character_
  out <- data.frame(
    grant_id   = p$.id,
    rank       = p$rank,
    is_top_pick = as.integer(p$.ein == res$overall_ein[ri]),
    status     = as.character(st$status[match(p$.id, st$grant_id)]),
    # ---- foundation (the filer) ----
    fdn_ein    = .pf_ein(gv("FILEREIN")),
    fdn_name   = gv("FILERNAME1"),
    # ---- grant ----
    grant_purpose = gv("SIGOCPYPOGOC"),
    grant_amount  = gv("SIGOCPYAMOUN"),
    grant_year    = gv("TAXYEAR"),
    recip_status_raw = gv("SIGOCPYRFSTA"),
    recipient_type   = as.character(g$recipient_type)[gi],
    # ---- recipient as filed ----
    recip_name   = gv("recip_name"),
    recip_name_alt = gv("recip_name_alt"),
    recip_street = gv("recip_street"),
    recip_city   = gv("recip_city"),
    recip_state  = gv("recip_state_raw"),
    recip_zip5   = gv("recip_zip5"),
    # ---- candidate ----
    ein          = .pf_ein(p$.ein),
    cand_name    = p$name_y,
    cand_street  = if (!is.null(p$street_y)) p$street_y else NA_character_,
    cand_city    = if (!is.null(p$city_y)) p$city_y else NA_character_,
    cand_state   = if (!is.null(p$state_y)) p$state_y else NA_character_,
    cand_zip5    = if (!is.null(p$zip5_y)) p$zip5_y else NA_character_,
    # ---- signals ----
    score      = round(p$score, 3),
    name_sim   = round(if (!is.null(p$name_key)) p$name_key else NA_real_, 3),
    geo_zip5   = p$geo_zip5,
    geo_state  = p$geo_state,
    geo_city   = if (!is.null(p$geo_city)) p$geo_city else NA_real_,
    geo_stnum  = if (!is.null(p$geo_stnum)) p$geo_stnum else NA_real_,
    pass       = if (!is.null(p$pass)) p$pass else NA_character_,
    veto_soft  = if (!is.null(p$veto_soft)) p$veto_soft else NA,
    veto_soft_reason = if (!is.null(p$veto_soft_reason)) p$veto_soft_reason else NA_character_,
    stringsAsFactors = FALSE)
  if (!is.null(bmf_context)) {
    ctx <- data.table::as.data.table(bmf_context)
    # candidate context (CAND_)
    ci <- match(out$ein, ctx$ein)
    for (nm in setdiff(names(ctx), "ein"))
      out[[sub("^BMF_", "CAND_", nm)]] <- ctx[[nm]][ci]
    # foundation context (FDN_)
    fi <- match(out$fdn_ein, ctx$ein)
    for (nm in c("BMF_org_addr_state", "BMF_org_addr_city", "BMF_ntee_code_clean",
                 "BMF_ntee_code_definition", "BMF_nteev2_subsector",
                 "BMF_activity_code_definitions", "BMF_asset_amount")) {
      if (nm %in% names(ctx))
        out[[sub("^BMF_", "FDN_", nm)]] <- ctx[[nm]][fi]
    }
    out$same_sector <- ifelse(
      is.na(out$CAND_nteev2_subsector) | is.na(out$FDN_nteev2_subsector), NA,
      out$CAND_nteev2_subsector == out$FDN_nteev2_subsector)
    out$fdn_recip_same_state <- ifelse(
      is.na(out$FDN_org_addr_state) | is.na(out$recip_state), NA,
      out$FDN_org_addr_state == out$recip_state)
  }
  out[order(out$grant_id, out$rank), ]
}
