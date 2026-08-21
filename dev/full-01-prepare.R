#!/usr/bin/env Rscript
# ============================================================================
# PHASE 1, STEP 1 -- ingest and dedup the full 990-PF grant file.
#
# The point of this step is the dedup ratio. At 33.5 s per 1,000 grants the
# naive cost of 12,559,051 grants is 117 hours single-threaded; the schedule for
# everything after this depends on how far dedup collapses the file and how many
# shards the machine can carry.
#
# Staging is written to ~/Documents/grants/staging -- outside Dropbox and
# outside the package repo, because these are multi-GB derived artefacts.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(library(pfmatch)))
setDTthreads(0L)

SRC   <- "C:/Users/jlecy/Documents/grants/2025_08_29_All_Years_990PFPart14Grants3A.csv"
STAGE <- "C:/Users/jlecy/Documents/grants/staging"
dir.create(STAGE, showWarnings = FALSE, recursive = TRUE)
say <- function(...) message(sprintf(...))   # stderr is unbuffered
hr  <- function() message(strrep("-", 78))
tick <- function() proc.time()[["elapsed"]]

hr(); say("PHASE 1.1 -- INGEST"); hr()
t0 <- tick()
g <- fread(SRC, colClasses = "character", showProgress = FALSE, na.strings = NULL)
say("read %s grants x %d columns in %.0f s",
    format(nrow(g), big.mark = ","), ncol(g), tick() - t0)
say("memory held by the grant table: %.1f GB", as.numeric(object.size(g)) / 2^30)
say("tax years present: %s - %s", min(g$TAXYEAR, na.rm = TRUE), max(g$TAXYEAR, na.rm = TRUE))
say("distinct filing foundations: %s", format(uniqueN(g$FILEREIN), big.mark = ","))
py <- g[, .N, by = .(FILEREIN, TAXYEAR)]
say("median grants per filer-year: %.0f   (the dev samples had 1)", median(py$N))
say("filers with >=5 grants in a year: %.0f%%", 100 * mean(py$N >= 5))

# grant_id must be unique across the whole file, not within a source file
g[, grant_id := sprintf("G%09d", .I)]

hr(); say("PHASE 1.2 -- PREPARE"); hr()
t1 <- tick()
# Exact dedup already delivers 3.72x on the full file and completes in minutes.
# The fuzzy pass ran 12.3 hours without finishing on this file: its cost is the
# sum of squared block sizes, and mean block size rises from 7.9 at 100k rows to
# 74 here. Fuzzy adds roughly 10-15% more collapse on top, which is not worth
# blocking the pipeline for. PF_DEDUP=fuzzy re-enables it now that pf_dedup()
# reports progress and sub-blocks oversized blocks instead of dropping them.
DEDUP <- Sys.getenv("PF_DEDUP", "exact")
say("dedup method: %s", DEDUP)
prep <- pf_prepare(g, dedup = DEDUP, verbose = TRUE)
say("prepare + dedup took %.0f s (%.1f min)", tick() - t1, (tick() - t1) / 60)

gp <- as.data.table(prep$grants)
say("")
say("prepared rows: %s", format(nrow(gp), big.mark = ","))
idcol <- intersect(c("identity_id", "dedup_id", "recipient_id"), names(gp))[1]
if (is.na(idcol)) {
  say("NOTE: no identity column found; columns are:")
  say("  %s", paste(names(gp), collapse = ", "))
} else {
  n_id <- uniqueN(gp[[idcol]])
  say("distinct recipient identities: %s", format(n_id, big.mark = ","))
  say("COLLAPSE RATIO: %.2fx   (the 100k sample measured 1.8x)", nrow(gp) / n_id)
  say("")
  say("Projected match cost at 33.5 s per 1,000 identities:")
  say("  single process : %.1f hours", n_id / 1000 * 33.5 / 3600)
  for (w in c(6, 10, 12)) say("  %2d workers     : %.1f hours", w, n_id / 1000 * 33.5 / 3600 / w)
}

hr(); say("PHASE 1.3 -- STAGE"); hr()
t2 <- tick()
saveRDS(prep, file.path(STAGE, "PREPARED-FULL.rds"), compress = FALSE)
say("wrote %s (%.1f GB) in %.0f s", file.path(STAGE, "PREPARED-FULL.rds"),
    file.size(file.path(STAGE, "PREPARED-FULL.rds")) / 2^30, tick() - t2)
say("")
say("TOTAL PHASE 1 PREPARE: %.1f min", (tick() - t0) / 60)
