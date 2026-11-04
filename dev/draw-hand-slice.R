#!/usr/bin/env Rscript
# ============================================================================
# draw-hand-slice.R -- draw the hand-labelled slice of stage 1.
#
# WHAT THIS IS FOR. Every label in stage 1 was written by a Claude model
# (`claude-fable-5-1`, plus `claude-haiku-5-5` on the gated rows), so where the
# two agree they can be wrong together and no figure in the round can see it.
# dev/TRUTH-LABELING-PROTOCOL.md section 6 step 4 is the fix: a slice labelled
# BY HAND, scored with pf_grade_verdicts(). That is what turns the round's
# agreement figures into an error rate.
#
# THE HUMAN LABELS, AND DOES NOT SCORE. The output here is the same pair of
# files a model labeler got -- `shard-99-cases.csv` and a blank
# `shard-99-truth.csv` -- and the task is identical: work the case, write a
# verdict. The model's answer is NOT in either file. It is held in
# HELD-slice-design-and-model-labels.csv, which the labeler does not open until
# their own rows are finished.
#
# Reading the model's verdict and marking it right or wrong would be a REVIEW,
# and a review is the worst available instrument for this: the notes are
# well-argued, a confident wrong answer with a plausible chain is exactly the
# error being hunted, and a reviewer cannot find the EIN the model never
# considered. It is also the principle section 6 step 3 already applies to the
# models themselves -- where two labelers agreed, the consolidated row keeps
# the WEAKER basis of the two, because concurrence is not corroboration.
#
# WHY THE SLICE IS STRATIFIED ON THE MODEL'S VERDICT, AND WHY THAT IS SAFE.
# A simple random 40 of 400 would hold ~32 ORG_FOUND and one or two of each
# NO_ORG_* class -- too thin to tell whether the model's *declines* are sound,
# and the declines are a quarter of the measured error. So the draw stratifies
# on the verdict with a floor on the small classes, exactly the
# proportional-allocation-plus-floors idiom pf_round_sample() uses, and records
# a `weight` per cell so the overall rate is recovered without bias. Per-class
# cells are small by construction; they are there to DETECT a broken class
# (all four UNFINDABLE cases turning out findable is a signal), not to measure
# one.
#
# The stratum is the model's verdict, so the design table would leak the answer
# -- which is why the weights live in the HELD file and not beside the cases,
# and why the rows are written in shuffled order.
#
# USAGE  Rscript dev/draw-hand-slice.R
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
DD   <- file.path(PF, "data-dev")
LAB  <- file.path(DD, "round-stage1-labelled")
OUT  <- file.path(DD, "round-stage1-handslice")

SHARD   <- 99L
LABELER <- Sys.getenv("PF_HAND_LABELER", "jesse-lecy/hand-01")
SEED    <- 20261103L
# Floors on the small classes, remainder to ORG_FOUND. Sums to 40.
WANT <- c(ORG_FOUND = 24L, NO_ORG_NOT_EXEMPT = 5L, NO_ORG_UNFINDABLE = 5L,
          NO_ORG_INDIVIDUAL = 3L, UNRESOLVED = 3L)

say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() cat(strrep("=", 78), "\n")
hr(); say("HAND-LABELLED SLICE  shard %02d  seed %d", SHARD, SEED); hr()

## ---- the round as labelled -------------------------------------------------
rd <- function(p, m) { x <- as.data.table(utils::read.csv(p, colClasses = "character"))
                       if (is.null(x$model)) x[, model := m]; x }
all <- rbindlist(c(
  list(rd(file.path(LAB, "shard-01-truth-claude-fable-5-1-truth-01.csv"), "pass2")),
  lapply(2:5, function(s) rd(file.path(LAB, sprintf("shard-%02d-truth-GATED.csv", s)), NA))),
  fill = TRUE)

# One row per CASE, preferring the all-fable reading where a case has two --
# the same rule dev/read-round-stage1.R uses, so the slice is stratified on the
# same labels the 48.6% was computed from.
lab <- unique(all[order(model != "pass2")], by = "grant_id")
say("round: %d label-rows over %d cases", nrow(all), nrow(lab))

cas <- unique(rbindlist(lapply(1:5, function(s) as.data.table(utils::read.csv(
  file.path(DD, "round-stage1", sprintf("shard-%02d-cases.csv", s)),
  colClasses = "character"))), fill = TRUE), by = "grant_id")
if (nrow(cas) != nrow(lab))
  stop(sprintf("%d cases on disk against %d labelled.", nrow(cas), nrow(lab)),
       call. = FALSE)

