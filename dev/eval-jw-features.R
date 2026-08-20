#!/usr/bin/env Rscript
# Which feature separates "same org" from "shares a generic head" among pairs
# that Jaro-Winkler already calls >= 0.95?
suppressWarnings(suppressMessages(library(data.table)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
NPM <- Sys.getenv("NPMATCH_DIR", "../npmatch")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 74), "\n")

ts <- fread(file.path(PF, "data-dev", "JW-HEAD-TESTSET.csv"), colClasses = list(character = c("a", "b")))
idf <- readRDS(file.path(PF, "data-dev", "BMF-REFERENCE-BUNDLE.rds"))$token_idf
sw  <- npmatch::np_stopwords()
mx  <- max(idf, na.rm = TRUE)
w1  <- function(t) { v <- idf[t]; v[is.na(v)] <- mx; v }

toks <- function(x) strsplit(ifelse(is.na(x), "", x), " ", fixed = TRUE)
ta <- toks(ts$a); tb <- toks(ts$b)

# --- feature 1: JW after dropping the shared leading tokens -----------------
ts[, jw_tail := mapply(function(x, y) {
  k <- 0L
  while (k < min(length(x), length(y)) && x[k + 1L] == y[k + 1L]) k <- k + 1L
  if (k == 0L) return(as.numeric(jw[1]))
  rx <- paste(x[-seq_len(k)], collapse = " "); ry <- paste(y[-seq_len(k)], collapse = " ")
  if (!nzchar(rx) || !nzchar(ry)) return(0)
  1 - stringdist::stringdist(rx, ry, method = "jw", p = 0.1)
}, ta, tb)]

# --- feature 2: IDF-weighted token agreement --------------------------------
ts[, idf_agree := mapply(function(x, y) {
  x <- unique(x[nzchar(x) & !(x %in% sw)]); y <- unique(y[nzchar(y) & !(y %in% sw)])
  if (!length(x) || !length(y)) return(1)
  shared <- intersect(x, y); all_t <- union(x, y)
  if (!length(all_t)) return(1)
  sum(w1(shared)) / sum(w1(all_t))
}, ta, tb)]

# --- feature 3: summed IDF of tokens unique to one side ---------------------
ts[, idf_disagree := mapply(function(x, y) {
  x <- unique(x[nzchar(x) & !(x %in% sw)]); y <- unique(y[nzchar(y) & !(y %in% sw)])
  d <- c(setdiff(x, y), setdiff(y, x))
  if (!length(d)) return(0)
  sum(w1(d))
}, ta, tb)]

hr(); say("SEPARATION (all pairs, JW >= 0.95 by construction)"); hr()
say("%-14s %22s %22s", "feature", "negatives (n=340)", "positives (n=1897)")
for (f in c("jw", "jw_tail", "idf_agree", "idf_disagree")) {
  n <- ts[label == 0][[f]]; p <- ts[label == 1][[f]]
  say("%-14s med %.3f  q90 %.3f   med %.3f  q10 %.3f", f,
      stats::median(n), stats::quantile(n, .9), stats::median(p), stats::quantile(p, .1))
}

hr(); say("THE HARD BAND: pairs that are NOT already exact (JW < 1)"); hr()
h <- ts[jw < 0.9999]
say("negatives %d | positives %d", sum(h$label == 0), sum(h$label == 1))
for (f in c("jw", "jw_tail", "idf_agree", "idf_disagree")) {
  n <- h[label == 0][[f]]; p <- h[label == 1][[f]]
  say("%-14s neg med %.3f | pos med %.3f", f, stats::median(n), stats::median(p))
}

hr(); say("GATE SWEEP -- how many negatives blocked per positive lost?"); hr()
say("%-28s %10s %10s %12s", "rule", "neg blocked", "pos lost", "neg per pos")
sweep <- function(lbl, keep) {
  nb <- sum(!keep[ts$label == 0]); pl <- sum(!keep[ts$label == 1])
  say("%-28s %9d%% %9d%% %12s", lbl, round(100 * nb / sum(ts$label == 0)),
      round(100 * pl / sum(ts$label == 1)),
      if (pl == 0) "inf" else sprintf("%.1f", nb / pl))
}
for (t in c(0.80, 0.85, 0.90)) sweep(sprintf("jw_tail >= %.2f", t), ts$jw_tail >= t)
for (t in c(0.30, 0.40, 0.50, 0.60)) sweep(sprintf("idf_agree >= %.2f", t), ts$idf_agree >= t)
for (t in c(20, 15, 12, 10)) sweep(sprintf("idf_disagree <= %d", t), ts$idf_disagree <= t)
sweep("idf_agree>=.4 & tail>=.85", ts$idf_agree >= 0.40 & ts$jw_tail >= 0.85)

hr(); say("WHAT DOES idf_agree >= 0.40 BLOCK?"); hr()
b <- ts[label == 0 & idf_agree < 0.40]
for (i in head(sample(nrow(b)), 10))
  say("  %-36s | %-36s agree=%.2f", substr(b$a[i], 1, 36), substr(b$b[i], 1, 36), b$idf_agree[i])
say("\npositives it would wrongly block:")
pl <- ts[label == 1 & idf_agree < 0.40]
say("  n = %d", nrow(pl))
for (i in head(seq_len(nrow(pl)), 8))
  say("  %-36s | %-36s agree=%.2f", substr(pl$a[i], 1, 36), substr(pl$b[i], 1, 36), pl$idf_agree[i])
fwrite(ts, file.path(PF, "data-dev", "JW-HEAD-FEATURES.csv"))
