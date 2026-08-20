#' Organization self-description text, keyed by EIN
#'
#' The BMF says what an organization *is* (NTEE code, activity codes); Form 990
#' Part III says what it *does* (mission, program service accomplishments). This
#' module assembles both into one table keyed by EIN, so that a grant purpose can
#' be compared against it.
#'
#' @section Coverage, and why it is the binding constraint:
#' Measured on the 1.92M-record BMF and the 553,488 tax-year-2022 Part III
#' returns:
#' \itemize{
#'   \item NTEE code usable (not blank/`INVALID`/`UNDEFINED`/`Z99`) — 66.5%,
#'     and *worse* for large organizations: only 43% above $10M revenue.
#'   \item Form 990 mission text — 27.1% of BMF EINs.
#'   \item Form 990 program descriptions — 17.2%.
#'   \item IRS activity-code text — 37.2%.
#' }
#' 990-EZ filers (37% of returns) have a mission and never a program
#' description, so program coverage tracks organization size rather than chance.
#' See `dev/PURPOSE-MATCH-FINDINGS.md` for what that costs.
#'
#' @name pf_text
NULL

.pf_txt_sq <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; x }

.pf_txt_read <- function(path, ...) {
  d <- data.table::fread(path, colClasses = "character", na.strings = NULL,
                         showProgress = FALSE, ...)
  # the NCCS NTEE description files carry stray Latin-1 bytes
  for (j in names(d))
    data.table::set(d, j = j, value = iconv(d[[j]], "UTF-8", "UTF-8", sub = " "))
  d[]
}

#' NTEE classification rendered as text
#'
#' A lookup from NTEE code to a bag of words describing that code: the level 3-5
#' labels, the category name and description, and the keyword list. Keyed twice —
#' by the NTEEv2 three-part code (`ART-A00-AA`) and by the legacy three-character
#' code (`A23`) — because the BMF populates the two unevenly. On the audit sample
#' the NTEEv2 key resolves 38% of candidates and the legacy key a further 51%,
#' for 89% combined.
#'
#' The table ships with the package as `nteev2` (1,082 codes, 84 KB); this
#' accessor exists so a caller can substitute a newer vintage without editing
#' code. Rebuild the bundled copy with `data-raw/make-nteev2.R`.
#'
#' @param x Optional replacement lookup, in the shape of [nteev2] — a list with
#'   `by_v2` and `by_legacy`, each a table of `key` and `ref`.
#' @return A list with `by_v2` and `by_legacy` lookup tables.
#' @seealso [nteev2] for the bundled data.
#' @keywords internal
#' @export
pf_ntee_text <- function(x = NULL) {
  if (is.null(x)) return(pfmatch::nteev2)
  if (!all(c("by_v2", "by_legacy") %in% names(x)))
    stop("`x` must have `by_v2` and `by_legacy` components.", call. = FALSE)
  x
}

#' NTEE codes rendered as text
#'
#' The bundled NTEE lookup used by [pf_build_org_text()], built from the two NCCS
#' description files by `data-raw/make-nteev2.R`.
#'
#' @format A list of three `data.table`s:
#' \describe{
#'   \item{`by_v2`}{1,082 rows, one per NTEEv2 code: `key` (e.g. `ART-A00-AA`)
#'     and `ref` (labels + category description + keywords, as one string).
#'     Several legacy codes collapse onto one NTEEv2 code — `B80`, `B8040`, and
#'     `B8043` are all `EDU-B80-RG` — and only some carry keywords, so the
#'     builder keeps the richest description per key rather than the first.}
#'   \item{`by_legacy`}{505 rows: `key` (legacy code, e.g. `A23`) and `ref`.}
#'   \item{`codes`}{the code table itself — `NTEE2`, `ntee`, `level1`, `level4`,
#'     `cat_name`.}
#' }
#' @source NCCS NTEEv2 description files.
"nteev2"

