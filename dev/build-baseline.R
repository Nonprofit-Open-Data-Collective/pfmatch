#!/usr/bin/env Rscript
# ============================================================================
# build-baseline.R -- freeze the Phase 0a baseline.
#
# Every matchdb gate reduces to "this reproduces the baseline". That is only a
# falsifiable claim if the baseline is pinned to specific bytes, produced by a
# specific (npmatch, pfmatch) pair, on a benchmark already shown to be
# deterministic (dev/DETERMINISM-FINDINGS.md).
#
# Writes dev/BASELINE-2026-08/ :
#
#   manifest.csv        machine-readable: artifact, role, md5, rows, bytes
#   environment.txt     R + package versions, commit SHAs, normalizer signature
#   columns-*.txt       pinned column lists for the comparison normal form
#   benchmark-*.rds     compact tiered output, versioned (small)
#
# MANIFEST.md sits alongside these and is written BY HAND: it carries the
# provenance reasoning -- which artifact each gate reads and why, and what is
# ambiguous about the augmented CSVs -- which is not derivable from the files.
#
# Artifacts are named by CONTENT, not by filename: three near-identical
# augmented CSVs exist and the reference bundles record their provenance
# nowhere. Row count plus md5 is the identity.
#
#   PF_BASE=bench-active     run + save the active-BMF 1k benchmark   (~10 min)
#   PF_BASE=bench-augmented  run + save the augmented 1k benchmark    (~20 min)
#   PF_BASE=manifest         hash the artifacts and write the manifest
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)

PF   <- Sys.getenv("PFMATCH_DIR", ".")
MODE <- Sys.getenv("PF_BASE", "manifest")
DD   <- file.path(PF, "data-dev")

# A baseline is a historical record, so it is SUPERSEDED, never rewritten.
# BASELINE-2026-08 was frozen on the GT-derived 1k samples, which are now known
# to be truncated at the recent end (2024 under-represented ~10x, 2025 absent --
# see inputs/archive-gt/README.md). Its clear rate is therefore not comparable
# to anything measured on the e-file population, which is why dev/bench-efilepf.R
# carries the note that a difference against it "is not a regression".
#
# PF_BASE_DIR      which baseline directory to write   (default: the current one)
# PF_BASE_GRANTS   grant-file pattern for the arms     (default: e-file samples)
# PF_BASE_FORCE=1  permit writing into a directory that already has a manifest
BASE_DIR <- Sys.getenv("PF_BASE_DIR", "BASELINE-2026-10")
GRANTS   <- Sys.getenv("PF_BASE_GRANTS", "^ef1k_grants_.*\\.csv$")
OUT  <- file.path(PF, "dev", BASE_DIR)
if (file.exists(file.path(OUT, "manifest.csv")) &&
    !nzchar(Sys.getenv("PF_BASE_FORCE"))) {
  stop(sprintf(paste0("%s already holds a frozen manifest.\n",
       "  A baseline is a historical record: supersede it with a new ",
       "PF_BASE_DIR rather than\n  overwriting it. Set PF_BASE_FORCE=1 only to ",
       "repair a baseline you are certain is wrong."), BASE_DIR), call. = FALSE)
}
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
say  <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr   <- function() cat(strrep("=", 78), "\n")

suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))

# The artifacts the gates read. `role` is what each one gates; nothing is here
# that no gate consumes.
ARTIFACTS <- data.frame(
  file = c("REF-active.rds", "REF-unified.rds", "REF-augmented.rds",
           "BMF-AUGMENTED-unified-fixed.csv"),
  role = c("Phase 1 target: md_compile(active-legal) must reproduce this",
           "Phase 0c arm A; the unified layer without aliases",
           "Phase 2 target: md_compile(*-observed) must reproduce this",
           "source of REF-augmented.rds, resolved by row count (see MANIFEST.md)"),
  stringsAsFactors = FALSE)

## ---- benchmark arms --------------------------------------------------------
run_bench <- function(which) {
  refpath <- file.path(DD, switch(which,
    active = "REF-active.rds", augmented = "REF-augmented.rds"))
  grants <- pf_read_grants(file.path(PF, "inputs"), pattern = GRANTS)
  grants <- pf_recover_name_from_street(grants)
  say("loading %s ...", basename(refpath))
  ref <- readRDS(refpath)
  say("  %s rows", format(nrow(ref$reference), big.mark = ","))

  # pin the reference column list here, while the frame is in hand: the
  # comparison normal form must NOT resolve np_fields at run time, because
  # Phase 0c adds variant_class to it (matchdb/dev/PROCESS.md 5).
  writeLines(sort(names(ref$reference)),
             file.path(OUT, sprintf("columns-reference-%s.txt", which)))

  passes <- c(pf_staged_passes("lean", concat = TRUE), pf_recovery_passes(state = TRUE))
  say("matching (%d passes) ...", length(passes))
  t0 <- proc.time()[["elapsed"]]
  m <- pf_match_grants(grants, ref, passes = passes, recover = TRUE, verbose = FALSE)
  say("  matched in %.1f s", proc.time()[["elapsed"]] - t0)

  # Compact. as.data.frame() does NOT drop the np_tiered object's attributes,
  # and `pairs` is 194 MB of a 198 MB object -- that is what makes a saved
  # result ~242 MB (dev/DETERMINISM-FINDINGS.md). Strip it explicitly. `config`,
  # `profile` and `stages` are kept: together they are under a megabyte and they
  # record the thresholds and pass table the baseline was produced with, which a
  # gate reading this file six months from now will want.
  res <- as.data.frame(m$result)
  res <- res[order(res$.id), , drop = FALSE]
  rownames(res) <- NULL
  attr(res, "pairs") <- NULL
  for (a in c("config", "profile", "stages")) attr(res, a) <- attr(m$result, a)
  f <- file.path(OUT, sprintf("benchmark-1k-%s.rds", which))
  saveRDS(res, f, compress = "xz")
  writeLines(sort(names(res)), file.path(OUT, sprintf("columns-tiered-%s.txt", which)))
  say("wrote %s (%d identities, %.2f MB)", basename(f), nrow(res), file.size(f) / 1e6)
  print(table(res$tier, useNA = "ifany"))
  invisible(res)
}

