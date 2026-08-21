#!/usr/bin/env Rscript
# ============================================================================
# probe-determinism.R -- is the 1k benchmark usable as a phase gate?
#
# matchdb's phase gates (matchdb/dev/PROCESS.md) all reduce to "the 1k benchmark
# is unchanged". That criterion is only falsifiable if the benchmark returns the
# same answer twice. data.table runs the blocking joins multi-threaded, and the
# selection layer breaks ties by first-row-wins (.np_argmax_by, !duplicated), so
# a thread-dependent row order could in principle move a verdict.
#
# Run twice in separate processes, then compare every column exactly:
#
#   PF_DET_RUN=1 Rscript dev/probe-determinism.R
#   PF_DET_RUN=2 Rscript dev/probe-determinism.R      <- compares against run 1
#
# Every run after the first compares itself against run 1.
#
# Same-thread-count reruns are the weaker test. The gate has to hold on a
# machine that is not the author's, so thread count is the variable that
# actually differs in practice:
#
#   PF_DET_RUN=3 PF_DET_THREADS=1 Rscript dev/probe-determinism.R
#
# Exact equality, not tolerance: determinism means bit-identical. A benchmark
# that is merely close cannot gate an extraction that must not change behaviour.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))

PF   <- Sys.getenv("PFMATCH_DIR", ".")
NPM  <- Sys.getenv("NPMATCH_DIR", "../npmatch")
RUN  <- Sys.getenv("PF_DET_RUN", "1")
THR  <- Sys.getenv("PF_DET_THREADS", "")
if (nzchar(THR)) setDTthreads(as.integer(THR))
REF_RDS <- file.path(PF, "data-dev", "BMF-REFERENCE-BUNDLE.rds")
OUT  <- file.path(PF, "data-dev", sprintf("DET-RUN%s.rds", RUN))
say  <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr   <- function() cat(strrep("=", 74), "\n")

suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))

hr(); say("determinism run %s | dt threads = %d", RUN, getDTthreads()); hr()

grants <- pf_read_grants(file.path(PF, "inputs"), pattern = "^1k_grants_.*\\.csv$")
grants <- pf_recover_name_from_street(grants)
say("grants: %d rows | %d in scope", nrow(grants), sum(grants$in_scope))

if (!file.exists(REF_RDS)) stop("no reference bundle at ", REF_RDS)
t0 <- proc.time()[["elapsed"]]
ref <- readRDS(REF_RDS)
say("reference: %s rows loaded in %.1f s",
    format(nrow(ref$reference), big.mark = ","), proc.time()[["elapsed"]] - t0)

passes <- c(pf_staged_passes("lean", concat = TRUE), pf_recovery_passes(state = TRUE))
say("matching, %d passes ...", length(passes))
t0 <- proc.time()[["elapsed"]]
m <- pf_match_grants(grants, ref, passes = passes, recover = TRUE, verbose = FALSE)
say("matched in %.1f s", proc.time()[["elapsed"]] - t0)

res <- as.data.frame(m$result)
res <- res[order(res$.id), , drop = FALSE]
rownames(res) <- NULL
saveRDS(res, OUT, compress = FALSE)
say("wrote %s (%d rows x %d cols)", basename(OUT), nrow(res), ncol(res))
print(table(res$tier, useNA = "ifany"))

## ---- compare against run 1 -------------------------------------------------
A <- file.path(PF, "data-dev", "DET-RUN1.rds")
B <- OUT
if (RUN == "1" || !file.exists(A)) {
  say(""); say("baseline written. Now run:")
  say("  PF_DET_RUN=2 Rscript dev/probe-determinism.R                  # same threads")
  say("  PF_DET_RUN=3 PF_DET_THREADS=1 Rscript dev/probe-determinism.R # thread-independence")
  quit(save = "no")
}

hr(); say("COMPARISON  DET-RUN1 vs DET-RUN%s", RUN); hr()
a <- readRDS(A); b <- readRDS(B)

fail <- 0L
chk <- function(label, ok, detail = "") {
  say("  %-34s %s%s", label, if (ok) "PASS" else "**FAIL**",
      if (nzchar(detail)) paste0("   ", detail) else "")
  if (!ok) fail <<- fail + 1L
}

chk("row count", nrow(a) == nrow(b), sprintf("%d vs %d", nrow(a), nrow(b)))
chk("column set", identical(sort(names(a)), sort(names(b))))
chk("identity set", setequal(a$.id, b$.id))

if (nrow(a) == nrow(b) && identical(sort(names(a)), sort(names(b)))) {
  b <- b[, names(a), drop = FALSE]
  diffs <- character(0)
  for (n in names(a)) {
    x <- a[[n]]; y <- b[[n]]
    if (is.factor(x)) { x <- as.character(x); y <- as.character(y) }
    same <- identical(x, y)
    if (!same) {
      nd <- sum(!(x == y | (is.na(x) & is.na(y))), na.rm = TRUE)
      diffs <- c(diffs, sprintf("%s (%d cells)", n, nd))
    }
  }
  chk("all columns bit-identical", length(diffs) == 0,
      if (length(diffs)) paste(diffs, collapse = "; ") else "24/24")

  # the gate criterion PROCESS.md names explicitly
  key <- function(d) paste(d$.id, d$overall_ein, d$tier, d$decision_score, sep = "\r")
  chk("(.id, ein, tier, score) exact", identical(key(a), key(b)))
}

hr()
if (fail == 0L) {
  say("DETERMINISTIC -- the 1k benchmark can serve as a phase gate.")
} else {
  say("NON-DETERMINISTIC -- %d check(s) failed.", fail)
  say("The benchmark cannot gate anything until this is resolved.")
  say("First suspects: data.table thread count (setDTthreads) and tie-breaking")
  say("in .np_argmax_by / !duplicated, which are first-row-wins over a")
  say("thread-dependent row order.")
}
quit(save = "no", status = if (fail == 0L) 0L else 1L)
