#!/usr/bin/env Rscript
# ============================================================================
# probe-additive-risk.R -- what does it cost to ADD purpose similarity to the
# linkage score, rather than using it only to break ties?
#
# The gain was measured in dev/PURPOSE-MATCH-FINDINGS.md (+2 grants in 28 on the
# gold set). This measures the other side: how often an additive term moves the
# top pick AWAY from an answer the cascade already had right. The YES tier is
# the right place to measure that -- those are the cases currently working.
#
# Two variants of the same idea:
#   NA -> 0        the naive encoding: a candidate with no text scores zero
#   NA -> neutral  the term applies only where every candidate is scoreable
# and two scopes: applied to every pair, vs applied only inside a tie band.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
PF  <- Sys.getenv("PFMATCH_DIR", ".")
say <- function(...) cat(sprintf(...), "\n")

load_set <- function(f) {
  d <- fread(file.path(PF, "data-dev", f), na.strings = NULL, showProgress = FALSE)
  d[, is_correct := is_correct %in% c(TRUE, "TRUE", "true")]
  d[, purpose_contentful := purpose_contentful %in% c(TRUE, "TRUE", "true")]
  d <- d[has_truth %in% c(TRUE, "TRUE", "true")]
  d[, score := as.numeric(score)]
  d[, `:=`(top_score = max(score), n_cand = .N), by = grant_id]
  d[, margin := top_score - score]
  d[, rank := as.integer(rank)]
  d[, .SD[.N >= 2 & sum(is_correct) == 1], by = grant_id]
}

# one evaluation of `score + w * metric` under a given NA rule and scope
flip <- function(d, m, w, na_rule = c("zero", "neutral"), tie_band = Inf) {
  na_rule <- match.arg(na_rule)
  z <- copy(d)
  v <- z[[m]]
  z[, mv := v]
  if (na_rule == "zero") {
    z[is.na(mv), mv := 0]
  } else {
    z[, ok := all(!is.na(mv)), by = grant_id]      # only where every candidate scores
    z[ok == FALSE, mv := 0]
  }
  z[purpose_contentful == FALSE, mv := 0]          # the content gate, always on
  # the tie band is a property of the GRANT (how close its top two are), not of
  # the individual pair -- gating per pair would just hand the leader a bonus
  z[, top2_margin := {s <- sort(score, decreasing = TRUE); s[1] - s[2]}, by = grant_id]
  z[top2_margin > tie_band, mv := 0]
  z[, adj := score + w * mv]
  # both sides must use the same tie-breaking convention, or a grant whose top
  # score is tied gets counted as a loss purely from row order
  setorder(z, grant_id, -score, rank)
  r <- z[, .(was_right = is_correct[which.max(score)],
             now_right = is_correct[which.max(adj)]), by = grant_id]
  c(gained = sum(!r$was_right & r$now_right),
    lost   = sum(r$was_right & !r$now_right),
    n      = nrow(r),
    top1   = mean(r$now_right),
    base   = mean(r$was_right))
}

grid <- function(d, label) {
  say(""); say("=== %s : %d grants with >1 candidate and a unique labeled answer ===",
               label, uniqueN(d$grant_id))
  out <- rbindlist(lapply(c("cov_all", "cos_all"), function(m)
    rbindlist(lapply(c("zero", "neutral"), function(nr)
      rbindlist(lapply(c(Inf, 0.05, 0.02), function(tb)
        rbindlist(lapply(c(0.05, 0.10, 0.20, 0.40), function(w) {
          f <- flip(d, m, w, nr, tb)
          data.table(metric = m, na_rule = nr,
                     scope = if (is.infinite(tb)) "all pairs" else sprintf("margin<=%.2f", tb),
                     w = w, gained = f[1], lost = f[2], net = f[1] - f[2],
                     top1 = round(f[4], 3), base = round(f[5], 3))
        }))))))))
  print(out[order(-net, metric, na_rule)][1:16])
  say("  ... worst rows:")
  print(out[order(net)][1:6])
}

gold   <- load_set("PURPOSE-TESTSET-SCORED.csv")
silver <- load_set("PURPOSE-TESTSET-YES-SCORED.csv")
grid(gold,   "GOLD (adjudicated MAYBE)")
grid(silver, "SILVER (YES tier -- everything here is currently right)")

## how well does LENGTH work as the gate, versus content-token count?
say(""); say("=== is character length a usable gate? ===")
g <- rbind(gold[, .(grant_id, grant_purpose, purpose_contentful)],
           silver[, .(grant_id, grant_purpose, purpose_contentful)])
g <- unique(g, by = "grant_id")
g[, nch := nchar(as.character(grant_purpose))]
print(g[, .(grants = .N,
            pct_contentful = round(100 * mean(purpose_contentful), 1)),
        by = .(len_bucket = cut(nch, c(-Inf, 10, 20, 30, 50, 100, Inf),
                                labels = c("<=10", "11-20", "21-30", "31-50",
                                           "51-100", ">100")))][order(len_bucket)])
say("contentless purposes longer than 30 chars: %d", g[nch > 30 & !purpose_contentful, .N])
print(head(unique(g[nch > 30 & !purpose_contentful]$grant_purpose), 8))
say("contentful purposes of 12 characters or fewer: %d", g[nch <= 12 & purpose_contentful, .N])
print(head(unique(g[nch <= 12 & purpose_contentful]$grant_purpose), 8))

say(""); say("=== compact: tie-band scope vs all-pairs, NA->neutral ===")
for (nm in c("GOLD", "SILVER")) {
  d <- if (nm == "GOLD") gold else silver
  say("-- %s --", nm)
  print(rbindlist(lapply(c("cov_all", "cos_all"), function(m)
    rbindlist(lapply(c(Inf, 0.05), function(tb)
      rbindlist(lapply(c(0.05, 0.10, 0.20, 0.40), function(w) {
        f <- flip(d, m, w, "neutral", tb)
        data.table(metric = m,
                   scope = if (is.infinite(tb)) "all pairs" else "margin<=0.05",
                   w = w, gained = f[1], lost = f[2], net = f[1] - f[2])
      })))))))
}
say(""); say("=== scale of the two metrics (why w is not comparable) ===")
for (nm in c("cov_all", "cos_all"))
  say("  %-8s gold p50=%.3f p90=%.3f max=%.3f | silver p50=%.3f p90=%.3f max=%.3f", nm,
      quantile(gold[[nm]], .5, na.rm = TRUE), quantile(gold[[nm]], .9, na.rm = TRUE),
      max(gold[[nm]], na.rm = TRUE),
      quantile(silver[[nm]], .5, na.rm = TRUE), quantile(silver[[nm]], .9, na.rm = TRUE),
      max(silver[[nm]], na.rm = TRUE))
say("grants whose top-2 margin is <= 0.05: gold %4.1f%% | silver %4.1f%%",
    100 * gold[, mean({s <- sort(score, TRUE); s[1]-s[2] <= 0.05}), by = grant_id][, mean(V1)],
    100 * silver[, mean({s <- sort(score, TRUE); s[1]-s[2] <= 0.05}), by = grant_id][, mean(V1)])
