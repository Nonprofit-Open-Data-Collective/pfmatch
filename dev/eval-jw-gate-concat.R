#!/usr/bin/env Rscript
# Token-level disagreement separates the promotion errors cleanly, EXCEPT on
# de-spacing pairs (GEORGIA FOREST WATCH / GEORGIA FORESTWATCH) where the tokens
# differ but the characters do not. Make the token match concat-aware and re-test.
suppressWarnings(suppressMessages(library(data.table)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
NPM <- Sys.getenv("NPMATCH_DIR", "../npmatch")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 74), "\n")

idf <- readRDS(file.path(PF, "data-dev", "BMF-REFERENCE-BUNDLE.rds"))$token_idf
sw  <- npmatch::np_stopwords(); mx <- max(idf, na.rm = TRUE)
w1  <- function(t) { v <- idf[t]; v[is.na(v)] <- mx; v }

# Tokens unique to one side, after allowing a token to be matched by the
# concatenation of two ADJACENT tokens on the other side (FOREST + WATCH =
# FORESTWATCH) and by a near-identical spelling (JW >= 0.90 on tokens >= 5 chars,
# which covers MCDONNELL/MCDONELL without letting short tokens collapse).
disagree <- function(x, y) {
  x <- x[nzchar(x) & !(x %in% sw)]; y <- y[nzchar(y) & !(y %in% sw)]
  if (!length(x) || !length(y)) return(list(d = character(0), all = unique(c(x, y))))
  pair <- function(v) if (length(v) < 2L) character(0) else paste0(v[-length(v)], v[-1])
  xc <- c(x, pair(x)); yc <- c(y, pair(y))
  fuzzy_in <- function(t, pool) {
    if (t %in% pool) return(TRUE)
    if (nchar(t) < 5L) return(FALSE)
    p <- pool[nchar(pool) >= 5L]
    if (!length(p)) return(FALSE)
    any(1 - stringdist::stringdist(t, p, method = "jw", p = 0.1) >= 0.90)
  }
  dx <- x[!vapply(x, fuzzy_in, logical(1), pool = yc)]
  dy <- y[!vapply(y, fuzzy_in, logical(1), pool = xc)]
  list(d = unique(c(dx, dy)), all = unique(c(x, y)))
}

score_pair <- function(a, b) {
  ta <- strsplit(toupper(ifelse(is.na(a), "", a)), " ", fixed = TRUE)
  tb <- strsplit(toupper(ifelse(is.na(b), "", b)), " ", fixed = TRUE)
  vapply(seq_along(ta), function(i) {
    r <- disagree(ta[[i]], tb[[i]])
    if (!length(r$d)) 0 else sum(w1(r$d))
  }, numeric(1))
}

p  <- readRDS(file.path(PF, "data-dev", "PROMOTION-PROBE.rds"))
m  <- readRDS(file.path(PF, "data-dev", "PF-MATCH-RESULT-1k.rds"))
st <- p$on; dep <- st$grant_id %in% p$dep_ids
pr <- as.data.table(attr(m$result, "pairs"))
sel <- pr[paste(.id, .ein) %in% paste(st$grant_id[dep], st$ein[dep])]
sel <- sel[!duplicated(paste(.id, .ein))]
sel[, dis_plain := {
  ta <- strsplit(toupper(ifelse(is.na(name_x), "", name_x)), " ", fixed = TRUE)
  tb <- strsplit(toupper(ifelse(is.na(name_y), "", name_y)), " ", fixed = TRUE)
  mapply(function(x, y) { x <- x[nzchar(x) & !(x %in% sw)]; y <- y[nzchar(y) & !(y %in% sw)]
    d <- c(setdiff(x, y), setdiff(y, x)); if (!length(d)) 0 else sum(w1(d)) }, ta, tb)
}]
sel[, dis_concat := score_pair(name_x, name_y)]   # the versions that actually matched
j <- match(paste(sel$.id, sel$.ein), paste(st$grant_id, st$ein))
sel[, qname := st$recip_name[j]][, bname := st$bmf_name[j]]

known_wrong <- c("CONGREGATION AGUDATH ISRAEL", "COMMUNITY CHURCH",
                 "CHRIST CHURCH", "HOUSE OF HOPE", "1")
known_right <- c("KOINONIA ACADEMY", "ATHOL MEMORIAL HOSPITAL", "FRACTURED ATLAS INC",
                 "GIVEMN", "YAFFED", "TIDES CENTER", "CASA OF CENTRAL TEXAS",
                 "FURNITURE SHAREHOUSE", "GEORGIA FOREST WATCH", "SIX FEET OVER",
                 "CROSSNORE COMMUNITIES FOR CHILDRE", "ENVIRONMENT AND HUMAN HEALTH INC")

hr(); say("LABELLED CASES: plain vs concat-aware disagreement"); hr()
lab <- sel[qname %in% c(known_wrong, known_right)]
lab[, verdict := ifelse(qname %in% known_wrong, "WRONG", "right")]
setorder(lab, verdict, -dis_concat)
print(lab[, .(qname = substr(qname, 1, 30), bname = substr(bname, 1, 28), verdict,
              plain = round(dis_plain, 1), concat = round(dis_concat, 1))], row.names = FALSE)

hr(); say("GATE SWEEP OVER ALL %d PROMOTED PAIRS", nrow(sel)); hr()
say("%-30s %9s %14s %14s", "rule", "demoted", "known-wrong", "known-right")
for (t in c(20, 15, 12, 10, 8, 5)) {
  d <- sel$dis_concat > t
  say("%-30s %8d  %6d of %-4d %6d of %-4d", sprintf("dis_concat > %d -> demote", t),
      sum(d), sum(d & sel$qname %in% known_wrong), sum(sel$qname %in% known_wrong),
      sum(d & sel$qname %in% known_right), sum(sel$qname %in% known_right))
}
say("\nfor comparison, without concat-awareness:")
for (t in c(12, 10)) {
  d <- sel$dis_plain > t
  say("%-30s %8d  %6d of %-4d %6d of %-4d", sprintf("dis_plain > %d -> demote", t),
      sum(d), sum(d & sel$qname %in% known_wrong), sum(sel$qname %in% known_wrong),
      sum(d & sel$qname %in% known_right), sum(sel$qname %in% known_right))
}

hr(); say("EVERYTHING A dis_concat > 10 GATE WOULD DEMOTE"); hr()
d <- sel[dis_concat > 10]
setorder(d, -dis_concat)
print(d[, .(qname = substr(qname, 1, 34), bname = substr(bname, 1, 34),
            concat = round(dis_concat, 1))], row.names = FALSE)
