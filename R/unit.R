# ============================================================================
# The secondary-unit line as adjudication evidence.
#
# THIS FILE IS A STOPGAP. npmatch and matchdb are integrating unit parsing and
# promotion of the unit to the adjudication stage; when that merges, this goes.
# Read dev/UNIT-UPSTREAM-SYNC.md BEFORE changing anything here -- it lists the
# decisions to diff against upstream, the retirement order, and the four
# behaviours any replacement has to keep.
#
# PF_15_G_PAID_RECIP_ADDR_L2 is where a suite number lands, and two renderings
# at one street that give DIFFERENT suites are very likely different
# organizations -- which is the one address fact that bears directly on a
# triangulated label. It cannot help the matcher: np_detect_geo() only selects
# the unit-bearing weight profile when unit coverage clears 50% and it runs at
# 2-3%, and .np_hier_score() has no unit term at all. It can help a human.
#
# Two things make it unusable raw. The field is polluted -- street lines, city
# names, PO boxes and prose all appear in it -- and the designator is not
# standardized, so UNIT 1200 and STE 1200 are the same suite written two ways.
# Both are handled here rather than at the call site, so the dev scripts and
# the pf_variants fixture agree on what a unit is.
# ============================================================================

.PF_UNIT_DESIG <- c("STE", "SUITE", "UNIT", "APT", "APARTMENT", "RM", "ROOM",
                    "SPC", "TRLR", "LOT", "OFFICE", "OFC", "NO")
.PF_UNIT_LEVEL <- c("FL", "FLOOR", "BLDG", "BUILDING", "TOWER", "WING")
.PF_STREET_TYPE <- c("ST", "STREET", "RD", "ROAD", "AVE", "AVENUE", "BLVD",
  "DR", "DRIVE", "LN", "LANE", "CT", "COURT", "PL", "PLACE", "PKWY", "PARKWAY",
  "HWY", "HIGHWAY", "TER", "TERRACE", "CIR", "CIRCLE", "WAY", "TRL", "TRAIL",
  "PLZ", "PLAZA", "SQ", "SQUARE", "LOOP", "PIKE", "RTE", "ROUTE")

