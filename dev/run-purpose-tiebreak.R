#!/usr/bin/env Rscript
# ============================================================================
# run-purpose-tiebreak.R -- apply pf_purpose_tiebreak() to an existing match
# result and report exactly what moved.
#
#   PF_SET=1k  Rscript dev/run-purpose-tiebreak.R                 # npmatch gates
#   PF_TIE_HIGH=0 PF_SET=1k Rscript dev/run-purpose-tiebreak.R    # widened
#
# Prints the changed picks and, where the grant is in the adjudicated audit set,
# whether the change was right or wrong.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
NPM <- Sys.getenv("NPMATCH_DIR", "../npmatch")
SET <- Sys.getenv("PF_SET", "1k")
TIE_HIGH <- as.numeric(Sys.getenv("PF_TIE_HIGH", "0.95"))
say <- function(...) cat(sprintf(...), "\n")

suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))

ORG_RDS <- file.path(PF, "data-dev", "ORG-TEXT-BUNDLE.rds")
say("building / loading the organization text bundle ...")
org <- pf_build_org_text(
  wide  = file.path(PF, "data-dev", "F9-P03-TEXT-WIDE-2022.rds"),
  bmf   = file.path(NPM, "data-raw", "bmf_2026_01_processed.csv"),
  cache = ORG_RDS)
say("  %d EINs | mission %4.1f%% | program %4.1f%% | ntee text %4.1f%%",
    nrow(org), 100*mean(org$has_mission), 100*mean(org$has_program),
    100*mean(nzchar(org$ntee_text)))

m <- readRDS(file.path(PF, "data-dev", sprintf("PF-MATCH-RESULT-%s.rds", SET)))
before <- pf_status(m)

say("")
say("applying tiebreak: tie_band=0.05 tie_high=%.2f keys=cov_all -> has_mission", TIE_HIGH)
m2 <- pf_purpose_tiebreak(m, org, pf_tiebreak_config(tie_high = TIE_HIGH))
after <- pf_status(m2)

ch <- as.data.frame(m2$result)
ch <- ch[ch$tiebreak_fired, c(".id", "tiebreak_key", "tiebreak_from_ein",
                              "overall_ein", "overall_name_y", "overall_score")]
say("")
say("=== %d picks changed ===", nrow(ch))
if (nrow(ch)) {
  b <- before[match(ch$.id, before$grant_id), c("grant_id", "recip_name", "bmf_name", "status")]
  ch$was_name <- b$bmf_name; ch$recip <- b$recip_name; ch$status <- b$status
  print(head(ch[, c(".id", "status", "recip", "was_name", "overall_name_y", "tiebreak_key")], 25))
  say("")
  say("outcome tier of the changed grants: %s",
      paste(sprintf("%s=%d", names(table(ch$status)), table(ch$status)), collapse = " "))
}

## score against the adjudicated verdicts where they exist
v <- fread(file.path(PF, "dev", "maybe-verdicts.csv"), colClasses = "character",
           na.strings = NULL, showProgress = FALSE)
a <- fread(file.path(PF, "data-dev", "AUDIT-MAYBE-100.csv"), colClasses = "character",
           na.strings = NULL, showProgress = FALSE)
a[, rank := as.integer(rank)]
v[, correct_rank := suppressWarnings(as.integer(correct_rank))]
truth <- merge(a[, .(grant_id, rank, ein)],
               v[!is.na(correct_rank), .(grant_id, correct_rank)], by = "grant_id")
truth <- truth[rank == correct_rank, .(grant_id, correct_ein = .pf_ein(ein))]

sc <- function(st, lab) {
  z <- merge(as.data.table(st)[, .(grant_id, ein = .pf_ein(ein))], truth, by = "grant_id")
  say("  %-8s correct top pick on %d of %d adjudicated grants (%.3f)",
      lab, sum(z$ein == z$correct_ein), nrow(z), mean(z$ein == z$correct_ein))
  invisible(z)
}
say("")
say("=== against the %d adjudicated answers ===", nrow(truth))
z0 <- sc(before, "before"); z1 <- sc(after, "after")
mv <- merge(z0[, .(grant_id, was = ein == correct_ein)],
            z1[, .(grant_id, now = ein == correct_ein)], by = "grant_id")
say("  gained %d, lost %d", mv[!was & now, .N], mv[was & !now, .N])
if (mv[was & !now, .N]) print(mv[was & !now])
