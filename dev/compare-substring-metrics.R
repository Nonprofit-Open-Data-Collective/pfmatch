#!/usr/bin/env Rscript
# ============================================================================
# Substring-oriented matchers on the NO-residual names.
#
# The earlier sweep (dev/NAME-METRIC-EVALUATION.md) tested token-SET measures --
# Jaccard, containment, Monge-Elkan. It did not test true SUBSTRING matching,
# which is a different mechanism and a fair gap: the dominant failure shape here
# is a filed name that is literally a prefix or an infix of the legal name
# ("PLAYWORKS" inside "PLAYWORKS WASHINGTON DC"). Character-level substring
# matchers target exactly that.
#
# This matters more now that dev/JARO-NOT-JAROWINKLER.md established the
# production comparator is plain Jaro (p=0). The reason Jaro-Winkler helps is
# its PREFIX BOOST -- a weak, bounded form of substring credit. So the real
# question is whether a full substring matcher beats a bounded prefix bonus, or
# whether it over-fires the way containment did.
#
# Baselines therefore include BOTH Jaro (what production actually does) and
# Jaro-Winkler (what it is documented to do).
#
# Same discrimination test as before: hard negatives from each case's own
# candidate pool, scored on whether the correct org outranks them and on how
# many WRONG names clear the operating threshold.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(library(stringdist)))
setDTthreads(0)
PF  <- Sys.getenv("PFMATCH_DIR", ".")
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("-", 86))

d <- fread(file.path(PF, "data-dev", "NAMESIM-TESTSET.csv"), colClasses = "character")
d[, label := as.integer(label)]
A <- d$filed_key; B <- d$cand_key
n <- nrow(d)
say("cases %d   positives %d   negatives %d", uniqueN(d$id), sum(d$label == 1),
    sum(d$label == 0))

mz <- function(f) { v <- vapply(seq_len(n), f, numeric(1)); v[!is.finite(v)] <- 0; v }

## ---- longest common contiguous substring -----------------------------------
lcsubstr <- function(a, b) {
  if (!nchar(a) || !nchar(b)) return(0L)
  x <- strsplit(a, "")[[1]]; y <- strsplit(b, "")[[1]]
  prev <- integer(length(y) + 1L); best <- 0L
  for (i in seq_along(x)) {
    cur <- integer(length(y) + 1L)
    eq <- which(y == x[i])
    if (length(eq)) {
      cur[eq + 1L] <- prev[eq] + 1L
      m <- max(cur[eq + 1L]); if (m > best) best <- m
    }
    prev <- cur
  }
  best
}

M <- list()
M$jaro        <- 1 - stringdist(A, B, method = "jw", p = 0)     # PRODUCTION
M$jw          <- 1 - stringdist(A, B, method = "jw", p = 0.1)   # documented

# fuzzywuzzy partial_ratio: slide a window the length of the shorter string over
# the longer one and keep the best local similarity. The canonical substring
# matcher.
M$partial_ratio <- mz(function(i) {
  a <- A[i]; b <- B[i]
  if (nchar(a) > nchar(b)) { t <- a; a <- b; b <- t }
  la <- nchar(a); lb <- nchar(b)
  if (!la) return(0)
  if (la == lb) return(1 - stringdist(a, b, method = "lv") / la)
  st <- seq_len(lb - la + 1L)
  w  <- substring(b, st, st + la - 1L)
  max(1 - stringdist(a, w, method = "lv") / la)
})

# longest common substring, normalised two ways: by the shorter string (a
# containment-flavoured view) and by both (a symmetric view)
M$lcsubstr_min <- mz(function(i) {
  l <- lcsubstr(A[i], B[i]); m <- min(nchar(A[i]), nchar(B[i]))
  if (!m) 0 else l / m })
M$lcsubstr_sym <- mz(function(i) {
  l <- lcsubstr(A[i], B[i]); s <- nchar(A[i]) + nchar(B[i])
  if (!s) 0 else 2 * l / s })

