#!/usr/bin/env Rscript
# What is RETAINED across passes? Per-pass peaks rise monotonically even after
# rm + gc(full), and a pass emitting 4 candidates peaks at 14.8 GB, so the cost
# is not the pass's work -- something reachable is growing. `acc` is the only
# thing the loop accumulates. Measure it, and its attributes, per pass.
suppressWarnings(suppressMessages(library(data.table)))
PF <- "."
suppressWarnings(suppressMessages(devtools::load_all("../npmatch", quiet = TRUE)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
setDTthreads(0L)
DD <- file.path(PF, "data-dev")
say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
gb <- function(x) as.numeric(object.size(x))/1e9

ref <- readRDS(file.path(DD, "REF-augmented.rds"))
ref$reference <- pf_add_recovery_keys(ref$reference)
ids <- readRDS(file.path(DD, "SHARD-RSS-IDENTITIES.rds"))
q <- ids[seq_len(500), , drop = FALSE]
query <- pf_add_recovery_keys(npmatch::np_normalize(
  npmatch::np_query(q[q$in_scope, , drop = FALSE], pf_map_grants())))
cfg <- npmatch::np_config()
PASSES <- c(pf_staged_passes("lean", concat = TRUE), pf_recovery_passes(state = TRUE))

# Replicate the cascade loop's first four passes, measuring what it retains.
r <- ref$reference
qq <- query; qq$.id <- as.character(qq$.id)
acc <- list()
say("%-18s %8s %10s %10s %12s", "pass", "cand", "df GB", "acc GB", "df attrs GB")
for (k in 1:4) {
  p <- PASSES[[k]]
  blk <- do.call(npmatch::np_block, c(list(qq, r), p$args, list(ref_index = ref$ref_index)))
  if (!nrow(blk)) { say("%-18s %8s", p$name, "0"); next }
  pr <- npmatch::np_veto(npmatch::np_score(npmatch::np_compare(
    qq, r, cfg, candidates = blk, name_freq = ref$name_freq,
    token_idf = ref$token_idf), cfg, method = "hier"))
  df <- as.data.frame(pr); df$pass <- p$name
  acc[[p$name]] <- df
  # size of the frame's own columns vs everything hanging off it as attributes
  bare <- df; for (a in setdiff(names(attributes(df)), c("names","row.names","class")))
    attr(bare, a) <- NULL
  say("%-18s %8s %10.3f %10.3f %12.3f", p$name, format(nrow(blk), big.mark=","),
      gb(df), gb(acc), gb(df) - gb(bare))
  atl <- attributes(df)
  big <- vapply(atl, function(a) as.numeric(object.size(a))/1e9, numeric(1))
  big <- big[order(-big)]
  say("     attributes: %s", paste(sprintf("%s=%.3f", names(big)[1:min(4,length(big))],
                                           big[1:min(4,length(big))]), collapse = " "))
  rm(blk, pr, df); gc(full = TRUE)
}
