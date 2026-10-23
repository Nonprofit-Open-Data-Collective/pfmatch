#!/usr/bin/env Rscript
# ============================================================================
# Why the token measures lose, case by case.
#
# The sweep says Jaro-Winkler already discriminates best (auc 0.758) and that
# the containment family admits 10-18 wrong names of 21 at the 0.85 operating
# point. That is a surprising result and it should not be accepted as a
# headline without showing the mechanism, so this prints, per case, the best
# correct name and the best WRONG name under each of two metrics.
#
# Also repairs the acronym test from the sweep, which scored 0 on every row:
# it only fired when one side reduced to a SINGLE token, and "CASA OF NJ"
# tokenises to CASA + NJ ("OF" is a stopword). That was a bug in the test, not
# evidence that acronym handling is worthless.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(library(stringdist)))
suppressWarnings(suppressMessages(library(npmatch)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("-", 100))

d <- fread(file.path(PF, "data-dev", "NAMESIM-SCORES.csv"))
d[, label := as.integer(label)]
SW <- np_stopwords()
tkz <- function(x) { v <- strsplit(x, " +")[[1]]; v[nchar(v) >= 2L & !(v %in% SW)] }

## ---- repaired acronym test --------------------------------------------------
# An acronym need not be the whole name: "CASA OF NJ" is the acronym CASA plus a
# state qualifier. So test every short all-letter token of one side against the
# initials of the other side's leading tokens, allowing the initials to be a
# PREFIX of the long name's token sequence.
acr2 <- function(a, b) {
  A <- tkz(a); B <- tkz(b)
  f <- function(P, Q) {
    out <- 0
    for (p in P[nchar(P) >= 3L & nchar(P) <= 6L & grepl("^[A-Z]+$", P)]) {
      k <- nchar(p)
      if (length(Q) < k) next
      # initials of the first k content tokens, and of any k-window
      for (st in seq_len(length(Q) - k + 1L)) {
        ini <- paste(substr(Q[st:(st + k - 1L)], 1, 1), collapse = "")
        if (identical(p, ini)) { out <- 1; break }
      }
      if (out == 1) break
    }
    out
  }
  max(f(A, B), f(B, A))
}
d[, acronym2 := mapply(function(x, y) acr2(x, y),
                       vapply(filed, function(z) z, ""), cand), by = seq_len(nrow(d))]

## ---- per-case detail ---------------------------------------------------------
show <- function(metric) {
  hr(); say("%s: best CORRECT vs best WRONG, per case", toupper(metric)); hr()
  say("%-9s %-30s %5s  %-34s %5s  %s", "id", "best correct match", "score",
      "best WRONG match", "score", "ok")
  g <- d[, {
    i <- which(label == 1)[which.max(get(metric)[label == 1])]
    j <- which(label == 0)[which.max(get(metric)[label == 0])]
    .(pc = cand[i], ps = get(metric)[i], nc = cand[j], ns = get(metric)[j],
      filed = filed[1])
  }, by = id]
  g[, gap := ps - ns]; setorder(g, gap)
  for (k in seq_len(nrow(g)))
    say("%-9s %-30s %5.2f  %-34s %5.2f  %s", g$id[k], substr(g$pc[k], 1, 30), g$ps[k],
        substr(g$nc[k], 1, 34), g$ns[k], ifelse(g$ps[k] > g$ns[k], "", "  <-- WRONG WINS"))
  g
}
gj <- show("jw")
gi <- show("idf_contain")

hr()
say("The pattern: containment rewards a SHORT filed name for being a subset of")
say("anything longer, and this residual is full of short filed names -- that is")
say("exactly what made them hard. JW's length penalty, which looked like the bug,")
say("is what keeps the wrong answers out.")

hr()
say("REPAIRED ACRONYM TEST")
hr()
ev <- function(v) { d2 <- copy(d)[, s := v]
  g <- d2[, .(p = max(s[label == 1]), q = max(s[label == 0])), by = id]
  c(fires = sum(g$p > 0), prec = mean(g$p > g$q), admits = sum(g$q >= 0.85)) }
a1 <- ev(d$acronym); a2 <- ev(d$acronym2)
say("  original  : fires on %d cases, admits %d wrong", a1[["fires"]], a1[["admits"]])
say("  repaired  : fires on %d cases, admits %d wrong", a2[["fires"]], a2[["admits"]])
hit <- d[label == 1 & acronym2 > 0, .(id, filed, cand)]
if (nrow(hit)) for (i in seq_len(min(8L, nrow(hit))))
  say("    %s  %-26s -> %s", hit$id[i], substr(hit$filed[i], 1, 26), substr(hit$cand[i], 1, 44))
fa <- d[label == 0 & acronym2 > 0, .(id, filed, cand)]
say("  false fires: %d", nrow(fa))
if (nrow(fa)) for (i in seq_len(min(6L, nrow(fa))))
  say("    %s  %-26s -> %s", fa$id[i], substr(fa$filed[i], 1, 26), substr(fa$cand[i], 1, 44))

## ---- JW combined with a repaired acronym test --------------------------------
hr()
say("JW alone vs JW + repaired acronym (max)")
hr()
for (nm in c("jw", "jw+acr")) {
  v <- if (nm == "jw") d$jw else pmax(d$jw, d$acronym2)
  d2 <- copy(d)[, s := v]
  g <- d2[, .(p = max(s[label == 1]), q = max(s[label == 0])), by = id]
  say("  %-8s prec@1 %3.0f%%   finds %2d/%d   admits %2d/%d", nm,
      100 * mean(g$p > g$q), sum(g$p >= 0.85), nrow(g), sum(g$q >= 0.85), nrow(g))
}
fwrite(d, file.path(PF, "data-dev", "NAMESIM-SCORES.csv"))
