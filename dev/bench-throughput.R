#!/usr/bin/env Rscript
# ============================================================================
# Clean throughput measurement: production code path, full thread count, one
# batch, timed on a quiet machine.
#
# The question this settles: the 5,000-grant benchmark reported ~4,300 s per
# 1,000 identities, flat across all five batches. The documented figure is 33.5
# s per 1,000. Contention and thread limits were offered as the explanation and
# neither was tested. If this reproduces the documented figure, the full run is
# a few hours; if it reproduces 4,300, something structural regressed.
#
#   PF_N=2000       identities to match
#   PF_REFS=plain|augmented|both
#   PF_THREADS=0    0 = all cores
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(library(pfmatch)))
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("-", 78))

TH <- as.integer(Sys.getenv("PF_THREADS", "0"))
setDTthreads(TH)
say("data.table threads: %d of %d", getDTthreads(), parallel::detectCores())

N     <- as.integer(Sys.getenv("PF_N", "2000"))
STAGE <- "C:/Users/jlecy/Documents/grants/staging"
refs  <- c(plain     = "data-dev/BMF-REFERENCE-BUNDLE.rds",
           augmented = "data-dev/BMF-REF-AUG-2026-08-20.rds")
w <- Sys.getenv("PF_REFS", "both"); if (w != "both") refs <- refs[w]

t0 <- proc.time()[["elapsed"]]
prep <- readRDS(file.path(STAGE, "PREPARED-FULL.rds"))
r <- as.data.frame(prep$recipients)
say("prepared identities: %s (load %.0f s)",
    format(nrow(r), big.mark = ","), proc.time()[["elapsed"]] - t0)
set.seed(1)
q <- r[sort(sample(nrow(r), min(N, nrow(r)))), , drop = FALSE]
rm(prep, r); invisible(gc())
say("sampled: %s identities", format(nrow(q), big.mark = ","))

# The 50k run that produced the 33.5 s per 1,000 figure used NINE passes:
# A1-A5, B1, B2, C1, C2. It did not include the D1-acronym and D2-prefix
# recovery passes, which every later timing has silently added via
# pf_recovery_passes(). PF_PASSES=lean reproduces the benchmarked
# configuration; full adds recovery back.
MODE    <- Sys.getenv("PF_PASSES", "full")
PASSES  <- if (MODE == "lean") pf_staged_passes("lean") else
             c(pf_staged_passes("lean"), pf_recovery_passes(state = TRUE))
RECOVER <- MODE != "lean"
say("passes: %s (%d)  recover=%s", MODE, length(PASSES), RECOVER)

for (nm in names(refs)) {
  p <- refs[[nm]]
  if (!file.exists(p)) { say("skip %s", nm); next }
  t1 <- proc.time()[["elapsed"]]
  ref <- readRDS(p)
  say("")
  hr(); say("%s -- %s rows (cache load %.0f s)", toupper(nm),
            format(nrow(ref$reference), big.mark = ","), proc.time()[["elapsed"]] - t1)
  d <- file.path(STAGE, "bench", nm)
  unlink(d, recursive = TRUE); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  t2 <- proc.time()[["elapsed"]]
  log <- utils::capture.output(
    st <- pf_run_batches(q, ref, dir = d, batch_size = nrow(q), passes = PASSES,
                         recover = RECOVER, resume = FALSE, verbose = TRUE))
  el <- proc.time()[["elapsed"]] - t2
  for (l in log) message("    ", l)
  tb <- table(st$status)
  say("%s: %s", toupper(nm), paste(sprintf("%s=%d", names(tb), as.integer(tb)), collapse = "  "))
  say("THROUGHPUT: %.1f s for %s identities = %.1f s per 1,000",
      el, format(nrow(q), big.mark = ","), el / nrow(q) * 1000)
  say("  projected for 3,337,585 identities: %.1f h single process, %.1f h over 10 shards",
      3337585 / 1000 * (el / nrow(q) * 1000) / 3600,
      3337585 / 1000 * (el / nrow(q) * 1000) / 3600 / 10)
  rm(ref, st); invisible(gc())
}
