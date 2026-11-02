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
# THE CLEAR RATE IS ON THE IN-SCOPE BASE, NOT THE RESULT FRAME. The arms are
# three different references, so they do not retrieve for the same identities,
# and an identity no blocking pass produced a pair for is ABSENT from the
# result frame rather than NO. A share denominated on the result frame
# therefore shrinks its own denominator exactly where the arm failed, and can
# rise while coverage falls -- which is the one outcome a reference comparison
# has to be able to show. See the denominator section at the bottom. The arm
# that "won outright" won on the result-frame reading; re-run all three to see
# whether it still does on this one.
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
source(file.path(PF, "dev", "assert-lib.R"))
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

## ---- the denominator, which is the whole comparison -----------------------
# The base is the in-scope identity count: a property of the grant file,
# identical across the three arms, and unmoved by how well any of them
# retrieves. Both readings are printed and the gap between them is named,
# because that gap IS the coverage the arm lost and the result-frame reading
# hides it. Conventions named on both sides (practice 5): pf_result_tiers() is
# the result-frame side, x$in_scope the population that was submitted.
scope   <- as.character(m$in_scope)
tier    <- pf_result_tiers(m)
no_pair <- setdiff(scope, names(tier))
need_rows(length(scope), min = 1L,
          what = "in-scope identities, the fixed base every share below uses")
need_vocab(tier, c("YES", "MAYBE", "NO"),
           what = "result-frame tiers; ABSENT is reported separately, not as a level")
stopifnot(length(tier) == nrow(res), all(names(tier) %in% scope))

say("%-6s %6d  %5.1f%%", names(tb), as.integer(tb),
    100 * as.integer(tb) / length(scope))
say("%-6s %6d  %5.1f%%   (in scope, no pair from any blocking pass)",
    "ABSENT", length(no_pair), 100 * length(no_pair) / length(scope))
say("in-scope identities %d   clear rate %.2f%%   YES+MAYBE %.2f%%",
    length(scope), 100 * tb[["YES"]] / length(scope),
    100 * (tb[["YES"]] + tb[["MAYBE"]]) / length(scope))
say("  on the result frame instead (%d identities, the %d with no pair dropped):",
    nrow(res), length(no_pair))
say("  clear %.2f%%   YES+MAYBE %.2f%%   -- %.2f points higher, and that gap",
    100 * tb[["YES"]] / nrow(res), 100 * (tb[["YES"]] + tb[["MAYBE"]]) / nrow(res),
    100 * tb[["YES"]] / nrow(res) - 100 * tb[["YES"]] / length(scope))
say("  widens as the arm retrieves less. Compare arms on the line above it.")
# The base travels with the artifact. Saving the frame alone is what let the
# result-frame denominator be re-derived downstream and the in-scope one not.
attr(res, "in_scope") <- scope
attr(res, "no_pair")  <- no_pair
saveRDS(res, file.path(OUT, sprintf("BENCH-MDREF-%s.rds", ARM)), compress = "xz")
