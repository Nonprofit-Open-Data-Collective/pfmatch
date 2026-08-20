#' Standardize the 990-PF recipient foundation-status field (SIGOCPYRFSTA)
#'
#' Form 990-PF Part XIV Table 3a, column (c) asks the filer for the "foundation
#' status of recipient". The IRS supplies no controlled vocabulary, so the field
#' is free text: across 155,000 sample grants it carries ~1,400 distinct
#' spellings of what are really a handful of concepts. This module collapses
#' that free text onto a five-level standard, which is what decides whether a
#' grant is even eligible to appear in the IRS Business Master File.
#'
#' @section Why a rule cascade and not a lookup table:
#' A lookup can only cover the spellings already seen. The rules below key off
#' the *concept* — an IRC section reference, the words "public charity", the
#' words "operating foundation" — so unseen spellings land in the same bucket.
#' Two normalizations do most of the work:
#' \itemize{
#'   \item **section collapsing** — `501(c)(3)`, `501C 3`, `501 C 3`, and
#'     `501c3` all become the single token `501C3`; likewise `509A1`, `170B1A`,
#'     `4942J3`. Without this, each spacing variant needs its own pattern.
#'   \item **de-spacing** — a second, space-free copy of the string is matched
#'     in parallel, so `PUB CHAR`, `PUBLIC CH`, and `OTHERPUBLICCHARITY` are all
#'     caught by one `PUBCHAR` / `PUBLICCH` pattern.
#' }
#'
#' @section Standard levels (`recipient_type`):
#' \itemize{
#'   \item `public_charity` — nonprofit, public charity (PC, 501(c)(3) with no
#'     foundation qualifier, 509(a)(1)-(3), church, school, hospital)
#'   \item `nonprofit_other` — nonprofit, other subsection or exempt-but-
#'     unspecified
#'   \item `foundation_pf` — private foundation, private operating foundation,
#'     exempt operating foundation
#'   \item `individual` — a natural person
#'   \item `other_unknown` — blank, N/A, government, foreign, and text that
#'     answers a different question ("PAID", "CASH", "VARIOUS", "ACTIVE")
#' }
#'
#' @section Detail levels (`recipient_type_detail`):
#' A finer split carried alongside the standard, because `other_unknown` mixes
#' cases that behave very differently: `government` and `foreign` can never be in
#' the BMF, while `blank` and `unrecognized` are usually organizations the filer
#' simply did not code. Only the detail level is precise enough to drive the
#' out-of-sample decision — see [pf_oos_details()].
#'
#' @name pf_recipient_type
NULL
# Collapse IRC section references so every spacing variant becomes one token:
# "501 (C) (3)" / "501C 3" / "501c3" -> "501C3". Applied repeatedly because each
# pass absorbs one trailing component.
.pf_collapse_sections <- function(v) {
  pat <- "\\b(501|509|170|4942|4940|4945|4946)([A-Z0-9]*)\\s+([A-Z0-9]{1,3})\\b"
  for (i in 1:4) v <- gsub(pat, "\\1\\2\\3", v, perl = TRUE)
  v
}
# Normalize a raw status string: uppercase, ASCII, punctuation to space,
# single-spaced, section references collapsed.
.pf_norm_status <- function(x) {
  v <- toupper(trimws(as.character(x)))
  v[is.na(v)] <- ""
  v <- stringi::stri_trans_general(v, "Latin-ASCII")
  v <- gsub("&", " AND ", v, fixed = TRUE)
  v <- gsub("[^A-Z0-9]+", " ", v)
  v <- trimws(gsub("\\s+", " ", v))
  .pf_collapse_sections(v)
}
# Ordered rule table; first match wins, so specific concepts (operating
# foundation, individual, government) are tested before broad ones (any 501(c)(3)).
#   on = "norm"  match the space-separated normalized string
#   on = "flat"  match the same string with all spaces removed
#   on = "exact" the normalized string must equal one of the "|"-separated alts
# Short IRS codes ("I", "PC", "NC") must be exact: they otherwise match inside words.
.pf_status_rules <- function() {
  r <- function(detail, type, on, pattern)
    data.frame(detail = detail, type = type, on = on, pattern = pattern,
               stringsAsFactors = FALSE)
  rules <- list(
    # -- blank / explicitly not supplied -------------------------------------
    r("blank", "other_unknown", "exact", paste(c(
      "", ".", "N A", "NA", "N", "NONE", "NO", "NOT APPLICABLE", "NOT AVAILABLE",
      "NOT PROVIDED", "NOT DETERMINED", "UNKNOWN", "UNK", "SOUNK", "TBD",
      "0", "1", "YES", "X"), collapse = "|")),
    # -- individual -----------------------------------------------------------
    r("individual", "individual", "exact", "I|IND|INDIV|INVID|INDV|IN"),
    r("individual", "individual", "norm",
      "\\bINDIVIDU|\\bPERSON\\b|\\bPERSONS\\b|\\bSTUDENT|\\bEMPLOYEE|\\bFAMILY MEMBER"),
    # -- government -----------------------------------------------------------
    r("government", "other_unknown", "exact", "GOV|GOVT|GVT|GOVERMENT"),
    r("government", "other_unknown", "norm", paste0(
      "\\bGOVERNMENT|\\bGOVERNMENTAL\\b|\\bGOVT\\b|\\bGOV\\b|\\bMUNICIPAL",
      "|\\bLOCAL GOV|\\bSTATE GOV|\\bFEDERAL GOV|\\bCITY OF\\b|\\bCOUNTY OF\\b",
      "|\\bSCHOOL DISTRICT\\b|\\bPUBLIC SCHOOL|\\bPUBLIC SCHOO\\b",
      "|\\bPUBLIC UNIVERSITY\\b|\\bSTATE UNIVERSITY\\b|\\b170C1\\b")),
    # -- foreign / equivalency determination ---------------------------------
    # An equivalency determination is how a US foundation grants to a foreign
    # org that has no IRS ruling -- by definition there is no BMF row.
    r("foreign", "other_unknown", "norm",
      "\\bFOREIGN\\b|\\bEQUIVALEN|\\bER DETERMINATION\\b|\\bNON US\\b|\\bOUTSIDE (THE )?US\\b"),
    # -- private / operating foundation ---------------------------------------
    # tested before the generic 501(c)(3) rules: an operating foundation is a
    # 501(c)(3) but is emphatically not a public charity.
    r("exempt_operating_foundation", "foundation_pf", "exact", "EOF|E O F"),
    r("exempt_operating_foundation", "foundation_pf", "flat",
      "EXEMPTOPERATING|EXEMPTOPFDN"),
    r("private_operating_foundation", "foundation_pf", "exact", "POF|PVTOF|PFOP|OPF|OPC"),
    r("private_operating_foundation", "foundation_pf", "flat",
      "OPERATINGFOUNDATION|OPERATINGFDN|PRIVATEOPERATING|4942J3"),
    r("private_operating_foundation", "foundation_pf", "exact", "OPERATING|OPERATING FDN"),
    r("private_foundation", "foundation_pf", "exact",
      "PF|PV|PVT|PRIV|PRVT|PRIVATE|FOUNDATION|FDN|FOUND|NON OPERATING|NONOPERATING"),
    r("private_foundation", "foundation_pf", "flat",
      "PRIVATEFOUNDATION|PRIVATEFDN|PRIVATEFOUND|FAMILYFOUNDATION|509A4|PRIVATENONOPERATING"),
    # -- non-charity ----------------------------------------------------------
    # "NC" is the standard 990-PF shorthand for a NON-CHARITY recipient, as the
    # filers who spell it out confirm ("NC: NON-EXEMPT"). It says what the
    # recipient is *not*, so it cannot be promoted to "nonprofit (other)" -- but
    # it stays IN scope, because a 501(c)(4) or a taxable entity may still hold
    # a BMF row.
    r("non_charity", "other_unknown", "exact", "NC|N C|NON CHARITY|NONCHARITY"),
    r("non_charity", "other_unknown", "norm", "^NC\\b"),
    # -- public charity -------------------------------------------------------
    r("public_charity", "public_charity", "exact",
      "PC|P C|PUBLIC|PUB|CHARITY|CHARITIES|CHAR|CHARIT|509|50 PC|50PC|SO"),
    r("public_charity", "public_charity", "norm", "^PC\\b|^P C\\b|^SO I{1,3}\\b"),
    r("public_charity", "public_charity", "flat", paste0(
      "PUBCHAR|PUBLICCHAR|PCHAR|PUBLICCH|PUBCH|PUBLICCHTY|PUBLICCHRTY|PUBLICCHARIT",
      "|PUBLICLYSUPPORTED|PUBLICSUPPORT|PUBLICSPRT|PUBLICWELFARE|PUBLICFOUNDATION",
      "|NONPRIVATE|NOTAPF|NONPF|NOTPRIVATE|SUPPORTINGORG|SUPPORTEDORG|PUB78")),
    r("public_charity", "public_charity", "norm",
      "\\bPUBLIC CHAR|\\bPUB CHAR|\\bPUBLIC CH\\b|\\bCHARITIES\\b|\\bQUALIFIED CHARIT"),
    r("public_charity", "public_charity", "flat",
      "509A|170B1A|170C2|CHURCH|SCHOOL|COLLEGE|UNIVERSIT|HOSPITAL|EDUCATION|EDUC\\b|LIBRARY|MUSEUM"),
    # a 501(c)(3) with no foundation qualifier (foundations were caught above),
    # and the truncated / mistyped variants of the same reference
    r("public_charity", "public_charity", "flat", "501C3|5013C|C3ORG|^5013?$|^C3$|^170C2?$"),
    # a bare "PUBLIC" anywhere, after government and foundation rules have run
    r("public_charity", "public_charity", "norm", "\\bPUBLIC\\b"),
    # -- nonprofit, other subsection or unspecified ---------------------------
    r("nonprofit_other_subsection", "nonprofit_other", "flat",
      "501C4|501C5|501C6|501C7|501C8|501C9|501C10|501C13|501C19|501C26"),
    r("nonprofit_exempt_unspecified", "nonprofit_other", "exact",
      "NP|N P|NFP|NPO|T E|TE|EXEMPT|NON EXEMPT|NONEXEMPT|NONPRO|INSTITUTION"),
    r("nonprofit_exempt_unspecified", "nonprofit_other", "flat", paste0(
      "TAXEXEMPT|EXEMPTORG|EXEMPTFROMTAX|NONPROFIT|NOTFORPROFIT|NONPROF|NOTFORPROF",
      "|NPORG|NONPRO|CHARITABLE|CHARITY|RELIGIOUS|MISSIONAR|CIVIC|FRATERNAL",
      "|SOCIALWELFARE|501C|IRC|SECTION501|EXEMPTORGANIZATION")),
    r("nonprofit_exempt_unspecified", "nonprofit_other", "exact",
      "ORG|ORGAN|ORGANIZATION|CORPORATION|CORP|EXEMPT ORG")
  )
  do.call(rbind, rules)
}
#' Standardize SIGOCPYRFSTA into recipient types
#'
#' Applies the rule cascade documented in [pf_recipient_type].
#'
#' @param x Character vector of raw `SIGOCPYRFSTA` values.
#' @return A data frame with one row per input value:
#'   \describe{
#'     \item{`recipient_type`}{the five-level standard, as a factor with levels
#'       from [pf_type_levels()]}
#'     \item{`recipient_type_detail`}{the finer level that drives scope}
#'     \item{`status_norm`}{the normalized string the rules matched against}
#'     \item{`status_rule`}{index of the rule that fired; `NA` if none did}
#'   }
#' @export
pf_standardize_status <- function(x) {
  norm  <- .pf_norm_status(x)
  rules <- .pf_status_rules()
  # Match against the DISTINCT normalized values only: the field has a long tail
  # but few unique strings, so this is ~30 regex passes over ~1,400 values
  # rather than over millions of rows.
  u    <- unique(norm)
  flat <- gsub(" ", "", u, fixed = TRUE)
  u_type <- rep(NA_character_, length(u))
  u_det  <- rep(NA_character_, length(u))
  u_rule <- rep(NA_integer_, length(u))
  for (i in seq_len(nrow(rules))) {
    todo <- is.na(u_type)
    if (!any(todo)) break
    hit <- rep(FALSE, length(u))
    hit[todo] <- switch(
      rules$on[i],
      exact = u[todo] %in% strsplit(rules$pattern[i], "|", fixed = TRUE)[[1]],
      flat  = grepl(rules$pattern[i], flat[todo], perl = TRUE),
      norm  = grepl(rules$pattern[i], u[todo], perl = TRUE))
    u_type[hit] <- rules$type[i]
    u_det[hit]  <- rules$detail[i]
    u_rule[hit] <- i
  }
  # text that answers a different question ("PAID", "CASH", "VARIOUS", "ACTIVE")
  u_type[is.na(u_type)] <- "other_unknown"
  u_det[is.na(u_det)]   <- "unrecognized"
  j <- match(norm, u)
  data.frame(recipient_type = factor(u_type[j], levels = pf_type_levels()),
             recipient_type_detail = u_det[j],
             status_norm = norm,
             status_rule = u_rule[j],
             stringsAsFactors = FALSE)
}
#' Audit the standardization
#'
#' Frequency table of raw status strings by assigned type, most common first.
#' Use it to find spellings the cascade still misses before trusting the scope
#' split on a new extract.
#'
#' @param x Character vector of raw `SIGOCPYRFSTA` values.
#' @param detail Optional `recipient_type_detail` to restrict to (e.g.
#'   `"unrecognized"`).
#' @param n Maximum rows to return.
#' @return A data frame of `status_norm`, `recipient_type`,
#'   `recipient_type_detail`, and count.
#' @export
pf_status_audit <- function(x, detail = NULL, n = 50) {
  ty <- pf_standardize_status(x)
  if (!is.null(detail)) ty <- ty[ty$recipient_type_detail %in% detail, , drop = FALSE]
  if (!nrow(ty)) return(ty[0, ])
  key <- paste(ty$status_norm, ty$recipient_type, ty$recipient_type_detail, sep = "\r")
  tb <- sort(table(key), decreasing = TRUE)
  parts <- do.call(rbind, strsplit(names(tb), "\r", fixed = TRUE))
  out <- data.frame(status_norm = parts[, 1], recipient_type = parts[, 2],
                    recipient_type_detail = parts[, 3], n = as.integer(tb),
                    stringsAsFactors = FALSE)
  utils::head(out, n)
}
#' The five standard recipient types, in report order
#' @return A character vector of factor levels.
#' @keywords internal
#' @export
pf_type_levels <- function() {
  c("public_charity", "nonprofit_other", "foundation_pf",
    "individual", "other_unknown")
}
#' Human-readable labels for the five recipient types
#' @return A named character vector.
#' @keywords internal
#' @export
pf_type_labels <- function() {
  c(public_charity  = "nonprofit (public charity)",
    nonprofit_other = "nonprofit (other)",
    foundation_pf   = "foundation (pf)",
    individual      = "individual",
    other_unknown   = "other/unknown")
}
#' Detail levels that can never appear in the BMF
#'
#' The BMF lists **US** exempt organizations, so only foreign geography is truly
#' disqualifying: an organization in London or Cape Town has no BMF row whatever
#' its tax status.
#'
#' `individual` and `government` are deliberately **not** here, though an earlier
#' version of this package did exclude them. Auditing 100 out-of-sample cases
#' showed the exclusion was wrong 24% of the time, because column (c) reports the
#' status of the grant's **beneficiary** while the check is written to the
#' **payee**. A foundation paying a named student's tuition codes the grant `I`,
#' and the payee is a university that is plainly in the BMF; filers also code
#' ordinary 501(c)(3)s as `GOV` when they are university- or school-adjacent.
#' Both are now carried as flags (`flag_individual`, `flag_government`) and
#' matched anyway. See `dev/AUDIT-FINDINGS.md`.
#'
#' @return A character vector of `recipient_type_detail` values.
#' @keywords internal
#' @export
pf_oos_details <- function() "foreign"
