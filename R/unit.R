# ============================================================================
# The secondary-unit line as adjudication evidence.
#
# The parser that used to live here is gone. npmatch PR #18 (merged 2026-10-26)
# parses the suite into `street_unit` / `street_unit_id` inside np_normalize(),
# scores it (`geo_weights["unit"] = 0.97`) and annotates every candidate pair
# for the reviewer, and the normalizer has since moved unchanged into
# npnormalize, which npmatch re-exports. By the rule in
# dev/NPMATCH-PROMOTION-PLAN.md -- generic machinery belongs upstream -- USPS
# secondary-unit parsing was never pfmatch's to own. The local copy was also
# measurably wrong: it listed NO and OFC as unit designators, which npmatch's
# BMF scan excludes for measured reasons (NO is North far more often than
# Number; the USPS C2 designators match street names -- PIERCE ST, KEYSER AVE).
#
# What is left here is the part that IS 990-PF specific: PF_15_G_PAID_RECIP_
# ADDR_L2 is an uncontrolled field, so two local rejections sit on top of the
# upstream parse (see pf_street_unit()), and the comparison that turns two
# parsed units into adjudication evidence keeps pfmatch's own semantics (see
# pf_unit_evidence()). dev/UNIT-UPSTREAM-SYNC.md §3 lists every decision that
# could have gone the other way and §5 the behaviours that were measured here
# and must not be discarded; dev/PLACES-SYNC.md §3b carries the retirement.
# The measured effect of the switch is recorded in UNIT-UPSTREAM-SYNC.md §4.
#
# Two renderings at one street that give DIFFERENT suites are very likely
# different organizations -- the one address fact that bears directly on a
# triangulated label. That is what this file is for: a prompt for a human
# reading the adjudication queue, never an automatic verdict.
# ============================================================================

# Room-level designators, in npmatch's canonical spelling. These are
# interchangeable: a filer writing UNIT 1200, STE 1200 or a bare 1200 means one
# door. `#` is npmatch's canon for both an explicit hash (`#400`) and a bare
# identifier, so it belongs here. Everything else npmatch can emit -- FL, BLDG,
# BSMT, LBBY, HNGR, PMB, DEPT, STOP -- is deliberately NOT folded in: FL 2 is
# not STE 2, and a mailbox or department number is not a door. npmatch compares
# `street_unit_id` alone, which collapses all of these; pfmatch does not,
# because a false `agree` is worse than a false `conflict` here (§5).
.PF_UNIT_ROOM <- c("STE", "APT", "UNIT", "RM", "SPC", "TRLR", "LOT", "#")

# The designators npmatch's .np_unit_pat recognizes, used only to tell "this
# value carries a designator" from "this value is a bare identifier". The two
# local rejections below apply to bare identifiers only, so a value with an
# explicit designator is never rejected by them.
.PF_UNIT_DESIG_RE <- paste0(
  "(^|[^A-Z0-9])(APARTMENT|NUMBER|SUITE|FLOOR|SPACE|UNIT|ROOM|BLDG|TRLR|",
  "DEPT|STOP|BSMT|LBBY|HNGR|STE|APT|PMB|SPC|LOT|NUM|RM|FL)([^A-Z0-9]|$)")

# Any BOX, not just PO BOX. The street lines that matter here are
# `300 KENAN CENTER DRIVE - CAMPUS BOX` and `4347 W NORTHWEST HWY STE 130 BOX`
# as well as `211 EMMET STREET SOUTH PO BOX`, and the digits on line 2 are a
# box number at all three. The letter guards keep BOXWOOD LANE and BOXER ST
# out, and the rule only ever suppresses a bare identifier, so its failure
# direction is toward `absent` rather than toward a false `agree`.
.PF_BOX_RE <- "(^|[^A-Z])(P[ .]?O[ .]?BOX|POBOX|POST[ ]?OFFICE[ ]?BOX|BOX)([^A-Z]|$)"

#' Parse the secondary-unit line into a comparable unit
#'
#' Extracts the unit from a raw `PF_15_G_PAID_RECIP_ADDR_L2` value and returns
#' it in npmatch's canonical `street_unit` spelling — `"STE 400"`, `"FL 2"`,
#' `"# 206"` — or `""` where the line holds no unit.
#'
#' The parse itself is npmatch's: the value is passed to [npmatch::np_normalize()]
#' as a `unit` column and `street_unit` is read back, so pfmatch compares units
#' the same way the matcher does and a normalizer change moves both together.
#' Values are de-duplicated before normalizing, since line 2 repeats heavily.
#'
#' Two rejections are applied on top, because `ADDR_L2` is not a unit field —
#' street lines, city names, PO boxes and prose all appear in it. Both apply
#' only to a *bare* identifier, one carrying no designator; a value with an
#' explicit designator is always read as a unit.
#'
#' * **No digits.** `STREET`, `WAY` and `CONSERVANCY` are real values of this
#'   field, and npmatch's bare-identifier path reads each as a unit id. The
#'   digit requirement is pfmatch's, and it is why it belongs on the bare path
#'   only: `SUITE B` is a real suite with no digit in it.
#' * **A box number at a box street.** At `211 EMMET STREET SOUTH PO BOX`, the
#'   `400891` on line 2 is a box, not a door. See `.PF_BOX_RE`.
#'
#' @param x Character vector of raw address line 2 values.
#' @param street Optional street line, same length as `x`, used for the
#'   box-number rejection. A value carrying an explicit designator is still
#'   read as a unit.
#' @return A character vector the length of `x`, holding npmatch's canonical
#'   `street_unit` string or `""`.
#' @seealso [pf_unit_evidence()], and `dev/UNIT-UPSTREAM-SYNC.md` for the
#'   decisions this delegation settles.
#' @export
pf_street_unit <- function(x, street = NULL) {
  v <- as.character(x); v[is.na(v)] <- ""
  n <- length(v)
  if (!n) return(character(0))

  u <- .pf_np_street_unit(v)

  vu <- toupper(trimws(v))
  bare <- !(grepl(.PF_UNIT_DESIG_RE, vu) | grepl("#", vu, fixed = TRUE))
  u[bare & !grepl("[0-9]", vu)] <- ""
  if (!is.null(street)) {
    s <- toupper(as.character(street)); s[is.na(s)] <- ""
    if (length(s) == n) u[bare & grepl(.PF_BOX_RE, s)] <- ""
  }
  u
}

