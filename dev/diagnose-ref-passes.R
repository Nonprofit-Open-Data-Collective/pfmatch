#!/usr/bin/env Rscript
# Per-pass candidate counts and timings, plain reference vs augmented, on a
# small fixed query set.
#
# npmatch's cascade logs with cat(), which R buffers when stdout is redirected,
# so the log of a long run only appears at exit. capture.output() collects it
# and message() re-emits it on stderr, which is unbuffered -- the log stays live
# and a stalled run can be told from a slow one.
#
#   PF_N=100      queries
#   PF_REFS=both|plain|augmented
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(library(pfmatch)))
setDTthreads(6L)
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("-", 78))

N    <- as.integer(Sys.getenv("PF_N", "100"))
WHICH <- Sys.getenv("PF_REFS", "both")
refs <- c(plain     = "data-dev/BMF-REFERENCE-BUNDLE.rds",
          augmented = "data-dev/BMF-REF-AUG-2026-08-20.rds")
if (WHICH != "both") refs <- refs[WHICH]

g <- fread("inputs/1k_grants_01.csv", colClasses = "character", showProgress = FALSE)
g[, grant_id := sprintf("G%06d", .I)]
prep <- pf_prepare(head(g, N), dedup = "none", verbose = FALSE)
q <- prep$recipients
say("queries: %s", format(nrow(q), big.mark = ","))

# pf_match_grants() defaults to pf_default_passes() -- the state-free baseline,
# whose token-any sweep compares across every state and is the configuration the
# scale work rejected. Production runs the state-blocked staged passes, so that
# is what has to be timed.
PASSES <- c(pf_staged_passes("lean"), pf_recovery_passes(state = TRUE))
say("passes: %s", paste(vapply(PASSES, function(p) p$name, ""), collapse = ", "))

for (nm in names(refs)) {
  p <- refs[[nm]]
  if (!file.exists(p)) { say("skip %s (no cache)", nm); next }
  t0 <- proc.time()[["elapsed"]]
  ref <- readRDS(p)
  hr(); say("%s -- %s reference rows (cache load %.0f s)", toupper(nm),
            format(nrow(ref$reference), big.mark = ","), proc.time()[["elapsed"]] - t0)

  t1 <- proc.time()[["elapsed"]]
  log <- utils::capture.output(
    res <- pf_match_grants(q, ref, passes = PASSES, verbose = TRUE, recover = TRUE))
  el <- proc.time()[["elapsed"]] - t1
  for (l in log) message("    ", l)
  say("MATCH TIME: %.1f s for %s queries  (%.1f s per 1,000)",
      el, format(nrow(q), big.mark = ","), el / nrow(q) * 1000)
  rm(ref, res); invisible(gc())
}
