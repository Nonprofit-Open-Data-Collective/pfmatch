#!/usr/bin/env Rscript
# ============================================================================
# check-nteev2.R -- is the BMF's `nteev2` field correct?
#
# Recomputes it with the canonical implementation from the `fiscal` package
# (R/nteev2.R: get_clean_ntee / get_industry / get_org_type / get_nteev2) and
# compares field by field.
#
# Which input column matters. `get_clean_ntee()` and `get_industry()` both treat
# 5-character legacy codes specially -- B8443 resolves to B43, not B84 -- so:
#
#   ntee_code_raw    0,2,3,4,5 chars.  The real input. Keeps the legacy 5-char form.
#   ntee_code_clean  3,7,9 chars.      Already truncated to 3, and carries the
#                                      text sentinels INVALID (7) and UNDEFINED (9),
#                                      which get_clean_ntee would read as "INV"/"UND".
#
# So both are computed and compared, and the answer to "which should we use" is
# part of the output rather than an assumption.
#
#   PF_BMF=unified|active   which file to check   (default unified)
# ============================================================================
suppressWarnings(suppressMessages({
  library(data.table); library(stringr); library(dplyr) }))
setDTthreads(0)

NPM  <- Sys.getenv("NPMATCH_DIR", "../npmatch")
BASE <- Sys.getenv("PF_BMF", "unified")
FISC <- Sys.getenv("FISCAL_DIR", "../fiscal")
say  <- function(...) cat(sprintf(...), "\n")
hr   <- function() cat(strrep("-", 72), "\n")

src <- file.path(FISC, "R", "nteev2.R")
if (!file.exists(src)) stop("cannot find fiscal/R/nteev2.R at ", src)
source(src)
say("sourced %s", src)

CSV <- switch(BASE,
  unified = file.path(NPM, "data-raw", "bmf_unified_geocoded.csv"),
  active  = file.path(NPM, "data-raw", "bmf_2026_01_processed.csv"))

cols <- c("ein", "ntee_code_raw", "ntee_code_clean", "nteev2_code",
          "nteev2_subsector", "nteev2_org_type", "nteev2")
have <- intersect(cols, names(fread(CSV, nrows = 0L)))
d <- fread(CSV, select = have, colClasses = "character", showProgress = FALSE)
say("%s BMF: %s rows", BASE, format(nrow(d), big.mark = ","))

## ---- recompute -------------------------------------------------------------
d[, v2_from_raw   := get_nteev2(ntee_code_raw)]
d[, v2_from_clean := get_nteev2(ntee_code_clean)]
d[, ind_raw  := get_industry(ntee_code_raw)]
d[, code_raw := get_clean_ntee(ntee_code_raw)]
d[, type_raw := get_org_type(ntee_code_raw)]

hr(); say("1. WHOLE-FIELD AGREEMENT with the stored `nteev2`"); hr()
say("recomputed from ntee_code_raw   : %6.2f%% agree", 100 * mean(d$v2_from_raw == d$nteev2))
say("recomputed from ntee_code_clean : %6.2f%% agree", 100 * mean(d$v2_from_clean == d$nteev2))

hr(); say("2. COMPONENT-BY-COMPONENT (recomputed from ntee_code_raw)"); hr()
say("nteev2_subsector vs get_industry()   : %6.2f%% agree", 100 * mean(d$ind_raw  == d$nteev2_subsector))
say("nteev2_code      vs get_clean_ntee() : %6.2f%% agree", 100 * mean(d$code_raw == d$nteev2_code))
say("nteev2_org_type  vs get_org_type()   : %6.2f%% agree", 100 * mean(d$type_raw == d$nteev2_org_type))

hr(); say("3. WHERE DO THEY DIVERGE?"); hr()
bad <- d[v2_from_raw != nteev2]
say("disagreeing rows: %s (%.2f%%)", format(nrow(bad), big.mark = ","),
    100 * nrow(bad) / nrow(d))
if (nrow(bad)) {
  bad[, raw_nchar := nchar(ntee_code_raw)]
  say("")
  say("by length of ntee_code_raw:")
  print(bad[, .(rows = .N), by = raw_nchar][order(raw_nchar)])
  say("")
  say("which component disagrees:")
  say("  subsector only : %s", format(bad[ind_raw != nteev2_subsector & code_raw == nteev2_code & type_raw == nteev2_org_type, .N], big.mark = ","))
  say("  code only      : %s", format(bad[ind_raw == nteev2_subsector & code_raw != nteev2_code & type_raw == nteev2_org_type, .N], big.mark = ","))
  say("  org_type only  : %s", format(bad[ind_raw == nteev2_subsector & code_raw == nteev2_code & type_raw != nteev2_org_type, .N], big.mark = ","))
  say("  more than one  : %s", format(bad[(ind_raw != nteev2_subsector) + (code_raw != nteev2_code) + (type_raw != nteev2_org_type) > 1, .N], big.mark = ","))
  say("")
  say("most common disagreements:")
  print(head(bad[, .N, by = .(ntee_code_raw, stored = nteev2, recomputed = v2_from_raw)][order(-N)], 25))
}

hr(); say("4. SANITY: the documented examples"); hr()
ex <- c("B29", "B8443", "E0521", "B01", "B0129", "B40", "E22", "", "A115", "Q12")
print(data.table(input = ex, clean = get_clean_ntee(ex), industry = get_industry(ex),
                 org_type = get_org_type(ex), nteev2 = get_nteev2(ex)))

hr(); say("5. VERDICT"); hr()
ok_raw <- mean(d$v2_from_raw == d$nteev2)
if (ok_raw > 0.9999) {
  say("stored nteev2 reproduces exactly from ntee_code_raw -- NO FIX NEEDED")
} else {
  say("stored nteev2 does NOT reproduce (%.2f%% agreement).", 100 * ok_raw)
  say("Review section 3 before overwriting: a disagreement can mean the stored")
  say("field is stale, or that it was built from a different input column.")
}
saveRDS(d[, .(ein, ntee_code_raw, ntee_code_clean, nteev2, v2_from_raw, v2_from_clean)],
        file.path(Sys.getenv("PFMATCH_DIR", "."), "data-dev",
                  sprintf("NTEEV2-CHECK-%s.rds", BASE)))
say("wrote data-dev/NTEEV2-CHECK-%s.rds", BASE)