# np_normalize() wants a frame, so hand it one holding only the distinct line-2
# values. A tripwire rather than a feature check: street_unit does not exist
# before npmatch PR #18, and a silent NULL here would read as "no value on this
# line holds a unit" -- every verdict `absent`, nothing failing.
.pf_np_street_unit <- function(v) {
  k <- unique(v)
  m <- length(k)
  d <- data.frame(name = rep("", m), dba = rep("", m), street = rep("", m),
                  unit = k, city = rep("", m), state = rep("", m),
                  zip5 = rep("", m), zip_plus4 = rep("", m),
                  stringsAsFactors = FALSE)
  nd <- npmatch::np_normalize(d)
  if (!"street_unit" %in% names(nd))
    stop("npmatch::np_normalize() returned no `street_unit` column; pfmatch ",
         "needs npmatch >= 0.1.1 (PR #18) for secondary-unit parsing",
         call. = FALSE)
  out <- nd$street_unit
  out[is.na(out)] <- ""
  out[match(v, k)]
}

.pf_unit_class <- function(u) {
  d <- sub(" .*$", "", u)
  ifelse(!nzchar(u), "", ifelse(d %in% .PF_UNIT_ROOM, "ROOM", d))
}

.pf_unit_id <- function(u) ifelse(nzchar(u), sub("^[^ ]+ ", "", u), "")

#' Compare two unit lines as adjudication evidence
#'
#' @param a,b Raw address line 2 values, the anchor's and the candidate's.
#' @param street_a,street_b Optional street lines, passed through to
#'   [pf_street_unit()] so a box number is not read as a suite.
#' @return A character vector, one per pair:
#' \describe{
#'   \item{`conflict`}{Both parse to a unit and they disagree. Two different
#'     doors at one street, so the two renderings are very likely different
#'     organizations and a triangulated label assigning them one EIN is
#'     probably wrong. This is the case worth a reviewer's attention.}
#'   \item{`agree`}{Both parse and match. **Do not read this as support for one
#'     organization.** Measured on the triangulation run it is close to
#'     worthless: `SUITE 100`, `SUITE 300` and `SUITE 400` are shared by
#'     unrelated tenants (`MIDDLE EAST CHILDRENS ALLIANCE` and
#'     `IRISH REPERTORY THEATER` both at Suite 100; `GLOBAL FUND FOR WOMEN` and
#'     `THAKKER CHARITABLE TRUST` both at Suite 400), a fiscal sponsor's suite
#'     is shared by everything it sponsors, and some values are not units at
#'     all — `15219` is a Pittsburgh ZIP code sitting on line 2. It is recorded
#'     for completeness, not as evidence.}
#'   \item{`one_sided`}{One parses, the other does not. Carries nothing —
#'     filers omit the line constantly, so silence is not disagreement.}
#'   \item{`absent`}{Neither parses.}
#' }
#'
#' Two units agree when their identifiers match **and** their designators fall
#' in the same class: the room-level designators are interchangeable
#' (`.PF_UNIT_ROOM`), everything else is not, so `UNIT 1200` is `STE 1200` but
#' `FL 2` is not `STE 2`. This is where pfmatch departs from npmatch, which
#' compares `street_unit_id` alone and so reads a floor as a suite. Upstream
#' the cost is a missing 0.97 rung in a `max()` ladder; here it would be a
#' false `agree`, which no reviewer ever looks at.
#'
#' Against npmatch's own pair annotations: `conflict` and `agree` are
#' `geo_unit == 0` and `geo_unit == 1` under the stricter designator rule above,
#' and `one_sided` and `absent` are the two halves of `geo_unit == NA` that
#' `geo_unit` cannot tell apart. The crowding half of the annotation —
#' `addr_shared`, `addr_units`, `addr_unit_shared`, `addr_note` — has no
#' counterpart here and should be taken from `np_compare()` rather than
#' reinvented; see `dev/PLACES-SYNC.md` §4.5.
#'
#' `conflict` fires on 0.47% of candidate pairs in the triangulation run — 69
#' of 14,790, of which 19 sit on a `MAYBE` candidate and so reach the
#' adjudication queue. It is a rare, sharp signal, not a routine one, and it
#' concentrates: one address (a fellowship program writing a sequential
#' counter into line 2, one per individual grantee) produced 31 of the 69. A
#' conflict is a prompt for a reviewer, never an automatic verdict. See the
#' "Name and address variants" vignette for the full rates.
#' @seealso [pf_street_unit()]
#' @export
pf_unit_evidence <- function(a, b, street_a = NULL, street_b = NULL) {
  ua <- pf_street_unit(a, street_a); ub <- pf_street_unit(b, street_b)
  ha <- nzchar(ua); hb <- nzchar(ub)
  same <- ha & hb & .pf_unit_class(ua) == .pf_unit_class(ub) &
          .pf_unit_id(ua) == .pf_unit_id(ub)
  out <- rep("absent", length(ha))
  out[xor(ha, hb)] <- "one_sided"
  out[ha & hb & same] <- "agree"
  out[ha & hb & !same] <- "conflict"
  out
}
