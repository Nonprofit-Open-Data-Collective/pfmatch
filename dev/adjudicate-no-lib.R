#!/usr/bin/env Rscript
# ============================================================================
# adjudicate-no-lib.R -- the NO tier's case renderer and verdict schema.
# Sourced by dev/adjudicate-11-no-search.R. Not a script.
#
# WHY A SECOND RENDERER RATHER THAN A FLAG ON THE FIRST.
#
# dev/adjudicate-lib.R's adj_render_case() is load-bearing: the MAYBE
# experiment's published light-vs-deep comparison rests on both tiers having
# been handed byte-identical case text, and the calibration run in
# ADJ-CAL-*.rds was produced by that exact function. Adding a branch to it
# would put the two experiments one edit away from each other, and a change
# made for this one would silently invalidate the comparison in the other.
#
# It also would not fit. The MAYBE renderer reads grant_purpose, grant_amount
# and grant_year off `cand_rows[1]`, which does not exist for a NO case with no
# scored candidate -- and 0 candidates is a normal outcome in this tier, not an
# edge case. The NO case frame carries those fields on the case row instead,
# which is the difference the two renderers actually encode.
#
# The API client, cost table, credential resolution and response readers are
# NOT duplicated: this file sources the original for all of that.
# ============================================================================
PF_LIB <- Sys.getenv("PFMATCH_DIR", ".")
source(file.path(PF_LIB, "dev", "adjudicate-lib.R"))

## ---- the case as the reviewer sees it --------------------------------------
# One NO case as markdown. The structure deliberately mirrors the MAYBE
# renderer's -- same field labels, same "-" for absent -- so that a reader
# comparing the two experiments is comparing results and not formats.
#
# The section that differs is WHAT THE CASCADE DID. A NO case is defined by the
# cascade having declined, and the reviewer cannot judge whether that was right
# without knowing which of the two ways it declined:
#
#   no pairs at all   nothing was retrieved; no comparator ever ran. The filed
#                     name reached no record, which is itself a strong hint
#                     about the name.
#   pairs, rejected   records were found and scored below the floor. The prior
#                     audit (dev/NO-RESIDUAL-AUDIT.md) found the correct record
#                     had already been offered in 18 of 25 recoverable cases,
#                     so these rows are evidence and not noise.
#
# Printing "no candidate was retrieved" explicitly matters: silence there would
# read as a packet defect rather than as the finding it is.
adj_render_no_case <- function(case_row, cand_rows = NULL) {
  cr <- as.list(case_row)
  nc <- if (is.null(cand_rows)) 0L else nrow(cand_rows)
  L  <- c(
    sprintf("### CASE %s", cr$grant_id),
    "",
    "GRANT AS FILED",
    adj_fld("  recip_name", cr$recip_name),
    adj_fld("  recip_name_alt", cr$recip_name_alt),
    adj_fld("  recip_street", cr$recip_street),
    adj_fld("  recip_city", cr$recip_city),
    adj_fld("  recip_state", cr$recip_state),
    adj_fld("  recip_zip5", cr$recip_zip5),
    adj_fld("  grant_purpose", cr$grant_purpose),
    adj_fld("  grant_amount", cr$grant_amount),
    adj_fld("  grant_year", cr$grant_year),
    adj_fld("  recip_status_raw", cr$recip_status_raw),
    adj_fld("  recipient_type", cr$recipient_type),
    "",
    "FILING FOUNDATION",
    adj_fld("  fdn_name", cr$filer_name),
    adj_fld("  fdn_city", cr$FDN_org_addr_city),
    adj_fld("  fdn_state", cr$FDN_org_addr_state),
    adj_fld("  fdn_ntee", paste(adj_sq(cr$FDN_ntee_code_clean),
                                adj_sq(cr$FDN_ntee_code_definition))),
    "",
    "WHAT THE CASCADE DID")
  if (nc == 0L) {
    L <- c(L,
      "  No candidate record was retrieved at all. No blocking pass produced",
      "  any record to score, so no comparison was ever made. The filed name",
      "  reached nothing in the reference.",
      "")
  } else {
    L <- c(L, sprintf(paste("  %d record%s found and REJECTED -- each scored below the",
                            "floor for review."), nc, if (nc == 1L) " was" else "s were"),
      sprintf("  The best of them scored %s. They are listed best first.",
              adj_sq(cr$best_score)),
      "")
    for (i in seq_len(nc)) {
      r <- as.list(cand_rows[i, ])
      L <- c(L,
        sprintf("REJECTED CANDIDATE %s  (rank %s of %d)", i, adj_sq(r$rank), nc),
        adj_fld("  ein", r$ein),
        adj_fld("  cand_name", r$cand_name),
        if (nzchar(adj_sq(r$CAND_org_name_display)) &&
            !identical(toupper(adj_sq(r$CAND_org_name_display)),
                       toupper(adj_sq(r$cand_name))))
          adj_fld("  cand_name_bmf_display", r$CAND_org_name_display) else NULL,
        adj_fld("  cand_city", r$cand_city),
        adj_fld("  cand_state", r$cand_state),
        adj_fld("  cand_zip5", r$cand_zip5),
        adj_fld("  cand_ntee", paste(adj_sq(r$CAND_ntee_code_clean),
                                     adj_sq(r$CAND_ntee_code_definition))),
        adj_fld("  cand_nteev2_subsector", r$CAND_nteev2_subsector),
        adj_fld("  cand_subsection", r$CAND_subsection_code),
        adj_fld("  cand_ruling_year", r$CAND_ruling_date),
        adj_fld("  cand_ntee_text", r$cand_ntee_text, 600),
        adj_fld("  cand_mission", r$cand_mission, 1000),
        adj_fld("  cand_prog", r$cand_prog, 1500),
        sprintf("  signals: score=%s name_sim=%s geo_zip5=%s geo_state=%s pass=%s",
                adj_sq(r$score), adj_sq(r$name_sim), adj_sq(r$geo_zip5),
                adj_sq(r$geo_state), adj_sq(r$pass)),
        "")
    }
  }
  paste(L, collapse = "\n")
}