if (MODE %in% c("bench-active", "bench-augmented")) {
  hr(); say("BASELINE benchmark: %s", sub("^bench-", "", MODE)); hr()
  run_bench(sub("^bench-", "", MODE))
  quit(save = "no")
}

## ---- manifest --------------------------------------------------------------
hr(); say("BASELINE manifest"); hr()

gitsha <- function(dir) {
  s <- tryCatch(system2("git", c("-C", dir, "rev-parse", "HEAD"), stdout = TRUE),
                error = function(e) NA_character_)
  if (length(s)) substr(s[1], 1, 7) else NA_character_
}
nrows <- function(p) {
  if (grepl("\\.csv$", p)) {
    as.integer(sub(" .*$", "", system2("wc", c("-l", shQuote(p)), stdout = TRUE))) - 1L
  } else {
    b <- readRDS(p); n <- nrow(if (!is.null(b$reference)) b$reference else b)
    rm(b); invisible(gc()); n
  }
}

rows <- list()
for (i in seq_len(nrow(ARTIFACTS))) {
  p <- file.path(DD, ARTIFACTS$file[i])
  if (!file.exists(p)) { say("  MISSING %s -- skipped", ARTIFACTS$file[i]); next }
  say("  hashing %-34s (%.1f GB) ...", ARTIFACTS$file[i], file.size(p) / 1e9)
  t0 <- proc.time()[["elapsed"]]
  md5 <- unname(tools::md5sum(p))
  n   <- nrows(p)
  say("    md5 %s | %s rows | %.0f s", md5, format(n, big.mark = ","),
      proc.time()[["elapsed"]] - t0)
  rows[[length(rows) + 1L]] <- data.frame(
    artifact = ARTIFACTS$file[i], role = ARTIFACTS$role[i],
    md5 = md5, rows = n, bytes = file.size(p), stringsAsFactors = FALSE)
}
# the versioned benchmark outputs, hashed the same way
for (f in list.files(OUT, pattern = "^benchmark-1k-.*\\.rds$", full.names = TRUE)) {
  d <- readRDS(f)
  rows[[length(rows) + 1L]] <- data.frame(
    artifact = basename(f), role = "1k benchmark verdicts (both phase gates)",
    md5 = unname(tools::md5sum(f)), rows = nrow(d), bytes = file.size(f),
    stringsAsFactors = FALSE)
  say("  %-34s md5 %s | %d identities", basename(f),
      unname(tools::md5sum(f)), nrow(d))
}
man <- do.call(rbind, rows)
write.csv(man, file.path(OUT, "manifest.csv"), row.names = FALSE)

## ---- environment -----------------------------------------------------------
sig <- tryCatch(npmatch::np_normalize_signature(), error = function(e) NA_character_)
env <- c(
  # Default to TODAY, not a pinned literal. The old default ("2026-08-21")
  # stamped every later baseline with the original freeze date, which made a
  # newly built baseline indistinguishable from the one it supersedes.
  sprintf("built             %s",
          Sys.getenv("PF_BASE_DATE", as.character(Sys.Date()))),
  sprintf("R                 %s", getRversion()),
  sprintf("platform          %s", R.version$platform),
  sprintf("pfmatch           %s", gitsha(PF)),
  sprintf("npmatch           %s", gitsha(file.path(PF, "..", "npmatch"))),
  sprintf("normalizer sig    %s", sig),
  "",
  "package versions:",
  paste0("  ", vapply(c("npmatch", "data.table", "stringi", "stringr", "reclin2",
                        "stringdist", "duckdb", "DBI"),
    function(p) tryCatch(sprintf("%-12s %s", p, utils::packageVersion(p)),
                         error = function(e) sprintf("%-12s (absent)", p)),
    character(1))))
writeLines(env, file.path(OUT, "environment.txt"))
cat("\n"); cat(env, sep = "\n"); cat("\n")
say("")
say("wrote %s", file.path(OUT, "manifest.csv"))
print(man[, c("artifact", "md5", "rows")])
