#!/usr/bin/env Rscript
# ============================================================================
# Confirm the dyad plan against the FULL UNIFIED REFERENCE.
#
# Everything measured so far used the 50k pf_match built on the January monthly
# BMF (1,924,822 rows). The package now matches against the augmented unified
# reference (3,891,187 rows: 3.69M unified BMF + 193k Schedule I aliases). That
# is a different candidate-generation regime, and the dyad claims are claims
# about candidate lists, so they have to be re-measured rather than assumed:
#
#   - the unified BMF adds 1.48M `legacy` EINs, so pairs that had no BMF row
#     now resolve, which can only ADD substitutable edges;
#   - the alias rows add name variants, which changes who is in the tie band;
#   - more candidates per query means more chances for a spurious tie AND more
#     chances for a genuine same-body tie.
#
# The prediction being tested, stated before the run:
#   1. MAYBE -> YES promotions occur at a similar or higher rate;
#   2. NO does not move;
#   3. accuracy on the adjudicated answers does not fall.
# (3) is the one that could kill the plan.
#
# Baseline for this benchmark, plain monthly BMF: 2,821 YES / 1,006 MAYBE /
# 1,093 NO / 80 OOS.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
# The INSTALLED npmatch is older than its source: np_cascade() there does not
# accept name_freq/token_idf/ref_index, which pf_match_grants() passes. Load the
# source tree so this measures the code we are actually developing.
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
DYADS <- file.path(PF, "data-dev", "PF-DYADS-UNIFIED.rds")

## ---------------------------------------------------------------- the grants
g <- rbindlist(lapply(sprintf(file.path(PF, "inputs", "1k_grants_0%d.csv"), 1:5),
                      function(p) fread(p, colClasses = "character", showProgress = FALSE)),
               use.names = TRUE, fill = TRUE)
g[, grant_id := sprintf("G%06d", .I)]
hr(); say("BENCHMARK: %s grants against the augmented unified reference",
          format(nrow(g), big.mark = ",")); hr()

prep <- pf_prepare(g, dedup = "fuzzy", verbose = FALSE)
say("identities: %s", format(nrow(prep$recipients), big.mark = ","))
ref <- pf_reference(REF, cache = CACHE, verbose = FALSE)
say("reference : %s rows", format(nrow(ref$reference), big.mark = ","))

## --------------------------------------------------------------- the cascade
# pf_match_grants keeps the scored pairs, which pf_link (batched) does not.
# The dyad collapse needs them, so the benchmark runs the unbatched path.
t0 <- proc.time()[["elapsed"]]
m <- pf_match_grants(prep$recipients, ref, recover = TRUE, verbose = FALSE,
                     passes = c(pf_staged_passes("lean"),
                                pf_recovery_passes(state = TRUE)))
say("cascade: %.0f s", proc.time()[["elapsed"]] - t0)
say("scored pairs: %s", format(nrow(as.data.frame(attr(m$result, "pairs"))), big.mark = ","))

D <- readRDS(DYADS)
say("dyads: %s (%s substitutable)", format(nrow(D), big.mark = ","),
    format(sum(D$dyad_class == "substitutable"), big.mark = ","))

## ------------------------------------------------------------ the comparison
tier_of <- function(x) table(factor(as.character(as.data.frame(x$result)$tier),
                                    levels = c("YES", "MAYBE", "NO")))
base_t <- tier_of(m)
say("")
say("baseline tiers on identities: YES %d  MAYBE %d  NO %d",
    base_t[["YES"]], base_t[["MAYBE"]], base_t[["NO"]])

variants <- list(
  `operating-first` = pf_dyad_config(policy = "operating"),
  `keep-top`        = pf_dyad_config(policy = "top"),
  `+related (unsafe)` = pf_dyad_config(policy = "operating",
                                       use = c("substitutable", "related")))
out <- list()
for (nm in names(variants)) {
  sb(); say("VARIANT: %s", nm); sb()
  out[[nm]] <- pf_dyad_collapse(m, D, variants[[nm]], np_config = m$config)
  t <- tier_of(out[[nm]])
  say("  YES %6d (%+d)   MAYBE %6d (%+d)   NO %6d (%+d)",
      t[["YES"]],   t[["YES"]]   - base_t[["YES"]],
      t[["MAYBE"]], t[["MAYBE"]] - base_t[["MAYBE"]],
      t[["NO"]],    t[["NO"]]    - base_t[["NO"]])
}

