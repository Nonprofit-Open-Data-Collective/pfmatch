#!/usr/bin/env Rscript
# ============================================================================
# Confirm Phase 0c against the augmented unified reference. Third design.
#
# The two earlier attempts both failed on cost, and the reason is worth
# recording because it is a Phase 1 problem, not a dyad problem:
#
#   - unbatched over 5,000 grants: the scored pair set reached 17 GB;
#   - batched at 1,000 through pf_link(), three variants: the FIRST batch of
#     1,000 identities had not finished after 60 CPU-minutes. Against the
#     January monthly BMF the same cascade runs at 33.5 s per 1,000 grants.
#     The augmented unified reference (3,891,187 rows against 1,924,822) is
#     roughly two orders of magnitude slower here, and that needs its own
#     investigation -- see dev/REF-PERFORMANCE.md.
#
# So: ONE cascade over 1,000 grants, three collapses applied to that one
# result. The cascade is the expensive part and the collapse is cheap, so
# re-running the cascade per variant was pure waste. pf_status() is called on
# each collapsed result, which also exercises the wiring path that
# pf_run_batches() uses.
#
# Predictions, unchanged and stated before the run:
#   1. MAYBE -> YES promotions occur;
#   2. nothing is pushed into NO;
#   3. accuracy on the adjudicated answers does not fall.
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
e9 <- function(z) { z <- gsub("[^0-9]", "", as.character(z))
                    fifelse(nchar(z) == 9L, z, NA_character_) }
tick <- function() proc.time()[["elapsed"]]

REF   <- file.path(PF, "data-dev", "BMF-AUGMENTED-bmf_unified_geocoded_2026-08-20.csv")
CACHE <- file.path(PF, "data-dev", "BMF-REF-AUG-2026-08-20.rds")
N     <- as.integer(Sys.getenv("PF_N", "1000"))

g <- fread(file.path(PF, "inputs", "1k_grants_01.csv"), colClasses = "character",
           showProgress = FALSE)
if (N < nrow(g)) g <- g[1:N]
g[, grant_id := sprintf("G%06d", .I)]
hr(); say("BENCHMARK  %s grants, augmented unified reference", format(nrow(g), big.mark=",")); hr()

prep <- pf_prepare(g, dedup = "fuzzy", verbose = FALSE)
say("identities: %s", format(nrow(prep$recipients), big.mark = ","))
t0 <- tick(); ref <- pf_reference(REF, cache = CACHE, verbose = FALSE)
say("reference : %s rows (loaded in %.0f s)", format(nrow(ref$reference), big.mark=","), tick()-t0)
D <- readRDS(file.path(PF, "data-dev", "PF-DYADS-UNIFIED.rds"))
say("dyads     : %s (%s substitutable)", format(nrow(D), big.mark=","),
    format(sum(D$dyad_class == "substitutable"), big.mark=","))

sb(); say("CASCADE (once)"); sb()
t0 <- tick()
m <- pf_match_grants(prep$recipients, ref, recover = TRUE, verbose = TRUE,
                     passes = c(pf_staged_passes("lean"), pf_recovery_passes(state = TRUE)))
el <- tick() - t0
m <- pf_drop_self_matches(m, verbose = FALSE)
np <- nrow(as.data.frame(attr(m$result, "pairs")))
say("cascade %.0f s (%.1f s per 1,000 identities) | %s scored pairs",
    el, 1000 * el / nrow(prep$recipients), format(np, big.mark = ","))
say("pairs per identity: %.0f", np / nrow(prep$recipients))

## ------------------------------------------------------------ the variants
status_of <- function(x) as.data.table(pf_status(x))
s0 <- status_of(m)
tb0 <- table(factor(s0$status, pf_status_levels()))
say(""); say("baseline: YES %d  MAYBE %d  NO %d  OOS %d",
             tb0[["YES"]], tb0[["MAYBE"]], tb0[["NO"]], tb0[["OOS"]])

variants <- list(
  `operating-first`   = pf_dyad_config(policy = "operating"),
  `keep-top`          = pf_dyad_config(policy = "top"),
  `+related (unsafe)` = pf_dyad_config(policy = "operating",
                                       use = c("substitutable", "related")))
S <- list(baseline = s0)
for (nm in names(variants)) {
  sb(); say("VARIANT: %s", nm); sb()
  x <- pf_dyad_collapse(m, D, variants[[nm]], np_config = m$config)
  st <- status_of(x)
  st <- pfmatch:::.pf_attach_dyad_cols(st, x)     # the pf_run_batches path
  S[[nm]] <- st
  tb <- table(factor(st$status, pf_status_levels()))
  say("  YES %5d (%+d)  MAYBE %5d (%+d)  NO %5d (%+d)",
      tb[["YES"]], tb[["YES"]]-tb0[["YES"]], tb[["MAYBE"]], tb[["MAYBE"]]-tb0[["MAYBE"]],
      tb[["NO"]], tb[["NO"]]-tb0[["NO"]])
}

