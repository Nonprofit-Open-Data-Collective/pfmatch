#!/usr/bin/env Rscript
# ============================================================================
# One clean cost measurement, after four wrong explanations.
#
# The thing that actually varied across my diagnostics was `setDTthreads()`:
# 6 in dev/diagnose-cascade-scaling.R, 0 (=14) in dev/diagnose-cascade-bundle.R.
# Same reference, same passes, same queries:
#
#     6 threads  -> 1,335 s per 1,000
#    14 threads  ->   192 s per 1,000
#
# Some of the earlier runs were also competing with an unrelated R process for
# cores. So the "reference is catastrophically slow" finding was substantially
# an artefact of how I ran it, not a property of the reference.
#
# This measures both references under identical, controlled conditions:
# all threads, idle machine, same queries, same passes, both pass sets.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(devtools::load_all(
  Sys.getenv("NPMATCH_DIR", "../npmatch"), quiet = TRUE)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
setDTthreads(0L)
say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() cat(strrep("=", 78), "\n")
tick <- function() proc.time()[["elapsed"]]
N <- as.integer(Sys.getenv("PF_N", "1000"))

say("data.table threads: %d", getDTthreads())
g <- rbindlist(lapply(sprintf(file.path(PF, "inputs", "1k_grants_0%d.csv"), 1:5),
                      function(p) fread(p, colClasses = "character", showProgress = FALSE)),
               use.names = TRUE, fill = TRUE)
g[, grant_id := sprintf("G%06d", .I)]
prep <- pf_prepare(g, dedup = "fuzzy", verbose = FALSE)
q <- as.data.frame(prep$recipients)[seq_len(min(N, nrow(prep$recipients))), , drop = FALSE]
say("queries: %d", nrow(q))

REFS <- list(
  `monthly BMF (1.92M)`   = list(csv = file.path(PF, "..", "npmatch", "data-raw",
                                                 "bmf_2026_01_processed.csv"),
                                 cache = file.path(PF, "data-dev", "REF-active.rds")),
  `augmented unified (3.89M)` = list(csv = file.path(PF, "data-dev",
                                       "BMF-AUGMENTED-bmf_unified_geocoded_2026-08-20.csv"),
                                 cache = file.path(PF, "data-dev", "BMF-REF-AUG-2026-08-20.rds")))

hr(); say("CASCADE COST, all threads, idle machine"); hr()
say("%-26s %-14s %9s %13s %10s %6s %6s", "reference", "passes", "seconds",
    "s per 1,000", "pairs", "YES", "MAYBE")
out <- list()
for (rn in names(REFS)) {
  b <- pf_reference(REFS[[rn]]$csv, cache = REFS[[rn]]$cache, verbose = FALSE)
  for (pn in c("9 (lean)", "11 (+recov)")) {
    ps <- if (pn == "9 (lean)") pf_staged_passes("lean")
          else c(pf_staged_passes("lean"), pf_recovery_passes(state = TRUE))
    t0 <- tick()
    m <- pf_match_grants(q, b, passes = ps, recover = (pn != "9 (lean)"),
                         verbose = FALSE)
    el <- tick() - t0
    np <- nrow(as.data.frame(attr(m$result, "pairs")))
    st <- table(factor(as.character(as.data.frame(m$result)$tier),
                       levels = c("YES","MAYBE","NO")))
    say("%-26s %-14s %9.0f %13.0f %10s %6d %6d", rn, pn, el, 1000*el/nrow(q),
        format(np, big.mark=","), st[["YES"]], st[["MAYBE"]])
    out[[paste(rn, pn)]] <- list(ref = rn, passes = pn, s_per_1k = 1000*el/nrow(q),
                                 yes = st[["YES"]], maybe = st[["MAYBE"]])
    rm(m); invisible(gc())
  }
  rm(b); invisible(gc())
}

hr(); say("WHAT THIS MEANS FOR PHASE 1"); hr()
say("The 50k run of 2026-08-19 recorded 35 s per 1,000 identities on the")
say("monthly BMF with 9 passes, and budgeted 117 h for 12.56M grants.")
say("")
r <- rbindlist(lapply(out, as.data.table))
say("%-26s %-14s %13s %14s", "reference", "passes", "s per 1,000", "12.56M grants")
for (i in seq_len(nrow(r))) {
  # 12.56M grants, dedup ~1.05x on this sample but far higher at full scale;
  # quote the pessimistic no-dedup figure and let the reader discount it
  hours <- 12559051 / 1000 * r$s_per_1k[i] / 3600
  say("%-26s %-14s %13.0f %10.0f h  (%.0f h on 12 shards)",
      r$ref[i], r$passes[i], r$s_per_1k[i], hours, hours / 12)
}
say("")
say("Dedup is the missing factor: this 5k sample collapses only 1.05x, but the")
say("full file repeats grantees heavily and Phase 1.2 is what measures it.")
fwrite(r, file.path(PF, "data-dev", "CASCADE-COST-CLEAN.csv"))
say(""); say("wrote data-dev/CASCADE-COST-CLEAN.csv")
