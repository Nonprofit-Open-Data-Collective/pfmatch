#!/usr/bin/env Rscript
# ============================================================================
# Compare string-similarity metrics on the names pfmatch actually fails on.
#
# Production uses Jaro-Winkler (reclin2::cmp_jarowinkler, and stringdist
# method="jw" p=0.1 for the DBA cross-products), floored to 0 below
# config$jw_threshold = 0.85. JW is a character-alignment measure with a prefix
# boost, and the NO-residual failures are mostly NOT character-level:
#
#   containment     MUSCULAR DYSTROPHY  vs  MUSCULAR DYSTROPHY ASSOCIATIONS ...
#   reordering      DANCE PLACE DC WHEEL ...  vs  DC WHEEL ... AKA DANCE PLACE
#   acronym         CASA OF NJ  vs  COURT APPOINTED SPECIAL ADVOCATES OF NJ
#   infix insertion SALVATION ARMY  vs  SALVATION ARMY BIRMINGHAM AREA COMMAND
#
# JW is structurally bad at all four: it is positional, and it penalises an
# unmatched tail in proportion to its length. Token-set measures are not.
#
# THE EVALUATION IS DISCRIMINATION, NOT RECALL. Scoring only the true pairs
# would rank the loosest metric first. Every metric is therefore scored against
# the hard negatives from the same candidate pool, and judged on whether the
# correct organisation outranks them -- and on how many WRONG names it would
# admit at the operating threshold.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(library(stringdist)))
suppressWarnings(suppressMessages(library(npmatch)))
setDTthreads(0)
PF  <- Sys.getenv("PFMATCH_DIR", ".")
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("-", 86))
sq  <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; x }

d <- fread(file.path(PF, "data-dev", "NAMESIM-TESTSET.csv"), colClasses = "character")
d[, label := as.integer(label)]
say("cases %d   positives %d   negatives %d",
    uniqueN(d$id), sum(d$label == 1), sum(d$label == 0))

## ---- IDF over the reference corpus, as the pipeline builds it --------------
# Normalising and counting 3.9M names takes ~15 minutes, so cache it. The cache
# is keyed to nothing: delete it if the reference or the normalizer changes.
IDFC <- file.path(PF, "data-dev", "NAMESIM-TOKEN-IDF.rds")
if (file.exists(IDFC)) {
  IDF <- readRDS(IDFC)
} else {
  b <- fread(file.path(PF, "data-dev", "BMF-AUGMENTED-unified-fixed.csv"),
             colClasses = "character", showProgress = FALSE,
             select = "org_name_join")
  nm <- npmatch:::.np_strip_lead_the(npmatch:::.np_strip_suffix(
          npmatch:::.np_replace_tokens(npmatch:::.np_basic_clean(b$org_name_join),
                                       npmatch:::.np_abbrev)))
  IDF <- np_token_idf(nm)
  saveRDS(IDF, IDFC)
  rm(b, nm); invisible(gc())
}
say("token idf entries: %s", format(length(IDF), big.mark = ","))
SW  <- np_stopwords()
MXI <- max(IDF, na.rm = TRUE)

tok <- function(x) {
  t <- strsplit(sq(x), " +", fixed = FALSE)
  lapply(t, function(v) v[nchar(v) >= 2L & !(v %in% SW)])
}
wt <- function(v) { w <- IDF[v]; w[is.na(w)] <- MXI; w }

A <- tok(d$filed_key); B <- tok(d$cand_key)

## ---- metrics ---------------------------------------------------------------
# Each returns a vector in [0,1], one value per row of d.
n <- nrow(d)
mz <- function(f) { v <- vapply(seq_len(n), f, numeric(1)); v[!is.finite(v)] <- 0; v }

M <- list()
M$jw            <- 1 - stringdist(d$filed_key, d$cand_key, method = "jw", p = 0.1)
M$jw_prod       <- { v <- M$jw; v[v < 0.85] <- 0; v }     # what production sees
M$lv            <- 1 - stringdist(d$filed_key, d$cand_key, method = "lv") /
                       pmax(nchar(d$filed_key), nchar(d$cand_key), 1)
M$lcs           <- 1 - stringdist(d$filed_key, d$cand_key, method = "lcs") /
                       pmax(nchar(d$filed_key) + nchar(d$cand_key), 1)
M$qgram_cosine  <- 1 - stringdist(d$filed_key, d$cand_key, method = "cosine", q = 2)
M$qgram_jaccard <- 1 - stringdist(d$filed_key, d$cand_key, method = "jaccard", q = 2)

M$token_jaccard <- mz(function(i) { a <- A[[i]]; b <- B[[i]]
  if (!length(a) || !length(b)) return(0)
  length(intersect(a, b)) / length(union(a, b)) })

M$token_contain <- mz(function(i) { a <- A[[i]]; b <- B[[i]]
  if (!length(a) || !length(b)) return(0)
  length(intersect(a, b)) / min(length(a), length(b)) })

