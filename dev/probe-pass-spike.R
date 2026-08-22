#!/usr/bin/env Rscript
# Which pass spends the 31 GB? reclaim=TRUE (rm + full gc between passes) did
# not move the peak, so it is not garbage accumulating ACROSS passes -- it is
# inside one of them. trace_memory resets R's counters after each pass, so each
# number below is that pass's own high-water mark.
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(Sys.getenv("NPMATCH_DIR", "../npmatch"), quiet = TRUE)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
setDTthreads(0L)
DD <- file.path(PF, "data-dev")
ref <- readRDS(file.path(DD, "REF-augmented.rds"))
ref$reference <- pf_add_recovery_keys(ref$reference)
ids <- readRDS(file.path(DD, "SHARD-RSS-IDENTITIES.rds"))
q <- ids[seq_len(500), , drop = FALSE]
query <- pf_add_recovery_keys(npmatch::np_normalize(
  npmatch::np_query(q[q$in_scope, , drop = FALSE], pf_map_grants())))
PASSES <- c(pf_staged_passes("lean", concat = TRUE), pf_recovery_passes(state = TRUE))
res <- npmatch::np_cascade(query, ref$reference, config = npmatch::np_config(),
                           method = "hier", passes = PASSES, verbose = TRUE,
                           name_freq = ref$name_freq, token_idf = ref$token_idf,
                           ref_index = ref$ref_index, trace_memory = TRUE)
st <- as.data.frame(attr(res, "stages"))
cat("\n"); print(st[, c("pass", "candidates", "peak_gb")], row.names = FALSE)
fwrite(st, file.path(DD, "PASS-SPIKE.csv"))
