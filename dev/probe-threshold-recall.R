#!/usr/bin/env Rscript
# ============================================================================
# probe-threshold-recall.R -- is purpose similarity better as a SET signal than
# as a RANK signal?
#
# Ranking asks: does the correct candidate score highest?
# Set membership asks: does the correct candidate clear an absolute floor, so it
# survives a prune while some distractors do not?
#
# These are different operating points on the same curve, and a feature can be
# useless for one and useful for the other -- a filter only has to be *safe*
# (never drop the truth), not *decisive*. This sweeps the threshold and reports
# recall of the correct candidate against how much of the candidate set is
# removed, for the similarity metrics and, as a yardstick, for the existing
# linkage score.
#
# Caveat carried in the read-out: the test sets hold the top 5 candidates per
# grant, so this measures "retained while pruning a candidate set", not
# "recovered a candidate the cascade never generated".
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
PF  <- Sys.getenv("PFMATCH_DIR", ".")
say <- function(...) cat(sprintf(...), "\n")

load_set <- function(f, contentful_only = TRUE) {
  d <- fread(file.path(PF, "data-dev", f), na.strings = NULL, showProgress = FALSE)
  d[, is_correct := is_correct %in% c(TRUE, "TRUE", "true")]
  d[, purpose_contentful := purpose_contentful %in% c(TRUE, "TRUE", "true")]
  d <- d[has_truth %in% c(TRUE, "TRUE", "true")]
  if (contentful_only) d <- d[purpose_contentful == TRUE]
  d[, score := as.numeric(score)]
  d[, .SD[.N >= 2 & sum(is_correct) == 1], by = grant_id]
}

# NA handling: a candidate with no text cannot clear a floor on evidence, but
# dropping it would be a size prior. Report both readings.
sweep <- function(d, m, na_keep) {
  v <- d[[m]]
  d2 <- copy(d)[, mv := v]
  d2[is.na(mv), mv := if (na_keep) Inf else -Inf]
  ts <- sort(unique(c(0, 1e-9, seq(0.05, 0.95, by = 0.05), 0.999)))
  rbindlist(lapply(ts, function(t) {
    r <- d2[, .(correct_kept = mv[is_correct] >= t,
                n_kept  = sum(mv >= t),
                n_cand  = .N,
                distractors_dropped = sum(mv < t & !is_correct)), by = grant_id]
    data.table(t = t,
               recall       = mean(r$correct_kept),
               prune_rate   = sum(r$distractors_dropped) / sum(r$n_cand - 1),
               mean_kept    = mean(r$n_kept),
               useful_grants = mean(r$correct_kept & r$distractors_dropped > 0))
  }))
}

safe_floor <- function(s, target) {
  ok <- s[recall >= target & prune_rate > 0]
  if (!nrow(ok)) return(NULL)
  ok[which.max(prune_rate)]
}

report <- function(d, label) {
  say(""); say("################ %s : %d grants, %d candidate rows ################",
               label, uniqueN(d$grant_id), nrow(d))
  for (m in c("cov_all", "cos_all", "score")) {
    for (na_keep in if (m == "score") TRUE else c(TRUE, FALSE)) {
      s <- sweep(d, m, na_keep)
      say(""); say("-- %s  (candidates with no text: %s) --", m,
                   if (na_keep) "KEPT" else "dropped")
      print(s[t %in% c(0, 1e-9, 0.1, 0.2, 0.3, 0.5, 0.7, 0.9, 0.999)][
        , .(t = round(t, 3), recall = round(recall, 3),
            prune_rate = round(prune_rate, 3), mean_kept = round(mean_kept, 2),
            useful_grants = round(useful_grants, 3))])
      for (tgt in c(1.00, 0.99, 0.95)) {
        f <- safe_floor(s, tgt)
        if (is.null(f)) say("  recall >= %.2f with any pruning: NOT ACHIEVABLE", tgt)
        else say("  recall >= %.2f : best floor t=%.3f prunes %4.1f%% of distractors",
                 tgt, f$t, 100 * f$prune_rate)
      }
    }
  }
  # precision at the top end -- is a HIGH score trustworthy on its own?
  say(""); say("-- precision of a high score (promotion rule) --")
  base <- d[, mean(is_correct)]
  say("   base rate P(candidate is correct) = %.3f", base)
  print(rbindlist(lapply(c("cov_all", "cos_all"), function(m)
    rbindlist(lapply(c(0.3, 0.5, 0.7, 0.9, 0.999), function(t) {
      k <- !is.na(d[[m]]) & d[[m]] >= t
      # only meaningful where the high scorer is unique within its grant
      u <- copy(d)[, hi := !is.na(get(m)) & get(m) >= t][, n_hi := sum(hi), by = grant_id]
      data.table(metric = m, t = t, n_rows = sum(k),
                 precision = if (sum(k)) round(mean(d$is_correct[k]), 3) else NA_real_,
                 n_unique_hi_grants = uniqueN(u[hi & n_hi == 1]$grant_id),
                 precision_when_unique = {
                   z <- u[hi & n_hi == 1]
                   if (nrow(z)) round(mean(z$is_correct), 3) else NA_real_ })
    })))))
}

report(load_set("PURPOSE-TESTSET-SCORED.csv"),     "GOLD (adjudicated MAYBE, contentful purpose)")
report(load_set("PURPOSE-TESTSET-YES-SCORED.csv"), "SILVER (YES tier, contentful purpose)")
