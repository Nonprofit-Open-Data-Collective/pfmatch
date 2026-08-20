#!/usr/bin/env Rscript
# ============================================================================
# The promotion floor gates on name_freq <= 3: "how many BMF records share this
# exact normalized name". That measures LEXICAL uniqueness, not whether the name
# actually identifies anything.
#
# "COMMUNITY CHURCH" is unique in the BMF as a literal string -- almost every
# other one is "<Place> Community Church" -- so it passes the gate, and a Big
# Bear Lake CA grant was auto-accepted to a Fort Jones CA congregation 700 miles
# away. "KOINONIA ACADEMY" passes the same gate and is genuinely identifying.
#
# Hypothesis: total token IDF separates the two. Test it.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
NPM <- Sys.getenv("NPMATCH_DIR", "../npmatch")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 74), "\n")

p <- readRDS(file.path(PF, "data-dev", "PROMOTION-PROBE.rds"))
B <- readRDS(file.path(PF, "data-dev", "BMF-REFERENCE-BUNDLE.rds"))
idf <- B$token_idf
sw <- npmatch::np_stopwords()

name_idf <- function(nm) {
  d <- npmatch::np_normalize(npmatch::np_query(
    data.frame(id = seq_along(nm), name = nm, state = "XX", stringsAsFactors = FALSE),
    c(.id = "id", name = "name", state = "state")))
  vapply(strsplit(ifelse(is.na(d$name_key), "", d$name_key), " ", fixed = TRUE),
         function(t) {
           t <- t[nzchar(t) & !(t %in% sw) & nchar(t) >= 2]
           if (!length(t)) return(0)
           w <- idf[t]; w[is.na(w)] <- max(idf, na.rm = TRUE)
           sum(w)
         }, numeric(1))
}

st <- p$on
dep <- st$grant_id %in% p$dep_ids
st$name_idf <- name_idf(st$recip_name)
st$ntok <- lengths(strsplit(trimws(gsub("[^A-Za-z ]", " ", st$recip_name)), " +"))

hr(); say("1. TOTAL TOKEN IDF: FLOOR-DEPENDENT vs THE REST OF THE YES TIER"); hr()
a <- st$name_idf[dep]
b <- st$name_idf[st$status == "YES" & !dep]
say("floor-dependent YES (n=%d): median %.1f | 10th pct %.1f | min %.1f",
    length(a), stats::median(a), stats::quantile(a, .1), min(a))
say("other YES         (n=%d): median %.1f | 10th pct %.1f | min %.1f",
    length(b), stats::median(b), stats::quantile(b, .1), min(b))

hr(); say("2. WHERE DO THE HAND-CHECKED ERRORS SIT?"); hr()
watch <- c("COMMUNITY CHURCH", "CONGREGATION AGUDATH ISRAEL", "RESOURCED INC",
           "NOAHS ARK ANIMAL RESCUE INC", "NORTHERN WESTCHESTER HOSPITAL ASS",
           "KOINONIA ACADEMY", "GEORGIA FOREST WATCH", "ATHOL MEMORIAL HOSPITAL",
           "FRACTURED ATLAS INC", "YAFFED", "TIDES CENTER", "GIVEMN",
           "CASA OF CENTRAL TEXAS", "FURNITURE SHAREHOUSE")
verdict <- c("WRONG", "WRONG", "doubtful", "doubtful", "doubtful",
             rep("correct", 9))
i <- match(watch, st$recip_name)
d <- data.table(name = watch, verdict = verdict,
                idf = round(st$name_idf[i], 1), ntok = st$ntok[i],
                bmf = substr(st$bmf_name[i], 1, 30))
setorder(d, idf)
print(d, row.names = FALSE)

hr(); say("3. WHAT WOULD AN IDF GATE COST AND BUY?"); hr()
say("%-10s %10s %12s %14s", "min IDF", "kept", "demoted", "of the 2 known-wrong")
for (thr in c(0, 10, 15, 20, 25, 30)) {
  keep <- dep & st$name_idf >= thr
  wrong_caught <- sum(st$name_idf[i[verdict == "WRONG"]] < thr)
  say("%-10.0f %10d %12d %14s", thr, sum(keep), sum(dep) - sum(keep),
      sprintf("%d of 2", wrong_caught))
}

hr(); say("4. IS name_freq DOING ANY WORK AT ALL?"); hr()
say("correlation between name_freq and total token IDF, over promoted pairs:")
pr <- as.data.table(attr(readRDS(file.path(PF, "data-dev", "PF-MATCH-RESULT-1k.rds"))$result, "pairs"))
sel <- pr[paste(.id, .ein) %in% paste(st$grant_id[dep], st$ein[dep])]
sel[, nidf := name_idf(name_raw_x)]
say("  name_freq = 1: median IDF %.1f (n=%d)",
    stats::median(sel$nidf[as.numeric(sel$name_freq) == 1]), sum(as.numeric(sel$name_freq) == 1))
say("  name_freq = 2: median IDF %.1f (n=%d)",
    stats::median(sel$nidf[as.numeric(sel$name_freq) == 2]), sum(as.numeric(sel$name_freq) == 2))
say("\n(if they were measuring the same thing these would differ sharply)")
