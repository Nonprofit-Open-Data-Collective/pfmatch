#!/usr/bin/env Rscript
# ============================================================================
# draw-b2-topup.R -- 50 more B2-token-concat cases, to confirm or kill 12%.
#
# WHY THIS ONE PASS AND NOTHING ELSE. Stage 1 put `B2-token-concat` pick
# precision at 3 of 25 -- 12% (ADJUDICATION-PREREQS.md 6b.7c). Every other cell
# in that table is a figure to refine; this one, if it holds, is an argument to
# turn a blocking pass OFF, and that makes it the only cell worth paying to
# confirm before the rest of stage 2 can be drawn.
#
# n = 75 is not a round number. 6b.2 says separating two cells with a 25-point
# gap needs n >= 75, and B2 against `B1-token-state` (50%, n = 222) is a
# 38-point gap. 25 existing scoreable cases plus 50 gets there. Going further
# buys precision on a pass that would be disabled anyway.
#
# WHAT THIS DOES NOT FIX, SAID PLAINLY. The labels will be model-produced, the
# same as stage 1's, so the figure inherits stage 1's unpriced truth error --
# `dev/draw-hand-slice.R` is what prices that, and it is running in parallel.
# If the hand slice comes back saying truth is weak, this figure moves with
# every other one. It is drawn now because the user asked for it to run
# alongside the hand labelling, and because at ~$8 it is cheap enough that
# paying twice is an acceptable risk.
#
# NOT GATED THROUGH HAIKU. 6b.8 measured the high-only gate at an 11% saving,
# which is ~$0.85 on 50 cases, and it would put two models' rows in a 50-case
# set whose entire purpose is a clean read on one blocking pass. Fable labels
# all of them.
#
# USAGE  Rscript dev/draw-b2-topup.R
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
DD <- file.path(PF, "data-dev")

RUN     <- file.path(DD, "TRI-V2-MATCH.rds")
STAGE1  <- file.path(DD, "ADJ-ROUND-STAGE1.rds")
DIR     <- file.path(DD, "round-b2-topup")
KEY_DIR <- file.path(DD, "round-b2-topup-key")
OUT     <- file.path(DD, "ADJ-ROUND-B2TOPUP.rds")
PASS    <- "B2-token-concat"
N       <- 50L
SEED    <- 20261103L
LABELER <- "claude-fable-5-1/b2-01"

say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() cat(strrep("=", 78), "\n")
hr(); say("B2-TOKEN-CONCAT TOP-UP  n=%d  seed %d", N, SEED); hr()

m  <- readRDS(RUN)
s  <- as.data.table(m$status)
g  <- as.data.table(m$grants)
d1 <- readRDS(STAGE1)

## ---- the fingerprints, taken from stage 1 and then re-derived --------------
# Read off stage 1's draw rather than recomputed from scratch, because these
# 50 cases must be poolable with its 25: a different population or frame id
# means the two sets are not the same organisations and must not be added
# together. Then checked against a fresh pf_population_id() so a silently
# rebuilt run cannot pass.
POP   <- attr(d1, "population")
FRAME <- attr(d1, "frame_id")
NORM  <- attr(d1, "normalizer")
live  <- pf_population_id(g)
say("stage 1: population %s | frame_id %s | normalizer %s", POP, FRAME, NORM)
if (!identical(as.character(POP), as.character(live)))
  stop(sprintf(paste0(
    "population mismatch: stage 1 was drawn on %s, this run fingerprints as\n",
    "  %s. These 50 cases could not be pooled with stage 1's 25, which is\n",
    "  the only reason to draw them."), POP, live), call. = FALSE)
say("re-derived from this run: %s  -- matches", live)

## ---- the pool: B2 MAYBE, minus what stage 1 already holds ------------------
g[, purp_ok := pf_purpose_is_contentful(.pf_col(g, "PF_15_G_PAID_PURPOSE"))]
g[, amt := suppressWarnings(as.numeric(.pf_col(g, "PF_15_G_PAID_AMT")))]
feat <- g[, .(dollars = sum(amt, na.rm = TRUE), n_grants = .N,
              purpose_band = ifelse(any(purp_ok %in% TRUE), "purpose", "bare")),
          by = .(grant_id = as.character(recipient_id))]

fr <- merge(s[status == "MAYBE" & match_pass == PASS,
              .(grant_id = as.character(grant_id), pass = match_pass,
                margin, n_close)],
            feat, by = "grant_id")
