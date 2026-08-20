#!/usr/bin/env Rscript
# ============================================================================
# probe-unified-bmf.R -- pfmatch matches against the ACTIVE BMF (1.92M rows).
# npmatch also ships the UNIFIED file (active + inactive). Two questions before
# building the Schedule I augmentation on top of the wrong base:
#
#   1. How much bigger is unified, and how many of the NO tier's recipients live
#      only in the inactive part?
#   2. The Schedule I evaluation found 25.5% of alias EINs absent from the active
#      BMF. Are they revoked organizations that the unified file contains?
#
# If the answer to either is "a lot", the augmentation should be built on the
# unified file, and some of the NO tier is a vintage problem rather than a name
# problem.
# ============================================================================
suppressWarnings(suppressMessages({ library(data.table); library(DBI); library(duckdb) }))
setDTthreads(0)
PF  <- Sys.getenv("PFMATCH_DIR", ".")
NPM <- Sys.getenv("NPMATCH_DIR", "../npmatch")
DIR <- Sys.getenv("PF_GRANTS_DIR", file.path(path.expand("~"), "Documents", "grants"))
say <- function(...) cat(sprintf(...), "\n")
ein9 <- function(x) { x <- gsub("[^0-9]", "", as.character(x)); x[nchar(x) != 9] <- NA; x }

ACT <- file.path(NPM, "data-raw", "bmf_2026_01_processed.csv")
UNI <- file.path(NPM, "data-raw", "bmf_unified_geocoded.csv")

say("reading active BMF ...")
a <- fread(ACT, select = "ein", colClasses = "character", showProgress = FALSE)
act <- unique(ein9(a$ein)); act <- act[!is.na(act)]
say("  active   : %s distinct EINs", format(length(act), big.mark = ","))

say("reading unified BMF ...")
hdr <- names(fread(UNI, nrows = 0L))
ecol <- intersect(c("ein", "EIN", "ein2", "EIN2"), hdr)[1]
say("  columns  : %d ; EIN column = %s", length(hdr), ecol)
u <- fread(UNI, select = ecol, colClasses = "character", showProgress = FALSE)
uni <- unique(ein9(u[[1]])); uni <- uni[!is.na(uni)]
say("  unified  : %s distinct EINs", format(length(uni), big.mark = ","))
say("  inactive-only (in unified, not active): %s",
    format(length(setdiff(uni, act)), big.mark = ","))

## ---- 1. does the unified file reach the NO tier? ---------------------------
say(""); say("=== NO-tier recipients: does unified help? ===")
r <- fread(file.path(PF, "data-dev", "PF-MATCH-REPORT-50k.csv"),
           colClasses = "character", na.strings = NULL, showProgress = FALSE)
say("benchmark: %s grants", format(nrow(r), big.mark = ","))
print(r[, .N, by = status][order(-N)])

## ---- 2. where do the Schedule I alias EINs live? ---------------------------
say(""); say("=== Schedule I alias EINs vs the two BMF vintages ===")
con <- dbConnect(duckdb::duckdb(), file.path(DIR, "schedi.duckdb"), read_only = TRUE)
al <- as.data.table(dbGetQuery(con,
  "SELECT DISTINCT ein FROM alias WHERE ein IS NOT NULL"))
dbDisconnect(con, shutdown = TRUE)
al[, e := ein9(ein)]
al <- al[!is.na(e)]
say("distinct alias EINs        : %s", format(nrow(al), big.mark = ","))
say("  in ACTIVE BMF            : %5.1f%%", 100 * mean(al$e %in% act))
say("  in UNIFIED BMF           : %5.1f%%", 100 * mean(al$e %in% uni))
say("  in neither               : %5.1f%%", 100 * mean(!al$e %in% uni))
say("  recovered by unified     : %s EINs",
    format(sum(!al$e %in% act & al$e %in% uni), big.mark = ","))

## ---- 3. how many alias rows would attach to each base? ---------------------
say(""); say("=== implication for the augmentation ===")
say("aliases attachable to active BMF  : %5.1f%% of distinct EINs", 100 * mean(al$e %in% act))
say("aliases attachable to unified BMF : %5.1f%% of distinct EINs", 100 * mean(al$e %in% uni))
