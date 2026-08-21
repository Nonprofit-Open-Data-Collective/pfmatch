#!/usr/bin/env Rscript
# ============================================================================
# Integration test for the Phase 0c wiring.
#
# Everything measured so far called pf_dyad_collapse() directly. The shipped
# path is different: pf_link() -> pf_run_batches() -> collapse -> pf_status().
# Two things could break there and nowhere else.
#
#   1. pf_status() reads columns off the re-selected result and looks up
#      geography in the pairs attribute. The collapse REPLACES both. If
#      np_select() drops a column pf_status() wants, or the winning pair is not
#      in the reduced pair set, it fails here and only here.
#   2. The batch checkpoints are keyed by file name only. Re-running with a
#      different dyad table silently reuses stale results unless the checkpoint
#      directory is distinct.
#
# Runs on the 1,000-grant sample against the monthly BMF, because this is a
# plumbing test, not a measurement.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
# The INSTALLED npmatch is older than its source: np_cascade() there does not
# accept name_freq/token_idf/ref_index, which pf_match_grants() passes. Load the
# source tree so this tests the code we are actually developing.
suppressWarnings(suppressMessages(devtools::load_all(
  Sys.getenv("NPMATCH_DIR", "../npmatch"), quiet = TRUE)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
setDTthreads(6L)
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("=", 78), "\n")
ok  <- function(cond, msg) {
  say("  [%s] %s", if (isTRUE(cond)) "PASS" else "FAIL", msg)
  if (!isTRUE(cond)) FAILED <<- TRUE
}
FAILED <- FALSE

BMF <- file.path(PF, "..", "npmatch", "data-raw", "bmf_2026_01_processed.csv")
D   <- readRDS(file.path(PF, "data-dev", "PF-DYADS-UNIFIED.rds"))

g <- fread(file.path(PF, "inputs", "1k_grants_01.csv"), colClasses = "character",
           showProgress = FALSE)
g[, grant_id := sprintf("G%06d", .I)]
prep <- pf_prepare(g, dedup = "fuzzy", verbose = FALSE)
ref  <- pf_reference(BMF, cache = file.path(PF, "data-dev", "REF-active.rds"),
                     verbose = FALSE)
say("identities %s | reference %s rows", format(nrow(prep$recipients), big.mark=","),
    format(nrow(ref$reference), big.mark=","))

hr(); say("WITHOUT DYADS"); hr()
d0 <- file.path(tempdir(), "wire-off"); unlink(d0, recursive = TRUE)
l0 <- pf_link(prep, ref, dir = d0, batch_size = 500L, verbose = FALSE)
s0 <- as.data.table(l0$status)
print(s0[, .N, by = status][order(-N)], row.names = FALSE)

hr(); say("WITH DYADS"); hr()
d1 <- file.path(tempdir(), "wire-on"); unlink(d1, recursive = TRUE)
l1 <- pf_link(prep, ref, dir = d1, batch_size = 500L, dyads = D, verbose = TRUE)
s1 <- as.data.table(l1$status)
print(s1[, .N, by = status][order(-N)], row.names = FALSE)

hr(); say("CHECKS"); hr()
ok(nrow(s0) == nrow(s1), "same number of identities either way")
ok(all(c("dyad_collapsed", "dyad_id", "dyad_from_ein") %in% names(s1)),
   "status frame carries the dyad audit columns")
ok(!any(c("dyad_collapsed", "dyad_id") %in% names(s0)),
   "and does not when dyads is NULL")
ok(sum(s1$dyad_collapsed, na.rm = TRUE) > 0, "the collapse actually fired")
ok(!any(is.na(s1$status)), "no identity lost its status")
ok(all(s1$grant_id %in% s0$grant_id), "identity ids are unchanged")

# no identity may be pushed into NO by collapsing
mv <- merge(s0[, .(grant_id, t0 = status)], s1[, .(grant_id, t1 = status)],
            by = "grant_id")[t0 != t1]
say("")
say("tier movement:")
if (nrow(mv)) print(mv[, .N, by = .(t0, t1)][order(-N)], row.names = FALSE) else
  say("  (none)")
ok(!any(mv$t1 == "NO" & mv$t0 != "NO"), "nothing was pushed into NO")
ok(all(mv$grant_id %in% s1[dyad_collapsed == TRUE]$grant_id),
   "every tier change happened on a collapsed identity")

# the EIN reported after a collapse must still be one of that grant's candidates
say("")
chg <- s1[!is.na(dyad_from_ein)]
say("identities where the reported EIN changed: %d", nrow(chg))
ok(all(!is.na(chg$ein)), "every changed pick still reports an EIN")
ok(all(chg$ein != chg$dyad_from_ein), "and it differs from the one it replaced")

# geography survived the pair-set replacement -- this is the pf_status() risk
say("")
gy <- s1[status %in% c("YES","MAYBE") & !is.na(ein)]
say("YES/MAYBE with a BMF state resolved: %.1f%% (dyad rows %.1f%%)",
    100*mean(!is.na(gy$bmf_state)),
    100*mean(!is.na(gy[dyad_collapsed == TRUE]$bmf_state)))
ok(mean(!is.na(gy[dyad_collapsed == TRUE]$bmf_state)) > 0.5,
   "collapsed rows still resolve geography from the reduced pair set")

hr()
say(if (FAILED) "SOME CHECKS FAILED" else "ALL CHECKS PASSED")
if (FAILED) quit(status = 1L)
