#!/usr/bin/env Rscript
# ============================================================================
# probe-presence-prior.R -- test the filing-presence features the way §9 tested
# purpose similarity, and the way §8 tested the additive score.
#
# §4 found that whether a candidate files a Form 990 with program descriptions
# discriminates better than any comparison of what those descriptions say:
# text_len 0.810 / n_prog 0.792 / has_mission 0.744 pair AUC, against cov_all
# 0.665. Unlike purpose similarity these features are DENSE -- never silent --
# so unlike §9 they could in principle support a safe recall floor.
#
# Three tests:
#   A  threshold sweep -- is there a floor that prunes without dropping truth?
#   B  tiebreak -- inside the tie band, does ordering on presence beat cov_all?
#   C  who gets hurt -- presence encodes organization size, so what does it cost
#      small grantees specifically?
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
PF  <- Sys.getenv("PFMATCH_DIR", ".")
say <- function(...) cat(sprintf(...), "\n")
bad <- function(x) { x <- toupper(trimws(as.character(x))); x[is.na(x)] <- ""
                     x == "" | x %in% c("INVALID", "UNDEFINED", "Z99", "Z") }

load_set <- function(f) {
  d <- fread(file.path(PF, "data-dev", f), na.strings = NULL, showProgress = FALSE)
  d[, is_correct := is_correct %in% c(TRUE, "TRUE", "true")]
  d[, purpose_contentful := purpose_contentful %in% c(TRUE, "TRUE", "true")]
  d <- d[has_truth %in% c(TRUE, "TRUE", "true")]
  d[, `:=`(score = as.numeric(score), rank = as.integer(rank))]
  d[, `:=`(has_mission = as.numeric(nzchar(as.character(cand_mission))),
           has_program = as.numeric(nzchar(as.character(cand_prog_all))),
           n_prog      = suppressWarnings(as.numeric(cand_n_programs)))]
  d[is.na(n_prog), n_prog := 0]
  d[, text_len := nchar(as.character(cand_mission)) + nchar(as.character(cand_prog_all))]
  d[, .SD[.N >= 2 & sum(is_correct) == 1], by = grant_id]
}

FEATS <- c("has_mission", "has_program", "n_prog", "text_len", "cov_all")

## ---- A. threshold sweep ----------------------------------------------------
sweep <- function(d, m) {
  v <- d[[m]]; v[is.na(v)] <- 0
  d2 <- copy(d)[, mv := v]
  ts <- sort(unique(c(0, quantile(v, seq(0.05, 0.95, 0.05), na.rm = TRUE))))
  rbindlist(lapply(ts, function(t) {
    r <- d2[, .(correct_kept = mv[is_correct] >= t,
                n_kept = sum(mv >= t), n_cand = .N,
                dropped = sum(mv < t & !is_correct)), by = grant_id]
    data.table(t = t, recall = mean(r$correct_kept),
               prune_rate = sum(r$dropped) / sum(r$n_cand - 1),
               mean_kept = mean(r$n_kept))
  }))[!duplicated(paste(recall, prune_rate))]
}
safe_floor <- function(s, tgt) {
  ok <- s[recall >= tgt & prune_rate > 0]
  if (!nrow(ok)) return(NULL)
  ok[which.max(prune_rate)]
}

## ---- B. tiebreak (no weight: reorder inside the band, score outside) --------
tiebreak <- function(d, m, band = 0.05, gate_contentful = FALSE) {
  z <- copy(d)
  z[, tv := as.numeric(get(m))]
  z[is.na(tv), tv := -Inf]
  if (gate_contentful) z[purpose_contentful == FALSE, tv := -Inf]
  z[, top2 := {s <- sort(score, decreasing = TRUE); s[1] - s[2]}, by = grant_id]
  setorder(z, grant_id, -score, rank)
  r <- z[, {
    was <- is_correct[which.max(score)]
    now <- if (top2[1] <= band) {
      lead <- which(score >= max(score) - band)          # the candidates in contention
      is_correct[lead][which.max(tv[lead])]
    } else was
    .(was_right = was, now_right = now)
  }, by = grant_id]
  c(gained = sum(!r$was_right & r$now_right), lost = sum(r$was_right & !r$now_right),
    n = nrow(r), top1 = mean(r$now_right), base = mean(r$was_right))
}

