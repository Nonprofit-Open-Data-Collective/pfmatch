#' Prepare 990-PF grant records for matching
#'
#' Turns the raw GTDC 990-PF "grants paid during year" extract (Part XIV Table
#' 3a) into a frame npmatch can consume, and attaches the scope decision.
#'
#' @section Name fields:
#' The extract carries three recipient-name columns, and the data dictionary is
#' explicit about what they are:
#' * `SIGOCPYRPNAM` — "Name of Grantee — **Person**"
#' * `SIGOCPYRBNBN1` — "Name of Grantee — **Business** Line 1"
#' * `SIGOCPYRBNBN2` — "Name of Grantee — **Business** Line 2"
#'
#' So `BNBN1` / `BNBN2` are a two-line **wrap of one name**, not a main name and
#' a DBA — line 2 exists because line 1 ran out of characters. In the 5,000-row
#' sample `PNAM` and `BNBN1` never co-occur (0 rows carry both), so the recipient
#' name is a straight coalesce of the two. `PNAM` is *not* a reliable individual
#' flag: filers routinely put organizations in it ("World Central Kitchen",
#' "Surfrider Foundation"), so scope is decided from `SIGOCPYRFSTA` instead.
#'
#' Line 2, when present, is one of four things, and each is handled differently:
#' \enumerate{
#'   \item a duplicate of line 1 — dropped
#'   \item a care-of / attention line ("ATTN LEGAL DEPARTMENT", "C/O JUDY AREANO")
#'         — dropped, it is address data in a name field
#'   \item an FBO beneficiary ("ROCKY MOUNTAIN COLLEGE FBO" + "ALYSSA PATTERSON")
#'         — dropped and the trailing `FBO` stripped from line 1, since the
#'         grantee of record is the college
#'   \item a genuine continuation ("MEMPHIS JEWISH HOME B'NAI B'RITH HOME &" +
#'         "HOSPITAL") — joined onto line 1 as an alternate name
#' }
#' The joined continuation is carried in npmatch's `dba` slot. That is a
#' deliberate reuse rather than a claim that it is a DBA: `np_compare()` scores
#' the full name/DBA cross-product and keeps the best, so putting the untruncated
#' name there lets a record match on either the truncated line-1 form or the
#' complete one, whichever the BMF happens to hold.
#'
#' @name pf_prepare
NULL
.pf_nz <- function(x) {
  v <- trimws(as.character(x))
  !is.na(v) & nzchar(v) & !(toupper(v) %in% c("NA", "N/A", "NONE", "NULL"))
}
.pf_blank_to_na <- function(x) {
  v <- trimws(as.character(x))
  v[!.pf_nz(v)] <- NA_character_
  v
}
# US postal jurisdictions the BMF can contain (states, DC, territories, APO/FPO).
.pf_us_states <- function() {
  c(datasets::state.abb, "DC", "PR", "VI", "GU", "AS", "MP", "FM", "MH", "PW",
    "AA", "AE", "AP")
}
# Care-of / attention lines masquerading as name line 2.
.pf_is_careof <- function(x) {
  grepl("^\\s*(ATTN|ATTENTION|C\\s*[/-]?\\s*O|CARE OF|IN CARE OF)\\b", x,
        ignore.case = TRUE)
}
# Tokens that mark a name as institutional. Used only for the diagnostic
# person-name flag, never to decide scope.
.pf_org_tokens <- function() c(
  "INC", "INCORPORATED", "CORP", "CORPORATION", "CO", "COMPANY", "LLC", "LTD",
  "FOUNDATION", "FDN", "FUND", "TRUST", "ASSOCIATION", "ASSN", "SOCIETY",
  "INSTITUTE", "INSTITUTION", "CENTER", "CENTRE", "COUNCIL", "COMMITTEE",
  "CHURCH", "TEMPLE", "SYNAGOGUE", "MOSQUE", "MINISTRY", "MINISTRIES",
  "MISSION", "MISSIONS", "SCHOOL", "SCHOOLS", "ACADEMY", "COLLEGE",
  "UNIVERSITY", "SEMINARY", "HOSPITAL", "CLINIC", "HEALTH", "MUSEUM",
  "LIBRARY", "THEATRE", "THEATER", "ORCHESTRA", "CHORUS", "BALLET", "GALLERY",
  "CLUB", "LEAGUE", "ALLIANCE", "COALITION", "NETWORK", "PARTNERSHIP",
  "PROJECT", "PROGRAM", "SERVICES", "SERVICE", "ORGANIZATION", "GROUP",
  "SOCIETIES", "CHAPTER", "CHARITIES", "CHARITABLE", "AMERICAN", "NATIONAL",
  "INTERNATIONAL", "COMMUNITY", "UNITED", "FRIENDS", "BOARD", "AUTHORITY",
  "DISTRICT", "COUNTY", "CITY", "STATE", "PUBLIC", "OF", "THE", "AND",
  "FOR", "USA", "US", "INSTITUTO", "ASSOCIATES", "ENDOWMENT"
)
# Common US given names, used only to raise the precision of the person-name
# diagnostic. Deliberately short and common-only: a rare given name that is not
# on the list simply fails to fire the flag, which is the safe direction.
.pf_given_names <- function() c(
  "JAMES", "JOHN", "ROBERT", "MICHAEL", "WILLIAM", "DAVID", "RICHARD", "JOSEPH",
  "THOMAS", "CHARLES", "CHRISTOPHER", "DANIEL", "MATTHEW", "ANTHONY", "DONALD",
  "MARK", "PAUL", "STEVEN", "ANDREW", "KENNETH", "JOSHUA", "GEORGE", "KEVIN",
  "BRIAN", "EDWARD", "RONALD", "TIMOTHY", "JASON", "JEFFREY", "RYAN", "JACOB",
  "GARY", "NICHOLAS", "ERIC", "STEPHEN", "JONATHAN", "LARRY", "JUSTIN", "SCOTT",
  "BRANDON", "FRANK", "BENJAMIN", "GREGORY", "SAMUEL", "RAYMOND", "PATRICK",
  "ALEXANDER", "JACK", "DENNIS", "JERRY", "TYLER", "AARON", "JOSE", "ADAM",
  "NATHAN", "HENRY", "ZACHARY", "DOUGLAS", "PETER", "KYLE", "WALTER", "ETHAN",
  "JEREMY", "HAROLD", "KEITH", "CHRISTIAN", "ROGER", "NOAH", "GERALD", "CARL",
  "TERRY", "SEAN", "AUSTIN", "ARTHUR", "LAWRENCE", "JESSE", "DYLAN", "BRYAN",
  "JOE", "JORDAN", "BILLY", "BRUCE", "ALBERT", "WILLIE", "GABRIEL", "LOGAN",
  "ALAN", "JUAN", "WAYNE", "RALPH", "ROY", "EUGENE", "RANDY", "VINCENT",
  "RUSSELL", "LOUIS", "PHILIP", "BOBBY", "JOHNNY", "BRADLEY",
  "MARY", "PATRICIA", "JENNIFER", "LINDA", "ELIZABETH", "BARBARA", "SUSAN",
  "JESSICA", "SARAH", "KAREN", "NANCY", "LISA", "MARGARET", "BETTY", "SANDRA",
  "ASHLEY", "DOROTHY", "KIMBERLY", "EMILY", "DONNA", "MICHELLE", "CAROL",
  "AMANDA", "MELISSA", "DEBORAH", "STEPHANIE", "REBECCA", "LAURA", "SHARON",
  "CYNTHIA", "KATHLEEN", "AMY", "SHIRLEY", "ANGELA", "HELEN", "ANNA", "BRENDA",
  "PAMELA", "NICOLE", "SAMANTHA", "KATHERINE", "EMMA", "RUTH", "CHRISTINE",
  "CATHERINE", "DEBRA", "RACHEL", "CAROLYN", "JANET", "VIRGINIA", "MARIA",
  "HEATHER", "DIANE", "JULIE", "JOYCE", "VICTORIA", "KELLY", "CHRISTINA",
  "JOAN", "EVELYN", "LAUREN", "JUDITH", "OLIVIA", "FRANCES", "MARTHA",
  "CHERYL", "MEGAN", "ANDREA", "HANNAH", "JACQUELINE", "ANN", "JEAN", "ALICE",
  "KATHRYN", "GLORIA", "TERESA", "DORIS", "SARA", "JANICE", "MARIE", "JULIA",
  "GRACE", "JUDY", "THERESA", "MADISON", "BEVERLY", "DENISE", "MARILYN",
  "AMBER", "DANIELLE", "ABIGAIL", "BRITTANY", "ROSE", "NATALIE", "SOPHIA",
  "ALEXIS", "LORI", "KAYLA", "JANE", "TIFFANY", "MARILYN", "CRYSTAL"
)
# Cheap "does this look like a natural person" diagnostic. Reported for context
# only -- it never drives the scope decision, which comes from SIGOCPYRFSTA.
#
# Fires on a 2-3 token name with no institutional token AND one of two positive
# signals: a single-letter middle/trailing initial ("SMITH JOHN A", "JOHN A
# SMITH"), which is near-absent from organization names, or a token on the
# common-given-name list. Requiring a positive signal rather than merely the
# absence of an org keyword is what keeps names like "HARLEM CHILDRENS ZONE"
# from flagging.
.pf_looks_personal <- function(name) {
  v <- toupper(trimws(as.character(name)))
  v[is.na(v)] <- ""
  v <- trimws(gsub("\\s+", " ", gsub("[^A-Z ]+", " ", v)))
  toks <- strsplit(v, " ", fixed = TRUE)
  org  <- .pf_org_tokens()
  give <- .pf_given_names()
  vapply(toks, function(t) {
    t <- t[nzchar(t)]
    if (length(t) < 2L || length(t) > 3L) return(FALSE)
    if (any(t %in% org)) return(FALSE)
    has_initial <- any(nchar(t[-1]) == 1L)
    has_given   <- any(t %in% give)
    has_initial || has_given
  }, logical(1))
}
#' Schema map from prepared grant columns onto npmatch canonical fields
#'
#' Use as the `query_map` argument of [npmatch::np_cascade()]. Operates on the
#' output of [pf_prepare_grants()], not the raw extract.
#'
#' @return A named character vector, `canonical_field = prepared_column`.
#' @keywords internal
#' @export
pf_map_grants <- function() {
  c(.id    = "grant_id",
    name   = "recip_name",
    dba    = "recip_name_alt",   # untruncated line1+line2 form; see [pf_prepare]
    street = "recip_street",
    unit   = "recip_unit",
    city   = "recip_city",
    state  = "recip_state",
    zip5   = "recip_zip5")
}
#' Prepare a raw 990-PF grants extract
#'
#' @param grants A data frame of the raw GTDC 990-PF current-grants extract
#'   (columns `SIGOCPYRPNAM`, `SIGOCPYRBNBN1`, ..., `SIGOCPYRFSTA`).
#' @param id_prefix Prefix for the generated `grant_id` when the input has none.
#' @return A data frame with the original columns plus the prepared recipient
#'   name / address fields, the standardized recipient type, and the scope
#'   decision (`in_scope`, `oos_reason`).
#' @export
pf_prepare_grants <- function(grants, id_prefix = "G") {
  g <- as.data.frame(grants, stringsAsFactors = FALSE)
  get <- function(col) if (!is.null(g[[col]])) as.character(g[[col]]) else rep(NA_character_, nrow(g))
  pnam <- .pf_blank_to_na(get("SIGOCPYRPNAM"))
  bn1  <- .pf_blank_to_na(get("SIGOCPYRBNBN1"))
  bn2  <- .pf_blank_to_na(get("SIGOCPYRBNBN2"))
  # -- line 2 disposition (see [pf_prepare]) --------------------------------
  fbo <- !is.na(bn1) & grepl("\\bF\\s*/?B\\s*/?O\\b|\\bFOR (THE )?BENEFIT OF\\b",
                             bn1, ignore.case = TRUE)
  dup <- !is.na(bn2) & !is.na(bn1) &
    toupper(gsub("\\s+", " ", trimws(bn2))) == toupper(gsub("\\s+", " ", trimws(bn1)))
  careof <- !is.na(bn2) & .pf_is_careof(bn2)
  keep2  <- !is.na(bn2) & !dup & !careof & !fbo
  # strip the trailing FBO marker: the grantee of record is the institution
  bn1_clean <- bn1
  bn1_clean[fbo] <- trimws(sub("\\s*\\b(F\\s*/?B\\s*/?O|FOR (THE )?BENEFIT OF)\\b.*$",
                               "", bn1[fbo], ignore.case = TRUE))
  bn1_clean[!is.na(bn1_clean) & !nzchar(bn1_clean)] <- bn1[!is.na(bn1_clean) & !nzchar(bn1_clean)]
  name <- ifelse(!is.na(pnam), pnam, bn1_clean)
  name_alt <- ifelse(keep2, trimws(paste(bn1_clean, bn2)), NA_character_)
  # -- address ---------------------------------------------------------------
  state <- toupper(trimws(.pf_blank_to_na(get("SIGOCPYRFAPO"))))
  zipr  <- .pf_blank_to_na(get("SIGOCPYRFAPC"))
  zip5  <- ifelse(grepl("^[0-9]{5}", gsub("[^0-9]", "", zipr)),
                  substr(gsub("[^0-9]", "", zipr), 1, 5), NA_character_)
  # a 4-digit ZIP is a New-England/Puerto-Rico leading zero the extract dropped
  z_digits <- gsub("[^0-9]", "", ifelse(is.na(zipr), "", zipr))
  z4 <- is.na(zip5) & nchar(z_digits) == 4L & state %in% .pf_us_states()
  zip5[z4] <- sprintf("%05d", as.integer(z_digits[z4]))
  # -- foreign / non-BMF geography ------------------------------------------
  # SIGOCAFFRFACO (country) is present in the schema but empty throughout the
  # sample, so foreign records are detected from the state field instead: a
  # value that is not a US postal code (or a spelled-out US state) is foreign.
  st_abb <- state
  full <- match(tolower(state), tolower(c(datasets::state.name, "District of Columbia", "Puerto Rico")))
  st_abb[!is.na(full)] <- c(datasets::state.abb, "DC", "PR")[full[!is.na(full)]]
  is_foreign <- !is.na(state) & !(st_abb %in% .pf_us_states())
  # -- recipient type --------------------------------------------------------
  ty <- pf_standardize_status(get("SIGOCPYRFSTA"))
  # foreign geography overrides an otherwise-plausible status: a "PC" in London
  # still has no BMF row.
  detail <- ty$recipient_type_detail
  detail[is_foreign & !(detail %in% c("individual"))] <- "foreign"
  # -- scope -----------------------------------------------------------------
  # Only geography is disqualifying. `individual` and `government` are FLAGGED
  # but still matched: the audit found that 24% of them are organizations, because
  # column (c) describes the grant's *beneficiary* while the check is written to
  # the *payee*. A foundation paying a student's tuition to a college codes the
  # grant `I`, and the college is very much in the BMF. See dev/AUDIT-FINDINGS.md.
  street   <- .pf_blank_to_na(get("SIGOCPYRFAAL1"))
  has_name <- !is.na(name)
  has_addr <- !is.na(zip5) | (!is.na(street) & !is.na(st_abb))
  oos_reason <- rep(NA_character_, nrow(g))
  oos_reason[detail %in% pf_oos_details()] <- "foreign address"
  # nothing to match on at all -- no name AND no usable address
  oos_reason[!has_name & !has_addr & is.na(oos_reason)] <- "no name or address"
  out <- g
  out$grant_id <- if (!is.null(g$grant_id)) as.character(g$grant_id)
                  else sprintf("%s%06d", id_prefix, seq_len(nrow(g)))
  out$recip_name     <- name
  out$recip_name_alt <- name_alt
  out$recip_name_l1  <- bn1_clean
  out$recip_name_l2  <- bn2
  # The two name fields have DIFFERENT width caps, so one threshold will not do:
  # SIGOCPYRPNAM is capped at 35 characters (6.1% of non-empty values sit exactly
  # there, cut off mid-name) while SIGOCPYRBNBN1 runs to 75. Testing a single
  # 35-character rule flagged 15% of names as truncated when the real figure is
  # a few percent, which made the stage-4 prefix pass fire on names that were
  # never cut off.
  cap_pnam <- 35L; cap_bn1 <- 75L
  out$name_truncated <-
    (!is.na(pnam) & nchar(pnam) >= cap_pnam) |
    (is.na(pnam) & !is.na(bn1) & nchar(bn1) >= cap_bn1)
  out$name_line2_use <- ifelse(is.na(bn2), NA_character_,
                        ifelse(dup, "duplicate",
                        ifelse(careof, "care-of",
                        ifelse(fbo, "fbo-beneficiary", "continuation"))))
  out$recip_street <- street
  out$recip_unit   <- .pf_blank_to_na(get("SIGOCPYRFAAL2"))
  out$recip_city   <- .pf_blank_to_na(get("SIGOCPYRFACI"))
  out$recip_state  <- ifelse(is_foreign, NA_character_, st_abb)
  out$recip_state_raw <- state
  out$recip_zip5   <- zip5
  out$is_foreign   <- is_foreign
  out$recipient_type        <- ty$recipient_type
  out$recipient_type_detail <- detail
  out$status_norm           <- ty$status_norm
  out$looks_personal        <- .pf_looks_personal(name)
  # Flags, not filters. These record what the filer *said* the recipient was so
  # results can be split by it, without that claim deciding whether we look.
  out$flag_individual <- ty$recipient_type_detail == "individual"
  out$flag_government <- ty$recipient_type_detail == "government"
  out$has_name    <- has_name
  out$has_address <- has_addr
  out$in_scope    <- is.na(oos_reason)
  out$oos_reason  <- oos_reason
  out
}
#' Read and prepare the sample grant CSVs
#'
#' @param path Directory or vector of CSV paths.
#' @param pattern File pattern when `path` is a directory. The default matches
#'   the `*_grants*.csv` benchmark files and so will pull in **every** size
#'   variant sitting in the folder — pass an explicit pattern or file vector to
#'   pick one set.
#' @param allow_mixed Set `TRUE` to suppress the vintage check described below.
#'   Only do this when the mixture is genuinely wanted.
#' @section Vintage check:
#' Grant extracts from different sources do not share a schema, and silently
#' concatenating them produces a population that is neither. The two vintages in
#' this project are distinguished by `OBJECTID`: the NCCS e-file rebuild carries
#' it, the older GT-derived extracts do not. Reading both at once also
#' double-counts, because the two sources were sampled from overlapping filings.
#'
#' The default `pattern` matched 15 files across both vintages in `inputs/` —
#' 422,806 rows where either population alone is a fraction of that — so this
#' function now stops when the matched files disagree on `OBJECTID`, naming the
#' files on each side. The check is on the column, not on filenames, so it keeps
#' working whatever the samples are called.
#' @return The prepared frame, with `source_file` recording provenance.
#' @export
pf_read_grants <- function(path = "inputs", pattern = "grants.*\\.csv$",
                           allow_mixed = FALSE) {
  files <- if (length(path) == 1L && dir.exists(path))
    list.files(path, pattern = pattern, full.names = TRUE) else path
  if (!length(files)) stop("no grant files found at: ", paste(path, collapse = ", "))
  parts <- lapply(files, function(f) {
    d <- data.table::fread(f, colClasses = "character", showProgress = FALSE)
    d$source_file <- basename(f)
    d
  })
  if (!isTRUE(allow_mixed) && length(parts) > 1L) {
    has_oid <- vapply(parts, function(d) "OBJECTID" %in% names(d), logical(1))
    if (any(has_oid) && !all(has_oid)) {
      stop("pf_read_grants() matched grant files of two different vintages.\n",
           "  with OBJECTID (e-file rebuild): ",
           paste(basename(files[has_oid]), collapse = ", "), "\n",
           "  without OBJECTID (older GT)   : ",
           paste(basename(files[!has_oid]), collapse = ", "), "\n",
           "Concatenating them double-counts overlapping filings and mixes two ",
           "schemas. Pass an explicit `pattern` for one vintage, or ",
           "allow_mixed = TRUE if the mixture is intended.", call. = FALSE)
    }
  }
  d <- as.data.frame(data.table::rbindlist(parts, fill = TRUE))
  pf_prepare_grants(d)
}
