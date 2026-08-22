#!/usr/bin/env Rscript
# ============================================================================
# probe-shard-rss.R -- how many shards actually fit in RAM?
#
# THE QUESTION
#
# The Phase 1 schedule says "up to ~12x on 24 cores, one process per shard".
# That is a core count. Every shard process holds its own reference bundle AND
# its own working set, and nothing has measured either at the batch size Phase 1
# will run. dev/SHARD-MEMORY.log measured the bundle alone (4.21 GB augmented) and
# found it is the small part: the 1k profile peaked far above it. So the shard
# count is bounded by the working set, and the working set is unmeasured.
#
# METHOD, AND WHY IT IS SHAPED THIS WAY
#
# * Peak WORKING SET, not gc(). gc()'s "max used" counts what R's allocator
#   tracked; the number that decides whether twelve processes fit is what the OS
#   charged the process. Read from Win32 PeakWorkingSet64.
# * One process per rung. PeakWorkingSet64 is cumulative over a process
#   lifetime, so a ladder measured inside one process reports the largest rung
#   four times. The driver re-launches for each.
# * A ladder, not a point. Working set = fixed (reference, keys, index) + slope
#   (candidate pairs, which scale with the batch). Two components with different
#   scaling cannot be separated by one measurement, and it is the slope that
#   decides whether batch_size is a lever.
# * Production config: augmented reference, 11 passes, dyads wired. Measuring a
#   cheaper configuration would answer a question nobody is going to run.
# * Ascending rungs. If the largest rung exhausts memory, every smaller one has
#   already been recorded -- and "it did not fit" is itself the finding.
#
#   PF_N      identities in the single batch (the rung)
#   PF_REF    active | augmented   (default augmented: the Phase 1 target)
#   PF_PREP   cached identity frame; built on first use
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(
  Sys.getenv("NPMATCH_DIR", "../npmatch"), quiet = TRUE)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
setDTthreads(0L)

DD   <- file.path(PF, "data-dev")
N    <- as.integer(Sys.getenv("PF_N", "2000"))
WREF <- Sys.getenv("PF_REF", "augmented")
PREP <- Sys.getenv("PF_PREP", file.path(DD, "SHARD-RSS-IDENTITIES.rds"))
OUT  <- file.path(DD, "SHARD-RSS.csv")
say  <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr   <- function() cat(strrep("=", 78), "\n")
tick <- function() proc.time()[["elapsed"]]

# True peak working set for this process, in GB. R has no portable accessor --
# memory.size() was retired in 4.2 -- so ask Windows directly.
peak_ws <- function() {
  v <- tryCatch(system2("powershell",
    c("-NoProfile", "-Command",
      sprintf("(Get-Process -Id %d).PeakWorkingSet64", Sys.getpid())),
    stdout = TRUE, stderr = FALSE), error = function(e) NA_character_)
  v <- suppressWarnings(as.numeric(v[length(v)]))
  if (length(v) && is.finite(v)) v / 1e9 else NA_real_
}
gc_peak <- function() sum(gc()[, "max used"] * c(56, 8)) / 1e9

hr(); say("SHARD RSS -- %s reference, batch of %s identities",
          WREF, format(N, big.mark = ",")); hr()
say("baseline working set before anything is loaded: %.2f GB", peak_ws())

## ---- identities, prepared once and cached ---------------------------------
# The cache build MUST be its own process. PeakWorkingSet is sticky, and
# pf_prepare()'s fuzzy dedup over 100,000 rows peaks high enough to dominate the
# shard measurement that follows it -- which is exactly what happened on the
# first ladder: rung 2,000 built the cache in-process and reported 38.4 GB
# against rung 8,000's 25.5 GB, an ordering that has no physical explanation.
# Build it with PF_N=prep, then measure.
if (!file.exists(PREP) && !identical(Sys.getenv("PF_N"), "prep"))
  stop(sprintf(paste0(
    "no cached identity frame at %s.\n",
    "  Build it in its own process first:  PF_N=prep Rscript dev/probe-shard-rss.R\n",
    "  Building it here would contaminate this rung's peak working set."), PREP),
    call. = FALSE)
