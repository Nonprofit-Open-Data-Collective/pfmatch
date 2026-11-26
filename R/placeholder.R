#' Detect grant rows whose recipient is a note rather than a payee
#'
#' "SEE ATTACHED", "VARIOUS INDIVIDUALS", "INDIVIDUAL PATIENT PROGRAMS",
#' "STATEMENT 25", HIPAA notes: a 990-PF line whose name field holds a pointer,
#' an aggregate or a privacy note cannot be matched by construction. On the
#' TY2021-2024 file these rows are 0.34% of grant rows and 24% of grant dollars
#' ($113B), and before this detector existed nearly all of them reached the
#' cascade and ended as `NO`. [pf_prepare_grants()] calls this and sets them
#' out of scope, so they are counted but not matched.
#'
#' @section The lexicon:
#' Rules live in `inst/extdata/placeholder-lexicon.csv` ([pf_placeholder_lexicon()]),
#' one regular expression per row, with a category, a sink (where the dollars
#' belong in a system of accounts), a scope (`whole`, `prefix` or `anywhere`)
#' and an example taken from the data. They apply in file order to the
#' normalized name (upper case, punctuation to spaces), and the first that
#' fires decides. The rules are **structural on purpose**: keyword rules fail
#' because the keywords also name real recipients. `SCHOLARSHIP` only as a whole
#' name (Scholarship America is an organisation), `ANONYMOUS` only as a whole
#' name (Alcoholics Anonymous), `SEE` only with a document word (SEE
#' International), `VARIOUS` only as an opening word and not when the name ends
#' in an entity word (Various Artists Collective Inc). See
#' `dev/PLACEHOLDER-SIDEBAR-NOTE.md`.
#'
#' @section A reference that names a payee:
#' `FIDELITY CHARITABLE - SEE ATTACHMENT A`, `SEE ATTACHED - UNITED WAY` and
#' `LINDA VISTA FOUNDATION SEE ATTACHED` name a real payee. The detector cuts
#' the reference off and returns `category = "reference_with_name"` with the
#' payee in `residual`; such rows are not placeholders and are matched on the
#' residual. The same holds for an institution paying for a group of people,
#' `INDIANA UNIVERSITY VARIOUS STUDENTS`. A residual counts only when it is not
#' itself a placeholder, carries no list word (`LIST`, `NAMES`, `DETAILS`) and
#' is not made only of generic words (`THE FOUNDATION`, `CASH GRANTS`).
#'
#' @section What it does not use:
#' peopleparser's `placeholder` name type. It was built for officer lists, and
#' on grantee names 37% of the rows only it flagged were matched `YES`
#' (`NO ONE LEFT BEHIND`, `THE TRUSTEES`), so it does not decide scope here.
#' The older [pf_is_placeholder()] flag, which does use it, is unchanged and
#' remains a flag.
#'
#' @param name Character vector of recipient names.
#' @param lexicon The rule table; see [pf_placeholder_lexicon()].
#' @return A data frame, one row per element of `name`: `name_norm`,
#'   `is_placeholder` (set the row aside), `category`, `rule_id`, `sink` and
#'   `residual` (the payee, for `reference_with_name`).
#' @examples
#' pf_detect_placeholders(c("SEE ATTACHED", "VARIOUS INDIVIDUALS",
#'                          "FIDELITY CHARITABLE - SEE ATTACHMENT A",
#'                          "SCHOLARSHIP AMERICA"))
#' @export
pf_detect_placeholders <- function(name, lexicon = pf_placeholder_lexicon()) {
  raw <- toupper(ifelse(is.na(name), "", as.character(name)))
  nk  <- .pf_ph_normalize(raw)
  n   <- length(nk)
  # distinct names only: the corpus repeats names heavily
  u    <- unique(nk)
  rule <- .pf_ph_rules(u, lexicon)[match(nk, u)]
  cat_ <- lexicon$category[match(rule, lexicon$rule_id)]
  sink <- lexicon$sink[match(rule, lexicon$rule_id)]
  residual <- rep(NA_character_, n)

  # -- a reference with a payee: cut the reference off, keep what is left ------
  good <- function(r) {
    ok <- !is.na(r) & nzchar(r) & .pf_ph_is_payee(r)
    ok[ok] <- is.na(.pf_ph_rules(r[ok], lexicon))
    ok
  }
  refs <- which(cat_ == "attachment_reference")
  if (length(refs)) {
    # the payee before the reference ("FIDELITY CHARITABLE - SEE ATTACHMENT A");
    # this is the prototype's rule, validated on the TY2021-2024 file
    cut_rx <- paste0("( |^)(PLEASE )?(SEE|ATTACHED|ENCLOSED|STATEMENT|STMT|",
                     "ATTACHMENT|ATCH|SCHEDULE|EXHIBIT|DETAILS? UPON|",
                     "INFORMATION ON FILE|LIST AVA|AVAILABLE UPON)( .*)?$")
    r  <- trimws(sub(cut_rx, "", nk[refs], perl = TRUE))
    ok <- good(r)
    # ... or after it, set off by the filer's own separator ("SEE ATTACHED -
    # UNITED WAY"). What follows a reference is usually more of the note
    # ("- NON-CASH", "- 5 PAGES"), so this side must also read as an institution.
    if (any(!ok)) {
      r2 <- .pf_ph_residual_parts(raw[refs[!ok]], lexicon)
      ok2 <- good(r2) & .pf_ph_is_institution(r2)
      r[!ok][ok2] <- r2[ok2]
      ok[!ok][ok2] <- TRUE
    }
    residual[refs[ok]] <- r[ok]
  }
  # an institution paying for a group of people: INDIANA UNIVERSITY VARIOUS
  # STUDENTS, SUNY CORTLAND FBO VARIOUS INDIVIDUALS. The residual must name an
  # institution, or "HOMELESS INDIGENT INDIVIDUALS" would keep HOMELESS.
  grp <- which(rule %in% "IND01")
  if (length(grp)) {
    cut_rx <- paste0(
      "( |^)(F B O |FBO |FOR (THE )?BENEFIT OF |FOR |TO )?",
      "(VARIOUS|ELIGIBLE|NEEDY|QUALIFIED|QUALIFYING|INDIGENT|DESERVING|",
      "UNNAMED|MULTIPLE|NUMEROUS) (PATIENTS?|INDIVIDUALS?|PERSONS?|PEOPLE|",
      "STUDENTS?|RECIPIENTS?|FAMILIES|EMPLOYEES?|APPLICANTS?|BENEFICIARIES)",
      "( .*)?$")
    r  <- trimws(sub(cut_rx, "", nk[grp], perl = TRUE))
    ok <- grepl(cut_rx, nk[grp], perl = TRUE) & good(r) & .pf_ph_is_institution(r)
    residual[grp[ok]] <- r[ok]
  }
  cand <- which(!is.na(residual))
  cat_[cand] <- "reference_with_name"
  sink[cand] <- NA_character_
  data.frame(name_norm = nk,
             is_placeholder = !is.na(rule) & !cat_ %in% "reference_with_name",
             category = cat_, rule_id = rule, sink = sink, residual = residual,
             stringsAsFactors = FALSE)
}