#' Build the EIN -> self-description table
#'
#' Joins the Form 990 Part III wide table (see `dev/build-990-text-wide.R`) to
#' the BMF's classification text, one row per EIN. Where an EIN filed more than
#' one return for the year — 8,571 of 544,917 do, from amendments and short
#' periods — the latest tax period wins, then the longest text.
#'
#' @param wide Path to `F9-P03-TEXT-WIDE-*.rds`/`.csv`, or the table itself.
#' @param bmf The processed BMF (path or data frame), for the NTEE and activity
#'   text. Optional: omit for 990-text-only.
#' @param ntee Output of [pf_ntee_text()]. Optional.
#' @param cache Path to cache the result as `.rds`. `NULL` to skip.
#' @return A `data.table` keyed by `ein` with `ntee_text`, `activity_text`,
#'   `mission`, `prog_all`, `all_text`, `has_mission`, `has_program`,
#'   `n_programs`, plus a `token_idf` attribute computed over the mission corpus.
#' @export
pf_build_org_text <- function(wide, bmf = NULL, ntee = NULL, cache = NULL) {
  if (!is.null(cache) && file.exists(cache)) return(readRDS(cache))

  if (is.character(wide) && length(wide) == 1L)
    wide <- if (grepl("[.]rds$", wide)) readRDS(wide) else .pf_txt_read(wide)
  w <- data.table::as.data.table(wide)

  pc <- grep("^program_[0-9]+_desc$", names(w), value = TRUE)
  w[, prog_all := trimws(gsub("  *", " ",
      do.call(paste, c(lapply(.SD, .pf_txt_sq), sep = " ")))), .SDcols = pc]
  if ("prog_overflow_desc" %in% names(w))
    w[, prog_all := trimws(paste(prog_all, .pf_txt_sq(prog_overflow_desc)))]
  w[, ein := .pf_ein(ORG_EIN)]
  w[, .tlen := nchar(.pf_txt_sq(mission)) + nchar(prog_all)]
  data.table::setorderv(w, c("ein", "TAX_PERIOD_END_DATE", ".tlen"), c(1L, -1L, -1L))
  d <- w[!duplicated(ein), .(ein, return_type = RETURN_TYPE,
                             mission = .pf_txt_sq(mission), prog_all,
                             n_programs = as.integer(n_programs))]

  d[, `:=`(ntee_text = "", activity_text = "")]
  if (!is.null(bmf)) {
    if (is.character(bmf) && length(bmf) == 1L) {
      have <- names(data.table::fread(bmf, nrows = 0L))
      cols <- intersect(c("ein", "ntee_code_clean", "nteev2",
                          "ntee_code_definition", "ntee_common_code_definition",
                          "activity_code_definitions"), have)
      bmf <- .pf_txt_read(bmf, select = cols)
    }
    b <- data.table::as.data.table(bmf)
    b[, ein := .pf_ein(ein)]
    if (is.null(ntee)) ntee <- pf_ntee_text()
    i <- match(d$ein, b$ein)
    ref <- rep("", nrow(d))
    if (!is.null(ntee)) {
      kv <- if ("nteev2" %in% names(b)) b$nteev2[i] else rep(NA_character_, nrow(d))
      kl <- if ("ntee_code_clean" %in% names(b)) b$ntee_code_clean[i] else rep(NA_character_, nrow(d))
      j1 <- match(.pf_txt_sq(kv), ntee$by_v2$key)
      j2 <- match(.pf_txt_sq(kl), ntee$by_legacy$key)
      ref <- data.table::fifelse(!is.na(j1), ntee$by_v2$ref[j1],
             data.table::fifelse(!is.na(j2), ntee$by_legacy$ref[j2], ""))
    }
    defn <- function(col) if (col %in% names(b)) .pf_txt_sq(b[[col]][i]) else ""
    d[, ntee_text := trimws(paste(ref, defn("ntee_code_definition"),
                                  defn("ntee_common_code_definition")))]
    d[, activity_text := defn("activity_code_definitions")]
  }

  d[, all_text := trimws(gsub("  *", " ",
      paste(ntee_text, activity_text, mission, prog_all)))]

  d[, `:=`(has_mission = nzchar(mission), has_program = nzchar(prog_all))]
  d[is.na(n_programs), n_programs := 0L]
  data.table::setkey(d, ein)

  # IDF over the mission corpus: the register a grant purpose is written in
  toks <- pf_purpose_tokens(d$mission, unique_only = TRUE)
  N  <- length(toks)
  df <- table(unlist(toks))
  idf <- log((N + 1) / (as.numeric(df) + 1)); names(idf) <- names(df)
  attr(d, "token_idf") <- idf
  attr(d, "n_docs") <- N

  if (!is.null(cache)) saveRDS(d, cache, compress = FALSE)
  d[]
}

