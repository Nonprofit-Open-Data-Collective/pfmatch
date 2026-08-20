#!/usr/bin/env Rscript
# ============================================================================
# probe-tiebreak-scope.R -- npmatch already implements the rule §10 recommends.
#
#   .np_overall_summary(): close <- candidates within `tie_band` of the top;
#   if length(close) >= 2 AND top >= `tie_high`, pick argmax of the tiebreak key
#   (currently full-name Jaccard-Winkler) instead of argmax score.
#   Defaults: tie_band = 0.05, tie_high = 0.95, tiebreak = "name".
#
# My probe used tie_band = 0.05 but ignored the tie_high >= 0.95 gate. If the
# measured gain sits mostly below 0.95, adopting it means WIDENING the tiebreak's
# scope, which is a much bigger change than adding a key. This checks.
#
# It also tests the honest cascade -- name first (npmatch's existing behaviour),
# then the new keys -- rather than pretending the slot is empty.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
PF <- Sys.getenv("PFMATCH_DIR", ".")
say <- function(...) cat(sprintf(...), "\n")

d <- fread(file.path(PF, "data-dev", "PURPOSE-TESTSET-SCORED.csv"),
           na.strings = NULL, showProgress = FALSE)
d[, is_correct := is_correct %in% c(TRUE, "TRUE", "true")]
d[, purpose_contentful := purpose_contentful %in% c(TRUE, "TRUE", "true")]
d <- d[has_truth %in% c(TRUE, "TRUE", "true")]
d[, `:=`(score = as.numeric(score), name_sim = as.numeric(name_sim),
         rank = as.integer(rank))]
d[, has_mission := as.numeric(nzchar(as.character(cand_mission)))]
d[, text_len := nchar(as.character(cand_mission)) + nchar(as.character(cand_prog_all))]
d <- d[, .SD[.N >= 2 & sum(is_correct) == 1], by = grant_id]
d[, top_score := max(score), by = grant_id]
d[, top2 := {s <- sort(score, decreasing = TRUE); s[1] - s[2]}, by = grant_id]

say("gold: %d contested grants", uniqueN(d$grant_id))
g <- unique(d, by = "grant_id")
say("")
say("=== where do the tie-band grants sit relative to tie_high = 0.95? ===")
print(g[, .(grants = .N), by = .(in_band = top2 <= 0.05,
                                 top_ge_95 = top_score >= 0.95)][order(-grants)])
say("npmatch's existing tiebreak fires on %d of %d grants (in band AND top>=0.95)",
    g[top2 <= 0.05 & top_score >= 0.95, .N], nrow(g))
say("my probe's scope was %d grants (in band, any top score)", g[top2 <= 0.05, .N])

## generalized cascade with both gates exposed
tb <- function(d, keys, band = 0.05, tie_high = 0) {
  z <- copy(d)
  kk <- character()
  for (k in keys) {
    v <- as.numeric(z[[k]]); v[is.na(v)] <- -Inf
    if (k == "cov_all") v[z$purpose_contentful == FALSE] <- -Inf
    nm <- paste0(".k_", k); z[[nm]] <- v; kk <- c(kk, nm)
  }
  setorder(z, grant_id, -score, rank)
  r <- z[, {
    was <- is_correct[which.max(score)]
    now <- was
    lead <- which(score >= max(score) - band)
    if (length(lead) >= 2 && max(score) >= tie_high) {
      ord <- do.call(order, c(lapply(kk, function(cc) -.SD[[cc]][lead]), list(lead)))
      now <- is_correct[lead][ord[1]]
    }
    .(was_right = was, now_right = now, fired = length(lead) >= 2 && max(score) >= tie_high)
  }, by = grant_id, .SDcols = kk]
  c(gained = sum(!r$was_right & r$now_right), lost = sum(r$was_right & !r$now_right),
    fired = sum(r$fired), top1 = mean(r$now_right), base = mean(r$was_right))
}

COMBOS <- list(
  "name_sim",                                    # npmatch's current key
  c("name_sim", "cov_all"),
  c("name_sim", "cov_all", "has_mission"),
  c("name_sim", "has_mission"),
  c("cov_all", "has_mission"),
  c("name_sim", "cov_all", "has_mission", "text_len"))

for (th in c(0.95, 0.90, 0.00)) {
  say(""); say("=== tie_high = %.2f ===", th)
  print(rbindlist(lapply(COMBOS, function(k) {
    f <- tb(d, k, 0.05, th)
    data.table(tiebreak = paste(k, collapse = " -> "), fires_on = f[3],
               gained = f[1], lost = f[2], net = f[1] - f[2],
               top1 = round(f[4], 3), base = round(f[5], 3))
  }))[order(-net)])
}
