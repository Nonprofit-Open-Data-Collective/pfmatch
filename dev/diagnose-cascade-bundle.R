#!/usr/bin/env Rscript
# ============================================================================
# Last cheap discriminator for the 38x gap.
#
# Refuted so far:
#   - the pass set          (9 vs 11 passes = 1.1x)
#   - a missing index       (all bundles carry ref_index/name_freq/token_idf)
#   - fixed per-call cost   (15 s; marginal is 1,324 s per 1,000, R2 = 0.999)
#
# The 50,000-grant run of 2026-08-19 recorded 35 s per 1,000 identities. It used
# BMF-REFERENCE-BUNDLE.rds (32 columns). Everything since has used
# REF-active.rds (35 columns). Both are the same 1,924,822-row monthly BMF and
# both carry an index, but they were built four days and several commits apart.
#
# Same queries, same passes, one bundle against the other.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(devtools::load_all(
  Sys.getenv("NPMATCH_DIR", "../npmatch"), quiet = TRUE)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
setDTthreads(0L)   # the historical run used all threads
say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() cat(strrep("=", 78), "\n")
tick <- function() proc.time()[["elapsed"]]
N <- as.integer(Sys.getenv("PF_N", "500"))

g <- fread(file.path(PF, "inputs", "1k_grants_01.csv"), colClasses = "character",
           showProgress = FALSE)
g[, grant_id := sprintf("G%06d", .I)]
prep <- pf_prepare(g, dedup = "fuzzy", verbose = FALSE)
q <- as.data.frame(prep$recipients)[seq_len(min(N, nrow(prep$recipients))), , drop = FALSE]
say("queries: %d   data.table threads: %d", nrow(q), getDTthreads())

hr(); say("BUNDLE COMPARISON, identical queries and passes"); hr()
say("%-28s %9s %13s %12s %8s %8s", "bundle", "seconds", "s per 1,000", "pairs", "YES", "MAYBE")
for (nm in c("BMF-REFERENCE-BUNDLE.rds", "REF-active.rds")) {
  p <- file.path(PF, "data-dev", nm)
  if (!file.exists(p)) { say("%-28s (absent)", nm); next }
  b <- readRDS(p)
  t0 <- tick()
  m <- pf_match_grants(q, b, passes = pf_staged_passes("lean"),
                       recover = FALSE, verbose = FALSE)
  el <- tick() - t0
  np <- nrow(as.data.frame(attr(m$result, "pairs")))
  st <- table(factor(as.character(as.data.frame(m$result)$tier),
                     levels = c("YES","MAYBE","NO")))
  say("%-28s %9.0f %13.0f %12s %8d %8d", nm, el, 1000 * el / nrow(q),
      format(np, big.mark = ","), st[["YES"]], st[["MAYBE"]])
  rm(b, m); invisible(gc())
}
say("")
say("The 50k run of 2026-08-19 recorded 35 s per 1,000 on the first of these.")
say("If both are slow here, the bundle is not the difference and what changed")
say("is npmatch itself between that run and now -- which is then worth a")
say("git bisect, not more guessing.")
