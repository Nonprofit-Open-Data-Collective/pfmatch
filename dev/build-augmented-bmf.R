#!/usr/bin/env Rscript
# ============================================================================
# build-augmented-bmf.R -- the Schedule I preprocessing stage, end to end.
#
#   download -> DuckDB -> normalize -> dedupe to aliases -> difference against
#   the BMF -> append the new (EIN, name) rows -> write the augmented reference
#
#   PF_BMF=active|unified   which BMF to augment      (default unified)
#   PF_MIN_FILERS=2         corroboration floor       (1=86%, 2=95%, 5=98%)
#   PF_GRANTS_DIR=<dir>     raw CSVs + duckdb         (default ~/Documents/grants)
#   PF_SKIP_DOWNLOAD=1      assume the CSVs are there
#   PF_BMF_CSV=<path>       explicit BMF path, overrides PF_BMF
#
# Writes data-dev/BMF-AUGMENTED-<base>.csv, which every later stage can use as a
# drop-in replacement for the plain BMF.
# ============================================================================
suppressWarnings(suppressMessages({
  library(data.table); library(DBI); library(duckdb); library(npmatch) }))
suppressWarnings(suppressMessages(devtools::load_all(
  Sys.getenv("PFMATCH_DIR", "."), quiet = TRUE)))
setDTthreads(0)

PF   <- Sys.getenv("PFMATCH_DIR", ".")
NPM  <- Sys.getenv("NPMATCH_DIR", "../npmatch")
DIR  <- Sys.getenv("PF_GRANTS_DIR", file.path(path.expand("~"), "Documents", "grants"))
BASE <- Sys.getenv("PF_BMF", "unified")
MINF <- as.integer(Sys.getenv("PF_MIN_FILERS", "2"))
DB   <- file.path(DIR, "schedi_grants.duckdb")
say  <- function(...) cat(sprintf(...), "\n")
hr   <- function() cat(strrep("=", 74), "\n")

BMF_CSV <- switch(BASE,
  active  = file.path(NPM, "data-raw", "bmf_2026_01_processed.csv"),
  unified = file.path(NPM, "data-raw", "bmf_unified_geocoded.csv"),
  stop("PF_BMF must be 'active' or 'unified'"))
if (nzchar(Sys.getenv("PF_BMF_CSV"))) {
  BMF_CSV <- Sys.getenv("PF_BMF_CSV")
  BASE <- tools::file_path_sans_ext(basename(BMF_CSV))
}
if (!file.exists(BMF_CSV)) stop("no BMF at ", BMF_CSV)
say("base BMF: %s", BMF_CSV)
OUT <- Sys.getenv("PF_AUG_OUT", file.path(PF, "data-dev", sprintf("BMF-AUGMENTED-%s.csv", BASE)))

hr(); say("STAGE 1  download"); hr()
if (Sys.getenv("PF_SKIP_DOWNLOAD", "") == "") {
  pf_schedi_download(DIR)
} else say("skipped (PF_SKIP_DOWNLOAD set)")

hr(); say("STAGE 2  DuckDB + alias table"); hr()
if (!file.exists(DB)) pf_schedi_build(DIR, DB) else
  say("using existing %s (delete to rebuild)", basename(DB))
if (!file.exists(DB)) stop("no duckdb at ", DB)

hr(); say("STAGE 3  alias table, min_filers = %d", MINF); hr()
al <- pf_schedi_alias(DB, min_filers = MINF)
say("aliases: %s rows over %s EINs",
    format(nrow(al), big.mark = ","), format(uniqueN(al$ein), big.mark = ","))
print(al[, .(aliases = .N), by = .(filers = cut(n_filers, c(0,1,4,19,Inf),
             labels = c("1","2-4","5-19","20+")))][order(filers)])

hr(); say("STAGE 4  difference against the %s BMF", BASE); hr()
aug <- pf_bmf_augment(BMF_CSV, al, address = "alias")

hr(); say("STAGE 5  write"); hr()
fwrite(aug, OUT)
say("wrote %s (%.0f MB)", OUT, file.size(OUT) / 1e6)
print(aug[, .N, by = row_source])

say("")
say("to match against it:")
say("  ref <- pf_reference('%s', cache = 'data-dev/BMF-REF-AUG-%s.rds')", OUT, BASE)