# pure prefix agreement -- the mechanism Jaro-Winkler approximates, unbounded
M$prefix_ratio <- mz(function(i) {
  a <- A[i]; b <- B[i]; m <- min(nchar(a), nchar(b))
  if (!m) return(0)
  k <- 0L
  while (k < m && substr(a, k + 1L, k + 1L) == substr(b, k + 1L, k + 1L)) k <- k + 1L
  k / m })

# is one string literally contained in the other?
M$is_substring <- as.numeric(mapply(function(a, b)
  grepl(a, b, fixed = TRUE) || grepl(b, a, fixed = TRUE), A, B))

# combinations with the production baseline
M$max_jaro_partial  <- pmax(M$jaro, M$partial_ratio)
M$max_jw_partial    <- pmax(M$jw,   M$partial_ratio)

## ---- evaluate ---------------------------------------------------------------
ev <- function(v, thr = 0.85) {
  d2 <- copy(d)[, s := v]
  g  <- d2[, .(p = max(s[label == 1]), q = max(s[label == 0])), by = id]
  auc <- d2[, { pp <- s[label == 1]; nn <- s[label == 0]
    if (!length(pp) || !length(nn)) NA_real_ else
      mean(outer(pp, nn, ">") + 0.5 * outer(pp, nn, "==")) }, by = id]$V1
  data.table(prec_at_1 = mean(g$p > g$q), auc = mean(auc, na.rm = TRUE),
             margin = mean(g$p - g$q), finds = sum(g$p >= thr),
             admits = sum(g$q >= thr), n_case = nrow(g))
}
res <- rbindlist(lapply(M, ev), idcol = "metric")
setorder(res, -auc)
hr()
say("SUBSTRING MATCHERS vs THE PRODUCTION COMPARATOR  (threshold 0.85)")
hr()
say("%-20s %8s %7s %8s %9s %9s", "metric", "prec@1", "auc", "margin", "finds", "admits")
for (i in seq_len(nrow(res)))
  say("%-20s %7.0f%% %7.3f %8.3f %6d/%d %6d/%d", res$metric[i],
      100 * res$prec_at_1[i], res$auc[i], res$margin[i],
      res$finds[i], res$n_case[i], res$admits[i], res$n_case[i])
hr()
say("finds = the CORRECT name clears 0.85; admits = a WRONG name clears 0.85")

## ---- the specific pairs this was meant to fix -------------------------------
hr()
say("ON THE SIX CASES THAT MOTIVATED THIS")
hr()
ex <- rbind(
  c("PLAYWORKS", "PLAYWORKS WASHINGTON DC"),
  c("THISTLEBEND COTTAGE", "THISTLEBEND MINISTRIES"),
  c("SALVATION ARMY", "SALVATION ARMY BIRMINGHAM AREA COMMAND"),
  c("MUSCULAR DYSTROPHY", "MUSCULAR DYSTROPHY ASSOCIATION"),
  c("GIRLS", "GIRLS INC OF WASHINGTON COUNTY"),
  c("GIRLS", "GIRLS"))
say("%-22s %-32s %6s %6s %8s %8s", "filed", "reference", "jaro", "jw", "partial", "lcs_min")
for (i in seq_len(nrow(ex))) {
  a <- ex[i, 1]; b <- ex[i, 2]
  pa <- { aa <- a; bb <- b
    if (nchar(aa) > nchar(bb)) { t <- aa; aa <- bb; bb <- t }
    la <- nchar(aa); lb <- nchar(bb)
    if (la == lb) 1 - stringdist(aa, bb, method = "lv") / la else {
      st <- seq_len(lb - la + 1L); w <- substring(bb, st, st + la - 1L)
      max(1 - stringdist(aa, w, method = "lv") / la) } }
  say("%-22s %-32s %6.3f %6.3f %8.3f %8.3f", substr(a, 1, 22), substr(b, 1, 32),
      1 - stringdist(a, b, method = "jw", p = 0),
      1 - stringdist(a, b, method = "jw", p = 0.1), pa,
      lcsubstr(a, b) / min(nchar(a), nchar(b)))
}
fwrite(res, file.path(PF, "data-dev", "SUBSTRING-METRICS.csv"))