#' Parse the secondary-unit line into a comparable identifier
#'
#' Extracts the unit from a raw `PF_15_G_PAID_RECIP_ADDR_L2` value and returns
#' it as `type` plus `id`, or `""` for both when the line does not hold a unit.
#'
#' A line is rejected when it is a PO box, when it looks like a street address
#' (a leading house number followed by a street-type word), or when it carries
#' no digits at all — `STREET`, `LAS VEGAS` and `114 HIGH ST` are all real
#' values of this field.
#'
#' `type` separates room-level designators (`STE`, `UNIT`, `APT`, `RM`, …,
#' normalized to `STE`) from level-level ones (`FL`, `BLDG`, `TOWER`, …), so
#' that `FL 2` is not read as the same place as `STE 2`. A bare identifier with
#' no designator — `206`, `A-304` — gets type `""`, and compares equal to a
#' room-level unit with the same `id`, since a filer writing `Suite 206` and
#' one writing `206` at the same street mean the same door.
#'
#' @param x Character vector of raw address line 2 values.
#' @param street Optional street line, same length as `x`. When it names a PO
#'   box, a *bare* identifier in `x` is rejected: at a box address the digits
#'   on line 2 are a box or account number, not a door. `211 EMMET STREET
#'   SOUTH PO BOX` with `400891` on line 2 is the case. A value carrying an
#'   explicit designator is still read as a unit.
#' @return A data frame with `type` and `id`, one row per input.
#' @seealso [pf_unit_evidence()]
#' @export
pf_parse_unit <- function(x, street = NULL) {
  v <- as.character(x); v[is.na(v)] <- ""
  v <- trimws(gsub(" +", " ", gsub("[^A-Z0-9 #/-]", " ", toupper(v))))
  n <- length(v)
  type <- rep("", n); id <- rep("", n)

  rej <- grepl("\\b(P[ ]?O|POST)\\b[ ]*(OFFICE[ ]*)?BOX\\b|^BOX\\b", v) |
         grepl("\\bC[ /]?O\\b", v) |
         (grepl("^[0-9]+\\b", v) &
            grepl(paste0("\\b(", paste(.PF_STREET_TYPE, collapse = "|"), ")\\b"), v)) |
         !grepl("[0-9]", v)

  boxy <- if (is.null(street)) rep(FALSE, n) else {
    s <- toupper(as.character(street)); s[is.na(s)] <- ""
    grepl("\\bP[ ]?O[ ]?BOX\\b|\\bPOBOX\\b|\\bPOST[ ]*OFFICE[ ]*BOX\\b", s)
  }
  if (length(boxy) != n) boxy <- rep(FALSE, n)

  dgs <- paste(c(.PF_UNIT_DESIG, .PF_UNIT_LEVEL), collapse = "|")
  # The identifier keeps internal separators and strips them below, so T-700
  # and T-205 stay distinct. Stopping at the hyphen collapsed both to "T" and
  # reported them as the same suite -- a false `agree`, which is worse than a
  # false `conflict`: a conflict gets looked at, an agreement never does.
  pat <- paste0("\\b(", dgs, ")\\b[ #/-]*([A-Z0-9][A-Z0-9/-]*)")
  m <- regexec(pat, v)
  g <- regmatches(v, m)
  for (i in seq_len(n)) {
    if (rej[i]) next
    if (length(g[[i]]) == 3L) {
      d <- g[[i]][2]
      type[i] <- if (d %in% .PF_UNIT_LEVEL) .pf_unit_level_canon(d) else "STE"
      id[i]   <- gsub("[ /-]", "", g[[i]][3])
    } else if (grepl("^#[ ]*[A-Z0-9]", v[i])) {
      # "#400" -- a hash carries no word boundary, so the designator pattern
      # above cannot see it
      type[i] <- "STE"
      id[i] <- gsub("[ /-]", "", sub("^#[ ]*", "", v[i]))
    } else if (grepl("^[0-9]+(ST|ND|RD|TH)?[ ]+(FLOOR|FL)\\b", v[i])) {
      # "2ND FLOOR", "2 FLOOR" -- identifier BEFORE the designator, which is
      # how filers usually write a floor
      type[i] <- "FL"
      id[i] <- sub("^([0-9]+).*$", "\\1", v[i])
    } else if (!boxy[i] &&
               grepl("^[A-Z]?[ -]?[0-9][A-Z0-9]*$|^[A-Z]-[0-9]+$", v[i])) {
      # a bare identifier standing alone
      id[i] <- gsub("[ -]", "", v[i])
    }
  }
  data.frame(type = type, id = id, stringsAsFactors = FALSE)
}

.pf_unit_level_canon <- function(d) {
  if (d %in% c("FL", "FLOOR")) "FL"
  else if (d %in% c("BLDG", "BUILDING")) "BLDG"
  else d
}

#' Compare two unit lines as adjudication evidence
#'
#' @param a,b Raw address line 2 values, the anchor's and the candidate's.
#' @param street_a,street_b Optional street lines, passed through to
#'   [pf_parse_unit()] so a box number is not read as a suite.
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
#' `conflict` fires on 0.47% of candidate pairs in the triangulation run — 69
#' of 14,790, of which 19 sit on a `MAYBE` candidate and so reach the
#' adjudication queue. It is a rare, sharp signal, not a routine one, and it
#' concentrates: one address (a fellowship program writing a sequential
#' counter into line 2, one per individual grantee) produced 31 of the 69. A
#' conflict is a prompt for a reviewer, never an automatic verdict. See the
#' "Name and address variants" vignette for the full rates.
#' @seealso [pf_parse_unit()]
#' @export
pf_unit_evidence <- function(a, b, street_a = NULL, street_b = NULL) {
  pa <- pf_parse_unit(a, street_a); pb <- pf_parse_unit(b, street_b)
  ha <- nzchar(pa$id); hb <- nzchar(pb$id)
  # a bare id compares against a room-level unit; FL 2 never against STE 2
  ta <- ifelse(nzchar(pa$type), pa$type, "STE")
  tb <- ifelse(nzchar(pb$type), pb$type, "STE")
  same <- ha & hb & ta == tb & pa$id == pb$id
  diff <- ha & hb & !same
  out <- rep("absent", length(ha))
  out[xor(ha, hb)] <- "one_sided"
  out[ha & hb & same] <- "agree"
  out[diff] <- "conflict"
  out
}