if (!file.exists(PREP)) {
  say("preparing inputs/100k_grants.csv (once; cached to %s) ...", basename(PREP))
  t0 <- tick()
  prep <- pf_prepare(file.path(PF, "inputs"), pattern = "^100k_grants[.]csv$",
                     dedup = "fuzzy", verbose = FALSE)
  say("  %s rows -> %s identities (%.3fx) in %.0f s",
      format(nrow(prep$grants), big.mark = ","),
      format(nrow(prep$recipients), big.mark = ","),
      sum(prep$grants$in_scope) / nrow(prep$recipients), tick() - t0)
  saveRDS(prep$recipients, PREP, compress = FALSE)
  say("cache built; peak working set of the BUILD was %.2f GB. Exiting so the",
      peak_ws())
  say("measurement runs in a clean process.")
  rm(prep); invisible(gc())
  quit(save = "no")
}
ids <- readRDS(PREP)
if (N > nrow(ids))
  stop(sprintf("asked for %d identities, only %d available", N, nrow(ids)))
q <- ids[seq_len(N), , drop = FALSE]
say("queries: %s of %s available", format(N, big.mark = ","),
    format(nrow(ids), big.mark = ","))

## ---- the shard ------------------------------------------------------------
reffile <- switch(WREF, active = "REF-active.rds", augmented = "REF-augmented.rds",
                  collapsed = "REF-augmented-collapsed.rds")
t0 <- tick(); ref <- readRDS(file.path(DD, reffile)); t_load <- tick() - t0
ws_ref <- peak_ws()
say("reference: %s rows, loaded in %.0f s | working set now %.2f GB",
    format(nrow(ref$reference), big.mark = ","), t_load, ws_ref)

DY <- readRDS(file.path(DD, "PF-DYADS-UNIFIED.rds"))
ws_dy <- peak_ws()
say("dyads: %s pairs | working set now %.2f GB (+%.2f)",
    format(nrow(DY), big.mark = ","), ws_dy, ws_dy - ws_ref)

CK <- file.path(DD, sprintf("batches-rss-%s-%d", WREF, N))
unlink(CK, recursive = TRUE)
PASSES <- c(pf_staged_passes("lean", concat = TRUE), pf_recovery_passes(state = TRUE))

say(""); say("running ONE batch of %s at the production config ...", format(N, big.mark = ","))
t0 <- tick()
st <- pf_run_batches(q, ref, dir = CK, batch_size = N, passes = PASSES,
                     recover = TRUE, dyads = DY,
                     dyad_config = pf_dyad_config(), verbose = TRUE)
el <- tick() - t0
ws_peak <- peak_ws()
gcp <- gc_peak()

tb <- table(factor(st$status, pf_status_levels()))
say("")
say("elapsed %.0f s | %.0f s per 1,000 identities", el, 1000 * el / N)
say("YES %d MAYBE %d NO %d OOS %d", tb[["YES"]], tb[["MAYBE"]], tb[["NO"]], tb[["OOS"]])
say("")
say("PEAK WORKING SET .......... %.2f GB", ws_peak)
say("  of which reference load   %.2f GB", ws_ref)
say("  gc() max used (for scale) %.2f GB", gcp)

row <- data.frame(ref = WREF, n = N, ref_rows = nrow(ref$reference),
                  elapsed_s = el, s_per_1k = 1000 * el / N,
                  ws_after_ref = ws_ref, ws_after_dyads = ws_dy,
                  ws_peak = ws_peak, gc_peak = gcp,
                  yes = tb[["YES"]], maybe = tb[["MAYBE"]], no = tb[["NO"]],
                  stringsAsFactors = FALSE)
old <- if (file.exists(OUT)) fread(OUT) else NULL
fwrite(rbind(old, as.data.table(row), fill = TRUE), OUT)
say("appended to %s", basename(OUT))

## ---- what it means, recomputed from every rung so far ---------------------
r <- fread(OUT)[ref == WREF]
if (nrow(r) >= 2L) {
  hr(); say("SHARD BUDGET, fitted over %d rungs", nrow(r)); hr()
  fit <- stats::lm(ws_peak ~ n, data = r)
  fixed <- unname(coef(fit)[1]); slope <- unname(coef(fit)[2])
  say("peak working set = %.2f GB fixed + %.3f GB per 1,000 identities",
      fixed, slope * 1000)
  say("")
  say("%-14s %12s %14s %10s", "batch_size", "predicted GB", "shards in 68 GB", "note")
  for (bs in c(5000, 10000, 25000, 50000)) {
    gb <- fixed + slope * bs
    say("%-14s %12.1f %14d %10s", format(bs, big.mark = ","), gb,
        max(0L, floor(68.1 * 0.85 / gb)),
        if (bs == 25000) "<- the default" else "")
  }
  say("")
  say("Smaller batches buy shards and cost amortization (REFIT-1K-FINDINGS 4:")
  say("81 s/1k at 4,733 against 228 at 978). The two trade against each other and")
  say("this is the table that prices the trade.")
}
