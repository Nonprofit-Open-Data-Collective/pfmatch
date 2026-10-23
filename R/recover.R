#' Stage 4 — alias and repair passes
#'
#' Stages A-C fail on names that are *spelled* differently from the BMF rather
#' than absent from it. The NO-tier audit found three recurring, mechanical
#' causes, and this module addresses each. Together they were the single largest
#' identified block of recoverable recall.
#'
#' \describe{
#'   \item{**Acronyms**}{`NJOP`, `CSCOE`, `OMSI`, `PVCC`. The BMF holds the
#'     spelled-out legal name, so query and reference share **no token at all**
#'     and blocking never surfaces the pair — 72 of 4,627 queries in the 5k
#'     benchmark generated zero candidates from any pass, mostly for this reason.}
#'   \item{**Truncation**}{`SIGOCPYRPNAM` is hard-capped at 35 characters and
#'     6.1% of non-empty values sit exactly at the cap, cut off mid-name
#'     (`MASSACHUSETTS SOCIETY FOR THE PREVENTION O`). A truncated name can never
#'     clear an exact pass.}
#'   \item{**Name typed into the street field**}{`Society of Jesus NY Province`
#'     and `St Ignatius School` appear as street values on rows whose name field
#'     is blank. Rare, but pure garbage-in that is cheap to catch.}
#' }
#'
#' @name pf_recover
NULL
# Filers elide function words inconsistently, so one initialism per name is not
# enough. Three tiers are generated:
#
#   all      every token                "Food In Need Of Distribution" -> FINOD
#   core     drop only OF / THE / AND                                  -> FIND
#   content  drop every function word                                  -> FND
#
# The middle tier is not decoration: F.I.N.D. is exactly "Food In Need of
# Distribution" with only "of" dropped, and neither of the outer tiers produces
# it. Likewise OMSI = "Oregon Museum of Science and Industry" keeps nothing but
# needs "of" and "and" gone.
.pf_acro_weak <- function() c("OF", "THE", "AND")
.pf_acro_stopwords <- function() c("OF", "AND", "THE", "FOR", "A", "AN", "IN",
                                   "TO", "AT", "ON", "OR")
