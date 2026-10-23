#!/usr/bin/env Rscript
# ============================================================================
# probe-memory-steps.R -- where the ~33 GB actually goes.
#
# dev/SHARD-AND-COLLAPSE-FINDINGS.md established that a shard peaks at ~37 GB
# and that this is FLAT in batch size, so the cost is fixed per process rather
# than proportional to the work. It did not establish which step spends it, and
# "reduce the fixed cost" is not actionable without that.
#
# METHOD
#
# * Per-step R-level peak via gc(reset = TRUE) before each step and
#   gc()[, "max used"] after. Unlike PeakWorkingSet64, R's counters CAN be
#   reset, which is the only way to attribute rather than accumulate.
# * PeakWorkingSet64 alongside it as the ground truth on the total, because R's
#   counters miss allocations data.table makes outside the R heap.
# * Each blocking pass run ALONE, so its cost is its own rather than the running
#   union's. Then the full 11-pass run, so the difference between the sum of the
#   parts and the whole is visible -- that difference IS the union.
# * n = 500. Justified by measurement, not convenience: peak working set moved
#   0.6 GB between 2,000 and 8,000 identities, so the fixed cost is fully
#   present at any small n and the probe costs minutes instead of hours.
#
#   PF_REF   active | augmented   (default augmented, the Phase 1 target)
#   PF_N     queries (default 500)
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(
  Sys.getenv("NPMATCH_DIR", "../npmatch"), quiet = TRUE)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
setDTthreads(0L)

DD  <- file.path(PF, "data-dev")
W   <- Sys.getenv("PF_REF", "augmented")
N   <- as.integer(Sys.getenv("PF_N", "500"))
say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function(t = NULL) { cat(strrep("=", 78), "\n")
                            if (!is.null(t)) { cat(t, "\n"); cat(strrep("=", 78), "\n") } }
tick <- function() proc.time()[["elapsed"]]

ws <- function() {
  v <- tryCatch(system2("powershell", c("-NoProfile", "-Command",
    sprintf("(Get-Process -Id %d).PeakWorkingSet64", Sys.getpid())),
    stdout = TRUE, stderr = FALSE), error = function(e) NA_character_)
  v <- suppressWarnings(as.numeric(v[length(v)]))
  if (length(v) && is.finite(v)) v / 1e9 else NA_real_
}
# R's own high-water mark, resettable, so each step reports ITS cost
reset <- function() invisible(gc(reset = TRUE, full = TRUE))
rpeak <- function() sum(gc()[, "max used"] * c(56, 8)) / 1e9
gbs   <- function(x) as.numeric(utils::object.size(x)) / 1e9

STEPS <- list()
step <- function(label, expr, note = "") {
  reset(); t0 <- tick()
  v <- force(expr)
  el <- tick() - t0; rp <- rpeak(); w <- ws()
  STEPS[[length(STEPS) + 1L]] <<- data.frame(
    step = label, seconds = el, r_peak_gb = rp, ws_cum_gb = w, note = note,
    stringsAsFactors = FALSE)
  say("  %-38s %7.1f s | step peak %6.2f GB | cumulative WS %6.2f GB %s",
      label, el, rp, w, note)
  v
}

hr(sprintf("MEMORY BY STEP -- %s reference, %d queries", W, N))
say("  %-38s %7s   %16s   %16s", "step", "seconds", "step peak (R)", "cumulative (OS)")
say("%s", strrep("-", 78))

## ---- 1. load ---------------------------------------------------------------
reffile <- switch(W, active = "REF-active.rds", augmented = "REF-augmented.rds",
                  collapsed = "REF-augmented-collapsed.rds")
ref <- step("1. readRDS(reference bundle)", readRDS(file.path(DD, reffile)))
say("")
say("  reference rows: %s", format(nrow(ref$reference), big.mark = ","))
say("  resident sizes: reference %.2f GB | ref_index %.2f GB | name_freq %.2f GB | token_idf %.2f GB",
    gbs(ref$reference), gbs(ref$ref_index), gbs(ref$name_freq), gbs(ref$token_idf))
