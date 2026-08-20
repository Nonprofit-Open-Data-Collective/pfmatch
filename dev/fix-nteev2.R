#!/usr/bin/env Rscript
# ============================================================================
# fix-nteev2.R -- rebuild the BMF's NTEEv2 fields with the canonical
# implementation from `fiscal` (get_clean_ntee / get_industry / get_org_type).
#
# dev/check-nteev2.R found the stored field wrong on 13.82% of unified-BMF rows,
# 483,072 of them in the code component alone. Two error classes:
#
#   specialty codes  B11 stored as EDU-B11-MS, correct EDU-B00-MS. In NTEEv2 the
#                    01-19 digits encode organization TYPE, not activity, so they
#                    belong in the third slot and the code slot becomes B00. The
#                    stored value double-encodes. Confirmed against the bundled
#                    NCCS reference, which maps A01 -> ART-A00-AA and
#                    A0161 -> ART-A61-AA -- exactly what get_clean_ntee() emits.
#   stale/missing    P20 stored as HMS-Z99-RG though the raw code is present.
#
# Input column: ntee_code_raw, NOT ntee_code_clean. Recomputing from raw agrees
# with the stored field 86.18% vs 68.69% from clean, because clean is already
# truncated to 3 characters (losing the B8443 -> B43 rule) and carries the text
# sentinels INVALID / UNDEFINED, which get_clean_ntee() would turn into codes
# like UNU-UND-RG.
#
# nteev2_org_type is NOT rebuilt -- it already agrees 100.00%.
#
#   PF_BMF=unified|active
# Writes <input>-nteev2fix.csv alongside the source, and a change report.
# ============================================================================
suppressWarnings(suppressMessages({
  library(data.table); library(stringr); library(dplyr) }))
setDTthreads(0)

NPM  <- Sys.getenv("NPMATCH_DIR", "../npmatch")
PF   <- Sys.getenv("PFMATCH_DIR", ".")
BASE <- Sys.getenv("PF_BMF", "unified")
FISC <- Sys.getenv("FISCAL_DIR", "../fiscal")
say  <- function(...) cat(sprintf(...), "\n")
hr   <- function() cat(strrep("-", 72), "\n")
source(file.path(FISC, "R", "nteev2.R"))

CSV <- switch(BASE,
  unified = file.path(NPM, "data-raw", "bmf_unified_geocoded.csv"),
  active  = file.path(NPM, "data-raw", "bmf_2026_01_processed.csv"))
OUT <- sub("[.]csv$", "-nteev2fix.csv", CSV)

say("reading %s ...", basename(CSV))
d <- fread(CSV, colClasses = "character", showProgress = FALSE)
say("  %s rows x %d cols", format(nrow(d), big.mark = ","), ncol(d))

old <- d[, .(nteev2, nteev2_code, nteev2_subsector, nteev2_org_type,
             nteev2_subsector_definition)]

## ---- recompute from the raw code -------------------------------------------
new_code <- get_clean_ntee(d$ntee_code_raw)
new_ind  <- get_industry(d$ntee_code_raw)
new_type <- get_org_type(d$ntee_code_raw)
new_v2   <- paste0(new_ind, "-", new_code, "-", new_type)

## subsector_definition: derive the code->label map from the BMF's own rows
## rather than inventing labels, so wording stays exactly as it already is.
lut <- unique(d[nzchar(nteev2_subsector_definition),
                .(nteev2_subsector, nteev2_subsector_definition)],
              by = "nteev2_subsector")
new_def <- lut$nteev2_subsector_definition[match(new_ind, lut$nteev2_subsector)]
miss_def <- unique(new_ind[is.na(new_def)])
if (length(miss_def))
  say("  NOTE: no existing label for subsector(s): %s -- left blank",
      paste(miss_def, collapse = ", "))
new_def[is.na(new_def)] <- ""

hr(); say("CHANGES"); hr()
chg <- function(a, b) sum(a != b, na.rm = TRUE)
say("nteev2                      : %s rows changed (%.2f%%)",
    format(chg(old$nteev2, new_v2), big.mark = ","), 100 * mean(old$nteev2 != new_v2))
say("nteev2_code                 : %s (%.2f%%)",
    format(chg(old$nteev2_code, new_code), big.mark = ","), 100 * mean(old$nteev2_code != new_code))
say("nteev2_subsector            : %s (%.2f%%)",
    format(chg(old$nteev2_subsector, new_ind), big.mark = ","), 100 * mean(old$nteev2_subsector != new_ind))
say("nteev2_org_type             : %s (%.2f%%)  [not rebuilt if 0]",
    format(chg(old$nteev2_org_type, new_type), big.mark = ","), 100 * mean(old$nteev2_org_type != new_type))
say("nteev2_subsector_definition : %s (%.2f%%)",
    format(chg(old$nteev2_subsector_definition, new_def), big.mark = ","),
    100 * mean(old$nteev2_subsector_definition != new_def))

## ---- write ------------------------------------------------------------------
d[, `:=`(nteev2 = new_v2, nteev2_code = new_code, nteev2_subsector = new_ind,
         nteev2_org_type = new_type, nteev2_subsector_definition = new_def)]
say("")
say("writing %s ...", basename(OUT))
fwrite(d, OUT)
say("  %.0f MB", file.size(OUT) / 1e6)

rep <- data.table(ntee_code_raw = d$ntee_code_raw,
                  old_nteev2 = old$nteev2, new_nteev2 = new_v2)[old_nteev2 != new_nteev2]
rep <- rep[, .N, by = .(ntee_code_raw, old_nteev2, new_nteev2)][order(-N)]
fwrite(rep, file.path(PF, "data-dev", sprintf("NTEEV2-CHANGES-%s.csv", BASE)))
hr(); say("TOP CHANGES"); hr()
print(head(rep, 20))
say("")
say("full change list: data-dev/NTEEV2-CHANGES-%s.csv (%s distinct patterns)",
    BASE, format(nrow(rep), big.mark = ","))
say("")
say("verify: PF_BMF=%s Rscript dev/check-nteev2.R  should now report ~100%%", BASE)