#' The placeholder lexicon
#'
#' @param path The rule table. Defaults to the copy shipped in
#'   `inst/extdata/placeholder-lexicon.csv`.
#' @return The rules, with a compiled `regex` column. Each rule is checked to
#'   compile, so a malformed edit fails here rather than matching nothing.
#' @seealso [pf_detect_placeholders()]
#' @export
pf_placeholder_lexicon <- function(path = system.file("extdata",
                                                      "placeholder-lexicon.csv",
                                                      package = "pfmatch")) {
  if (!nzchar(path) || !file.exists(path))
    stop("placeholder lexicon not found: ", path, call. = FALSE)
  lx <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE,
                        colClasses = "character")
  need <- c("rule_id", "category", "sink", "scope", "pattern")
  if (!all(need %in% names(lx)) || anyDuplicated(lx$rule_id) ||
      !all(lx$scope %in% c("whole", "prefix", "anywhere")))
    stop("placeholder lexicon ", path, " needs unique rule_id and columns ",
         paste(need, collapse = ", "), " with scope whole/prefix/anywhere",
         call. = FALSE)
  lx$regex <- ifelse(lx$scope == "whole",  paste0("^(", lx$pattern, ")$"),
              ifelse(lx$scope == "prefix", paste0("^(", lx$pattern, ")"),
                                           paste0("(^| )(", lx$pattern, ")( |$)")))
  bad <- vapply(lx$regex, function(r)
    inherits(try(grepl(r, "X", perl = TRUE), silent = TRUE), "try-error"), TRUE)
  if (any(bad))
    stop("invalid regex in placeholder rule(s): ",
         paste(lx$rule_id[bad], collapse = ", "), call. = FALSE)
  lx
}

.pf_ph_normalize <- function(x) {
  x <- toupper(ifelse(is.na(x), "", as.character(x)))
  gsub(" +", " ", trimws(gsub("[^A-Z0-9 ]", " ", x)))
}

