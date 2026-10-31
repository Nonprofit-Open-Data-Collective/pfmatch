#!/usr/bin/env Rscript
# ============================================================================
# adjudicate-00b-patch-fdn.R -- backfill the foundation name into an already
# built packet, without re-running the 34-minute match.
#
# WHAT WAS WRONG. pf_status() reads the filer's name from FILERNAME1
# (R/report.R:44). The efv2 grant files do not carry that column -- they name
# the filer in ORG_NAME_L1 / ORG_NAME_L2 -- so filer_name came back NA on all
# 100 cases and the packet's FILING FOUNDATION block rendered "fdn_name: -"
# every time. The foundation's state and NTEE were present on 100 of 100, so
# only the name was missing.
#
# It is not fatal: dev/LLM-REVIEW-INSTRUCTIONS.md calls the filing foundation
# "useful context ... but weak evidence on its own". It is still worth having,
# because a reviewer deciding between a hospital and its foundation can use
# "who wrote the cheque" and the name is the readable part of that.
#
# WHY A PATCH RATHER THAN A RE-RUN. The defect is in one column of the
# case-level file. Re-running stage 00 would cost 34 minutes of matching to
# regenerate 479 candidate rows that are already correct, and -- more
# importantly -- would redraw nothing: the sample is seeded, so the same 100
# cases would come back. dev/adjudicate-00-packet.R has the same fix inline
# for any future run; this script exists only to repair the existing artifact.
#
# The join is on filer EIN, taking the first name seen per EIN. A filer that
# changed its name between tax years therefore gets one of its names rather
# than the per-year one, which does not matter for a context field.
#
# Idempotent: re-running it changes nothing once the names are in.
#
# USAGE  PFMATCH_DIR=. Rscript dev/adjudicate-00b-patch-fdn.R
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(library(npmatch)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
DD     <- file.path(PF, "data-dev")
GRANTS <- Sys.getenv("PF_ADJ_GRANTS", "^efv2_1k_grants_.*\\.csv$")

say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() cat(strrep("=", 78), "\n")

hr(); say("patch: foundation name into ADJ-EXP-CASES.rds"); hr()

f <- file.path(DD, "ADJ-EXP-CASES.rds")
if (!file.exists(f)) stop("ADJ-EXP-CASES.rds absent; run stage 00 first.", call. = FALSE)
cs <- as.data.table(readRDS(f))
say("cases: %d   with a foundation name now: %d",
    nrow(cs), sum(!is.na(cs$filer_name) & nzchar(cs$filer_name)))

if (all(!is.na(cs$filer_name) & nzchar(cs$filer_name))) {
  say("\nAlready populated. Nothing to do."); hr(); quit(save = "no")
}

g <- pf_read_grants(file.path(PF, "inputs"), pattern = GRANTS)
if (is.null(g$ORG_NAME_L1))
  stop("ORG_NAME_L1 is absent from the grant files; nothing to backfill from.",
       call. = FALSE)
sq <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; x }
fn <- data.table(ein = .pf_ein(g$ORG_EIN),
                 nm  = trimws(paste(sq(g$ORG_NAME_L1),
                                    if (!is.null(g$ORG_NAME_L2)) sq(g$ORG_NAME_L2) else "")))
fn <- fn[!is.na(ein) & nzchar(nm)][!duplicated(ein)]
say("filer names available: %d distinct EINs", nrow(fn))

cs[, filer_name := fn$nm[match(filer_ein, fn$ein)]]
hit <- sum(!is.na(cs$filer_name) & nzchar(cs$filer_name))
say("matched: %d of %d cases", hit, nrow(cs))
if (hit < nrow(cs))
  say("  %d unmatched -- those keep NA and render as '-', which is honest",
      nrow(cs) - hit)

saveRDS(cs, f)
say("\nrewrote %s", f)
say("\nexamples:")
print(head(cs[!is.na(filer_name), .(grant_id, filer_ein, filer_name, recip_name)], 5))
hr()