## ---- the verdict schema ----------------------------------------------------
# dev/LLM-NO-INSTRUCTIONS.md's output table, as a strict tool schema. The same
# API constraints as the MAYBE schema apply and for the same reasons: no
# minimum/maximum/minLength, additionalProperties FALSE, and every property in
# `required`, so a field that does not apply is the empty string or an explicit
# NOT_APPLICABLE rather than an absent key.
#
# The three enums are the experiment's output and are deliberately separate:
#
#   entity_class      what the payee IS
#   bmf_expectation   whether a record SHOULD exist
#   outside_reason    why not, when it should not
#   miss_hypothesis   why the cascade failed, when it should
#
# entity_class and bmf_expectation are not redundant. A GROUP_SUBORDINATE may be
# separately listed (a Salvation Army area command) or not (a Scout troop), so
# collapsing the two would destroy exactly the distinction this experiment
# exists to measure.
#
# ein_source is the circularity guard. dev/NO-RESIDUAL-AUDIT.md's headline
# result -- that every independently established EIN was already in both
# references -- holds only because four EINs read off reference near-miss rows
# were excluded from it. Those are in the reference by construction. Recording
# the provenance on every verdict lets stage 12 reproduce that exclusion by
# filter rather than by hand.
adj_no_schema <- function() {
  props <- list(
    grant_id        = list(type = "string"),
    org_found       = list(type = "string", enum = adj_array(c("YES", "NO", "UNCERTAIN"))),
    org_name        = list(type = "string"),
    ein             = list(type = "string"),
    ein_source      = list(type = "string", enum = adj_array(c("WEB", "CANDIDATE", "NONE"))),
    entity_class    = list(type = "string", enum = adj_array(c(
      "NONPROFIT", "GROUP_SUBORDINATE", "CHURCH", "GOVERNMENT", "FOREIGN",
      "FISCALLY_SPONSORED", "INDIVIDUAL", "FOR_PROFIT", "PROGRAM_OR_EVENT",
      "AGGREGATE", "UNKNOWN"))),
    bmf_expectation = list(type = "string", enum = adj_array(c(
      "LISTED", "NOT_LISTED", "UNCERTAIN"))),
    outside_reason  = list(type = "string", enum = adj_array(c(
      "NOT_AN_ORG", "GROUP_RULING", "CHURCH_EXEMPT", "NO_SEPARATE_EXEMPTION",
      "TOO_NEW", "REVOKED_OR_DISSOLVED", "NOT_TRACEABLE", "NOT_APPLICABLE"))),
    miss_hypothesis = list(type = "string", enum = adj_array(c(
      "ACRONYM", "LEGAL_NAME_DIFFERS", "DBA_OR_TRADE_NAME", "TRUNCATED", "TYPO",
      "PROGRAM_NAMED", "GEOGRAPHY_WRONG", "PARENT_OR_CHAPTER", "PLAIN_MISS",
      "NOT_APPLICABLE"))),
    confidence      = list(type = "string", enum = adj_array(c("high", "medium", "low"))),
    evidence        = list(type = "string"),
    search_findings = list(type = "string"),
    search_confirmed = list(type = "string", enum = adj_array(c(
      "CONFIRMED", "CONTRADICTED", "INCONCLUSIVE", "NOT_SEARCHED"))))
  list(type = "object", properties = props,
       required = adj_array(names(props)), additionalProperties = FALSE)
}

