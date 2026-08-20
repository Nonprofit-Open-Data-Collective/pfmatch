#!/usr/bin/env Rscript
# PHASE 1, STEP 3 -- match one shard of recipient identities against the BMF.
# Usage: Rscript dev/full-03-shard.R <shard_index>
#
# One process per shard. Each loads the reference bundle itself (~5 GB resident),
# so the worker count is bounded by RAM, not by cores. Batches checkpoint inside
# the shard directory, so a killed worker resumes rather than restarting.
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(library(pfmatch)))
setDTthreads(2L)                       # leave headroom for the other workers

a     <- commandArgs(TRUE)
i     <- as.integer(a[1])
STAGE <- "C:/Users/jlecy/Documents/grants/staging"
BMF   <- "C:/Users/jlecy/Dropbox/00 - URBAN/00-GITHUB/npmatch/data-raw/bmf_2026_01_processed.csv"
CACHE <- "C:/Users/jlecy/Dropbox/00 - URBAN/00-GITHUB/pfmatch/data-dev/BMF-REFERENCE-BUNDLE.rds"
say <- function(...) { cat(sprintf("[shard %02d] ", i), sprintf(...), "\n", sep = ""); flush.console() }

t0 <- proc.time()[["elapsed"]]
r <- readRDS(file.path(STAGE, "shards", sprintf("shard-%02d.rds", i)))
say("identities: %s", format(nrow(r), big.mark = ","))

ref <- pf_reference(BMF, cache = CACHE, verbose = FALSE)
say("reference loaded (%.0f s)", proc.time()[["elapsed"]] - t0)

t1 <- proc.time()[["elapsed"]]
status <- pf_run_batches(
  r, ref,
  dir = file.path(STAGE, "batches", sprintf("shard-%02d", i)),
  batch_size = 25000L, resume = TRUE, verbose = TRUE)
el <- proc.time()[["elapsed"]] - t1

saveRDS(status, file.path(STAGE, "shards", sprintf("status-%02d.rds", i)),
        compress = FALSE)
say("matched %s identities in %.1f min (%.1f s per 1,000)",
    format(nrow(r), big.mark = ","), el / 60, el / nrow(r) * 1000)
print(table(status$status))
say("total %.1f min", (proc.time()[["elapsed"]] - t0) / 60)