say("")
say("%s MAYBE identities in the frame: %d", PASS, nrow(fr))
had <- as.character(d1$grant_id[d1$pass == PASS])
say("  already in stage 1: %d", length(had))
fr <- fr[!grant_id %in% had]
say("  eligible pool: %d", nrow(fr))
if (nrow(fr) < N)
  stop(sprintf("pool holds %d, asked for %d.", nrow(fr), N), call. = FALSE)

if (!all(grepl("^PFI-[0-9a-f]{16}$", fr$grant_id)))
  stop(paste0("the pool is not keyed on content-derived identity ids.\n",
       "  Rekey the frame (dev/rekey-tri-v2.R) before drawing against it."),
       call. = FALSE)

## ---- draw, proportional on purpose_band -----------------------------------
# The one axis stage 1 stratified on inside a pass, kept so the 75 pooled cases
# stay proportional to the frame on it rather than drifting.
fr[, stratum := paste("MAYBE", pass, purpose_band, sep = " | ")]
tb <- table(fr$stratum)
share <- as.numeric(tb) / sum(tb) * N
alloc <- pmin(as.integer(floor(share)), as.integer(tb))
left  <- N - sum(alloc)
if (left > 0) for (i in order(share - floor(share), decreasing = TRUE)) {
  if (left == 0L) break
  if (alloc[i] < tb[i]) { alloc[i] <- alloc[i] + 1L; left <- left - 1L }
}
names(alloc) <- names(tb)
set.seed(SEED)
pick <- unlist(lapply(names(alloc), function(st)
  if (alloc[[st]] > 0L) sample(fr$grant_id[fr$stratum == st], alloc[[st]])),
  use.names = FALSE)
say("")
say("allocation:")
for (st in names(alloc))
  say("  %-42s frame %5d  drawn %2d", st, as.integer(tb[[st]]), alloc[[st]])

d <- fr[match(pick, grant_id)]
d[, stage := "b2topup"]
attr(d, "population") <- POP
attr(d, "frame_id")   <- FRAME
attr(d, "normalizer") <- NORM

## ---- case features, identical to stage 1's ------------------------------
# Same columns in the same order, so dev/label-shard.R needs no change and the
# two sets pool without a reshape.
i <- match(d$grant_id, as.character(s$grant_id))
cases <- data.table(
  grant_id    = d$grant_id,
  recip_name  = s$recip_name[i],
  recip_city  = s$recip_city[i],
  recip_state = s$recip_state[i],
  recip_zip5  = s$recip_zip5[i],
  n_grants    = d$n_grants,
  dollars     = round(d$dollars),
  purpose_band = d$purpose_band,
  cascade_pass = d$pass,
  cascade_ein  = s$ein[i],
  cascade_name = s$bmf_name[i],
  cascade_city = s$bmf_city[i],
  cascade_state = s$bmf_state[i],
  cascade_score = round(as.numeric(s$score[i]), 3),
  cascade_margin = round(as.numeric(d$margin), 3),
  n_close      = d$n_close)

## ---- deal to one labeler, no overlap -------------------------------------
# k = 1 and overlap = 0, stated rather than defaulted: there is no second
# labeler, so there is no agreement read on this set at all. That is a real
# loss and it is the right trade here -- a blinded overlap on 50 cases would
# cost ~15% of the budget to produce a cell under pf_labeler_agreement()'s
# min_n of 20, which reads as unusable anyway.
say("")
sh <- pf_truth_shards(as.data.frame(d[, .(grant_id, stratum)]), k = 1L,
                      overlap = 0, seed = SEED, labelers = LABELER,
                      population = POP, verbose = TRUE)
attr(sh, "frame_id")   <- FRAME
attr(sh, "normalizer") <- NORM

for (p in c(DIR, KEY_DIR)) if (!dir.exists(p)) dir.create(p, recursive = TRUE)
w <- pf_write_shards(sh, DIR, cases = as.data.frame(cases), key_dir = KEY_DIR,
                     overwrite = TRUE)
saveRDS(d, OUT)

say("")
say("wrote %d files", length(w))
say("  cases: %s", DIR)
say("  key:   %s", KEY_DIR)
say("")
say("label it with:")
say("  PF_LABEL_SHARD=1 PF_LABEL_DIR=%s \\", DIR)
say("    PF_LABEL_KEY=%s \\", file.path(KEY_DIR, "SHARD-KEY.csv"))
say("    PF_LABEL_OUTDIR=%s \\", file.path(DD, "round-b2-topup-labelled"))
say("    Rscript dev/label-shard.R")
say("")
say("reproduce with: seed %d, n %d, pass %s", SEED, N, PASS)
say("  population %s | frame_id %s", POP, FRAME)
hr()
