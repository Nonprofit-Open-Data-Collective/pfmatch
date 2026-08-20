#!/usr/bin/env Rscript
# ============================================================================
# probe-text-presence.R -- the availability probe showed that the CORRECT
# candidate carries 990 text far more often than the distractors do (gold:
# 94% vs 45% have a mission). That is not a similarity signal at all -- it is a
# filing-activity prior. This measures how much of the discrimination comes
# from merely HAVING text, before any word is compared.
#
# Run after dev/eval-purpose-sim.R (it reads the *-SCORED.csv files).
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
PF  <- Sys.getenv("PFMATCH_DIR", ".")
say <- function(...) cat(sprintf(...), "\n")
bad <- function(x) { x <- toupper(trimws(as.character(x))); x[is.na(x)] <- ""
                     x == "" | x %in% c("INVALID", "UNDEFINED", "Z99", "Z") }

auc <- function(x, y) {
  ok <- !is.na(x); p <- x[ok & y]; n <- x[ok & !y]
  if (!length(p) || !length(n)) return(NA_real_)
  r <- rank(c(p, n))
  (sum(r[seq_along(p)]) - length(p) * (length(p) + 1) / 2) / (length(p) * length(n))
}
top1 <- function(d, col) {
  z <- d[!is.na(get(col)), .(grant_id, v = get(col), is_correct)]
  z <- z[, if (.N >= 2 && sum(is_correct) == 1 && uniqueN(v) > 1) .SD, by = grant_id]
  if (!nrow(z)) return(c(NA, 0))
  r <- z[, .(hit = is_correct[which.max(v)]), by = grant_id]
  c(mean(r$hit), nrow(r))
}

for (f in c("PURPOSE-TESTSET-SCORED", "PURPOSE-TESTSET-YES-SCORED")) {
  p <- file.path(PF, "data-dev", paste0(f, ".csv"))
  if (!file.exists(p)) { say("missing %s -- run dev/eval-purpose-sim.R first", p); next }
  d <- fread(p, na.strings = NULL, showProgress = FALSE)
  d[, is_correct := is_correct %in% c(TRUE, "TRUE", "true")]
  d <- d[has_truth %in% c(TRUE, "TRUE", "true")]
  d[, `:=`(has_mission = as.numeric(nzchar(as.character(cand_mission))),
           has_program = as.numeric(nzchar(as.character(cand_prog_all))),
           has_ntee    = as.numeric(!bad(CAND_ntee_code_clean)),
           n_prog      = suppressWarnings(as.numeric(cand_n_programs)))]
  d[is.na(n_prog), n_prog := 0]
  d[, text_len := nchar(as.character(cand_mission)) + nchar(as.character(cand_prog_all))]
  d[, files_990 := as.numeric(as.character(cand_return_type) == "990")]

  say(""); say("=== %s : %d grants, %d rows ===", f, uniqueN(d$grant_id), nrow(d))
  tb <- rbindlist(lapply(c("has_mission", "has_program", "has_ntee", "n_prog",
                           "text_len", "files_990",
                           "cov_all", "cos_all", "score"), function(m) {
    t <- top1(d, m)
    data.table(feature = m, pair_auc = round(auc(d[[m]], d$is_correct), 3),
               top1 = round(t[1], 3), n_grants = t[2])
  }))
  print(tb[order(-pair_auc)])

  # does purpose similarity add anything once presence is controlled for?
  say("  among candidate rows that ALL have 990 text:")
  sub <- d[, if (all(has_mission == 1) && .N >= 2 && sum(is_correct) == 1) .SD, by = grant_id]
  if (nrow(sub)) {
    tb2 <- rbindlist(lapply(c("cov_all", "cos_all", "cov_mis", "cov_prog", "cov_ntee",
                              "nb_major", "score"), function(m) {
      t <- top1(sub, m)
      data.table(feature = m, pair_auc = round(auc(sub[[m]], sub$is_correct), 3),
                 top1 = round(t[1], 3), n_grants = t[2])
    }))
    print(tb2[order(-pair_auc)])
    say("  (%d grants where every candidate has a mission)", uniqueN(sub$grant_id))
  } else say("  none")
}
