#!/usr/bin/env Rscript
# ============================================================================
# Separate the two explanations for the 44x gap on the monthly BMF.
#
#   (a) the two recovery passes (D1-acronym, D2-prefix) are very expensive;
#   (b) REF-active.rds lacks the precomputed blocking index that
#       BMF-REFERENCE-BUNDLE.rds has, so np_cascade() takes a slower path.
#
# They imply opposite fixes, so guessing is not an option. Two checks:
#   1. inspect what each bundle actually carries;
#   2. run the same identities 9-pass vs 11-pass on the same bundle.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(devtools::load_all(
  Sys.getenv("NPMATCH_DIR", "../npmatch"), quiet = TRUE)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
setDTthreads(6L)
say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() cat(strrep("=", 78), "\n")
sb  <- function() cat(strrep("-", 78), "\n")
tick <- function() proc.time()[["elapsed"]]

hr(); say("CHECK 1  WHAT DOES EACH REFERENCE BUNDLE CARRY?"); hr()
bundles <- c(`REF-active.rds`             = "data-dev/REF-active.rds",
             `BMF-REFERENCE-BUNDLE.rds`   = "data-dev/BMF-REFERENCE-BUNDLE.rds",
             `BMF-REF-AUG-2026-08-20.rds` = "data-dev/BMF-REF-AUG-2026-08-20.rds")
for (nm in names(bundles)) {
  p <- file.path(PF, bundles[[nm]])
  if (!file.exists(p)) { say("%-28s (absent)", nm); next }
  t0 <- tick(); b <- readRDS(p); el <- tick() - t0
  say("%-28s %5.0f s to load", nm, el)
  say("   components   : %s", paste(names(b), collapse = ", "))
  say("   reference    : %s rows, %d cols",
      format(nrow(b$reference), big.mark = ","), ncol(b$reference))
  say("   ref_index    : %s", if (is.null(b$ref_index)) "NULL <- slow path" else
        sprintf("present (%s)", paste(class(b$ref_index), collapse = "/")))
  say("   name_freq    : %s", if (is.null(b$name_freq)) "NULL" else
        sprintf("present, %s entries", format(length(b$name_freq), big.mark = ",")))
  say("   token_idf    : %s", if (is.null(b$token_idf)) "NULL" else
        sprintf("present, %s tokens", format(length(b$token_idf), big.mark = ",")))
  say("   name_acro    : %s", if (is.null(b$reference$name_acro)) "NULL <- rebuilt per call" else "present")
  rm(b); invisible(gc())
}

hr(); say("CHECK 2  NINE PASSES VS ELEVEN, SAME BUNDLE, SAME QUERIES"); hr()
N <- as.integer(Sys.getenv("PF_N", "300"))
g <- fread(file.path(PF, "inputs", "1k_grants_01.csv"), colClasses = "character",
           showProgress = FALSE)[1:N]
g[, grant_id := sprintf("G%06d", .I)]
prep <- pf_prepare(g, dedup = "fuzzy", verbose = FALSE)
say("identities: %d", nrow(prep$recipients))

ref <- pf_reference(file.path(PF, "..", "npmatch", "data-raw",
                              "bmf_2026_01_processed.csv"),
                    cache = file.path(PF, "data-dev", "REF-active.rds"),
                    verbose = FALSE)
say("reference : %s rows", format(nrow(ref$reference), big.mark = ","))

timeit <- function(label, passes, recover) {
  t0 <- tick()
  m <- pf_match_grants(prep$recipients, ref, passes = passes,
                       recover = recover, verbose = FALSE)
  el <- tick() - t0
  np <- nrow(as.data.frame(attr(m$result, "pairs")))
  st <- table(factor(as.character(as.data.frame(m$result)$tier),
                     levels = c("YES","MAYBE","NO")))
  say("%-26s %7.0f s  %8.0f s/1k  %9s pairs  YES %4d MAYBE %4d",
      label, el, 1000 * el / nrow(prep$recipients), format(np, big.mark = ","),
      st[["YES"]], st[["MAYBE"]])
  invisible(list(el = el, np = np, yes = st[["YES"]], maybe = st[["MAYBE"]]))
}

sb()
say("%-26s %7s %12s %15s %s", "configuration", "seconds", "s/1k", "pairs", "outcome")
sb()
nine   <- timeit("9 passes (staged lean)", pf_staged_passes("lean"), FALSE)
eleven <- timeit("11 passes (+ recovery)",
                 c(pf_staged_passes("lean"), pf_recovery_passes(state = TRUE)), TRUE)

sb()
say("recovery passes multiply the cost by %.1fx and add %s candidate pairs",
    eleven$el / nine$el, format(eleven$np - nine$np, big.mark = ","))
say("for %+d YES and %+d MAYBE.", eleven$yes - nine$yes, eleven$maybe - nine$maybe)
say("")
say("If this ratio is near 1, the bundle is the problem, not the passes, and")
say("the 44x sits in whatever REF-active.rds is missing. If it is large, the")
say("recovery passes are the lever and D1-acronym is the first suspect.")
