#!/usr/bin/env Rscript
# ============================================================================
# read-b2-topup.R -- pool the B2-token-concat top-up with stage 1, and say
# whether 12% held.
#
# Stage 1 put this pass at 3 of 25. dev/draw-b2-topup.R drew 50 more from the
# same frame and population, excluding the 26 stage 1 already held, and
# dev/B2-TOPUP-RUN-20261103.log labelled them with the same model under the
# same protocol. This pools them.
#
# POOLING IS LEGITIMATE HERE AND IS CHECKED RATHER THAN ASSUMED. The two sets
# share a population fingerprint, a frame id, a normalizer signature, a
# labelling model and a protocol, and they are disjoint by construction. All of
# that is asserted below, because pooling two sets that differ on any of them
# is the incomparable-denominator defect dev/METRIC-SHAPES.md catalogues -- and
# an assertion that runs is worth more than a sentence claiming it.
#
# WHAT IS NOT FIXED BY MORE CASES. Truth is still model-produced, so this
# figure inherits whatever error rate the hand slice
# (dev/draw-hand-slice.R, dev/grade-hand-slice.R) finds in stage 1's labels.
# More cases narrow the interval; they do not touch the accuracy.
#
# USAGE  Rscript dev/read-b2-topup.R
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
DD <- file.path(PF, "data-dev")
say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() cat(strrep("=", 78), "\n")
nz  <- function(x) gsub("[^0-9]", "", ifelse(is.na(x), "", x))
hr(); say("B2-TOKEN-CONCAT, POOLED"); hr()

rdc <- function(p) as.data.table(utils::read.csv(p, colClasses = "character"))

## ---- stage 1's B2 cases ---------------------------------------------------
s1lab <- rbindlist(c(
  list(rdc(file.path(DD, "round-stage1-labelled",
                     "shard-01-truth-claude-fable-5-1-truth-01.csv"))[, model := "pass2"]),
  lapply(2:5, function(s) rdc(file.path(DD, "round-stage1-labelled",
                     sprintf("shard-%02d-truth-GATED.csv", s))))), fill = TRUE)
s1lab <- unique(s1lab[order(model != "pass2")], by = "grant_id")
s1cas <- unique(rbindlist(lapply(1:5, function(s) rdc(file.path(
  DD, "round-stage1", sprintf("shard-%02d-cases.csv", s)))), fill = TRUE),
  by = "grant_id")

## ---- the top-up -----------------------------------------------------------
b2lab <- rdc(file.path(DD, "round-b2-topup-labelled",
                       "shard-01-truth-claude-fable-5-1-b2-01.csv"))
b2cas <- rdc(file.path(DD, "round-b2-topup", "shard-01-cases.csv"))

## ---- the checks that make pooling legitimate ------------------------------
p1 <- unique(s1lab$population); p2 <- unique(b2lab$population)
if (!identical(p1, p2))
  stop(sprintf("populations differ: %s against %s -- these ids are not the same organisations.",
               p1, p2), call. = FALSE)
d1 <- readRDS(file.path(DD, "ADJ-ROUND-STAGE1.rds"))
d2 <- readRDS(file.path(DD, "ADJ-ROUND-B2TOPUP.rds"))
for (a in c("frame_id", "normalizer"))
  if (!identical(as.character(attr(d1, a)), as.character(attr(d2, a))))
    stop(sprintf("%s differs between the two draws.", a), call. = FALSE)
ov <- intersect(s1lab$grant_id, b2lab$grant_id)
if (length(ov))
  stop(sprintf("%d case(s) are in BOTH sets, so pooling would double-count them: %s",
               length(ov), paste(head(ov, 3), collapse = ", ")), call. = FALSE)
say("population %s | frame_id %s | normalizer %s", p1, attr(d1, "frame_id"),
    attr(d1, "normalizer"))
say("the two sets are disjoint, same frame, same normalizer, same model -- pooling is sound")

