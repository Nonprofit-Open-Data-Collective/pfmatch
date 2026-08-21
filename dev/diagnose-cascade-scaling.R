#!/usr/bin/env Rscript
# ============================================================================
# Third hypothesis, after the first two were refuted.
#
# Refuted: the recovery passes (1.1x, not 44x) and a missing blocking index
# (all three bundles carry ref_index, name_freq and token_idf).
#
# What is left is the shape of the numbers:
#
#     294 identities   ->   370 s        (1,259 s per 1,000)
#     978 identities   -> 1,506 s        (1,539 s per 1,000, in 2 batches)
#  46,900 identities   -> 1,653 s        (   35 s per 1,000, historical)
#
# Total time barely moves between 294 and 978, and the 46,900-identity run cost
# about the same as the 294-identity one. That is not per-query cost. It is a
# FIXED cost paid once per np_cascade() call over the whole reference, which
# amortises to nothing at 46,900 queries and dominates completely at 294.
#
# If true it inverts the Phase 1 advice: the fixed cost is paid PER BATCH, so
# small batches multiply it. The 50k run used the 25,000 default and paid it
# twice; my benchmarks used 500-1,000 and paid it fifty times.
#
# Test: same reference, same passes, increasing query counts. Fit time = a + b*N.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(devtools::load_all(
  Sys.getenv("NPMATCH_DIR", "../npmatch"), quiet = TRUE)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
setDTthreads(6L)
say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() cat(strrep("=", 78), "\n")
tick <- function() proc.time()[["elapsed"]]

g <- rbindlist(lapply(sprintf(file.path(PF, "inputs", "1k_grants_0%d.csv"), 1:5),
                      function(p) fread(p, colClasses = "character", showProgress = FALSE)),
               use.names = TRUE, fill = TRUE)
g[, grant_id := sprintf("G%06d", .I)]
prep_all <- pf_prepare(g, dedup = "fuzzy", verbose = FALSE)
R <- as.data.frame(prep_all$recipients)
say("identity pool: %s", format(nrow(R), big.mark = ","))

ref <- pf_reference(file.path(PF, "..", "npmatch", "data-raw",
                              "bmf_2026_01_processed.csv"),
                    cache = file.path(PF, "data-dev", "REF-active.rds"),
                    verbose = FALSE)
say("reference    : %s rows", format(nrow(ref$reference), big.mark = ","))

hr(); say("COST AGAINST QUERY COUNT, one np_cascade call each"); hr()
Ns <- c(100L, 250L, 500L, 1000L, 2000L, 4000L)
Ns <- Ns[Ns <= nrow(R)]
say("%8s %10s %12s %12s", "queries", "seconds", "s per 1,000", "pairs")
res <- data.table(n = integer(), el = numeric(), np = integer())
for (n in Ns) {
  q <- R[seq_len(n), , drop = FALSE]
  t0 <- tick()
  m <- pf_match_grants(q, ref, passes = pf_staged_passes("lean"),
                       recover = FALSE, verbose = FALSE)
  el <- tick() - t0
  np <- nrow(as.data.frame(attr(m$result, "pairs")))
  say("%8d %10.0f %12.0f %12s", n, el, 1000 * el / n, format(np, big.mark = ","))
  res <- rbind(res, data.table(n = n, el = el, np = np))
  rm(m); invisible(gc())
}

hr(); say("IS IT FIXED COST?"); hr()
fit <- stats::lm(el ~ n, data = res)
a <- unname(coef(fit)[1]); b <- unname(coef(fit)[2])
say("time = %.0f s + %.4f s per query   (R2 = %.3f)", a, b, summary(fit)$r.squared)
say("")
say("fixed component  : %.0f s per np_cascade() call", a)
say("marginal per 1k  : %.1f s", 1000 * b)
say("")
if (a > 60) {
  say("A fixed cost of %.0f s is paid ONCE PER CALL, and pf_run_batches() makes", a)
  say("one call per batch. Implications:")
  say("  batch 500   over 3,000,000 identities = %6.0f calls = %8.0f h of pure overhead",
      3e6/500, 3e6/500 * a / 3600)
  say("  batch 25000 over 3,000,000 identities = %6.0f calls = %8.0f h of pure overhead",
      3e6/25000, 3e6/25000 * a / 3600)
  say("  marginal work either way              = %8.0f h", 3e6 * b / 3600)
  say("")
  say("The historical 35 s/1,000 is what this looks like once amortised.")
} else {
  say("No large fixed cost. The scaling explanation is wrong too; look elsewhere.")
}

fwrite(res, file.path(PF, "data-dev", "CASCADE-SCALING.csv"))
say(""); say("wrote data-dev/CASCADE-SCALING.csv")
