#!/usr/bin/env Rscript
# ============================================================================
# run-test-match.R -- benchmark 990-PF grant recipients against the IRS BMF
#
# Stage 1  prepare grants          (preprocessing -- not timed)
# Stage 2  build the BMF reference (preprocessing -- not timed, checkpointed)
# Stage 3  match                   (TIMED)
# Stage 4  report + crosstab
#
# pfmatch is a package; dev scripts use devtools::load_all() so that internal
# and unexported functions stay reachable.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))

PF      <- Sys.getenv("PFMATCH_DIR", ".")
NPM     <- Sys.getenv("NPMATCH_DIR", "../npmatch")

BMF_CSV <- file.path(NPM, "data-raw", "bmf_2026_01_processed.csv")
REF_RDS <- file.path(PF, "data-dev", "BMF-REFERENCE-BUNDLE.rds")

# which benchmark file set to run: "1k" (the five 1,000-row files), "50k", "100k"
SET     <- Sys.getenv("PF_SET", "1k")
PATTERN <- switch(SET,
                  "1k"   = "^1k_grants_.*\\.csv$",
                  "50k"  = "^50k_grants\\.csv$",
                  "100k" = "^100k_grants\\.csv$",
                  stop("PF_SET must be one of 1k / 50k / 100k"))
OUT_CSV <- file.path(PF, "data-dev", sprintf("PF-MATCH-REPORT-%s.csv", SET))

say <- function(...) cat(sprintf(...), "\n")

suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))

# ---- Stage 1: grants ---------------------------------------------------------
say("[1/4] preparing grants (set = %s) ...", SET)
grants <- pf_read_grants(file.path(PF, "inputs"), pattern = PATTERN)
grants <- pf_recover_name_from_street(grants)
say("      %d grant rows | %d in scope | %d out of sample",
    nrow(grants), sum(grants$in_scope), sum(!grants$in_scope))
say("      recipient types: %s",
    paste(sprintf("%s=%d", names(table(grants$recipient_type)),
                  table(grants$recipient_type)), collapse = "  "))

# ---- Stage 2: BMF reference (checkpointed) -----------------------------------
if (file.exists(REF_RDS)) {
  say("[2/4] loading cached BMF reference bundle ...")
  t0 <- proc.time()[["elapsed"]]
  ref <- readRDS(REF_RDS)
  say("      %d records loaded in %.1f s", nrow(ref$reference), proc.time()[["elapsed"]] - t0)
} else {
  say("[2/4] building BMF reference (read + normalize + index; one time) ...")
  ref <- pf_build_reference(BMF_CSV)
  say("      %d records | read %.1fs  normalize %.1fs  index %.1fs",
      nrow(ref$reference), ref$timing[["read"]], ref$timing[["normalize"]],
      ref$timing[["index"]])
  saveRDS(ref, REF_RDS, compress = FALSE)
  say("      cached -> %s", basename(REF_RDS))
}

# ---- Stage 3: match (TIMED) --------------------------------------------------
# PF_PASSES=staged (default) uses the state-blocked cascade with a cheap
# cross-state exact sweep; "free" reproduces the original state-free baseline.
MODE    <- Sys.getenv("PF_PASSES", "staged")
RECOVER <- Sys.getenv("PF_RECOVER", "1") == "1"
passes <- switch(MODE,
                 staged = pf_staged_passes(Sys.getenv("PF_SWEEP", "lean"),
                                           concat = Sys.getenv("PF_CONCAT", "1") == "1"),
                 free   = pf_default_passes(),
                 stop("PF_PASSES must be 'staged' or 'free'"))
if (RECOVER) passes <- c(passes, pf_recovery_passes(state = TRUE))
say("[3/4] matching (%s cascade%s, %d passes) ...", MODE,
    if (RECOVER) " + stage 4 recovery" else "", length(passes))
m <- pf_match_grants(grants, ref, passes = passes, recover = RECOVER, verbose = TRUE)

# ---- Stage 4: report ---------------------------------------------------------
say("[4/4] report ...")
rep <- pf_report(m, file = OUT_CSV)
saveRDS(m, file.path(PF, "data-dev", sprintf("PF-MATCH-RESULT-%s.rds", SET)),
        compress = FALSE)