# First rule, in file order, that fires on each (already normalized) name.
.pf_ph_rules <- function(nk, lexicon) {
  out <- rep(NA_character_, length(nk))
  for (i in seq_len(nrow(lexicon))) {
    todo <- which(is.na(out))
    if (!length(todo)) break
    out[todo[grepl(lexicon$regex[i], nk[todo], perl = TRUE)]] <- lexicon$rule_id[i]
  }
  out
}

# A filed name split on its own separators ("FIDELITY CHARITABLE - SEE
# ATTACHMENT A", "SEE ATTACHED - UNITED WAY"): the one part that is a payee and
# not a reference, or NA. Normalizing first would erase the separator, which is
# the only thing telling "SEE ATTACHED - UNITED WAY" from a sentence.
.pf_ph_residual_parts <- function(raw, lexicon) {
  parts <- strsplit(raw, "\\s+-+\\s*|\\s*-+\\s+|[:;()/,]", perl = TRUE)
  vapply(parts, function(p) {
    p <- .pf_ph_normalize(p)
    p <- p[nzchar(p)]
    if (length(p) < 2L) return(NA_character_)
    p <- p[is.na(.pf_ph_rules(p, lexicon)) & .pf_ph_is_payee(p)]
    if (length(p) == 1L) p else NA_character_
  }, character(1))
}

# What is left once a reference is cut off is a payee only if it has a word that
# is not generic, no word that describes a list rather than a payee, and does
# not end mid-phrase. "LINDA VISTA FOUNDATION" and "FIDELITY CHARITABLE" pass;
# "LIST", "NAMES", "501C3 ORG", "CASH GRANTS", "THE FOUNDATION",
# "ASSISTANCE TO" do not.
.pf_ph_listy_rx <- paste0(
  "(^| )(LISTS?|LISTING|DETAILS?|DETAILED|INFORMATION|NAMES?|RECIPIENTS?|",
  "501 ?C ?3S?|ORGS?|TOTALS?|MATCHING|REQUESTS?|SCHEDULES?|SUPPORTING|VARIOUS|",
  "MISC|MISCELLANEOUS|OTHERS|ALL|MADE|PAID)( |$)")
.pf_ph_generic_words <- c(
  "THE", "A", "AND", "OF", "FOR", "TO", "FOUNDATION", "FUND", "TRUST", "INC",
  "ORGANIZATION", "ORGANIZATIONS", "CHARITY", "CHARITIES", "CHARITABLE",
  "GRANT", "GRANTS", "DONEE", "DONEES", "GRANTEE", "GRANTEES", "OTHER", "GIFT",
  "GIFTS", "STOCK", "CASH", "SECURITIES", "DONATION", "DONATIONS",
  "CONTRIBUTION", "CONTRIBUTIONS", "SCHOLARSHIP", "SCHOLARSHIPS", "INDIVIDUAL",
  "INDIVIDUALS", "COMMUNITY", "EDUCATION", "HARDSHIP", "RELIEF", "EMPLOYEE",
  "EMPLOYEES", "PROGRAM", "PROGRAMS", "SUPPORT", "GENERAL", "OPERATING",
  "ASSISTANCE", "AID", "FINANCIAL", "MEDICAL", "EMERGENCY", "TUITION",
  "PAYMENTS", "PAYMENT", "EXPENSES", "AWARDS", "AWARD")
# Does a residual name an institution? Required where the residual is not the
# prototype's (text before a reference), because those positions are mostly
# more note.
.pf_ph_institution_rx <- paste0(
  "(^| )(UNIVERSITY|UNIV|COLLEGE|SCHOOLS?|ACADEMY|INSTITUTE|HOSPITAL|CENTER|",
  "CENTRE|CHURCH|SUNY|CUNY|FOUNDATION|SOCIETY|ASSOCIATION|MUSEUM|LIBRARY|",
  "CLINIC|MINISTRIES|CHARITABLE|COUNCIL|ALLIANCE|UNITED WAY)( |$)")
.pf_ph_is_institution <- function(r)
  !is.na(r) & grepl(.pf_ph_institution_rx, r, perl = TRUE) &
    grepl(" ", r, fixed = TRUE)   # "UNIVERSITY" alone names no one

.pf_ph_is_payee <- function(r) {
  toks <- strsplit(r, " ", fixed = TRUE)
  last <- vapply(toks, function(t) if (length(t)) t[length(t)] else "", "")
  nchar(r) >= 4 & !grepl(.pf_ph_listy_rx, r, perl = TRUE) &
    !last %in% c("THE", "A", "AND", "OF", "FOR", "TO", "FBO", "IN", "ON",
                 "BENEFITING", "BENEFITTING", "THROUGH", "VIA", "BY") &
    vapply(toks, function(t) any(!t %in% .pf_ph_generic_words), TRUE)
}
