#!/usr/bin/env Rscript
# ============================================================================
# probe-dedup-rule.R -- measurement 1 of 2 from STATE-PARTITION-FINDINGS Part 7.
#
# THE QUESTION
#
# Candidate pairs are keyed (.id, .ein) and np_cascade() deduplicates with
# !duplicated(), keeping the FIRST occurrence -- deliberately, "keep tightest
# pass". On the augmented reference 127,499 EINs carry more than one row, and
# those rows score differently, so "which row represents this EIN" is decided by
# whichever pass reached it first. Change the pass order and a different row
# survives under the same EIN at a different score. That is the whole mechanism
# behind the 60 partition movers.
#
# The proposed fix is to dedupe by HIGHEST SCORE instead, making the pair set
# independent of pass order. Before adopting it: what does it move in the
# MONOLITHIC run, where partitioning is not involved at all?
#
# METHOD, AND THE SELF-CHECK THAT MAKES IT TRUSTWORTHY
#
# np_cascade() dedupes internally and returns the already-deduped union, so the
# pre-dedup accumulator cannot be recovered from its output. This replicates the
# cascade loop -- faithfully, including the `pending` logic -- to hold the raw
# accumulator, then applies both rules to the SAME pairs.
#
# The replication is validated rather than asserted: arm A (keep-first) must
# reproduce BASELINE-2026-08 exactly. If it does not, the replication is wrong
# and arm B means nothing. That check runs first and its result is reported
# whether it passes or fails.
#
#   PF_REF   active | augmented   (default augmented -- the one with multi-row EINs)
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- "."
suppressWarnings(suppressMessages(devtools::load_all("../npmatch", quiet = TRUE)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
setDTthreads(0L)
DD <- file.path(PF, "data-dev")
W  <- Sys.getenv("PF_REF", "augmented")
say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function(t = NULL) { cat(strrep("=", 78), "\n")
                            if (!is.null(t)) { cat(t, "\n"); cat(strrep("=", 78), "\n") } }
tick <- function() proc.time()[["elapsed"]]

CFG <- npmatch::np_config()
PASSES <- c(pf_staged_passes("lean", concat = TRUE), pf_recovery_passes(state = TRUE))

hr(sprintf("DEDUP RULE -- %s reference", W))
ref <- readRDS(file.path(DD, switch(W, active = "REF-active.rds",
                                    augmented = "REF-augmented.rds")))
ref$reference <- pf_add_recovery_keys(ref$reference)
r <- ref$reference
say("reference: %s rows, %s distinct EINs", format(nrow(r), big.mark = ","),
    format(length(unique(r$.ein)), big.mark = ","))

g <- pf_read_grants(file.path(PF, "inputs"), pattern = "^1k_grants_.*[.]csv$")
g <- pf_recover_name_from_street(g)
q_in <- g[g$in_scope, , drop = FALSE]
# built exactly as pf_match_grants() builds it, including only_truncated
trunc <- if (!is.null(q_in$name_truncated)) q_in$name_truncated else NULL
q <- pf_add_recovery_keys(npmatch::np_normalize(
  npmatch::np_query(q_in, pf_map_grants())), only_truncated = trunc)
q$.id <- as.character(q$.id)
say("queries: %s in scope", format(nrow(q), big.mark = ","))

## ---- the cascade loop, replicated to keep the RAW accumulator --------------
pending <- unique(q$.id)
acc <- list(); cmp_cols <- NULL; profile <- NULL
t0 <- tick()
for (p in PASSES) {
  if (!length(pending)) break
  q_sub <- q[q$.id %in% pending, , drop = FALSE]
  if (!nrow(q_sub)) break
  blk <- do.call(npmatch::np_block,
                 c(list(q_sub, r), p$args, list(ref_index = ref$ref_index)))
  if (!nrow(blk)) { say("  [%-16s] 0 candidates", p$name); next }
  blk$.x <- match(q_sub$.id[blk$.x], q$.id)
  pr <- npmatch::np_veto(npmatch::np_score(
    npmatch::np_compare(q, r, CFG, candidates = blk,
                        name_freq = ref$name_freq, token_idf = ref$token_idf),
    CFG, method = "hier"))
  if (is.null(cmp_cols)) { cmp_cols <- attr(pr, "cmp_cols"); profile <- attr(pr, "profile") }
  df <- as.data.frame(pr); df$pass <- p$name
  acc[[p$name]] <- df
  sel <- npmatch::np_tier(npmatch::np_select(pr, CFG), CFG)
  yes <- as.character(sel$.id[as.character(sel$tier) == "YES"])
  pending <- setdiff(pending, yes)
  say("  [%-16s] %8s cand | resolved %4d | pending %d", p$name,
      format(nrow(blk), big.mark = ","), length(yes), length(pending))
}
say("cascade replicated in %.0f s", tick() - t0)

raw <- as.data.frame(data.table::rbindlist(acc, fill = TRUE))
say("")
say("RAW accumulator      : %s pairs", format(nrow(raw), big.mark = ","))
key <- paste(raw$.id, raw$.ein)
say("distinct (.id,.ein)  : %s", format(length(unique(key)), big.mark = ","))
say("duplicate rows       : %s (%.1f%%)  <- pairs where the rule bites",
    format(sum(duplicated(key)), big.mark = ","), 100*mean(duplicated(key)))

## ---- how often do duplicates of one (.id,.ein) DISAGREE on score? ----------
dt <- as.data.table(raw)[, .(.id, .ein, score, pass)]
agg <- dt[, .(n = .N, spread = max(score) - min(score)), by = .(.id, .ein)]
multi <- agg[n > 1]
say("")
say("(.id,.ein) seen more than once : %s", format(nrow(multi), big.mark = ","))
if (nrow(multi)) {
  say("  ...with DIFFERENT scores      : %s (%.0f%%)  <- the rule decides these",
      format(sum(multi$spread > 1e-9), big.mark = ","),
      100*mean(multi$spread > 1e-9))
  say("  median score spread            : %.3f", median(multi$spread[multi$spread > 1e-9]))
  say("  max score spread               : %.3f", max(multi$spread))
}

## ---- two rules, same pairs -------------------------------------------------
finish <- function(u, lab) {
  attr(u, "cmp_cols") <- cmp_cols; attr(u, "profile") <- profile
  class(u) <- c("np_pairs", "data.frame")
  o <- as.data.frame(npmatch::np_tier(npmatch::np_select(u, CFG), CFG))
  o <- o[order(o$.id), , drop = FALSE]; rownames(o) <- NULL
  tb <- table(factor(as.character(o$tier), c("YES","MAYBE","NO")))
  say("%-14s %s pairs | YES %4d MAYBE %4d NO %4d", lab,
      format(nrow(u), big.mark = ","), tb[["YES"]], tb[["MAYBE"]], tb[["NO"]])
  o
}
hr("TWO RULES, SAME PAIRS")
A <- finish(raw[!duplicated(key), , drop = FALSE], "keep-FIRST")
ord <- order(raw$.id, raw$.ein, -raw$score)
rb <- raw[ord, , drop = FALSE]
B <- finish(rb[!duplicated(paste(rb$.id, rb$.ein)), , drop = FALSE], "keep-HIGHEST")

## ---- self-check: does keep-first reproduce the freeze? ---------------------
hr("SELF-CHECK -- keep-FIRST must reproduce BASELINE-2026-08")
base <- readRDS(file.path(PF, "dev", "BASELINE-2026-08",
                          sprintf("benchmark-1k-%s.rds", W)))
b <- base[order(base$.id), , drop = FALSE]
cols <- intersect(names(b), names(A))
same <- vapply(cols, function(cn) identical(b[[cn]], A[[cn]]), logical(1))
say("rows: baseline %d | replicated %d", nrow(b), nrow(A))
say("columns identical: %d / %d", sum(same), length(cols))
if (any(!same)) say("  DIFFER: %s", paste(cols[!same], collapse = ", "))
ok <- nrow(b) == nrow(A) && all(as.character(b$tier) == as.character(A$tier))
say("tiers identical to the freeze: %s", ok)
if (!ok) say("  ** replication is NOT faithful; arm B below is not interpretable **")

## ---- the comparison --------------------------------------------------------
hr("WHAT keep-HIGHEST MOVES, monolithically")
m <- merge(A[, c(".id","tier","overall_ein","overall_score")],
           B[, c(".id","tier","overall_ein","overall_score")],
           by = ".id", suffixes = c(".a", ".b"))
say("identities compared : %d", nrow(m))
say("  same tier         : %d (%.2f%%)",
    sum(as.character(m$tier.a) == as.character(m$tier.b)),
    100*mean(as.character(m$tier.a) == as.character(m$tier.b)))
say("  same EIN          : %d (%.2f%%)",
    sum(m$overall_ein.a == m$overall_ein.b, na.rm = TRUE),
    100*mean(m$overall_ein.a == m$overall_ein.b, na.rm = TRUE))
say("")
print(table(keep_first = factor(as.character(m$tier.a), c("YES","MAYBE","NO")),
            keep_highest = factor(as.character(m$tier.b), c("YES","MAYBE","NO"))))
mv <- m[as.character(m$tier.a) != as.character(m$tier.b), , drop = FALSE]
say("")
say("tier changes: %d", nrow(mv))
if (nrow(mv)) {
  say("  score rises under keep-highest on %d of them", sum(mv$overall_score.b > mv$overall_score.a))
  print(head(mv[order(-abs(mv$overall_score.b - mv$overall_score.a)),
                c(".id","tier.a","tier.b","overall_score.a","overall_score.b")], 15),
        row.names = FALSE)
}
fwrite(as.data.table(m), file.path(DD, sprintf("DEDUP-RULE-%s.csv", W)))
saveRDS(B, file.path(DD, sprintf("DEDUP-HIGHEST-%s.rds", W)), compress = FALSE)
say(""); say("wrote data-dev/DEDUP-RULE-%s.csv", W)