say("  reference columns: %d", ncol(ref$reference))
say("")

## ---- 2. reference-side preprocessing --------------------------------------
ref$reference <- step("2. pf_add_recovery_keys(reference)",
                      pf_add_recovery_keys(ref$reference),
                      "(stage-4 acro/prefix keys)")

## ---- 3. queries ------------------------------------------------------------
ids <- readRDS(file.path(DD, "SHARD-RSS-IDENTITIES.rds"))
q <- ids[seq_len(min(N, nrow(ids))), , drop = FALSE]
query <- step("3. np_query + normalize + keys",
              pf_add_recovery_keys(npmatch::np_normalize(
                npmatch::np_query(q[q$in_scope, , drop = FALSE], pf_map_grants()))),
              sprintf("(%d queries)", sum(q$in_scope)))

## ---- 4. every pass, alone --------------------------------------------------
hr("EACH BLOCKING PASS, RUN ALONE")
PASSES <- c(pf_staged_passes("lean", concat = TRUE), pf_recovery_passes(state = TRUE))
cfg <- npmatch::np_config()
say("  %-38s %7s   %16s   %10s", "pass", "seconds", "step peak (R)", "candidates")
say("%s", strrep("-", 78))
per <- list()
for (k in seq_along(PASSES)) {
  nm <- PASSES[[k]]$name %||% sprintf("pass %d", k)
  reset(); t0 <- tick()
  r1 <- try(suppressWarnings(npmatch::np_cascade(
    query, ref$reference, config = cfg, method = "hier", passes = PASSES[k],
    verbose = FALSE, name_freq = ref$name_freq, token_idf = ref$token_idf,
    ref_index = ref$ref_index)), silent = TRUE)
  el <- tick() - t0; rp <- rpeak()
  nc <- if (inherits(r1, "try-error")) NA_integer_ else
          nrow(as.data.frame(attr(r1, "pairs")))
  say("  %-38s %7.1f s | %13.2f GB | %10s", nm, el, rp,
      if (is.na(nc)) "FAILED" else format(nc, big.mark = ","))
  per[[k]] <- data.frame(pass = nm, seconds = el, r_peak_gb = rp,
                         candidates = nc, stringsAsFactors = FALSE)
  rm(r1); invisible(gc())
}
per <- rbindlist(per)

## ---- 5. the whole cascade --------------------------------------------------
hr("THE FULL CASCADE, ALL 11 PASSES")
reset(); t0 <- tick()
full <- npmatch::np_cascade(query, ref$reference, config = cfg, method = "hier",
                            passes = PASSES, verbose = FALSE,
                            name_freq = ref$name_freq, token_idf = ref$token_idf,
                            ref_index = ref$ref_index)
el <- tick() - t0
rp <- rpeak()
npairs <- nrow(as.data.frame(attr(full, "pairs")))
say("  full cascade  %7.1f s | step peak %6.2f GB | %s candidates in the union",
    el, rp, format(npairs, big.mark = ","))
say("  pairs attribute resident: %.2f GB", gbs(attr(full, "pairs")))
say("")
say("  sum of the parts    %6.2f GB   (worst single pass %.2f GB: %s)",
    sum(per$r_peak_gb), max(per$r_peak_gb), per$pass[which.max(per$r_peak_gb)])
say("  the whole           %6.2f GB", rp)
say("  candidates: sum of parts %s vs union %s (%.2fx dedup across passes)",
    format(sum(per$candidates, na.rm = TRUE), big.mark = ","),
    format(npairs, big.mark = ","),
    sum(per$candidates, na.rm = TRUE) / max(1, npairs))
say("")
say("  FINAL cumulative working set: %.2f GB", ws())

fwrite(rbindlist(STEPS), file.path(DD, sprintf("MEMORY-STEPS-%s.csv", W)))
fwrite(per, file.path(DD, sprintf("MEMORY-PASSES-%s.csv", W)))
say("wrote data-dev/MEMORY-STEPS-%s.csv and MEMORY-PASSES-%s.csv", W, W)
