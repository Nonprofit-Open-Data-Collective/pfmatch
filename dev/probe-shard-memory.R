#!/usr/bin/env Rscript
# ============================================================================
# probe-shard-memory.R -- how many shards fit in RAM?
#
# The Phase 1 schedule assumes "up to ~12x on 24 cores", one process per shard.
# Every process holds its own copy of the normalized reference bundle, so the
# shard count is bounded by memory, not by cores. Nothing has measured the
# resident size of the bundle, only the compressed file. This does.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
setDTthreads(0L)
say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
DD <- file.path(PF, "data-dev")
RAM <- 68.1  # GB, this machine

for (f in c("REF-active.rds", "REF-augmented.rds")) {
  p <- file.path(DD, f)
  invisible(gc(reset = TRUE))
  b <- readRDS(p)
  sz <- sum(vapply(b, function(x) as.numeric(object.size(x)), numeric(1))) / 1e9
  refsz <- as.numeric(object.size(b$reference)) / 1e9
  peak <- sum(gc()[, "max used"] * c(8, 8)) / 1e9
  say("%-20s disk %5.2f GB | resident %5.2f GB (reference %5.2f) | R peak %5.2f GB",
      f, file.size(p) / 1e9, sz, refsz, peak)
  say("    components: %s", paste(sprintf("%s=%.2f", names(b),
      vapply(b, function(x) as.numeric(object.size(x)) / 1e9, numeric(1))), collapse = " "))
  # A shard needs the bundle plus working set. The 1k profile peaked at ~14 GB
  # (active) and ~26 GB cumulative (augmented) inside one process.
  for (work in c(2, 4, 8)) {
    n <- floor((RAM * 0.85) / (sz + work))
    say("    at %2.0f GB working set -> %d concurrent shards fit in %.0f GB RAM",
        work, n, RAM)
  }
  rm(b); invisible(gc())
}