hr(); say("PREDICTION 1  PROMOTIONS"); hr()
say("%-20s %6s %6s %6s %6s %10s", "run", "YES", "MAYBE", "NO", "OOS", "collapsed")
for (nm in names(S)) {
  tb <- table(factor(S[[nm]]$status, pf_status_levels()))
  cl <- if (is.null(S[[nm]]$dyad_collapsed)) NA_integer_ else sum(S[[nm]]$dyad_collapsed, na.rm=TRUE)
  say("%-20s %6d %6d %6d %6d %10s", nm, tb[["YES"]], tb[["MAYBE"]], tb[["NO"]], tb[["OOS"]],
      ifelse(is.na(cl), "-", format(cl)))
}
say("")
o <- S$`operating-first`
say("promotions as a share of baseline MAYBE: %.1f%%",
    100 * (tb0[["MAYBE"]] - table(factor(o$status, pf_status_levels()))[["MAYBE"]]) / tb0[["MAYBE"]])
say("(the 50k monthly-BMF run gave 6.5%%)")

hr(); say("PREDICTION 2  DOES ANYTHING FALL INTO NO?"); hr()
for (nm in setdiff(names(S), "baseline")) {
  mv <- merge(s0[, .(grant_id, t0 = status)], S[[nm]][, .(grant_id, t1 = status)],
              by = "grant_id")[t0 != t1]
  say("%s: %d changed tier; into NO from elsewhere: %d", nm, nrow(mv),
      sum(mv$t1 == "NO" & mv$t0 != "NO"))
  if (nrow(mv)) print(mv[, .N, by = .(t0, t1)][order(-N)], row.names = FALSE)
  if (!is.null(S[[nm]]$dyad_collapsed))
    say("  every change on a collapsed identity: %s",
        all(mv$grant_id %in% S[[nm]][dyad_collapsed == TRUE]$grant_id))
}

hr(); say("PREDICTION 3  ACCURACY ON THE ADJUDICATED ANSWERS"); hr()
au <- fread(file.path(PF, "data-dev", "AUDIT-MAYBE-100.csv"), colClasses = "character")
v  <- fread(file.path(PF, "dev", "maybe-verdicts.csv"), colClasses = "character")
au[, rank := as.integer(rank)]; v[, correct_rank := suppressWarnings(as.integer(correct_rank))]
truth <- merge(au[, .(grant_id, rank, ein, recip_name, recip_state)],
               v[!is.na(correct_rank), .(grant_id, correct_rank)], by = "grant_id")
truth <- truth[rank == correct_rank, .(recip_name, recip_state, correct_ein = e9(ein))]
key <- function(n, s) paste(toupper(trimws(gsub("[^A-Za-z0-9 ]", " ", n))), s)
truth[, k := key(recip_name, recip_state)]
truth <- unique(truth[!is.na(correct_ein)], by = "k")
say("adjudicated answers: %d", nrow(truth))
for (nm in names(S)) {
  r <- copy(S[[nm]]); r[, k := key(recip_name, recip_state)]
  j <- merge(r[, .(k, ein = e9(ein))], truth, by = "k")
  if (!nrow(j)) { say("%-20s no overlap with this sample", nm); next }
  say("%-20s n = %3d   correct %3d (%.0f%%)", nm, nrow(j),
      sum(j$ein == j$correct_ein, na.rm=TRUE), 100*mean(j$ein == j$correct_ein, na.rm=TRUE))
}

hr(); say("WHAT COLLAPSED"); hr()
cmp <- merge(s0[, .(grant_id, recip_name, t0 = status, e0 = ein, n0 = bmf_name)],
             o[, .(grant_id, t1 = status, e1 = ein, n1 = bmf_name,
                   dyad_collapsed, dyad_from_ein)], by = "grant_id")
say("identities collapsed: %d   reported EIN changed: %d",
    sum(cmp$dyad_collapsed, na.rm=TRUE), sum(!is.na(cmp$dyad_from_ein)))
pro <- cmp[t0 == "MAYBE" & t1 == "YES"]
say("promotions: %d", nrow(pro))
if (nrow(pro)) print(pro[, .(recip = substr(recip_name,1,26), kept = substr(n1,1,30),
                             was = substr(n0,1,30))], row.names = FALSE)
say("")
say("collapsed but NOT promoted (the tie shrank, the tier did not move): %d",
    sum(cmp$dyad_collapsed & cmp$t0 == cmp$t1, na.rm = TRUE))

fwrite(cmp, file.path(PF, "data-dev", "BENCH-DYAD-1K.csv"))
say(""); say("wrote data-dev/BENCH-DYAD-1K.csv")
