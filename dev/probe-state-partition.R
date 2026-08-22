#!/usr/bin/env Rscript
# ============================================================================
# probe-state-partition.R -- does slicing the reference by state shrink the peak?
#
# Peak working set is ~31 GB regardless of threads, of batch size, of gc, and of
# the reference-row collapse. The one thing not yet varied is the SIZE of the
# reference the cascade sees. Seven of eleven passes already block on state, so
# a state-sliced reference is lossless for them -- a CA query can only match a
# CA reference row under those passes, whether or not the other 89% is present.
#
# Held constant: the same CA queries, the same seven state-blocked passes.
# Varied: full 3.88M-row reference vs the 410,127-row CA slice.
#
#   PF_SLICE  full | CA   (default full)
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- "."
suppressWarnings(suppressMessages(devtools::load_all("../npmatch", quiet = TRUE)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
setDTthreads(0L)
DD <- file.path(PF, "data-dev")
SLICE <- Sys.getenv("PF_SLICE", "full")
say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
ws <- function() {
  v <- tryCatch(system2("powershell", c("-NoProfile","-Command",
    sprintf("(Get-Process -Id %d).PeakWorkingSet64", Sys.getpid())),
    stdout = TRUE, stderr = FALSE), error = function(e) NA_character_)
  suppressWarnings(as.numeric(v[length(v)]))/1e9
}
tick <- function() proc.time()[["elapsed"]]

b <- readRDS(file.path(DD, "REF-augmented.rds"))
if (SLICE != "full") {
  keep <- which(b$reference$state == SLICE)
  b$reference <- b$reference[keep, , drop = FALSE]
  # every derived structure is a function of the reference, so all must be rebuilt
  b$name_freq <- npmatch::np_name_freq(b$reference$name_key)
  b$token_idf <- npmatch::np_token_idf(b$reference$name_key)
  b$ref_index <- npmatch::np_ref_index(b$reference)
}
b$reference <- pf_add_recovery_keys(b$reference)
say("reference: %s rows (slice = %s) | working set %.2f GB",
    format(nrow(b$reference), big.mark = ","), SLICE, ws())

ids <- as.data.frame(readRDS(file.path(DD, "SHARD-RSS-IDENTITIES.rds")))
ca <- ids[ids$in_scope & !is.na(ids$recip_state_raw) & ids$recip_state_raw == "CA", , drop = FALSE]
q <- ca[seq_len(min(500, nrow(ca))), , drop = FALSE]
say("queries: %d CA identities (of %d available)", nrow(q), nrow(ca))

# only the passes that block on state; a slice cannot serve the cross-state ones
ALL <- c(pf_staged_passes("lean", concat = TRUE), pf_recovery_passes(state = TRUE))
STATE_PASSES <- c("A2-name-state","A3-name-dba","A4-dba-name","A5-dba-dba",
                  "B1-token-state","B2-token-concat","D1-acronym")
P <- ALL[vapply(ALL, function(p) p$name %in% STATE_PASSES, logical(1))]
say("passes: %d state-blocked (%s)", length(P),
    paste(vapply(P, function(p) p$name, character(1)), collapse = ", "))

query <- pf_add_recovery_keys(npmatch::np_normalize(
  npmatch::np_query(q, pf_map_grants())))
invisible(gc(reset = TRUE, full = TRUE))
t0 <- tick()
res <- npmatch::np_cascade(query, b$reference, config = npmatch::np_config(),
                           method = "hier", passes = P, verbose = FALSE,
                           name_freq = b$name_freq, token_idf = b$token_idf,
                           ref_index = b$ref_index)
el <- tick() - t0
rp <- sum(gc()[, "max used"] * c(56, 8))/1e9
pr <- as.data.frame(attr(res, "pairs"))
tb <- table(factor(as.character(as.data.frame(res)$tier), c("YES","MAYBE","NO")))
say("")
say("slice %-4s | %6.1f s | cascade peak %6.2f GB | process peak %6.2f GB | %s pairs | YES %d MAYBE %d NO %d",
    SLICE, el, rp, ws(), format(nrow(pr), big.mark=","), tb[["YES"]], tb[["MAYBE"]], tb[["NO"]])
saveRDS(as.data.frame(res)[order(as.data.frame(res)$.id), ],
        file.path(DD, sprintf("STATE-PARTITION-%s.rds", SLICE)))
f <- file.path(DD, "STATE-PARTITION.csv")
old <- if (file.exists(f)) fread(f) else NULL
fwrite(rbind(old, data.table(slice = SLICE, ref_rows = nrow(b$reference), seconds = el,
        cascade_peak_gb = rp, process_peak_gb = ws(), pairs = nrow(pr),
        yes = tb[["YES"]], maybe = tb[["MAYBE"]], no = tb[["NO"]]), fill = TRUE), f)
