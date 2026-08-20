#!/usr/bin/env Rscript
# The decisive test: apply the candidate gates to the 121 pairs the promotion
# floor actually promotes, and see what moves. Population statistics on a
# synthetic test set are not the same as behaviour on the live tier.
suppressWarnings(suppressMessages(library(data.table)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
NPM <- Sys.getenv("NPMATCH_DIR", "../npmatch")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 74), "\n")

p  <- readRDS(file.path(PF, "data-dev", "PROMOTION-PROBE.rds"))
m  <- readRDS(file.path(PF, "data-dev", "PF-MATCH-RESULT-1k.rds"))
st <- p$on
dep <- st$grant_id %in% p$dep_ids
pr <- as.data.table(attr(m$result, "pairs"))
sel <- pr[paste(.id, .ein) %in% paste(st$grant_id[dep], st$ein[dep])]
sel <- sel[!duplicated(paste(.id, .ein))]
say("floor-dependent pairs recovered: %d", nrow(sel))

idf <- readRDS(file.path(PF, "data-dev", "BMF-REFERENCE-BUNDLE.rds"))$token_idf
sw  <- npmatch::np_stopwords(); mx <- max(idf, na.rm = TRUE)
w1  <- function(t) { v <- idf[t]; v[is.na(v)] <- mx; v }
tk  <- function(x) strsplit(ifelse(is.na(x), "", toupper(x)), " ", fixed = TRUE)
ta <- tk(sel$name_key_x); tb <- tk(sel$name_key_y)

sel[, idf_disagree := mapply(function(x, y) {
  x <- unique(x[nzchar(x) & !(x %in% sw)]); y <- unique(y[nzchar(y) & !(y %in% sw)])
  d <- c(setdiff(x, y), setdiff(y, x)); if (!length(d)) return(0); sum(w1(d))
}, ta, tb)]
sel[, idf_agree := mapply(function(x, y) {
  x <- unique(x[nzchar(x) & !(x %in% sw)]); y <- unique(y[nzchar(y) & !(y %in% sw)])
  if (!length(x) || !length(y)) return(1)
  s <- intersect(x, y); a <- union(x, y)
  if (!length(a)) return(1); sum(w1(s)) / sum(w1(a))
}, ta, tb)]

j <- match(paste(sel$.id, sel$.ein), paste(st$grant_id, st$ein))
sel[, qname := st$recip_name[j]][, bname := st$bmf_name[j]]

known_wrong <- c("CONGREGATION AGUDATH ISRAEL", "COMMUNITY CHURCH",
                 "CHRIST CHURCH", "HOUSE OF HOPE", "1")
known_right <- c("KOINONIA ACADEMY", "ATHOL MEMORIAL HOSPITAL", "FRACTURED ATLAS INC",
                 "GIVEMN", "YAFFED", "TIDES CENTER", "CASA OF CENTRAL TEXAS",
                 "FURNITURE SHAREHOUSE", "GEORGIA FOREST WATCH", "SIX FEET OVER",
                 "CROSSNORE COMMUNITIES FOR CHILDRE", "ENVIRONMENT AND HUMAN HEALTH INC")

hr(); say("GATE BEHAVIOUR ON THE LIVE PROMOTED SET (n = %d)", nrow(sel)); hr()
say("%-26s %8s %14s %14s", "rule", "demoted", "known-wrong", "known-right")
test <- function(lbl, keep) {
  d <- !keep
  kw <- sum(d & sel$qname %in% known_wrong)
  kr <- sum(d & sel$qname %in% known_right)
  say("%-26s %7d  %6d of %-4d %6d of %-4d", lbl, sum(d),
      kw, sum(sel$qname %in% known_wrong), kr, sum(sel$qname %in% known_right))
}
for (t in c(20, 15, 12)) test(sprintf("idf_disagree <= %d", t), sel$idf_disagree <= t)
for (t in c(0.40, 0.50, 0.60)) test(sprintf("idf_agree >= %.2f", t), sel$idf_agree >= t)

hr(); say("WHERE DO THE LABELLED CASES SIT?"); hr()
lab <- sel[qname %in% c(known_wrong, known_right)]
lab[, verdict := ifelse(qname %in% known_wrong, "WRONG", "right")]
setorder(lab, -idf_disagree)
print(lab[, .(qname = substr(qname, 1, 30), bname = substr(bname, 1, 30),
              verdict, idf_disagree = round(idf_disagree, 1),
              idf_agree = round(idf_agree, 2))], row.names = FALSE)