## ---------------------------------------------------- prediction 2: NO moves?
hr(); say("PREDICTION 2  DOES ANYTHING FALL INTO NO?"); hr()
for (nm in names(out)) {
  b <- as.data.table(as.data.frame(m$result))[, .(.id, t0 = tier)]
  a <- as.data.table(as.data.frame(out[[nm]]$result))[, .(.id, t1 = tier)]
  mv <- merge(b, a, by = ".id")[t0 != t1, .N, by = .(t0, t1)][order(-N)]
  say("%s:", nm); print(mv, row.names = FALSE)
}

## ------------------------------------------ prediction 3: accuracy vs truth
hr(); say("PREDICTION 3  ACCURACY ON THE ADJUDICATED ANSWERS"); hr()
# The verdicts were labelled on 50k grant ids; this benchmark is the 5k sample,
# so join on the recipient identity rather than the grant id.
au <- fread(file.path(PF, "data-dev", "AUDIT-MAYBE-100.csv"), colClasses = "character")
v  <- fread(file.path(PF, "dev", "maybe-verdicts.csv"), colClasses = "character")
v[, correct_rank := suppressWarnings(as.integer(correct_rank))]
au[, rank := as.integer(rank)]
truth <- merge(au[, .(grant_id, rank, ein, recip_name, recip_state)],
               v[!is.na(correct_rank), .(grant_id, correct_rank, verdict)],
               by = "grant_id")
truth <- truth[rank == correct_rank, .(recip_name, recip_state,
                                       correct_ein = e9(ein), verdict)]
key <- function(n, s) paste(toupper(trimws(gsub("[^A-Za-z0-9 ]", " ", n))), s)
truth[, k := key(recip_name, recip_state)]
truth <- unique(truth, by = "k")
say("adjudicated answers with a resolvable key: %d", nrow(truth))

score_of <- function(x, label) {
  r <- as.data.table(as.data.frame(x$result))
  # pf_recipients() sets grant_id = paste0("R", recipient_uid), and the cascade
  # carries that through as .id, so the join is on grant_id.
  q <- as.data.table(prep$recipients)
  nmcol <- intersect(c("recip_name", "name_x"), names(q))[1]
  stcol <- intersect(c("recip_state", "recip_state_raw"), names(q))[1]
  i <- match(r$.id, q$grant_id)
  r[, k := key(q[[nmcol]][i], q[[stcol]][i])]
  j <- merge(r[, .(k, ein = e9(overall_ein), tier)], truth, by = "k")
  if (!nrow(j)) { say("%-20s no overlap", label); return(invisible(NULL)) }
  say("%-20s n = %3d   correct EIN %3d (%.0f%%)   YES-tier %3d", label,
      nrow(j), sum(j$ein == j$correct_ein, na.rm = TRUE),
      100*mean(j$ein == j$correct_ein, na.rm = TRUE), sum(j$tier == "YES"))
  invisible(j)
}
jb <- score_of(m, "baseline")
for (nm in names(out)) score_of(out[[nm]], nm)

## ----------------------------------------------------------- what collapsed
hr(); say("WHAT THE DEFAULT COLLAPSED"); hr()
a <- as.data.table(as.data.frame(out[["operating-first"]]$result))
say("grants with a collapse : %s", format(sum(a$dyad_collapsed), big.mark = ","))
say("candidates removed     : %s",
    format(sum(a$dyad_n_before - a$dyad_n_after, na.rm = TRUE), big.mark = ","))
b <- as.data.table(as.data.frame(m$result))[, .(.id, t0 = tier, e0 = overall_ein,
                                                n0 = overall_name_y)]
cmp <- merge(b, a[, .(.id, t1 = tier, e1 = overall_ein, n1 = overall_name_y,
                      dyad_collapsed)], by = ".id")
pro <- cmp[t0 == "MAYBE" & t1 == "YES"]
say("promotions: %d", nrow(pro))
if (nrow(pro)) print(head(pro[, .(kept = substr(n1,1,36), was = substr(n0,1,36))], 20),
                     row.names = FALSE)

saveRDS(list(base = base_t, variants = lapply(out, tier_of), truth_n = nrow(truth)),
        file.path(PF, "data-dev", "BENCH-DYAD-UNIFIED.rds"), compress = FALSE)
say(""); say("wrote data-dev/BENCH-DYAD-UNIFIED.rds")
