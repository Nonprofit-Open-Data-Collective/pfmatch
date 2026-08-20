#' @keywords internal
"_PACKAGE"

## usethis namespace: start
## usethis namespace: end
NULL

# `:=` and other data.table NSE only work inside a package whose namespace
# data.table recognises. pfmatch has data.table under Imports but no
# importFrom() directive, so `cedta()` fails and every `dt[, x := y]` inside a
# package function raises "not data.table-aware". Declaring this fixes it for
# the whole namespace; without it text.R, enrich.R, purpose.R and affiliation.R
# all fail the moment they are called from the installed package rather than
# from a script.
.datatable.aware <- TRUE

# data.table's non-standard evaluation makes column names look like undeclared
# globals to R CMD check. Declaring them here silences the note without
# suppressing genuine ones: anything added to a `[ ... ]` expression that is NOT
# in this list will still be flagged, which is the behaviour worth keeping.
utils::globalVariables(c(
  # data.table's own symbols
  ".", ".N", ".SD", ":=",
  # npmatch pair/result columns
  ".ein", ".id", "score", "n_close", "top", "veto",
  # 990 Part III / org-text columns
  "ORG_EIN", "RETURN_TYPE", "TAX_PERIOD_END_DATE", "mission", "prog_all",
  "prog_overflow_desc", "n_programs", "ntee_text", "activity_text", "all_text",
  "ein", "has_mission", ".tlen",
  # NTEE lookup columns
  "NTEE2", "l1", "l24", "l5", "cat_name", "cat_desc", "keywords", "level4",
  "level3.label", "level4.label", "level5.label", "ref",
  # grant-purpose columns
  "purpose", "contentful", "cov_all"
))
