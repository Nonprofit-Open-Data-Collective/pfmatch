#' Returns that do not report grants directly
#'
#' Some 990-PF filers decline to itemize Part XIV Table 3a electronically. They
#' file a single row whose recipient name is a pointer — `SEE ATTACHED
#' SCHEDULE`, `SCHEDULE AVAILABLE UPON REQUEST`, `VARIOUS` — carrying the full
#' year's grant total.
#'
#' These are not match failures and must not be counted as such. No amount of
#' record linkage resolves them, because there is no recipient name to link. They
#' need their own report so the dollars they represent are visible rather than
#' buried in the NO tier.
#'
#' @section The detail is not recoverable from the e-file:
#' Eight such returns were fetched and inspected (`dev/probe-attached-xml.R`,
#' `dev/check-xml-attachments.R`). Every one files **exactly one**
#' `GrantOrContributionPdDurYrGrp` whose `BusinessNameLine1Txt` is the
#' placeholder text and whose `Amt` is the whole total, and every one declares
#' `binaryAttachmentCnt="0"`. No supplemental block, no free-text field long
#' enough to hold a grant list. The itemization exists only on paper.
#'
#' What the XML *does* give reliably is the filer EIN, tax year, and the
#' authoritative Part XIV totals — which is what this report carries.
#'
#' @name pf_attached
NULL

#' Patterns that mark a recipient name as a pointer rather than a name
#'
#' @section Why `MISC` is spelled out:
#' `^MISC` was the pattern until 2026-11-24, and it matched `MISCARRIAGE
#' ABORTION HOTLINE` — a real organisation with an EIN, discarded as a pointer.
#' `^MISC\\b` alone would fix that but drops `MISCELLEANOUS`, a filer's
#' misspelling that is a genuine pointer, so both branches are needed.
#'
#' @return A single regular expression, matched against an upper-cased name.
#' @export
pf_placeholder_pattern <- function() {
  paste0("SEE ATTACH|SEE SCHED|SEE PART|SEE STATEMENT|SEE LIST|ATTACHED LIST|",
         "^VARIOUS$|^VARIOUS |^SEVERAL|^MISCELL|^MISC\\b|AVAILABLE UPON|",
         "SEE EXHIBIT|SCHEDULE ATTACHED|SEE ABOVE|SEE FOOTNOTE|SEE SUPPLEMENT|",
         "PER ATTACHED|AS ATTACHED|SEE ANNEX|SEE ADDENDUM|SEE BELOW")
}

# Vector-level placeholder test. `pf_prepare_grants()` works on bare name
# vectors, so the frame-taking export below delegates here.
#
# The regex and peopleparser's placeholder class each catch what the other
# misses, so the flag is their union. Measured on inputs/ef100k_grants.csv:
# the regex alone catches 272 rows, the model alone 147, the union 284. The
# model's contribution is the `ALL OTHER(S) ...` family (ALL OTHERS 1000 OR
# LESS PER DONEE, ALL OTHER MEDICAL MISSIONS), plus THE BOARD OF TRUSTEES,
# bare SEE and bare X -- shapes a keyword list did not anticipate. The regex
# keeps the far larger share because it was written against this corpus.
.pf_placeholder <- function(name, use_model = TRUE) {
  v <- toupper(trimws(as.character(name)))
  v[is.na(v)] <- ""
  out <- grepl(pf_placeholder_pattern(), v)
  if (!use_model || !length(v)) return(out)
  nz <- nzchar(v)
  if (!any(nz)) return(out)
  u <- unique(v[nz])
  cl <- peopleparser::classify_names(u)
  ph <- cl$name_type[match(u, cl$name)] == "placeholder"
  ph[is.na(ph)] <- FALSE
  out[nz] <- out[nz] | ph[match(v[nz], u)]
  out
}

#' Flag grant rows whose recipient is a pointer rather than a name
#'
#' Fires on both the hand-written pattern in [pf_placeholder_pattern()] and
#' peopleparser's `placeholder` class, which disagree in both directions; see
#' `vignette("identifying-people")` for the measurement and for the one shape
#' this over-reaches on — a named recipient with a pointer appended, as in
#' `WEILL CORNELL MEDICAL COLLEGE- SEE ATTACHMENT`.
#'
#' @param grants A prepared frame from [pf_prepare_grants()].
#' @param name_col Column holding the recipient name.
#' @param use_model Set `FALSE` for the regular expression alone.
#' @return A logical vector, one element per row.
#' @export
pf_is_placeholder <- function(grants, name_col = "recip_name",
                              use_model = TRUE) {
  .pf_placeholder(grants[[name_col]], use_model = use_model)
}

