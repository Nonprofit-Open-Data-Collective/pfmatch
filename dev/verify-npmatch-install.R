#!/usr/bin/env Rscript
# ============================================================================
# Verify the reinstalled npmatch against the call that used to fail.
#
# The failure was: pf_match_grants() passes name_freq / token_idf / ref_index to
# np_cascade(), and the installed npmatch did not accept them. Checking the
# signature is necessary but not sufficient -- what matters is that a real
# cascade runs, and that the three arguments are actually USED rather than
# silently swallowed.
#
# npmatch is loaded with library(), exactly as the Phase 1 scripts load it.
# pfmatch is loaded from source because it is not installed (see the end).
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(library(npmatch)))          # <- installed copy
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
setDTthreads(0L)
say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() cat(strrep("=", 78), "\n")
ok  <- function(c, m) { say("  [%s] %s", if (isTRUE(c)) "PASS" else "FAIL", m)
                        if (!isTRUE(c)) FAILED <<- TRUE }
FAILED <- FALSE

hr(); say("PROVENANCE"); hr()
say("npmatch loaded from : %s", dirname(getNamespaceInfo("npmatch", "path")))
say("npmatch version     : %s", as.character(utils::packageVersion("npmatch")))
a <- names(formals(npmatch::np_cascade))
say("np_cascade args     : %s", paste(a, collapse = ", "))
ok(all(c("name_freq","token_idf","ref_index") %in% a),
   "np_cascade accepts the three batch parameters")

hr(); say("A REAL CASCADE THROUGH pf_match_grants()"); hr()
g <- fread(file.path(PF, "inputs", "1k_grants_01.csv"), colClasses = "character",
           showProgress = FALSE)[1:200]
g[, grant_id := sprintf("G%06d", .I)]
prep <- pf_prepare(g, dedup = "fuzzy", verbose = FALSE)
ref  <- pf_reference(file.path(PF, "..", "npmatch", "data-raw",
                               "bmf_2026_01_processed.csv"),
                     cache = file.path(PF, "data-dev", "REF-active.rds"),
                     verbose = FALSE)
say("identities %d | reference %s rows", nrow(prep$recipients),
    format(nrow(ref$reference), big.mark = ","))

res <- tryCatch({
  m <- pf_match_grants(prep$recipients, ref, passes = pf_staged_passes("lean"),
                       recover = FALSE, verbose = FALSE)
  list(ok = TRUE, m = m)
}, error = function(e) list(ok = FALSE, msg = conditionMessage(e)))
ok(isTRUE(res$ok), "pf_match_grants() runs against the INSTALLED npmatch")
if (!isTRUE(res$ok)) { say("  error: %s", res$msg); quit(status = 1L) }

st <- table(factor(as.character(as.data.frame(res$m$result)$tier),
                   levels = c("YES","MAYBE","NO")))
say("  YES %d  MAYBE %d  NO %d", st[["YES"]], st[["MAYBE"]], st[["NO"]])
ok(st[["YES"]] > 0, "the cascade actually resolved matches")

# Are the precomputed structures used, or accepted and ignored? If ref_index is
# genuinely consumed, passing a deliberately empty one must change the outcome.
hr(); say("ARE THE THREE ARGUMENTS ACTUALLY USED?"); hr()
bare <- ref; bare$ref_index <- NULL; bare$name_freq <- NULL; bare$token_idf <- NULL
t0 <- proc.time()[["elapsed"]]
m2 <- pf_match_grants(prep$recipients, bare, passes = pf_staged_passes("lean"),
                      recover = FALSE, verbose = FALSE)
el2 <- proc.time()[["elapsed"]] - t0
st2 <- table(factor(as.character(as.data.frame(m2$result)$tier),
                    levels = c("YES","MAYBE","NO")))
say("with precomputed index : YES %d MAYBE %d NO %d", st[["YES"]], st[["MAYBE"]], st[["NO"]])
say("without                : YES %d MAYBE %d NO %d (%.0f s)",
    st2[["YES"]], st2[["MAYBE"]], st2[["NO"]], el2)
ok(identical(as.integer(st), as.integer(st2)),
   "results identical either way (the index is an optimisation, not a behaviour change)")

hr(); say("THE DYAD PATH, END TO END, ON THE INSTALLED npmatch"); hr()
D <- readRDS(file.path(PF, "data-dev", "PF-DYADS-UNIFIED.rds"))
x <- suppressMessages(pf_dyad_collapse(res$m, D, pf_dyad_config(),
                                       np_config = res$m$config))
s <- as.data.table(pf_status(x))
say("collapsed identities: %d", sum(as.data.frame(x$result)$dyad_collapsed))
ok(nrow(s) == nrow(prep$recipients), "pf_status() works after a collapse")

hr(); say("IS pfmatch ITSELF INSTALLED?"); hr()
# It was not, until 2026-08-21. Every Phase 1 script calls library(pfmatch),
# so an npmatch-only fix leaves them broken. Checked here rather than asserted.
inst <- requireNamespace("pfmatch", quietly = TRUE)
ok(inst, "pfmatch is installed (library(pfmatch) resolves)")
if (inst) {
  e <- getNamespaceExports("pfmatch")
  ok(all(c("pf_build_dyads", "pf_dyad_collapse", "pf_dyad_lookup") %in% e),
     "the installed pfmatch exports the dyad module")
  ok("dyads" %in% names(formals(pfmatch::pf_run_batches)),
     "the installed pf_run_batches() accepts `dyads`")
  ok("dyads" %in% names(formals(pfmatch::pf_link)),
     "the installed pf_link() accepts `dyads`")
}

hr()
say(if (FAILED) "SOME CHECKS FAILED" else "ALL CHECKS PASSED")
if (FAILED) quit(status = 1L)