#' Initialisms of a name at three levels of function-word elision
#'
#' @param name_key Character vector of normalized names.
#' @return A data frame with `acro_all`, `acro_core`, and `acro_content`.
#'   Values shorter than three characters are `NA` — two-letter initialisms are
#'   far too common to block on — and duplicates across the three tiers are
#'   collapsed to `NA` so the index is not padded with repeats.
#' @keywords internal
#' @export
pf_initials <- function(name_key) {
  v <- ifelse(is.na(name_key), "", name_key)
  toks <- strsplit(v, " ", fixed = TRUE)
  ini <- function(t) paste(substr(t, 1, 1), collapse = "")
  build <- function(drop) vapply(toks, function(t) {
    t <- t[nzchar(t) & !(t %in% drop)]
    if (length(t) < 2L) "" else ini(t)
  }, character(1))
  a_all <- build(character(0))
  a_cor <- build(.pf_acro_weak())
  a_con <- build(.pf_acro_stopwords())
  for (nm in c("a_all", "a_cor", "a_con")) {
    x <- get(nm); x[nchar(x) < 3L] <- NA_character_; assign(nm, x)
  }
  # collapse repeats so one record does not contribute the same token twice
  a_cor[!is.na(a_cor) & !is.na(a_all) & a_cor == a_all] <- NA_character_
  a_con[!is.na(a_con) & ((!is.na(a_all) & a_con == a_all) |
                         (!is.na(a_cor) & a_con == a_cor))] <- NA_character_
  data.frame(acro_all = a_all, acro_core = a_cor, acro_content = a_con,
             stringsAsFactors = FALSE)
}
#' Add acronym and prefix recovery columns to a normalized frame
#'
#' Adds three blocking columns:
#' \describe{
#'   \item{`name_acro`}{`name_key` with the record's initials appended as extra
#'     synthetic tokens. Blocking on this column lets a query that *is* an
#'     acronym (`NJOP`) or merely *contains* one (`PVCC EDUCATIONAL FOUNDATION`)
#'     find the spelled-out reference record. Initials are rare, so they carry
#'     high IDF and justify a pair on their own — while the IDF machinery still
#'     prunes the common ones.}
#'   \item{`name_pre`}{the first `prefix_len` characters of `name_key`, for the
#'     truncation pass.}
#'   \item{`name_is_acro`}{`TRUE` when the whole name is a single short
#'     all-letter token, i.e. the query is itself an acronym.}
#' }
#'
#' Apply to **both** sides. On the reference it supplies the initials to match
#' against; on the query it supplies the prefix and the acronym flag.
#'
#' @section Restricting the prefix key:
#' On the reference side every record gets a `name_pre`. On the **query** side it
#' should be set only for names that are actually truncated — pass
#' `only_truncated`. Without that restriction the pass fires on every long name
#' and an 18-character prefix is far too blunt a key: `AMERICAN ASSOCIATION OF
#' PRO-LIFE OBSTETRICIANS` and `AMERICAN ASSOCIATION OF ZOO KEEPERS` share one,
#' and that exact false positive appeared in testing.
#'
#' @param d A normalized frame from [npmatch::np_normalize()].
#' @param prefix_len Characters to keep for the truncation prefix key.
#' @param only_truncated Optional logical vector, one per row. When supplied,
#'   `name_pre` is `NA` wherever it is `FALSE`, so the prefix pass never fires on
#'   a name that was not cut off.
#' @return `d` with the three columns added.
pf_add_recovery_keys <- function(d, prefix_len = 18L, only_truncated = NULL) {
  ac <- pf_initials(d$name_key)
  nk <- ifelse(is.na(d$name_key), "", d$name_key)
  blank <- function(x) ifelse(is.na(x), "", x)
  extra <- paste(blank(ac$acro_all), blank(ac$acro_core), blank(ac$acro_content))
  d$name_acro <- gsub("\\s+", " ", trimws(paste(nk, extra)))
  d$name_pre  <- ifelse(nchar(nk) >= prefix_len, substr(nk, 1, prefix_len), NA_character_)
  if (!is.null(only_truncated)) {
    stopifnot(length(only_truncated) == nrow(d))
    d$name_pre[!(only_truncated %in% TRUE)] <- NA_character_
  }
  d$name_is_acro <- !grepl(" ", nk, fixed = TRUE) & nchar(nk) >= 3L & nchar(nk) <= 8L &
                    !grepl("[0-9]", nk)
  d
}
#' Stage 4 recovery passes
#'
#' Appended after [pf_staged_passes()]. Every pass here runs only on the residual
#' the earlier stages could not resolve, so the cost is bounded by how few
#' queries are left rather than by the size of the reference.
#'
#' @section On the YES bar:
#' Acronym and prefix matches are structurally weaker evidence than a full-name
#' match — an acronym is a lossy encoding and many organizations share one. They
#' are expected to land mostly in MAYBE unless the address corroborates, which is
#' the correct outcome: npmatch's acronym-aware overlap in [npmatch::np_compare()]
#' only fires when the address is confirmed, and caps such matches below YES
#' otherwise.
#'
#' @param state Block these passes on state as well. `TRUE` keeps them cheap;
#'   `FALSE` is the recall-maximising setting for a small residual.
#' @param max_ref_freq,min_pair_idf Token pruning for the acronym pass.
#' @return A list of pass specifications.
#' @export
pf_recovery_passes <- function(state = TRUE, max_ref_freq = 5000,
                               min_pair_idf = 8) {
  by <- if (state) "state" else NULL
  keys <- function(k) if (state) c(k, "state") else k
  list(
    list(name = "D1-acronym", desc = "shared token incl. initials",
         args = list(by = by, token = TRUE, token_col = "name_acro",
                     max_ref_freq = max_ref_freq, min_pair_idf = min_pair_idf)),
    # A truncated prefix plus a *state* is weak: "AMERICAN ASSOCIATION OF
    # PRO-LIFE OBSTETRICIANS" and "AMERICAN ASSOCIATION OF ZOO KEEPERS" share an
    # 18-character prefix, and that was the only match the state-keyed version
    # produced in testing. Pairing the prefix with an exact ZIP5 instead mirrors
    # pass A1, the most efficient pass in the whole cascade.
    list(name = "D2-prefix", desc = "name prefix + ZIP5 (truncated source names)",
         args = list(by = NULL, by_x = c("name_pre", "zip5"),
                     by_y = c("name_pre", "zip5"), token = FALSE))
  )
}
#' Recover a recipient name typed into the street field
#'
#' Some rows carry the organization name in `SIGOCPYRFAAL1` with the name fields
#' blank (`Society of Jesus NY Province`, `St Ignatius School`), or a placeholder
#' such as `x` in the name field. Detected by the street value looking nothing
#' like a street: no leading house number, no PO box, and no USPS street-type
#' token.
#'
#' Measured on 55,000 grants this fires on ~6 rows, so it is a correctness guard
#' rather than a recall lever — but the alternative is matching on a name that is
#' known to be wrong.
#'
#' @param grants A prepared frame from [pf_prepare_grants()].
#' @param verbose Report how many rows were repaired.
#' @return `grants` with `recip_name` filled from `recip_street` where
#'   applicable, and a logical `name_from_street` column recording it.
#' @export
pf_recover_name_from_street <- function(grants, verbose = TRUE) {
  st <- grants$recip_street
  nm <- grants$recip_name
  # a name field that is blank, or a single-character placeholder
  bad_name <- is.na(nm) | nchar(trimws(nm)) <= 1L
  types <- paste0("\\b(", paste(c("ST", "STREET", "AVE", "AVENUE", "RD", "ROAD",
    "DR", "DRIVE", "LN", "LANE", "BLVD", "CT", "COURT", "WAY", "PL", "PLACE",
    "HWY", "PKWY", "CIR", "TER", "TRL", "SUITE", "STE", "APT", "BOX", "PO",
    "POB", "RR", "HC"), collapse = "|"), ")\\b")
  looks_street <- !is.na(st) &
    (grepl("^\\s*[0-9]", st) | grepl(types, toupper(st)) | grepl("^\\s*P\\.?\\s*O", toupper(st)))
  fix <- bad_name & !is.na(st) & !looks_street & nchar(trimws(st)) > 3L
  grants$name_from_street <- fix
  grants$recip_name[fix] <- trimws(st[fix])
  grants$recip_street[fix] <- NA_character_
  if (verbose && any(fix))
    cat(sprintf("recovered %d recipient name(s) from the street field: %s\n",
                sum(fix), paste(utils::head(grants$recip_name[fix], 4), collapse = " | ")))
  grants
}
