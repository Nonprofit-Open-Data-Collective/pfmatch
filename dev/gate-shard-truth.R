#!/usr/bin/env Rscript
# ============================================================================
# gate-shard-truth.R -- apply the high-only gate to a shard, in two stages.
#
# THE POLICY, AND THE EVIDENCE FOR IT. dev/SHADOW-HAIKU-SHARD01-20261103.log
# measured claude-haiku-5-5 against claude-fable-5-1 as LABELERS over the same
# 92 cases. On the 60 cases where both found an organisation they named the
# same EIN 60 times out of 60, and no case in 92 had both resolve and disagree
# -- 19 of the 20 disagreements are haiku declining what fable settled. Haiku's
# own confidence separates the two outcomes: high 38/38 = 100% [90.8, 100],
# medium 30/33 = 90.9%, low 4/21 = 19.0%.
#
# So: accept haiku's `high` rows, send everything else to fable. The accepted
# set agreed with fable on every measured row, and the escalated set is the
# known-price failure (a re-label) rather than the silent one (a confident
# wrong EIN). The medium tier is NOT accepted, deliberately: 9% disagreement
# going into a truth set is the same contamination as putting a cheap labeler
# on the panel, arriving by a cheaper route, and truth is the denominator under
# every figure the round reports.
#
# WHY TWO STAGES AND NO MODE FLAG. Run it once and it writes the escalation
# list and the command for pass 2; run it again once pass 2 exists and it
# merges. That is resumable without an argument to get wrong, and the stage is
# a fact about what is on disk rather than something to remember.
#
# WHAT THE MERGED FILE CLAIMS. One `labeler` per shard, because that is what
# the key deals and what pf_read_truth() enforces -- so the name has to
# describe the PIPELINE, not one of its two models. Per-row provenance goes in
# a `model` column beside the schema: without it the round could not separate
# a haiku-labelled row from a fable-labelled one later, and the blinded
# overlap between a gated shard and all-fable shard 1 would be a mixture
# reported as one number. That is the defect class dev/METRIC-SHAPES.md and
# dev/PLAUSIBLE-WRONG-NUMBERS.md both catalogue.
#
# USAGE  PF_LABEL_SHARD=2 Rscript dev/gate-shard-truth.R
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
DD   <- file.path(PF, "data-dev")
DIR  <- file.path(DD, "round-stage1-labelled")
KEY  <- file.path(DD, "round-stage1-key", "SHARD-KEY.csv")

SHARD <- as.integer(Sys.getenv("PF_LABEL_SHARD", "0"))
KEEP  <- Sys.getenv("PF_GATE_KEEP", "high")      # confidences accepted from pass 1
P1    <- Sys.getenv("PF_GATE_PASS1", "claude-haiku-5-5/pass1-%02d")
P2    <- Sys.getenv("PF_GATE_PASS2", "claude-fable-5-1/pass2-%02d")

say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() cat(strrep("=", 78), "\n")
if (is.na(SHARD) || SHARD < 1L)
  stop("set PF_LABEL_SHARD.", call. = FALSE)

slug <- function(x) gsub("[^A-Za-z0-9._-]+", "-", x)
path <- function(tmpl) file.path(DIR, sprintf("shard-%02d-truth-%s.csv", SHARD,
                                              slug(sprintf(tmpl, SHARD))))
f1 <- path(P1); f2 <- path(P2)
hr(); say("HIGH-ONLY GATE  shard %02d", SHARD); hr()

if (!file.exists(f1))
  stop(sprintf(paste0("pass 1 is missing: %s\n",
       "  PF_LABEL_SHARD=%d PF_LABEL_MODEL=claude-haiku-5-5 \\\n",
       "    PF_LABEL_LABELER=%s Rscript dev/label-shard.R"),
       f1, SHARD, sprintf(P1, SHARD)), call. = FALSE)

a <- as.data.table(utils::read.csv(f1, colClasses = "character"))
say("pass 1: %s  (%d rows)", basename(f1), nrow(a))
keep <- strsplit(KEEP, ",")[[1]]
a[, accept := nzchar(verdict) & confidence %in% keep]
say("  accepted at confidence in {%s}: %d", paste(keep, collapse = ","),
    sum(a$accept))
say("  to escalate: %d", sum(!a$accept))
print(table(confidence = a$confidence, accepted = a$accept))

## ---- stage 1: emit the escalation list -------------------------------------
if (!file.exists(f2)) {
  esc <- file.path(DIR, sprintf("shard-%02d-escalate.csv", SHARD))
  utils::write.csv(a[accept == FALSE, .(grant_id)], esc, row.names = FALSE)
  say("\nwrote %s  (%d ids)", esc, sum(!a$accept))
  say("\npass 2 is not on disk yet. Run it, then run this again to merge:")
  say("  PF_LABEL_SHARD=%d PF_LABEL_ONLY=%s \\", SHARD, esc)
  say("    PF_LABEL_LABELER=%s Rscript dev/label-shard.R", sprintf(P2, SHARD))
  hr(); quit(save = "no", status = 0L)
}

## ---- stage 2: merge --------------------------------------------------------
b <- as.data.table(utils::read.csv(f2, colClasses = "character"))
say("\npass 2: %s  (%d rows)", basename(f2), nrow(b))

over <- intersect(b$grant_id, a[accept == TRUE, grant_id])
if (length(over))
  say("note: %d pass-2 row(s) cover cases pass 1 had already settled; pass 2 wins",
      length(over))
miss <- setdiff(a[accept == FALSE, grant_id], b$grant_id)
if (length(miss))
  say("WARNING: %d escalated case(s) never came back from pass 2, so they stay blank",
      length(miss))

cols <- pf_shard_schema()
A <- a[accept == TRUE & !grant_id %in% b$grant_id, ..cols][, model := "pass1"]
B <- b[, ..cols][, model := "pass2"]
# Anything neither pass settled is still a row of the shard: pf_read_truth()
# reports a blank row as missing, which is the truth about it. Dropping it
# would make the shard look complete.
settled <- c(A$grant_id, B$grant_id)
C <- a[!grant_id %in% settled, ..cols][, model := "unsettled"]
C[, `:=`(verdict = "", correct_ein = "", basis = "", confidence = "")]
out <- rbind(A, B, C)

# One labeler per shard, naming the pipeline. The key must agree or
# pf_read_truth() refuses the file -- which is the check doing its job, not an
# obstacle: re-stamp the roster (dev/deal-round-stage1.R, a free re-stamp since
# the assignment is fixed by the seed) before merging.
key <- as.data.table(utils::read.csv(KEY, colClasses = "character"))
want <- unique(key[as.integer(shard) == SHARD, labeler])
want <- want[nzchar(want)]
if (!length(want))
  stop("the key names no labeler for this shard; re-stamp the roster first.",
       call. = FALSE)
out[, labeler := want[1L]]
out[, shard := as.character(SHARD)]
say("\nstamped as %s (%d row%s)", want[1L], nrow(out),
    if (nrow(out) == 1L) "" else "s")
print(table(model = out$model))

pc <- file.path(DIR, sprintf("shard-%02d-truth-GATED.csv", SHARD))
utils::write.csv(out, pc, row.names = FALSE, na = "")
say("\nwrote %s", pc)

say("")
v <- tryCatch(pf_read_truth(as.data.frame(out[, ..cols]), key = key,
                            population = unique(out$population)[1L],
                            verbose = TRUE),
              error = function(e) { say("pf_read_truth() REFUSES it:");
                                    say("  %s", conditionMessage(e)); NULL })
if (!is.null(v)) say("pf_read_truth() accepts it.")
hr()
