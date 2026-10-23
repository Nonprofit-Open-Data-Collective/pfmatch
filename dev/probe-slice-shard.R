#!/usr/bin/env Rscript
# A state shard as it would actually run: the slice plus whole-corpus blocking
# statistics, in its own process. The equivalence probe measured all three arms
# in ONE process, so its peaks include the full reference staying resident --
# fine for diffing answers, useless for sizing a shard.
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(devtools::load_all("../npmatch", quiet = TRUE)))
suppressWarnings(suppressMessages(devtools::load_all(".", quiet = TRUE)))
setDTthreads(0L)
DD <- "data-dev"; STATE <- Sys.getenv("PF_STATE", "CA")
say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
ws <- function() { v <- system2("powershell", c("-NoProfile","-Command",
  sprintf("(Get-Process -Id %d).PeakWorkingSet64", Sys.getpid())), stdout = TRUE)
  as.numeric(v[length(v)])/1e9 }

b <- readRDS(file.path(DD, "REF-augmented.rds"))
gdf_base <- b$ref_index$df_base; gdf_concat <- b$ref_index$df_concat
gn <- b$ref_index$n_reference; gnf <- b$name_freq; gti <- b$token_idf
sl <- pf_add_recovery_keys(b$reference[b$reference$state == STATE, , drop = FALSE])
ids <- as.data.frame(readRDS(file.path(DD, "SHARD-RSS-IDENTITIES.rds")))
q <- ids[ids$in_scope & !is.na(ids$recip_state_raw) & ids$recip_state_raw == STATE, ]
q <- q[seq_len(min(500, nrow(q))), , drop = FALSE]
# drop the full reference: a real shard never holds it
rm(b); invisible(gc(full = TRUE))
say("shard holds: %s slice rows + whole-corpus stats | working set %.2f GB",
    format(nrow(sl), big.mark = ","), ws())

ix <- npmatch::np_ref_index(sl)
ix$df_base <- gdf_base; ix$df_concat <- gdf_concat; ix$n_reference <- gn
query <- pf_add_recovery_keys(npmatch::np_normalize(npmatch::np_query(q, pf_map_grants())))
P <- Filter(function(p) p$name %in% c("A2-name-state","A3-name-dba","A4-dba-name",
  "A5-dba-dba","B1-token-state","B2-token-concat","D1-acronym"),
  c(pf_staged_passes("lean", concat = TRUE), pf_recovery_passes(state = TRUE)))
invisible(gc(reset = TRUE, full = TRUE))
t0 <- proc.time()[["elapsed"]]
res <- npmatch::np_cascade(query, sl, config = npmatch::np_config(), method = "hier",
  passes = P, verbose = FALSE, name_freq = gnf, token_idf = gti, ref_index = ix)
el <- proc.time()[["elapsed"]] - t0
say("")
say("SHARD: %s | %.0f s | cascade peak %.2f GB | PROCESS PEAK %.2f GB | %s pairs",
    STATE, el, sum(gc()[, "max used"] * c(56,8))/1e9, ws(),
    format(nrow(as.data.frame(attr(res, "pairs"))), big.mark = ","))
say("  -> %.0f such shards fit in 68 GB", floor(68*0.85/ws()))
