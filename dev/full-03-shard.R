#!/usr/bin/env Rscript
# PHASE 1, STEP 3 -- match one shard of recipient identities against the
# reference. Usage: Rscript dev/full-03-shard.R <shard_index>
#
# The reference defaults to the AUGMENTED unified BMF: the NCCS unified file
# (one row per EIN, 1989-present, so it carries organisations the monthly
# snapshot has dropped) plus the Schedule I alias rows gated on corroboration.
# Running against the plain monthly BMF forfeits both, which is worth several
# points of recall -- see dev/CODE-AUDIT.md sections 4-5.
#
#   PF_REF_CSV    path to the reference CSV
#   PF_REF_CACHE  path to the reference bundle cache (.rds)
#
# One process per shard. Each loads the reference itself (~6 GB resident), so
# the worker count is bounded by RAM, not by cores. Batches checkpoint inside
# the shard directory, so a killed worker resumes rather than restarting.
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(library(pfmatch)))
setDTthreads(2L)                       # leave headroom for the other workers

a     <- commandArgs(TRUE)
i     <- as.integer(a[1])
STAGE <- "C:/Users/jlecy/Documents/grants/staging"
PF    <- "C:/Users/jlecy/Dropbox/00 - URBAN/00-GITHUB/pfmatch"
REF   <- Sys.getenv("PF_REF_CSV",
           file.path(PF, "data-dev", "BMF-AUGMENTED-bmf_unified_geocoded_2026-08-20.csv"))
CACHE <- Sys.getenv("PF_REF_CACHE",
           file.path(PF, "data-dev", "BMF-REF-AUG-2026-08-20.rds"))
say <- function(...) { cat(sprintf("[shard %02d] ", i), sprintf(...), "\n", sep = ""); flush.console() }

stopifnot(file.exists(REF) || file.exists(CACHE))
t0 <- proc.time()[["elapsed"]]
r <- readRDS(file.path(STAGE, "shards", sprintf("shard-%02d.rds", i)))
say("identities: %s", format(nrow(r), big.mark = ","))
say("reference : %s", basename(if (file.exists(CACHE)) CACHE else REF))

ref <- pf_reference(REF, cache = CACHE, verbose = FALSE)
say("reference loaded, %s rows (%.0f s)",
    format(nrow(ref$reference), big.mark = ","), proc.time()[["elapsed"]] - t0)

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