# IDF-weighted containment: of the INFORMATION in the shorter name, how much is
# present in the longer one. This is the measure that matches the actual failure
# mode -- a filed name that is a true subset of the legal name should score 1.
M$idf_contain <- mz(function(i) { a <- A[[i]]; b <- B[[i]]
  if (!length(a) || !length(b)) return(0)
  sh <- intersect(a, b); if (!length(sh)) return(0)
  sum(wt(sh)) / min(sum(wt(unique(a))), sum(wt(unique(b)))) })

M$idf_cosine <- mz(function(i) { a <- unique(A[[i]]); b <- unique(B[[i]])
  if (!length(a) || !length(b)) return(0)
  sh <- intersect(a, b); if (!length(sh)) return(0)
  sum(wt(sh)^2) / sqrt(sum(wt(a)^2) * sum(wt(b)^2)) })

# fuzzywuzzy token_set_ratio, with JW as the inner comparator so the comparison
# isolates the TOKENISATION change rather than also swapping the base metric.
M$token_set <- mz(function(i) { a <- A[[i]]; b <- B[[i]]
  if (!length(a) || !length(b)) return(0)
  sh <- sort(intersect(a, b))
  s1 <- paste(sh, collapse = " ")
  s2 <- paste(c(sh, sort(setdiff(a, b))), collapse = " ")
  s3 <- paste(c(sh, sort(setdiff(b, a))), collapse = " ")
  max(1 - stringdist(c(s1, s1, s2), c(s2, s3, s3), method = "jw", p = 0.1)) })

# Monge-Elkan: every token of the shorter name finds its best partner in the
# longer one. Tolerates reordering AND per-token typos, which no set measure does.
M$monge_elkan <- mz(function(i) { a <- A[[i]]; b <- B[[i]]
  if (!length(a) || !length(b)) return(0)
  if (length(a) > length(b)) { t <- a; a <- b; b <- t }
  mean(vapply(a, function(x) max(1 - stringdist(x, b, method = "jw", p = 0.1)), 0)) })

# Acronym: initials of one side against the other side's tokens, both directions.
M$acronym <- mz(function(i) { a <- A[[i]]; b <- B[[i]]
  if (!length(a) || !length(b)) return(0)
  f <- function(p, q) {
    if (length(p) != 1L || nchar(p) < 2L || length(q) < 2L) return(0)
    as.numeric(identical(toupper(p), paste(substr(q, 1, 1), collapse = "")))
  }
  max(f(a, b), f(b, a)) })

## ---- a combined rule, not a single metric ----------------------------------
# No single measure covers typos AND reordering AND acronyms. Production already
# takes a max over name/DBA variants, so the natural form is a max over
# complementary measures rather than a replacement for JW.
M$max_jw_idf      <- pmax(M$jw, M$idf_contain)
M$max_jw_idf_acr  <- pmax(M$jw, M$idf_contain, M$acronym)
M$max_jw_me_acr   <- pmax(M$jw, M$monge_elkan, M$acronym)

## ---- evaluate ---------------------------------------------------------------
# precision@1 : does the best positive beat the best negative, per case
# margin      : how decisively
# admits@t    : cases where a WRONG name reaches the threshold (the real cost)
# finds@t     : cases where a RIGHT name reaches the threshold (the real gain)
ev <- function(v, thr = 0.85) {
  d2 <- copy(d)[, s := v]
  g  <- d2[, .(p = max(s[label == 1], -Inf), q = max(s[label == 0], -Inf)), by = id]
  auc <- d2[, {
    pp <- s[label == 1]; nn <- s[label == 0]
    if (!length(pp) || !length(nn)) NA_real_ else
      mean(outer(pp, nn, ">") + 0.5 * outer(pp, nn, "=="))
  }, by = id]$V1
  data.table(
    prec_at_1 = mean(g$p > g$q),
    auc       = mean(auc, na.rm = TRUE),
    margin    = mean(g$p - g$q),
    finds     = sum(g$p >= thr),
    admits    = sum(g$q >= thr),
    n_case    = nrow(g))
}
res <- rbindlist(lapply(M, ev), idcol = "metric")
setorder(res, -prec_at_1, -auc)

hr()
say("NAME METRICS ON THE %d NO-RESIDUAL CASES  (threshold 0.85, as in production)",
    uniqueN(d$id))
hr()
say("%-16s %9s %7s %8s %8s %8s", "metric", "prec@1", "auc", "margin",
    "finds", "admits")
for (i in seq_len(nrow(res)))
  say("%-16s %8.0f%% %7.3f %8.3f %5d/%d %5d/%d", res$metric[i],
      100 * res$prec_at_1[i], res$auc[i], res$margin[i],
      res$finds[i], res$n_case[i], res$admits[i], res$n_case[i])
hr()
say("finds  = cases where the CORRECT name reaches 0.85 (recall gained)")
say("admits = cases where a WRONG name reaches 0.85 (precision lost)")

fwrite(res, file.path(PF, "data-dev", "NAMESIM-METRICS.csv"))
sc <- as.data.table(M); sc[, c("id", "filed", "cand", "label") :=
                            .(d$id, d$filed, d$cand, d$label)]
fwrite(sc, file.path(PF, "data-dev", "NAMESIM-SCORES.csv"))
say("")
say("wrote data-dev/NAMESIM-METRICS.csv and NAMESIM-SCORES.csv")
