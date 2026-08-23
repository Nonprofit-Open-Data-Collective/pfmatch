#!/usr/bin/env Rscript
# ============================================================================
# probe-mover-diagnosis.R -- why do 60 identities change tier under partitioning
# on the AUGMENTED reference, when zero do on the active one?
#
# STATE-PARTITION-FINDINGS Part 6. Movement is two-directional (15 YES->MAYBE,
# 12 YES->NO, 15 MAYBE->YES, 6 NO->YES), which rules out a systematic loss of
# candidates and points at sensitivity. This asks *which* sensitivity, by testing
# the candidate explanations against each other rather than one at a time:
#
#   H1 BOUNDARY   movers sit near a tier threshold (0.78 / 0.65) or near the
#                 margin brake (0.05), so any candidate-set change tips them.
#   H2 TIES       movers are in near-tie bands (n_close >= 2), where which
#                 candidate wins is already under-determined.
#   H3 SHARD      movers concentrate in particular shards -- a routing or
#                 slice-construction defect rather than a general one.
#   H4 PASS       movers were resolved by a pass whose position changed, i.e.
#                 the cross-state passes C1/C2 that now run last.
#   H5 ALIAS      movers are won by alias rows, which is what the augmented
#                 reference adds over the active one and would explain why the
#                 active reference shows zero movement.
#
# H5 is the one the active-vs-augmented contrast predicts, so it gets tested
# first-class rather than as an afterthought.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- "."
suppressWarnings(suppressMessages(devtools::load_all("../npmatch", quiet = TRUE)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
setDTthreads(0L)
DD <- file.path(PF, "data-dev")
say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function(t = NULL) { cat(strrep("=", 78), "\n")
                            if (!is.null(t)) { cat(t, "\n"); cat(strrep("=", 78), "\n") } }

b <- as.data.table(readRDS(file.path(PF, "dev", "BASELINE-2026-08",
                                     "benchmark-1k-augmented.rds")))
p <- readRDS(file.path(DD, "PARTITION-RESULT-augmented.rds"))
prs <- as.data.table(as.data.frame(attr(p, "pairs")))
p <- as.data.table(as.data.frame(p))
say("baseline %d rows | partitioned %d rows | partitioned pairs %s",
    nrow(b), nrow(p), format(nrow(prs), big.mark = ","))

m <- merge(b[, .(.id, tier.b = as.character(tier), ein.b = overall_ein,
                 score.b = overall_score, margin.b = overall_margin,
                 nclose.b = n_close, tie.b = tie, pass.b = pass,
                 runner.b = runner_up_score, name_x)],
           p[, .(.id, tier.p = as.character(tier), ein.p = overall_ein,
                 score.p = overall_score, margin.p = overall_margin,
                 nclose.p = n_close)],
           by = ".id")
m[, moved := tier.b != tier.p]
say("compared %d identities | movers %d", nrow(m), sum(m$moved))

hr("DIRECTION")
print(table(baseline = m$tier.b, partitioned = m$tier.p))

## ---- H1 BOUNDARY -----------------------------------------------------------
hr("H1  Are movers near a threshold?")
cfg <- npmatch::np_config()
yes_t <- cfg$thresholds[["yes"]]; may_t <- cfg$thresholds[["maybe"]]
mm <- cfg$min_margin
say("thresholds: yes >= %.2f, maybe >= %.2f, min_margin %.2f", yes_t, may_t, mm)
m[, d_yes := abs(score.b - yes_t)]
m[, d_may := abs(score.b - may_t)]
m[, d_mar := abs(margin.b - mm)]
sm <- function(v, lab) say("  %-26s movers %6.3f | others %6.3f",
                           lab, median(v[m$moved], na.rm = TRUE),
                           median(v[!m$moved], na.rm = TRUE))
sm(m$d_yes, "|score - yes threshold|")
sm(m$d_may, "|score - maybe threshold|")
sm(m$d_mar, "|margin - min_margin|")
say("")
say("  within 0.02 of the margin brake : movers %.0f%% | others %.0f%%",
    100*mean(m$d_mar[m$moved] < 0.02, na.rm = TRUE),
    100*mean(m$d_mar[!m$moved] < 0.02, na.rm = TRUE))
say("  within 0.02 of a tier threshold : movers %.0f%% | others %.0f%%",
    100*mean(pmin(m$d_yes, m$d_may)[m$moved] < 0.02, na.rm = TRUE),
    100*mean(pmin(m$d_yes, m$d_may)[!m$moved] < 0.02, na.rm = TRUE))

## ---- H2 TIES ---------------------------------------------------------------
hr("H2  Are movers in near-tie bands?")
say("  median n_close  : movers %.1f | others %.1f",
    median(m$nclose.b[m$moved], na.rm = TRUE), median(m$nclose.b[!m$moved], na.rm = TRUE))
say("  tie flagged     : movers %.0f%% | others %.0f%%",
    100*mean(m$tie.b[m$moved] %in% TRUE), 100*mean(m$tie.b[!m$moved] %in% TRUE))
say("  n_close >= 2    : movers %.0f%% | others %.0f%%",
    100*mean(m$nclose.b[m$moved] >= 2, na.rm = TRUE),
    100*mean(m$nclose.b[!m$moved] >= 2, na.rm = TRUE))

## ---- H4 PASS ---------------------------------------------------------------
hr("H4  Which pass resolved them in the baseline?")
tb <- table(pass = m$pass.b, moved = m$moved)
rate <- data.table(pass = rownames(tb), n = as.integer(tb[, "FALSE"] + tb[, "TRUE"]),
                   movers = as.integer(tb[, "TRUE"]))
rate[, pct := 100 * movers / n]
print(rate[order(-pct)], row.names = FALSE)
say("")
say("C1/C2 are the passes whose position changed under partitioning.")

## ---- H5 ALIAS --------------------------------------------------------------
hr("H5  Do movers involve rows the AUGMENTED reference adds?")
# The augmented reference = unified BMF + Schedule I alias rows. If movers are
# won by alias rows, that explains why the active reference shows zero movement:
# it has none of them.
ref <- readRDS(file.path(DD, "REF-augmented.rds"))$reference
rs <- if (!is.null(ref$row_source)) ref$row_source else NULL
if (is.null(rs)) {
  say("  reference carries no row_source column; using an EIN-duplication proxy.")
  # an alias row shares its EIN with the legal-name row it was cloned from
  dup <- ref$.ein[duplicated(ref$.ein)]
  is_alias_ein <- function(e) e %in% dup
  say("  EINs carrying >1 reference row: %s of %s (%.1f%%)",
      format(length(unique(dup)), big.mark = ","),
      format(length(unique(ref$.ein)), big.mark = ","),
      100*length(unique(dup))/length(unique(ref$.ein)))
  say("  baseline pick sits on a multi-row EIN : movers %.0f%% | others %.0f%%",
      100*mean(is_alias_ein(m$ein.b[m$moved]), na.rm = TRUE),
      100*mean(is_alias_ein(m$ein.b[!m$moved]), na.rm = TRUE))
} else {
  say("  row_source values: %s", paste(names(table(rs)), collapse = ", "))
}

## ---- candidate volume ------------------------------------------------------
hr("CANDIDATE VOLUME for movers, partitioned side")
cnt <- prs[, .N, by = .id]
m <- merge(m, cnt, by = ".id", all.x = TRUE)
say("  median candidates : movers %.0f | others %.0f",
    median(m$N[m$moved], na.rm = TRUE), median(m$N[!m$moved], na.rm = TRUE))
say("  n_close  baseline vs partitioned, movers: %.1f -> %.1f",
    median(m$nclose.b[m$moved], na.rm = TRUE), median(m$nclose.p[m$moved], na.rm = TRUE))
say("  margin   baseline vs partitioned, movers: %.3f -> %.3f",
    median(m$margin.b[m$moved], na.rm = TRUE), median(m$margin.p[m$moved], na.rm = TRUE))

hr("THE MOVERS")
mv <- m[moved == TRUE][order(tier.b, tier.p)]
print(mv[, .(.id, name = substr(name_x, 1, 28), from = tier.b, to = tier.p,
             sc.b = round(score.b, 3), sc.p = round(score.p, 3),
             mg.b = round(margin.b, 3), mg.p = round(margin.p, 3),
             nc.b = nclose.b, nc.p = nclose.p, pass.b)][1:min(40, nrow(mv))],
      row.names = FALSE)
fwrite(mv, file.path(DD, "MOVERS-AUGMENTED.csv"))
say(""); say("wrote data-dev/MOVERS-AUGMENTED.csv (%d rows)", nrow(mv))