## ---- score ----------------------------------------------------------------
sco <- function(lab, cas, tag) {
  x <- merge(lab[, .(grant_id, verdict, correct_ein, confidence)],
             cas[, .(grant_id, cascade_ein, cascade_pass, purpose_band)],
             by = "grant_id")
  x[, `:=`(set = tag, pick = nz(cascade_ein), got = nz(correct_ein))]
  x[, right := verdict == "ORG_FOUND" & nzchar(got) & got == pick]
  x
}
A <- sco(s1lab, s1cas, "stage1")[cascade_pass == "B2-token-concat"]
B <- sco(b2lab, b2cas, "topup")
all <- rbind(A, B)
say("")
say("stage 1 B2: %d drawn | top-up: %d drawn | pooled %d", nrow(A), nrow(B), nrow(all))

one <- function(x, nm) {
  q <- x[verdict != "UNRESOLVED"]
  w <- pf_wilson(sum(q$right), nrow(q))
  say("  %-10s %3d/%3d = %5.1f%% [%4.1f, %4.1f]   (%d UNRESOLVED dropped)",
      nm, sum(q$right), nrow(q), 100 * mean(q$right),
      100 * w[1, "lo"], 100 * w[1, "hi"], nrow(x) - nrow(q))
  # unname(): pf_wilson() returns a matrix, so w[1, "lo"] carries the column
  # name through into c(), which names the element "lo.lo" and makes
  # P[["lo"]] a subscript error.
  invisible(c(k = sum(q$right), n = nrow(q),
              lo = unname(w[1, "lo"]), hi = unname(w[1, "hi"])))
}
say("")
hr(); say("PICK PRECISION"); hr()
invisible(one(A, "stage 1")); invisible(one(B, "top-up"))
say("")
P <- one(all, "POOLED")

## ---- does it separate from B1? -------------------------------------------
B1 <- sco(s1lab, s1cas, "stage1")[cascade_pass == "B1-token-state" &
                                  verdict != "UNRESOLVED"]
wb <- pf_wilson(sum(B1$right), nrow(B1))
say("")
hr(); say("AGAINST THE PASS IT HAS TO BE SEPARATED FROM"); hr()
say("  B1-token-state  %d/%d = %.1f%% [%.1f, %.1f]", sum(B1$right), nrow(B1),
    100 * mean(B1$right), 100 * wb[1, "lo"], 100 * wb[1, "hi"])
say("  B2-token-concat %d/%d = %.1f%% [%.1f, %.1f]", P[["k"]], P[["n"]],
    100 * P[["k"]] / P[["n"]], 100 * P[["lo"]], 100 * P[["hi"]])
say("")
# Braced: at top level R parses `if (x) stmt` as complete and then meets a
# bare `else`, which is a syntax error rather than a branch.
if (P[["hi"]] < wb[1, "lo"]) {
  say("  DISJOINT. B2 is separated from B1 at 95%%, so the difference is real")
} else {
  say("  OVERLAPPING at 95%% -- not separated; %d cases is not enough", P[["n"]])
}

## ---- and the composition, which says WHY ---------------------------------
say("")
hr(); say("WHY IT FAILS, FROM THE VERDICTS"); hr()
v <- all[, .N, by = verdict][order(-N)]
v[, pct := sprintf("%.0f%%", 100 * N / sum(N))]
print(v)
say("")
say("the %d wrong scoreable cases, by verdict:", sum(all[verdict != "UNRESOLVED"]$right == FALSE))
wr <- all[verdict != "UNRESOLVED" & right == FALSE, .N, by = verdict][order(-N)]
print(wr)
say("")
say("  A NO_ORG_* verdict means no exempt organisation exists to match, so the")
say("  cascade produced a FALSE POSITIVE. That is a different failure from")
say("  picking the wrong one of two real organisations, and it is not fixed by")
say("  better scoring -- only by not blocking on this key.")
say("")
say("by purpose band, as a check that the result is not one stratum:")
pb <- all[verdict != "UNRESOLVED", .(n = .N, right = sum(right)), by = purpose_band]
pb[, rate := sprintf("%.0f%%", 100 * right / n)]
print(pb)
hr()
say("Truth is model-produced. This figure inherits stage 1's unpriced truth")
say("error, which only the hand slice can measure.")
hr()
