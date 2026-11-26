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
# Score below which a recipient name reads as a natural person. See
# [.pf_looks_personal] for how it was chosen.
.pf_personal_cutoff <- 0.05

# Cheap "does this look like a natural person" diagnostic. Reported for context
# only -- it never drives the scope decision, which comes from SIGOCPYRFSTA.
#
# Delegates to peopleparser::classify_names(), whose logistic model scores each
# token on how much more often it appears in organisation names than in people's
# names, combines that with token count and with given-name and surname hits in
# the 2020 Census name lists, and was trained on Form 990 Part VII names
# 2009-2025: 982,000 filer names against 9.4 million person-field names.
#
# Two things sit on top of the model, and both matter:
#
#   * Read `org_score`, never `name_type`. classify_names() only *labels* a name
#     an organisation once the score clears 0.99 for one- and two-word names, a
#     default tuned for officer lists where most two-word entries are people.
#     Grant recipients are full of acronyms and short institutional names, so
#     ASPCA (0.839), KQED (0.839), BARNARD COLLEGE (0.874) and CHARITY NAVIGATOR
#     (0.954) all come back `name_type == "person"`. Taking the label at face
#     value flags 7.7% of filer-declared public charities; reading the score at
#     0.05 flags 0.4%.
#   * Keep the 2-3 token precondition the whitelist rule had. A one-token
#     recipient is never a person's full name, and without the constraint bare
#     surnames and acronyms flag (FRICK, CHIP, CISA, MARC, CHOW).
#
# Measured 2026-11-24 on inputs/ef100k_grants.csv against the filed status
# (3,211 declared individual, 71,762 declared public charity): 73.7% recall at a
# 0.4% flag rate on declared charities, against 30.7% at 0.9% for the 202-name
# given-name whitelist this replaces -- more than double the recall at half the
# false-positive rate. Six of the seven people the whitelist is documented to
# miss in dev/NO-RESIDUAL-AUDIT.md now flag (JOEL BASS, JONES MAURICE, SMALL
# RANDALL, MITCHELL MILLER, BETH SMITH, TANNER JONES); BROOKLYN GARRISON-OSBORN
# scores 0.115 and still does not. Both label sets are filer-declared and noisy
# in both directions, so 0.4% is an upper bound on the true false-positive rate.
#
# An institutional-token veto was measured on top of the score and moved one row
# in 71,762: the model already encodes what a keyword list encodes, learned from
# 10 million names rather than 90 hand-chosen words, so no veto is applied.
.pf_looks_personal <- function(name, cutoff = .pf_personal_cutoff) {
  raw <- toupper(trimws(as.character(name)))
  raw[is.na(raw)] <- ""
  # Token count is judged on letters only, so punctuation and digits cannot
  # inflate it; the model is handed the name as filed, since it does its own
  # cleaning.
  v <- trimws(gsub("[[:space:]]+", " ", gsub("[^A-Z ]+", " ", raw)))
  ntok <- vapply(strsplit(v, " ", fixed = TRUE),
                 function(t) sum(nzchar(t)), integer(1))
  out <- logical(length(raw))
  ok <- ntok >= 2L & ntok <= 3L
  if (!any(ok)) return(out)
  # classify_names() is vectorised but not free -- score each distinct name once.
  u <- unique(raw[ok])
  cl <- peopleparser::classify_names(u)
  score <- cl$org_score[match(u, cl$name)]
  out[ok] <- (!is.na(score) & score < cutoff)[match(raw[ok], u)]
  out
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
#' @param placeholders Run [pf_detect_placeholders()] and set placeholder rows
#'   out of scope, with `oos_reason = "placeholder:<category>"`. On by default;
#'   `FALSE` restores the earlier scoping, in which they reach the cascade.
#'   Either way a reference that names a payee is not a placeholder; with the
#'   detector on, it is matched on the payee (`recip_name`) and the filed text
#'   is kept in `recip_name_filed`.
#' @return A data frame with the original columns plus the prepared recipient
#'   name / address fields, the standardized recipient type, the scope decision
#'   (`in_scope`, `oos_reason`), the placeholder decision (`placeholder_rule`,
#'   `placeholder_category`, `placeholder_sink`, all `NA` when the detector is
#'   off or did not fire), and four flags that describe the recipient without
#'   deciding scope:
#'   \describe{
#'     \item{`looks_personal`}{the name reads as a natural person, scored with
#'       `peopleparser::classify_names()`. Never fires on a placeholder.}
#'     \item{`flag_placeholder`}{the name is a pointer to an attachment rather
#'       than a name — see [pf_is_placeholder()].}
#'     \item{`flag_individual`, `flag_government`}{what the *filer* said the
#'       recipient was, from the status field.}
#'   }
#'   `vignette("identifying-people")` covers what each one is worth.
#' @export
pf_prepare_grants <- function(grants, id_prefix = "G", placeholders = TRUE) {
  g <- as.data.frame(grants, stringsAsFactors = FALSE)
  # Columns are named by the current concordance990 v2 schema. .pf_col() falls
  # back to the legacy v1/GTDC name, so files built before the migration still
  # read correctly -- see R/schema.R.
  get <- function(col) .pf_col(g, col)
  pnam <- .pf_blank_to_na(get("PF_15_G_PAID_RECIP_NAME_PERS"))
  bn1  <- .pf_blank_to_na(get("PF_15_G_PAID_RECIP_NAME_ORG_L1"))
  bn2  <- .pf_blank_to_na(get("PF_15_G_PAID_RECIP_NAME_ORG_L2"))
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
  name_filed <- name
  # -- placeholders (see pf_detect_placeholders) ------------------------------
  # A pointer, an aggregate or a privacy note is set aside below, before
  # matching. A reference that names a payee ("FIDELITY CHARITABLE - SEE
  # ATTACHMENT A") is matched on the payee instead; the filed name is kept in
  # recip_name_filed.
  ph <- if (isTRUE(placeholders)) pf_detect_placeholders(name) else NULL
  if (!is.null(ph)) {
    rw <- ph$category %in% "reference_with_name" & !is.na(name)
    name[rw] <- ph$residual[rw]
    name_alt[rw] <- NA_character_
  }
  # -- address ---------------------------------------------------------------
  state <- toupper(trimws(.pf_blank_to_na(get("PF_15_G_PAID_RECIP_ADDR_STATE"))))
  zipr  <- .pf_blank_to_na(get("PF_15_G_PAID_RECIP_ADDR_ZIP"))
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
  ty <- pf_standardize_status(get("PF_15_G_PAID_RECIP_STAT"))
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
  street   <- .pf_blank_to_na(get("PF_15_G_PAID_RECIP_ADDR_L1"))
  has_name <- !is.na(name)
  has_addr <- !is.na(zip5) | (!is.na(street) & !is.na(st_abb))
  oos_reason <- rep(NA_character_, nrow(g))
  oos_reason[detail %in% pf_oos_details()] <- "foreign address"
  # nothing to match on at all -- no name AND no usable address
  oos_reason[!has_name & !has_addr & is.na(oos_reason)] <- "no name or address"
  # A placeholder takes precedence over geography: it describes the row, and
  # its dollars are reported under that reason. A blank name is left to the
  # rule above, and a one-character name with a street is left for
  # pf_recover_name_from_street(), which may find the payee there.
  set_aside <- logical(nrow(g))
  if (!is.null(ph)) {
    set_aside <- ph$is_placeholder & has_name &
      !(ph$category %in% "unknown_or_none" & nchar(trimws(name)) <= 1L &
          !is.na(street))
    oos_reason[set_aside] <- paste0("placeholder:", ph$category[set_aside])
  }
  out <- g
  out$grant_id <- if (!is.null(g$grant_id)) as.character(g$grant_id)
                  else sprintf("%s%06d", id_prefix, seq_len(nrow(g)))
  out$recip_name     <- name
  out$recip_name_filed <- name_filed
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
  out$recip_unit   <- .pf_blank_to_na(get("PF_15_G_PAID_RECIP_ADDR_L2"))
  out$recip_city   <- .pf_blank_to_na(get("PF_15_G_PAID_RECIP_ADDR_CITY"))
  out$recip_state  <- ifelse(is_foreign, NA_character_, st_abb)
  out$recip_state_raw <- state
  out$recip_zip5   <- zip5
  out$is_foreign   <- is_foreign
  out$recipient_type        <- ty$recipient_type
  out$recipient_type_detail <- detail
  out$status_norm           <- ty$status_norm
  # A pointer to an attachment is not a name, so it cannot be a person's name
  # either. Without this precedence the person flag fires on 99 rows per 100k
  # that are all SEE ATTACHED variants: `SEE ATTACHED` is two tokens with no
  # institutional word in it, which is exactly the shape the score rewards.
  placeholder <- .pf_placeholder(name)
  out$flag_placeholder      <- placeholder
  out$looks_personal        <- .pf_looks_personal(name) & !placeholder & !set_aside
  out$placeholder_rule     <- if (is.null(ph)) NA_character_ else ph$rule_id
  out$placeholder_category <- if (is.null(ph)) NA_character_ else ph$category
  out$placeholder_sink     <- if (is.null(ph)) NA_character_ else ph$sink
  # Flags, not filters. These record what the filer *said* the recipient was so
  # results can be split by it, without that claim deciding whether we look.
  # `flag_placeholder` is the one that is read off the name rather than the
  # filed status, and it stays a flag too: the pointer rows carry 4.0% of all
  # grant dollars, which should be visible rather than silently dropped.
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
#' @param placeholders Passed to [pf_prepare_grants()].
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
                           allow_mixed = FALSE, placeholders = TRUE) {
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
    # The OBJECTID test above separates GT from e-file, but BOTH e-file schemas
    # carry OBJECTID, so a v1 build and a v2 build of the same source passed it
    # and concatenated into a frame where every column is half empty. `fill`
    # below makes that silent rather than fatal. Check the schema too.
    sch <- vapply(parts, .pf_schema_of, character(1))
    real <- setdiff(unique(sch), "unknown")
    if (length(real) > 1L) {
      stop("pf_read_grants() matched grant files of two different SCHEMAS.\n",
           paste(sprintf("  %-6s %s", sch, basename(files)), collapse = "\n"), "\n",
           "Concatenating them yields a frame where each schema's columns are ",
           "NA on the other's rows. Pass an explicit `pattern` for one schema, ",
           "or allow_mixed = TRUE if the mixture is intended.", call. = FALSE)
    }
  }
  d <- as.data.frame(data.table::rbindlist(parts, fill = TRUE))
  pf_prepare_grants(d, placeholders = placeholders)
}
