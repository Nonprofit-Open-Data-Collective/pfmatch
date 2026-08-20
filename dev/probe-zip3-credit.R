#!/usr/bin/env Rscript
# ZIP3 is weighted 0.55 -- above city (0.50) and 2.75x state (0.20) -- for
# sharing a 3-digit prefix. In a dense metro that prefix covers an enormous area.
# How much of the YES tier rests on it, and how discriminating is it?
suppressWarnings(suppressMessages(library(data.table)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
NPM <- Sys.getenv("NPMATCH_DIR", "../npmatch")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 74), "\n")

hr(); say("1. HOW BIG IS A ZIP3?"); hr()
ref <- readRDS(file.path(PF, "data-dev", "BMF-REFERENCE-BUNDLE.rds"))$reference
z3 <- ref$zip3[!is.na(ref$zip3) & nzchar(ref$zip3)]
z5 <- ref$zip5[!is.na(ref$zip5) & nzchar(ref$zip5)]
t3 <- table(z3); t5 <- table(z5)
say("BMF orgs per ZIP3: median %s | 90th pct %s | max %s (%s)",
    format(stats::median(t3), big.mark = ","),
    format(round(stats::quantile(t3, .9)), big.mark = ","),
    format(max(t3), big.mark = ","), names(which.max(t3)))
say("BMF orgs per ZIP5: median %s | 90th pct %s | max %s",
    format(stats::median(t5), big.mark = ","),
    format(round(stats::quantile(t5, .9)), big.mark = ","),
    format(max(t5), big.mark = ","))
say("\nso a ZIP3 'match' narrows the field ~%.0fx less than a ZIP5 match",
    as.numeric(stats::median(t3)) / as.numeric(stats::median(t5)))
say("and it is weighted 0.55 vs ZIP5's 0.90 -- 61%% of the credit for %.0fx the area",
    as.numeric(stats::median(t3)) / as.numeric(stats::median(t5)))

hr(); say("2. HOW MANY MATCHES REST ON ZIP3 AS THEIR STRONGEST SIGNAL?"); hr()
m <- readRDS(file.path(PF, "data-dev", "PF-MATCH-RESULT-1k.rds"))
st <- pf_status(m)
pr <- as.data.table(attr(m$result, "pairs"))
sel <- pr[paste(.id, .ein) %in% paste(st$grant_id, st$ein)]
gw <- npmatch::np_default_geo_weights()
z <- function(v) { v <- as.numeric(v); v[is.na(v)] <- 0; v }
sel[, strongest := {
  terms <- cbind(zip9 = gw[["zip9"]] * z(geo_zip9), zip5 = gw[["zip5"]] * z(geo_zip5),
                 zip3 = gw[["zip3"]] * z(geo_zip3), state = gw[["state"]] * z(geo_state))
  colnames(terms)[max.col(terms, ties.method = "first")]
}]
sel[, best := do.call(pmax, list(gw[["zip9"]] * z(geo_zip9), gw[["zip5"]] * z(geo_zip5),
                                 gw[["zip3"]] * z(geo_zip3), gw[["state"]] * z(geo_state)))]
sel[best == 0, strongest := "none"]
j <- match(paste(sel$.id, sel$.ein), paste(st$grant_id, st$ein))
sel[, tier := as.character(st$status[j])]
say("strongest ZIP-family signal on the SELECTED pair, by outcome:")
print(table(strongest = sel$strongest, tier = sel$tier))

yes_z3 <- sel[tier == "YES" & strongest == "zip3"]
say("\nYES matches whose strongest geo evidence is ZIP3 only: %d (%.1f%% of YES)",
    nrow(yes_z3), 100 * nrow(yes_z3) / sum(sel$tier == "YES", na.rm = TRUE))
if (nrow(yes_z3)) {
  say("examples (query vs matched BMF record):")
  k <- match(yes_z3$.id, st$grant_id)
  d <- data.table(name = substr(st$recip_name[k], 1, 32), qz = st$recip_zip5[k],
                  bmf = substr(st$bmf_name[k], 1, 32), bz = st$bmf_zip5[k],
                  score = st$score[k])
  print(head(d[order(score)], 12), row.names = FALSE)
}
