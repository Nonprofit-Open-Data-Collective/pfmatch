#!/usr/bin/env Rscript
# ============================================================================
# build-purpose-testset-yes.R -- a SILVER-standard companion to
# data-dev/PURPOSE-TESTSET.csv.
#
# The 63 adjudicated MAYBE grants are the gold set but far too small to measure
# a similarity metric on (31 have a contentful purpose). This builds a much
# larger set from the YES tier of the 5,000-grant run: the accepted EIN is
# treated as correct, and the other top-k candidates for the same grant are
# distractors. YES is not hand-verified, so it is silver, not gold -- but it is
# the same discrimination task, at n in the thousands.
#
# `hard` marks grants where the runner-up is inside the tie band, which is the
# situation a purpose tiebreak would actually be invoked in.
#
# Out: data-dev/PURPOSE-TESTSET-YES.csv
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
PF  <- Sys.getenv("PFMATCH_DIR", ".")
NPM <- Sys.getenv("NPMATCH_DIR", "../npmatch")
BMF_CSV <- file.path(NPM, "data-raw", "bmf_2026_01_processed.csv")
K <- 5L
say <- function(...) cat(sprintf(...), "\n")

suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
source(file.path(PF, "dev", "purpose-enrich.R"))

m  <- readRDS(file.path(PF, "data-dev", "PF-MATCH-RESULT-1k.rds"))
st <- pf_status(m)
yes_ids <- st$grant_id[st$status == "YES"]
say("YES grants in the 5,000-grant run: %d", length(yes_ids))

say("building BMF context ...")
ctx <- pf_bmf_context(BMF_CSV)

say("building candidate frame (k = %d) ...", K)
cand <- as.data.table(pf_candidate_frame(m, ids = yes_ids, k = K, bmf_context = ctx))
say("  %d candidate rows over %d grants", nrow(cand), uniqueN(cand$grant_id))

cand[, is_correct := is_top_pick == 1L]
cand[, has_truth  := TRUE]
cand[, verdict    := "YES_SILVER"]
cand[, correct_rank := rank[which(is_correct)][1], by = grant_id]
# how contested is this grant? tie band is where a purpose tiebreak would fire
cand[, n_cand := .N, by = grant_id]
cand[, top_score := max(score), by = grant_id]
cand[, runner_up := {s <- sort(score, decreasing = TRUE); if (.N > 1) s[2] else NA_real_},
     by = grant_id]
cand[, margin := top_score - runner_up]
cand[, hard := !is.na(margin) & margin <= 0.05]

cand <- pt_enrich(cand)

fwrite(cand, file.path(PF, "data-dev", "PURPOSE-TESTSET-YES.csv"), na = "")

g <- unique(cand, by = "grant_id")
say("")
say("wrote data-dev/PURPOSE-TESTSET-YES.csv : %d rows, %d grants", nrow(cand), nrow(g))
say("  grants with >1 candidate            : %d", sum(g$n_cand > 1))
say("  ... and a contentful purpose        : %d", sum(g$n_cand > 1 & g$purpose_contentful))
say("  ... and a runner-up in the tie band : %d",
    sum(g$n_cand > 1 & g$purpose_contentful & g$hard))
say("candidate rows with NTEE ref text %4.1f%% | mission %4.1f%% | program %4.1f%%",
    100*mean(nzchar(cand$cand_ntee_ref_text)), 100*mean(nzchar(cand$cand_mission)),
    100*mean(nzchar(cand$cand_prog_all)))