adj_no_cols <- function() names(adj_no_schema()$properties)

# Same contract as adj_verdict_row(): stable columns, NA for anything the model
# omitted or mistyped, and the key written from our side rather than trusted
# from the model's echo.
adj_no_row <- function(v, grant_id) {
  cols <- adj_no_cols()
  out <- as.list(setNames(rep(NA_character_, length(cols)), cols))
  if (!is.null(v) && length(v))
    for (nm in intersect(cols, names(v))) {
      x <- v[[nm]]
      out[[nm]] <- if (length(x) == 0L) NA_character_ else as.character(x)[1]
    }
  out$grant_id <- grant_id
  as.data.frame(out, stringsAsFactors = FALSE)
}

## ---- EIN normalisation, without loading pfmatch ----------------------------
# Mirrors pfmatch's internal .pf_ein(): strip to digits, blank to NA, left-pad
# to nine. Reimplemented rather than reached for via devtools::load_all()
# because stage 11 is a pure API client -- loading the package there would pull
# in data.table, npmatch and a reference just to format nine characters.
#
# This is not cosmetic. The model reports whatever its source printed:
# "05-0448102", "050448102", "EIN 05-0448102". An un-normalised value fails the
# exact set-membership test in stage 12 for a formatting reason that is
# indistinguishable, in the output, from the organisation genuinely being
# absent from the reference -- which is the experiment's headline number. The
# nine-digit check is reported rather than silently dropped for the same
# reason: a value that does not normalise is a parsing problem to look at, not
# evidence about the BMF.
#
# The padding is done by paste0/strrep and NOT by formatC(width = 9,
# flag = "0"), which is what pfmatch's own .pf_ein() uses. formatC's "0" flag
# applies to NUMERIC input; handed a CHARACTER vector it pads with SPACES and
# silently ignores the flag. So "123" comes back as "      123" -- nine
# characters, so a nchar() == 9 check passes it, and the value then fails an
# exact match against every reference EIN. In this script that failure mode is
# not cosmetic: a space-padded EIN would be counted as "established by search
# but absent from the reference", which is this experiment's headline claim
# about BMF coverage. A formatting artefact would have been read as a finding.
.pf_ein_local <- function(x) {
  v <- gsub("[^0-9]", "", as.character(x))
  v[is.na(v) | !nzchar(v)] <- NA_character_
  # Pad 8 digits to 9 and nothing shorter. pfmatch's .pf_ein() pads anything up
  # to 9 because it normalises BMF and filing fields, where a dropped leading
  # zero is the known defect and is always exactly one digit. A model-reported
  # value of 3 or 5 digits is not a dropped zero, it is a parse failure, and
  # padding it produces a well-formed EIN that belongs to nobody -- which would
  # then be counted as "established by search, absent from the reference", the
  # one cell in this experiment that must not collect artefacts.
  ok <- !is.na(v) & nchar(v) == 8L
  v[ok] <- paste0("0", v[ok])
  v[!is.na(v) & nchar(v) != 9L] <- NA_character_   # unparseable, not absent
  v
}