report <- function(d, label) {
  say(""); say("############ %s : %d grants, %d rows ############",
               label, uniqueN(d$grant_id), nrow(d))
  say(""); say("--- A. can a presence floor prune safely? ---")
  for (m in FEATS) {
    s <- sweep(d, m)
    line <- sapply(c(1.00, 0.99, 0.95, 0.90), function(tg) {
      f <- safe_floor(s, tg)
      if (is.null(f)) "--" else sprintf("t=%g:%0.0f%%", f$t, 100 * f$prune_rate)
    })
    say("  %-12s recall>=1.00 %-12s >=0.99 %-12s >=0.95 %-12s >=0.90 %-12s",
        m, line[1], line[2], line[3], line[4])
  }
  say("  (cell = best floor achieving that recall, and what it prunes; -- = not achievable)")

  say(""); say("--- B. tiebreak inside the tie band (no weight) ---")
  tb <- rbindlist(lapply(FEATS, function(m) {
    a <- tiebreak(d, m, 0.05, gate_contentful = (m == "cov_all"))
    b <- tiebreak(d, m, 0.02, gate_contentful = (m == "cov_all"))
    data.table(feature = m, band = c(0.05, 0.02),
               gained = c(a[1], b[1]), lost = c(a[2], b[2]),
               net = c(a[1] - a[2], b[1] - b[2]),
               top1 = round(c(a[4], b[4]), 3), base = round(a[5], 3))
  }))
  print(tb[order(-net)])

  say(""); say("--- C. where the presence prior would be wrong ---")
  say("  correct candidates lacking each signal:")
  print(d[is_correct == TRUE, .(n = .N,
      no_mission = sum(has_mission == 0), no_program = sum(has_program == 0),
      no_ntee = sum(bad(CAND_ntee_code_clean)))])
  h <- d[, .(correct_has = has_mission[is_correct],
             best_distractor = max(has_mission[!is_correct])), by = grant_id]
  say("  grants where the correct candidate has NO mission but a distractor does: %d of %d (%4.1f%%)",
      h[correct_has == 0 & best_distractor == 1, .N], nrow(h),
      100 * h[, mean(correct_has == 0 & best_distractor == 1)])
  say("  -- a presence tiebreak actively picks the wrong one in every such grant.")
  if ("grant_amount" %in% names(d)) {
    d[, amt := suppressWarnings(as.numeric(gsub("[^0-9.]", "", as.character(grant_amount))))]
    g <- unique(d[is_correct == TRUE, .(grant_id, amt, has_mission)], by = "grant_id")
    print(g[!is.na(amt), .(grants = .N, median_grant = median(amt)),
            by = .(correct_candidate_files_990 = has_mission == 1)])
  }
}

report(load_set("PURPOSE-TESTSET-SCORED.csv"),     "GOLD (adjudicated MAYBE)")
report(load_set("PURPOSE-TESTSET-YES-SCORED.csv"), "SILVER (YES tier, all currently right)")

## ---- D. cascaded tiebreak: does combining presence and purpose beat either? --
tiebreak2 <- function(d, keys, band = 0.05) {
  z <- copy(d)
  for (k in keys) {
    v <- as.numeric(z[[k]]); v[is.na(v)] <- -Inf
    if (k == "cov_all") v[z$purpose_contentful == FALSE] <- -Inf
    z[[paste0(".k_", k)]] <- v
  }
  z[, top2 := {s <- sort(score, decreasing = TRUE); s[1] - s[2]}, by = grant_id]
  setorder(z, grant_id, -score, rank)
  kk <- paste0(".k_", keys)
  r <- z[, {
    was <- is_correct[which.max(score)]
    now <- was
    if (top2[1] <= band) {
      lead <- which(score >= max(score) - band)
      ord <- do.call(order, c(lapply(kk, function(c) -.SD[[c]][lead]), list(lead)))
      now <- is_correct[lead][ord[1]]
    }
    .(was_right = was, now_right = now)
  }, by = grant_id, .SDcols = kk]
  c(gained = sum(!r$was_right & r$now_right), lost = sum(r$was_right & !r$now_right),
    top1 = mean(r$now_right), base = mean(r$was_right))
}

say(""); say("############ D. cascaded tiebreaks, band 0.05 ############")
COMBOS <- list("has_mission", "cov_all", "text_len",
               c("has_mission", "cov_all"), c("cov_all", "has_mission"),
               c("has_mission", "text_len"), c("cov_all", "has_mission", "text_len"))
for (nm in c("GOLD", "SILVER")) {
  d <- load_set(if (nm == "GOLD") "PURPOSE-TESTSET-SCORED.csv" else "PURPOSE-TESTSET-YES-SCORED.csv")
  say("-- %s --", nm)
  print(rbindlist(lapply(COMBOS, function(k) {
    f <- tiebreak2(d, k, 0.05)
    data.table(tiebreak = paste(k, collapse = " -> "), gained = f[1], lost = f[2],
               net = f[1] - f[2], top1 = round(f[3], 3), base = round(f[4], 3))
  }))[order(-net)])
}
