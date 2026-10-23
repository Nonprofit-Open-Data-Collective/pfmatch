# ============================================================================
# Column resolution across the two grant-file schemas.
#
# pfmatch was prototyped against GT's Data Mart extract, whose column names are
# the concordance990 **v1** names (SIGOCPYRPNAM, SIGOCPYRBNBN1, FILEREIN, ...).
# The published ef2 files carry the **v2** names (PF_15_G_PAID_RECIP_NAME_PERS,
# PF_15_G_PAID_RECIP_NAME_ORG_L1, ORG_EIN, ...), which are the current
# concordance and the ones to write new code against.
#
# Rather than rename every reference at once -- which would strand the stored
# artifacts, verdict files and frozen baseline keyed to the old names -- reads
# go through one resolver that accepts either name and finds whichever the frame
# actually has. New code uses v2 names; old files keep working; nothing is
# silently read as NA because a schema changed under it.
#
# The alias table is derived from pf_efilepf_map() rather than restated, so the
# two cannot drift apart.
# ============================================================================

# v2 canonical -> v1 legacy, inverted from the build map (which is v1 -> v2)
.pf_v2_to_v1 <- function() {
  m <- pf_efilepf_map()
  stats::setNames(names(m), unname(m))
}

#' Read a grant column by either schema name
#'
#' Accepts a concordance990 v2 name or the legacy v1/GTDC name and returns
#' whichever the frame carries, so a reader works against both the published
#' ef2 files and artifacts built before the migration.
#'
#' Returns `default` (recycled) when neither name is present. That is
#' deliberate for genuinely optional fields — 2025 has no
#' `PF_15_G_PAID_RECIP_STAT`, for instance — but it does mean a typo reads as
#' all-missing rather than erroring, so [.pf_require_cols()] guards the columns
#' a caller cannot proceed without.
#'
#' @param g A grant frame.
#' @param name Column name in either schema.
#' @param default Value when the column is absent in both schemas.
#' @return A character vector, `nrow(g)` long.
#' @keywords internal
.pf_col <- function(g, name, default = NA_character_) {
  n <- if (is.data.frame(g)) nrow(g) else length(g[[1]])
  if (!is.null(g[[name]])) return(as.character(g[[name]]))
  # name given as v2 -> try its v1 alias
  v1 <- .pf_v2_to_v1()[[name]]
  if (!is.null(v1) && !is.null(g[[v1]])) return(as.character(g[[v1]]))
  # name given as v1 -> try its v2 form
  v2 <- pf_efilepf_map()[[name]]
  if (!is.null(v2) && !is.null(g[[v2]])) return(as.character(g[[v2]]))
  rep(default, n)
}

#' Which schema does this frame use?
#'
#' @param g A grant frame.
#' @return `"v2"`, `"gtdc"`, or `"mixed"` when columns of both appear, which
#'   usually means two vintages were concatenated.
#' @keywords internal
.pf_schema_of <- function(g) {
  m <- pf_efilepf_map()
  # Identity mappings carry no information about which schema a file uses:
  # URL is spelled "URL" in both, so counting it made every pure file look
  # "mixed". Compare only on names that actually differ between the schemas.
  m <- m[names(m) != unname(m)]
  nm <- names(g)
  has_v2 <- any(unname(m) %in% nm)
  has_v1 <- any(names(m) %in% nm)
  if (has_v2 && has_v1) "mixed" else if (has_v2) "v2" else if (has_v1) "gtdc" else "unknown"
}

#' Stop unless the required grant columns resolve in some schema
#'
#' @param g A grant frame.
#' @param cols Column names in either schema.
#' @param what Context for the error message.
#' @keywords internal
.pf_require_cols <- function(g, cols, what = "this operation") {
  nm <- names(g)
  v1 <- .pf_v2_to_v1(); v2 <- pf_efilepf_map()
  ok <- vapply(cols, function(c0)
    c0 %in% nm || (!is.null(v1[[c0]]) && v1[[c0]] %in% nm) ||
      (!is.null(v2[[c0]]) && v2[[c0]] %in% nm), logical(1))
  if (!all(ok))
    stop(what, " needs grant column(s) absent in both schemas: ",
         paste(cols[!ok], collapse = ", "),
         ". Build the grant file with pf_efilepf_build(schema = \"v2\").",
         call. = FALSE)
  invisible(TRUE)
}