# Which cases carry two labels that AGREED. Not stratified on -- that would
# load the slice toward cases two models found easy and bias the error rate
# downward -- but recorded, because it is the population the whole exercise is
# worried about and the subgroup read is free.
ov <- all[, .N, by = grant_id][N > 1L, grant_id]
agr <- all[grant_id %in% ov, .(agreed = uniqueN(paste(verdict, correct_ein)) == 1L),
           by = grant_id][agreed == TRUE, grant_id]
say("  %d overlap cases, %d of them agreeing", length(ov), length(agr))

## ---- allocate --------------------------------------------------------------
pool <- lab[, .N, by = verdict]
setnames(pool, "N", "pool_n")
pool[, want := WANT[verdict]]
if (any(is.na(pool$want)))
  stop(sprintf("verdict %s is in the round but not in WANT.",
               paste(pool$verdict[is.na(pool$want)], collapse = ", ")), call. = FALSE)
pool[, drawn_n := pmin(want, pool_n)]
if (sum(pool$drawn_n) != sum(WANT))
  say("NOTE: a class is shorter than its floor; slice is %d, not %d",
      sum(pool$drawn_n), sum(WANT))
pool[, weight := pool_n / drawn_n]
say("")
print(pool[order(-pool_n), .(verdict, pool_n, drawn_n, weight = round(weight, 2))])

set.seed(SEED)
pick <- unlist(lapply(pool$verdict, function(v) {
  ids <- lab[verdict == v, grant_id]
  sample(ids, pool[verdict == v, drawn_n])
}), use.names = FALSE)
if (anyDuplicated(pick)) stop("a case was drawn twice.", call. = FALSE)
say("\ndrew %d cases", length(pick))

## ---- the three files -------------------------------------------------------
if (!dir.exists(OUT)) dir.create(OUT, recursive = TRUE)
pop <- unique(lab$population); pop <- pop[nzchar(pop)][1L]

# Shuffled, so the file order cannot be read back into the stratum (which is
# the model's verdict).
set.seed(SEED + 1L)
ord <- sample(pick)

cases <- cas[match(ord, grant_id)]
utils::write.csv(cases, file.path(OUT, sprintf("shard-%02d-cases.csv", SHARD)),
                 row.names = FALSE, na = "")

tmpl <- data.table(truth_id = "", grant_id = ord, population = pop,
                   verdict = "", correct_ein = "", wrong_ein = "",
                   basis = "", confidence = "", labeler = LABELER,
                   shard = SHARD, source_url = "", note = "")
cols <- pf_shard_schema()
miss <- setdiff(cols, names(tmpl))
if (length(miss)) stop(sprintf("template lacks %s", paste(miss, collapse = ", ")),
                       call. = FALSE)
utils::write.csv(tmpl, file.path(OUT, sprintf("shard-%02d-truth.csv", SHARD)),
                 row.names = FALSE, na = "")

key <- data.table(grant_id = ord, stratum = cases$stratum, shard = SHARD,
                  labeler = LABELER, overlap = FALSE, primary = TRUE)
utils::write.csv(key, file.path(OUT, "SLICE-KEY.csv"), row.names = FALSE, na = "")

# Everything the labeler must not see, in one file with one obvious name: the
# model's rows AND the slice design, because the stratum IS the model's verdict.
held <- merge(lab[grant_id %in% ord],
              pool[, .(verdict, slice_pool_n = pool_n, slice_drawn_n = drawn_n,
                       slice_weight = weight)], by = "verdict")
held[, overlap_agreed := grant_id %in% agr]
setcolorder(held, c("grant_id", "verdict"))
utils::write.csv(held, file.path(OUT, "HELD-slice-design-and-model-labels.csv"),
                 row.names = FALSE, na = "")

say("")
say("wrote into %s", OUT)
say("  shard-%02d-cases.csv   the 40 cases, shuffled -- what you work from", SHARD)
say("  shard-%02d-truth.csv   the blank template -- what you fill", SHARD)
say("  SLICE-KEY.csv         roster, for pf_read_truth()")
say("  HELD-...csv           model labels AND the weights -- DO NOT OPEN YET")
say("")
say("realized composition of the slice (from the held file, printed once here")
say("because it is the draw's own audit and the labeler reads the README):")
print(held[, .N, by = .(verdict, overlap_agreed)][order(verdict)])
say("")
say("reproduce with: seed %d, shard %d, labeler %s", SEED, SHARD, LABELER)
say("  population %s", pop)
hr()
