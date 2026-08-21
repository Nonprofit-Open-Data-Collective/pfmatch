#!/usr/bin/env Rscript
# ============================================================================
# Confirm Phase 0c against the FULL UNIFIED REFERENCE, through the shipped path.
#
# An earlier version of this benchmark called pf_match_grants() unbatched so it
# could hold the scored pairs and hand them to pf_dyad_collapse(). Against the
# 3,891,187-row augmented reference that pair set reached 17 GB and was still
# growing. The wired path does not have that problem -- pf_run_batches()
# collapses inside each batch and discards the pairs with it -- and it is also
# the code that actually ships, so this measures that instead.
#
# Predictions, stated before the run:
#   1. MAYBE -> YES promotions occur, at a similar or higher rate than the
#      6.5% of MAYBE seen on the 50k monthly-BMF run;
#   2. nothing is pushed into NO;
#   3. accuracy on the adjudicated answers does not fall.
# (3) is the one that could kill the plan.
#
# Baseline for this benchmark on the plain monthly BMF:
#   2,821 YES / 1,006 MAYBE / 1,093 NO / 80 OOS.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
# The INSTALLED npmatch is older than its source: np_cascade() there does not
# accept name_freq/token_idf/ref_index, which pf_match_grants() passes.
suppressWarnings(suppressMessages(devtools::load_all(
  Sys.getenv("NPMATCH_DIR", "../npmatch"), quiet = TRUE)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
setDTthreads(6L)
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("=", 78), "\n")
sb  <- function() cat(strrep("-", 78), "\n")
e9 <- function(z) { z <- gsub("[^0-9]", "", as.character(z))
                    fifelse(nchar(z) == 9L, z, NA_character_) }

REF   <- file.path(PF, "data-dev", "BMF-AUGMENTED-bmf_unified_geocoded_2026-08-20.csv")
CACHE <- file.path(PF, "data-dev", "BMF-REF-AUG-2026-08-20.rds")
BATCH <- 1000L

g <- rbindlist(lapply(sprintf(file.path(PF, "inputs", "1k_grants_0%d.csv"), 1:5),
                      function(p) fread(p, colClasses = "character", showProgress = FALSE)),
               use.names = TRUE, fill = TRUE)
g[, grant_id := sprintf("G%06d", .I)]
hr(); say("BENCHMARK  %s grants, augmented unified reference, wired path",
          format(nrow(g), big.mark = ",")); hr()

prep <- pf_prepare(g, dedup = "fuzzy", verbose = FALSE)
say("identities: %s", format(nrow(prep$recipients), big.mark = ","))
ref <- pf_reference(REF, cache = CACHE, verbose = FALSE)
say("reference : %s rows", format(nrow(ref$reference), big.mark = ","))
D <- readRDS(file.path(PF, "data-dev", "PF-DYADS-UNIFIED.rds"))
say("dyads     : %s (%s substitutable)", format(nrow(D), big.mark = ","),
    format(sum(D$dyad_class == "substitutable"), big.mark = ","))

runs <- list(
  baseline          = NULL,
  `operating-first` = pf_dyad_config(policy = "operating"),
  `keep-top`        = pf_dyad_config(policy = "top"))

res <- list()
for (nm in names(runs)) {
  sb(); say("RUN: %s", nm); sb()
  # a distinct checkpoint dir per variant: pf_run_batches resumes on file name
  # alone and would otherwise hand back another variant's results
  d <- file.path(PF, "data-dev", sprintf("bench-dyad-%s",
                                         gsub("[^a-z]", "", tolower(nm))))
  unlink(d, recursive = TRUE)
  t0 <- proc.time()[["elapsed"]]
  l <- pf_link(prep, ref, dir = d, batch_size = BATCH,
               dyads = if (is.null(runs[[nm]])) NULL else D,
               dyad_config = if (is.null(runs[[nm]])) pf_dyad_config() else runs[[nm]],
               verbose = FALSE)
  say("  %.0f s", proc.time()[["elapsed"]] - t0)
  res[[nm]] <- as.data.table(l$status)
  tb <- table(factor(res[[nm]]$status, pf_status_levels()))
  say("  YES %5d  MAYBE %5d  NO %5d  OOS %4d",
      tb[["YES"]], tb[["MAYBE"]], tb[["NO"]], tb[["OOS"]])
}

## ------------------------------------------------------------- predictions
hr(); say("PREDICTION 1  DO PROMOTIONS HAPPEN?"); hr()
b <- res$baseline
say("%-18s %7s %7s %7s %7s", "run", "YES", "MAYBE", "NO", "OOS")
for (nm in names(res)) {
  tb <- table(factor(res[[nm]]$status, pf_status_levels()))
  bb <- table(factor(b$status, pf_status_levels()))
  say("%-18s %7d %7d %7d %7d   %s", nm, tb[["YES"]], tb[["MAYBE"]], tb[["NO"]], tb[["OOS"]],
      if (nm == "baseline") "" else
        sprintf("(YES %+d, MAYBE %+d, NO %+d)", tb[["YES"]] - bb[["YES"]],
                tb[["MAYBE"]] - bb[["MAYBE"]], tb[["NO"]] - bb[["NO"]]))
}
say("")
o <- res$`operating-first`
say("identities with a collapse: %s (%.1f%%)",
    format(sum(o$dyad_collapsed, na.rm = TRUE), big.mark = ","),
    100 * mean(o$dyad_collapsed, na.rm = TRUE))
say("reported EIN changed by the policy: %s",
    format(sum(!is.na(o$dyad_from_ein)), big.mark = ","))
bb <- table(factor(b$status, pf_status_levels()))
tb <- table(factor(o$status, pf_status_levels()))
say("promotions as a share of baseline MAYBE: %.1f%%",
    100 * (bb[["MAYBE"]] - tb[["MAYBE"]]) / bb[["MAYBE"]])

hr(); say("PREDICTION 2  DOES ANYTHING FALL INTO NO?"); hr()
for (nm in setdiff(names(res), "baseline")) {
  mv <- merge(b[, .(grant_id, t0 = status)],
              res[[nm]][, .(grant_id, t1 = status)], by = "grant_id")[t0 != t1]
  say("%s: %d identities changed tier", nm, nrow(mv))
  if (nrow(mv)) print(mv[, .N, by = .(t0, t1)][order(-N)], row.names = FALSE)
  say("  into NO from elsewhere: %d", sum(mv$t1 == "NO" & mv$t0 != "NO"))
  coll <- res[[nm]][dyad_collapsed == TRUE]$grant_id
  say("  every change on a collapsed identity: %s", all(mv$grant_id %in% coll))
}

hr(); say("PREDICTION 3  ACCURACY ON THE ADJUDICATED ANSWERS"); hr()
au <- fread(file.path(PF, "data-dev", "AUDIT-MAYBE-100.csv"), colClasses = "character")
v  <- fread(file.path(PF, "dev", "maybe-verdicts.csv"), colClasses = "character")
au[, rank := as.integer(rank)]
v[, correct_rank := suppressWarnings(as.integer(correct_rank))]
truth <- merge(au[, .(grant_id, rank, ein, recip_name, recip_state)],
               v[!is.na(correct_rank), .(grant_id, correct_rank)], by = "grant_id")
truth <- truth[rank == correct_rank, .(recip_name, recip_state, correct_ein = e9(ein))]
key <- function(n, s) paste(toupper(trimws(gsub("[^A-Za-z0-9 ]", " ", n))), s)
truth[, k := key(recip_name, recip_state)]
truth <- unique(truth[!is.na(correct_ein)], by = "k")
say("adjudicated answers: %d", nrow(truth))
say("")
say("%-18s %5s %10s %10s", "run", "n", "correct", "YES-tier")
for (nm in names(res)) {
  r <- copy(res[[nm]])
  r[, k := key(recip_name, recip_state)]
  j <- merge(r[, .(k, ein = e9(ein), status)], truth, by = "k")
  if (!nrow(j)) { say("%-18s no overlap", nm); next }
  say("%-18s %5d %5d (%3.0f%%) %10d", nm, nrow(j),
      sum(j$ein == j$correct_ein, na.rm = TRUE),
      100 * mean(j$ein == j$correct_ein, na.rm = TRUE), sum(j$status == "YES"))
}
say("")
say("The adjudicated set is 100 cases drawn from the 50k sample; the overlap")
say("with this 5k benchmark is small, so this is a regression check, not a")
say("measurement. A DROP here would still be disqualifying.")

hr(); say("WHAT COLLAPSED"); hr()
cmp <- merge(b[, .(grant_id, t0 = status, e0 = ein, n0 = bmf_name, recip_name)],
             o[, .(grant_id, t1 = status, e1 = ein, n1 = bmf_name,
                   dyad_collapsed, dyad_from_ein)], by = "grant_id")
pro <- cmp[t0 == "MAYBE" & t1 == "YES"]
say("promotions: %d", nrow(pro))
if (nrow(pro)) print(head(pro[, .(recip = substr(recip_name,1,26),
                                  kept = substr(n1,1,30), was = substr(n0,1,30))], 25),
                     row.names = FALSE)

fwrite(cmp, file.path(PF, "data-dev", "BENCH-DYAD-WIRED.csv"))
saveRDS(res, file.path(PF, "data-dev", "BENCH-DYAD-WIRED.rds"), compress = FALSE)
say(""); say("wrote data-dev/BENCH-DYAD-WIRED.csv / .rds")
