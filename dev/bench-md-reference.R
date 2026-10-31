#!/usr/bin/env Rscript
# ============================================================================
# bench-md-reference.R -- the published matchdb tiers against the augmented
# BMF, on the current benchmark population (efv2_1k, the population of
# BASELINE-2026-10B), through pf_reference() itself.
#
# One arm per process (memory: the augmented bundle alone peaks near 37 GB):
#   MD_ARM=augmented         the local bundle pfmatch has used so far
#   MD_ARM=unified-observed  the matchdb tier closest to the augmented bundle
#   MD_ARM=active-observed   the same without the inactive-BMF tranche -- the
#                            default since this benchmark, which it won outright
#
#   PFMATCH_DIR=<checkout>  REF_CACHE=<augmented .rds>  OUT=<dir>  [GRANTS_DIR=<inputs>]
#   [MATCHDB_CODE=<matchdb checkout, if not installed>]  [PF_BENCH_GRANTS=<pattern>]
#   Rscript dev/bench-md-reference.R
#
# Written with the Write tool: a bash heredoc strips one backslash level.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
PF <- Sys.getenv("PFMATCH_DIR", ".")
ARM <- Sys.getenv("MD_ARM")
OUT <- Sys.getenv("OUT", file.path(PF, "data-dev"))
suppressWarnings(suppressMessages({
  if (nzchar(Sys.getenv("MATCHDB_CODE")))
    pkgload::load_all(Sys.getenv("MATCHDB_CODE"), quiet = TRUE, export_all = FALSE)
  devtools::load_all(PF, quiet = TRUE)
}))
say <- function(...) message(sprintf(...))

t0 <- proc.time()[["elapsed"]]
ref <- if (ARM == "augmented") {
  pf_reference(cache = Sys.getenv("REF_CACHE"), source = "local", verbose = FALSE)
} else {
  pf_reference(source = "matchdb", tier = ARM, verbose = FALSE)
}
say("arm %s: %s reference, %s rows (loaded in %.1f min)", ARM, ref$source,
    format(nrow(ref$reference), big.mark = ","), (proc.time()[["elapsed"]] - t0) / 60)
if (!is.null(ref$stamp)) say("  spec %s, normalizer %s", ref$stamp$spec_hash,
                             ref$stamp$normalize_signature)

grants <- pf_read_grants(Sys.getenv("GRANTS_DIR", file.path(PF, "inputs")),
                         pattern = Sys.getenv("PF_BENCH_GRANTS", "^efv2_1k_grants_"))
grants <- pf_recover_name_from_street(grants)
passes <- c(pf_staged_passes("lean", concat = TRUE), pf_recovery_passes(state = TRUE))
t1 <- proc.time()[["elapsed"]]
m <- pf_match_grants(grants, ref, passes = passes, recover = TRUE, verbose = FALSE)
say("matched %s grants in %.1f min", format(nrow(grants), big.mark = ","),
    (proc.time()[["elapsed"]] - t1) / 60)

res <- as.data.frame(m$result); attr(res, "pairs") <- NULL
tb  <- table(factor(res$tier, levels = c("YES", "MAYBE", "NO")))
say("%-6s %6d  %5.1f%%", names(tb), as.integer(tb), 100 * as.integer(tb) / nrow(res))
say("identities %d   clear rate %.1f%%   YES+MAYBE %.1f%%", nrow(res),
    100 * tb[["YES"]] / nrow(res), 100 * (tb[["YES"]] + tb[["MAYBE"]]) / nrow(res))
saveRDS(res, file.path(OUT, sprintf("BENCH-MDREF-%s.rds", ARM)), compress = "xz")
