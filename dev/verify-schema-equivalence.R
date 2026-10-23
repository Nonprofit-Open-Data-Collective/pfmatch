#!/usr/bin/env Rscript
# ============================================================================
# The migration's safety gate: both schemas must prepare IDENTICALLY.
#
# The readers now name columns by concordance990 v2 and fall back to the legacy
# v1/GTDC names through .pf_col(). If that fallback is wrong anywhere, a column
# silently reads as all-NA and the pipeline carries on with missing data rather
# than failing -- which is the worst possible outcome and exactly what this
# checks for.
#
# The test builds the same year under both schemas, runs pf_prepare_grants() on
# each, and compares every prepared column. Any difference is a migration bug.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
PF  <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("-", 80))

yr <- as.integer(Sys.getenv("PF_YR", "2023"))
tmp <- tempdir()
v2  <- file.path(tmp, "grants-v2.csv")
gt  <- file.path(tmp, "grants-gtdc.csv")

say("building %d under both schemas (dedup off, so only naming differs) ...", yr)
pf_efilepf_build(out = v2, years = yr, schema = "v2",   dedup = FALSE, verbose = FALSE)
pf_efilepf_build(out = gt, years = yr, schema = "gtdc", dedup = FALSE, verbose = FALSE)

a <- fread(v2, colClasses = "character", showProgress = FALSE)
b <- fread(gt, colClasses = "character", showProgress = FALSE)
say("v2 file   : %s rows, %d cols", format(nrow(a), big.mark = ","), ncol(a))
say("gtdc file : %s rows, %d cols", format(nrow(b), big.mark = ","), ncol(b))
say("  schema detected: v2=%s gtdc=%s", .pf_schema_of(a), .pf_schema_of(b))

pa <- as.data.table(pf_prepare_grants(a))
pb <- as.data.table(pf_prepare_grants(b))
hr(); say("PREPARED FRAMES")
say("  rows : %s vs %s", format(nrow(pa), big.mark = ","), format(nrow(pb), big.mark = ","))

shared <- intersect(names(pa), names(pb))
only_a <- setdiff(names(pa), names(pb))
say("  shared columns: %d | only in v2: %d", length(shared), length(only_a))
if (length(only_a)) say("    (%s)", paste(utils::head(only_a, 12), collapse = ", "))

cmp <- function(x, y) {
  x <- as.character(x); y <- as.character(y)
  x[is.na(x)] <- "\001"; y[is.na(y)] <- "\001"
  sum(x != y)
}
hr(); say("COLUMN-BY-COLUMN DIFFERENCES (0 everywhere = migration is safe)")
bad <- 0L
for (k in shared) {
  n <- cmp(pa[[k]], pb[[k]])
  if (n > 0L) {
    bad <- bad + 1L
    say("  DIFFERS %-24s %s rows", k, format(n, big.mark = ","))
    i <- which(as.character(pa[[k]]) != as.character(pb[[k]]))[1]
    if (!is.na(i)) say("      v2[%d]=%s | gtdc[%d]=%s", i, pa[[k]][i], i, pb[[k]][i])
  }
}
hr()
if (bad == 0L) {
  say("ALL %d shared prepared columns identical -- the v2 readers and the", length(shared))
  say("legacy fallback agree, so no column is silently reading as NA.")
} else {
  say("%d column(s) DIFFER. The migration is not safe yet.", bad)
}
say("")
say("columns the v2 schema adds that the legacy one could not carry:")
say("  %s", paste(intersect(c("OBJECTID", "TABLE_ID", "EIN2", "VERSION",
                             "RETURN_AMENDED_X", "RETURN_PARTIAL_X",
                             "RETURN_GROUP_X", "RETURN_TIME_STAMP",
                             "RETURN_TYPE", "RETURN_TAXPER_DAYS"), names(a)),
                 collapse = ", "))
quit(status = if (bad == 0L) 0L else 1L)