#' Report on returns that do not itemize their grants
#'
#' One row per (filer, tax year), because the unit of the problem is the
#' *return*: a filer that writes "see attached" usually does it for the whole
#' year, and the actionable object is the return, not the row.
#'
#' @param grants A prepared frame from [pf_prepare_grants()], carrying the raw
#'   `FILEREIN`, `FILERNAME1`, `TAXYEAR`, `SIGOCPYAMOUN` and `URL` columns.
#' @param verbose Print a summary.
#' @return A data frame, one row per non-itemizing return:
#'   \describe{
#'     \item{`filer_ein`, `filer_name`, `taxyear`}{who and when}
#'     \item{`n_placeholder_rows`, `placeholder_amount`}{the un-itemized rows and
#'       their dollars}
#'     \item{`n_itemized_rows`, `itemized_amount`}{what the same return *did*
#'       itemize — a return can do both}
#'     \item{`pct_dollars_hidden`}{share of the return's grant dollars that are
#'       not itemized. 100% means the whole year is a single pointer row}
#'     \item{`placeholder_text`}{the exact wording used, which varies by filer}
#'     \item{`url`}{the e-file XML for the return}
#'   }
#' @export
pf_attached_report <- function(grants, verbose = TRUE) {
  # Written with base aggregation rather than data.table's `:=` DSL: that DSL
  # requires the calling namespace to be data.table-aware, and pfmatch imports
  # only selected functions.
  g <- as.data.frame(grants, stringsAsFactors = FALSE)
  need <- c("ORG_EIN", "TAX_YEAR", "PF_15_G_PAID_AMT", "URL")
  miss <- setdiff(need, names(g))
  if (length(miss))
    stop("grants is missing raw column(s): ", paste(miss, collapse = ", "), call. = FALSE)

  ph  <- pf_is_placeholder(g)
  amt <- suppressWarnings(as.numeric(.pf_col(g, "PF_15_G_PAID_AMT"))); amt[is.na(amt)] <- 0
  fnm <- if (!is.null(g$FILERNAME1)) g$FILERNAME1 else rep(NA_character_, nrow(g))
  key <- paste(.pf_col(g, "ORG_EIN"), .pf_col(g, "TAX_YEAR"), sep = "\r")

  keep <- unique(key[ph])                       # returns with at least one pointer row
  idx  <- split(seq_len(nrow(g)), key)[keep]

  out <- do.call(rbind, lapply(idx, function(i) {
    p <- ph[i]
    data.frame(
      filer_ein          = .pf_col(g, "ORG_EIN")[i][1],
      filer_name         = fnm[i][1],
      taxyear            = .pf_col(g, "TAX_YEAR")[i][1],
      n_placeholder_rows = sum(p),
      placeholder_amount = sum(amt[i][p]),
      n_itemized_rows    = sum(!p),
      itemized_amount    = sum(amt[i][!p]),
      total_amount       = sum(amt[i]),
      placeholder_text   = paste(utils::head(unique(g$recip_name[i][p]), 3), collapse = " | "),
      url                = g$URL[i][p][1],
      stringsAsFactors   = FALSE)
  }))
  rownames(out) <- NULL
  out$pct_dollars_hidden <- ifelse(out$total_amount > 0,
    round(100 * out$placeholder_amount / out$total_amount, 1), NA_real_)
  out <- out[order(-out$placeholder_amount), c(
    "filer_ein", "filer_name", "taxyear", "n_placeholder_rows", "placeholder_amount",
    "n_itemized_rows", "itemized_amount", "total_amount", "pct_dollars_hidden",
    "placeholder_text", "url")]
  rownames(out) <- NULL
  if (verbose) {
    cat(sprintf("non-itemizing returns .... %s\n", format(nrow(out), big.mark = ",")))
    cat(sprintf("un-itemized grant rows ... %s\n",
                format(sum(out$n_placeholder_rows), big.mark = ",")))
    cat(sprintf("dollars not itemized ..... $%s\n",
                formatC(sum(out$placeholder_amount), format = "f", digits = 0, big.mark = ",")))
    cat(sprintf("returns hiding 100%% of their grant dollars: %s\n",
                format(sum(out$pct_dollars_hidden >= 99.9, na.rm = TRUE), big.mark = ",")))
  }
  out
}
