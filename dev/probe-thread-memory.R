#!/usr/bin/env Rscript
# ============================================================================
# probe-thread-memory.R -- is the 31 GB cascade peak per-thread churn?
#
# dev/MEMORY-STEPS.log: the 11-pass cascade peaks at 31.07 GB and returns a
# 0.06 GB pair set. Nothing that large is being KEPT, so the peak is transient
# allocation. The worst single pass peaks at 8.75 GB, so it is also not one
# pass -- it is what accumulates across them.
#
# data.table parallelises the blocking joins and allocates per-thread buffers,
# so thread count is the first candidate and the cheapest to test. It is also
# safe to change: dev/DETERMINISM-FINDINGS.md establishes the cascade is
# thread-INDEPENDENT, bit-identical at 1 thread and 7.
#
# If peak falls with threads, setDTthreads() is a shard-count lever costing only
# wall-clock. If it does not, the churn is in the cascade's own accumulation and
# the fix is in npmatch.
#
#   PF_THREADS  data.table threads (default 1)
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(
  Sys.getenv("NPMATCH_DIR", "../npmatch"), quiet = TRUE)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
TH <- as.integer(Sys.getenv("PF_THREADS", "1"))
setDTthreads(TH)
DD <- file.path(PF, "data-dev")
say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
ws <- function() {
  v <- tryCatch(system2("powershell", c("-NoProfile", "-Command",
    sprintf("(Get-Process -Id %d).PeakWorkingSet64", Sys.getpid())),
    stdout = TRUE, stderr = FALSE), error = function(e) NA_character_)
  suppressWarnings(as.numeric(v[length(v)])) / 1e9
}
say("data.table threads: %d", getDTthreads())

ref <- readRDS(file.path(DD, "REF-augmented.rds"))
ref$reference <- pf_add_recovery_keys(ref$reference)
ids <- readRDS(file.path(DD, "SHARD-RSS-IDENTITIES.rds"))
q <- ids[seq_len(500), , drop = FALSE]
query <- pf_add_recovery_keys(npmatch::np_normalize(
  npmatch::np_query(q[q$in_scope, , drop = FALSE], pf_map_grants())))
say("after setup, working set %.2f GB", ws())

PASSES <- c(pf_staged_passes("lean", concat = TRUE), pf_recovery_passes(state = TRUE))
invisible(gc(reset = TRUE, full = TRUE))
t0 <- proc.time()[["elapsed"]]
res <- npmatch::np_cascade(query, ref$reference, config = npmatch::np_config(),
                           method = "hier", passes = PASSES, verbose = FALSE,
                           name_freq = ref$name_freq, token_idf = ref$token_idf,
                           ref_index = ref$ref_index)
el <- proc.time()[["elapsed"]] - t0
rp <- sum(gc()[, "max used"] * c(56, 8)) / 1e9
say("")
say("threads %2d | cascade %6.1f s | cascade peak (R) %6.2f GB | process peak %6.2f GB | %s pairs",
    TH, el, rp, ws(), format(nrow(as.data.frame(attr(res, "pairs"))), big.mark = ","))
f <- file.path(DD, "THREAD-MEMORY.csv")
old <- if (file.exists(f)) fread(f) else NULL
fwrite(rbind(old, data.table(threads = TH, seconds = el, cascade_peak_gb = rp,
                             process_peak_gb = ws()), fill = TRUE), f)
