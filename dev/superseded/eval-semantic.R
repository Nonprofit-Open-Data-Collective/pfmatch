#!/usr/bin/env Rscript
# ============================================================================
# Evaluate the stage-5 re-ranker against the 100 hand-adjudicated MAYBE cases.
#
# dev/maybe-verdicts.csv records, for each case, whether the algorithm's top
# pick was correct (CORRECT_TOP) or the correct EIN sat lower in the list
# (CORRECT_DEEPER, with correct_rank). That is exactly the ground truth this
# needs: does re-ranking move the correct candidate to first place, and does it
# break any case that was already right?
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
NPM <- Sys.getenv("NPMATCH_DIR", "../npmatch")
suppressWarnings(suppressMessages(devtools::load_all(NPM, quiet = TRUE)))
for (f in list.files(file.path(PF, "R"), pattern = "\\.R$", full.names = TRUE)) source(f)
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 74), "\n")

cand <- fread(file.path(PF, "data-dev", "AUDIT-MAYBE-100.csv"), colClasses = "character")
cand[, score := as.numeric(score)][, rank := as.integer(rank)]
v <- fread(file.path(PF, "dev", "maybe-verdicts.csv"), colClasses = "character")
v[, correct_rank := as.integer(correct_rank)]

# cases with a known correct candidate inside the surfaced list
truth <- v[verdict %in% c("CORRECT_TOP", "CORRECT_DEEPER")]
truth[verdict == "CORRECT_TOP" & is.na(correct_rank), correct_rank := 1L]
say("adjudicated cases with a known correct candidate: %d", nrow(truth))
say("  algorithm's top pick already correct: %d", sum(truth$verdict == "CORRECT_TOP"))
say("  correct EIN present but mis-ranked  : %d", sum(truth$verdict == "CORRECT_DEEPER"))

hr(); say("SEMANTIC SCORE SANITY"); hr()
rr <- pf_semantic_rerank(as.data.frame(cand))
setDT(rr)
say("purpose strings with no content words (semantic NA): %d of %d (%.0f%%)",
    sum(is.na(rr$semantic)), nrow(rr), 100 * mean(is.na(rr$semantic)))
say("semantic score distribution over scorable rows:")
print(round(quantile(rr$semantic, c(0, .25, .5, .75, .95, 1), na.rm = TRUE), 3))

hr(); say("DOES IT MOVE THE CORRECT CANDIDATE TO FIRST PLACE?"); hr()
# The baseline is npmatch's OWN pick (is_top_pick), which is not always the
# highest-scoring row: np_select() applies a separate high-tie rule. Comparing
# against score rank instead would score npmatch as wrong on cases it got right.
cand[, is_top_pick := as.integer(is_top_pick)]
evaluate <- function(w, band) {
  r <- as.data.table(pf_semantic_rerank(as.data.frame(cand), tie_band = band, weight = w))
  first <- r[rank_reranked == 1L, .(grant_id, new_top_rank = rank)]
  m <- merge(truth[, .(grant_id, correct_rank, verdict)], first, by = "grant_id")
  m[, ok := new_top_rank == correct_rank]
  list(n = nrow(m), ok = sum(m$ok),
       fixed = sum(m$ok & m$verdict == "CORRECT_DEEPER"),
       broke = sum(!m$ok & m$verdict == "CORRECT_TOP"))
}
base_ok <- sum(truth$verdict == "CORRECT_TOP")
say("baseline (npmatch's own pick): %d of %d correct", base_ok, nrow(truth))
say("")
say("%-8s %-8s %8s %8s %8s %8s", "weight", "band", "correct", "delta", "fixed", "broken")
for (w in c(0.02, 0.06, 0.15, 0.30)) {
  for (band in c(0.05, 0.15, 0.30, 0.50)) {
    e <- evaluate(w, band)
    say("%-8.2f %-8.2f %8d %8+d %8d %8d", w, band, e$ok, e$ok - base_ok, e$fixed, e$broke)
  }
}

hr(); say("WHICH MIS-RANKED CASES DOES IT FIX? (weight 0.06, band 0.05)"); hr()
r <- as.data.table(pf_semantic_rerank(as.data.frame(cand), tie_band = 0.05, weight = 0.06))
first <- r[rank_reranked == 1L, .(grant_id, new_top_rank = rank, new_name = cand_name,
                                  new_sem = round(semantic, 3))]
m <- merge(truth[, .(grant_id, correct_rank, verdict, note)], first, by = "grant_id")
fixed <- m[verdict == "CORRECT_DEEPER" & new_top_rank == correct_rank]
still <- m[verdict == "CORRECT_DEEPER" & new_top_rank != correct_rank]
broke <- m[verdict == "CORRECT_TOP" & new_top_rank != correct_rank]
say("FIXED (%d):", nrow(fixed))
if (nrow(fixed)) for (i in seq_len(nrow(fixed)))
  say("  %s  -> %s (sem %.2f)", fixed$grant_id[i], substr(fixed$new_name[i], 1, 44), fixed$new_sem[i])
say("\nSTILL WRONG (%d):", nrow(still))
if (nrow(still)) for (i in seq_len(nrow(still)))
  say("  %s  picked %s (sem %.2f), correct was rank %d",
      still$grant_id[i], substr(still$new_name[i], 1, 34), still$new_sem[i], still$correct_rank[i])
say("\nBROKEN (%d):", nrow(broke))
if (nrow(broke)) for (i in seq_len(nrow(broke)))
  say("  %s  now picks %s (sem %.2f)", broke$grant_id[i], substr(broke$new_name[i], 1, 44), broke$new_sem[i])
