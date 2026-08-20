#!/usr/bin/env Rscript
# ============================================================================
# probe-ntee-availability.R -- is the NTEE code available on the candidates that
# actually need disambiguating?
#
# The per-case dump from eval-purpose-sim.R showed the correct candidate
# carrying ntee_code_clean = INVALID / UNDEFINED in most of the hard cases.
# If that is systematic, every NTEE-based tiebreak is structurally blind on
# exactly the pairs it was added to separate. This measures it.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
PF  <- Sys.getenv("PFMATCH_DIR", ".")
NPM <- Sys.getenv("NPMATCH_DIR", "../npmatch")
BMF <- file.path(NPM, "data-raw", "bmf_2026_01_processed.csv")
say <- function(...) cat(sprintf(...), "\n")
bad <- function(x) { x <- toupper(trimws(as.character(x))); x[is.na(x)] <- ""
                     x == "" | x %in% c("INVALID", "UNDEFINED", "Z99", "Z") }

b <- fread(BMF, select = c("ein", "ntee_code_clean", "revenue_amount",
                           "filing_requirement_code_definition"),
           colClasses = "character", na.strings = NULL, showProgress = FALSE)
say("=== BMF, n = %d ===", nrow(b))
say("ntee_code_clean unusable (blank/INVALID/UNDEFINED/Z99): %4.1f%%",
    100 * mean(bad(b$ntee_code_clean)))
b[, rev := suppressWarnings(as.numeric(revenue_amount))]
b[, bucket := cut(rev, c(-Inf, 0, 1e5, 1e6, 1e7, Inf),
                  labels = c("no revenue", "<100k", "100k-1M", "1M-10M", ">10M"))]
print(b[, .(n = .N, pct_unusable_ntee = round(100 * mean(bad(ntee_code_clean)), 1)),
        by = bucket][order(bucket)])

for (f in c("PURPOSE-TESTSET", "PURPOSE-TESTSET-YES")) {
  p <- file.path(PF, "data-dev", paste0(f, ".csv"))
  if (!file.exists(p)) next
  d <- fread(p, colClasses = "character", na.strings = NULL, showProgress = FALSE)
  d[, is_correct := is_correct %in% c("TRUE", "true")]
  d <- d[has_truth %in% c("TRUE", "true")]
  say("")
  say("=== %s : %d rows, %d grants ===", f, nrow(d), uniqueN(d$grant_id))
  print(d[, .(rows = .N,
              pct_unusable_ntee = round(100 * mean(bad(CAND_ntee_code_clean)), 1),
              pct_no_mission    = round(100 * mean(!nzchar(cand_mission)), 1),
              pct_no_program    = round(100 * mean(!nzchar(cand_prog_all)), 1),
              pct_no_text_at_all = round(100 * mean(bad(CAND_ntee_code_clean) &
                                    !nzchar(cand_mission) & !nzchar(cand_prog_all)), 1)),
          by = is_correct])
  g <- d[, .(any_usable = sum(!bad(CAND_ntee_code_clean)),
             n = .N,
             correct_unusable = any(is_correct & bad(CAND_ntee_code_clean))), by = grant_id]
  say("grants where the CORRECT candidate has no usable NTEE: %d of %d (%4.1f%%)",
      sum(g$correct_unusable), nrow(g), 100 * mean(g$correct_unusable))
  say("grants where NO candidate has a usable NTEE          : %d (%4.1f%%)",
      sum(g$any_usable == 0), 100 * mean(g$any_usable == 0))
  say("grants where every candidate shares one NTEE letter  : %d (%4.1f%%)",
      d[, .(u = uniqueN(substr(CAND_ntee_code_clean, 1, 1)[!bad(CAND_ntee_code_clean)])),
        by = grant_id][, sum(u == 1)],
      d[, .(u = uniqueN(substr(CAND_ntee_code_clean, 1, 1)[!bad(CAND_ntee_code_clean)])),
        by = grant_id][, 100 * mean(u == 1)])
}
