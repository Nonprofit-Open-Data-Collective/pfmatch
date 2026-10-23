#!/usr/bin/env Rscript
# ============================================================================
# build-ref-collapsed.R -- the collapsed augmented reference, as a candidate.
#
# Writes data-dev/REF-augmented-collapsed.rds so dev/probe-shard-rss.R can run
# the SAME rung against it and give a direct before/after on the two numbers
# that cap Phase 1 at one shard: peak working set and seconds per 1,000.
#
# This does not adopt anything. dev/REF-COLLAPSE.log prices the reference; the
# rung prices the shard; the 1k benchmark prices the answers. All three before
# the plan changes.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(
  Sys.getenv("NPMATCH_DIR", "../npmatch"), quiet = TRUE)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
setDTthreads(0L)
DD  <- file.path(PF, "data-dev")
say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
tick <- function() proc.time()[["elapsed"]]

t0 <- tick(); b <- readRDS(file.path(DD, "REF-augmented.rds"))
say("loaded REF-augmented.rds: %s rows in %.0f s",
    format(nrow(b$reference), big.mark = ","), tick() - t0)

cl <- pf_collapse_reference(b, rebuild = TRUE, verbose = TRUE)

f <- file.path(DD, "REF-augmented-collapsed.rds")
t0 <- tick(); saveRDS(cl, f, compress = FALSE); say("wrote %s (%.2f GB) in %.0f s",
                                                    basename(f), file.size(f)/1e9, tick() - t0)
fwrite(as.data.table(cl$collapse[c("rows_before","rows_after","groups_multi",
                                   "eins_merged","max_group")]),
       file.path(DD, "REF-COLLAPSE-BUILD.csv"))
say("members table: %s rows", format(nrow(cl$members), big.mark = ","))
