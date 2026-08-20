#!/usr/bin/env Rscript
# ============================================================================
# Step 1 of SCALE-PLAN.md: how much does deduplication shrink the work?
#
# IMPORTANT sampling caveat. Collapse ratio measured on a sample is a LOWER
# BOUND on the full file: a 100k random sample is 0.8% of 12.5M rows, so two
# grants to the same recipient rarely both land in it. The ratio therefore grows
# with sample size, and a single-point measurement badly understates the full
# file. This script measures the accumulation curve at increasing n and
# extrapolates, rather than quoting one number.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
NPM <- Sys.getenv("NPMATCH_DIR", "../npmatch")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 74), "\n")

g <- pf_read_grants(file.path(PF, "inputs"), pattern = "^100k_grants\\.csv$")
g <- g[g$in_scope, , drop = FALSE]
say("in-scope grant rows: %s", format(nrow(g), big.mark = ","))

hr(); say("1. IDENTITY-KEY GUARD (must NOT merge an org with its foundation)"); hr()
probe <- data.frame(
  grant_id = as.character(1:8),
  recip_name = c("DENVER ART MUSEUM", "DENVER ART MUSEUM FOUNDATION",
                 "SIERRA CLUB", "SIERRA CLUB FOUNDATION",
                 "AMERICAN HEART ASSOCIATION", "AMERICAN HEART ASSOCIATION INC",
                 "UNIVERSITY OF MASSACHUSETTS AMHERST",
                 "UNIVERSITY OF MASSACHUSETTS AMHERST FOUNDATION"),
  recip_name_alt = NA, recip_street = "1 MAIN ST", recip_unit = NA,
  recip_city = "X", recip_state = "CO", recip_zip5 = "80204",
  stringsAsFactors = FALSE)
pd <- pf_dedup(probe, method = "fuzzy", verbose = FALSE)
for (i in 1:8) say("  uid %d  %s", pd$recipient_uid[i], pd$recip_name[i])
ok <- pd$recipient_uid[1] != pd$recipient_uid[2] &&
      pd$recipient_uid[3] != pd$recipient_uid[4] &&
      pd$recipient_uid[5] == pd$recipient_uid[6] &&
      pd$recipient_uid[7] != pd$recipient_uid[8]
say("  guard %s (org/foundation held apart; Inc variant merged)", if (ok) "PASS" else "FAIL")

hr(); say("2. ACCUMULATION CURVE"); hr()
set.seed(7)
ns <- c(2000, 5000, 10000, 25000, 50000, nrow(g))
curve <- rbindlist(lapply(ns, function(n) {
  s <- g[sample(nrow(g), n), , drop = FALSE]
  e <- pf_dedup(s, method = "exact", verbose = FALSE)
  f <- pf_dedup(s, method = "fuzzy", verbose = FALSE)
  data.table(n = n,
             exact = n / length(unique(e$recipient_uid)),
             fuzzy = n / length(unique(f$recipient_uid)))
}))
print(curve[, .(n, exact = round(exact, 3), fuzzy = round(fuzzy, 3))], row.names = FALSE)

# Distinct identities K(n) follow a saturating curve. Fit log K = a + b log n on
# the observed range and extrapolate; b < 1 means duplicates keep accumulating.
fitk <- function(col) {
  K <- curve$n / curve[[col]]
  m <- stats::lm(log(K) ~ log(curve$n))
  b <- unname(coef(m)[2])
  Kfull <- exp(unname(coef(m)[1]) + b * log(12.5e6))
  list(b = b, K = Kfull, ratio = 12.5e6 / Kfull)
}
fe <- fitk("exact"); ff <- fitk("fuzzy")
say("\nlog-log fit of distinct identities K(n):")
say("  exact  slope %.3f -> K(12.5M) ~ %s  (collapse %.2fx)",
    fe$b, format(round(fe$K), big.mark = ","), fe$ratio)
say("  fuzzy  slope %.3f -> K(12.5M) ~ %s  (collapse %.2fx)",
    ff$b, format(round(ff$K), big.mark = ","), ff$ratio)
say("  (slope < 1 means the collapse ratio keeps rising with file size)")
say("  EXTRAPOLATION WARNING: this reaches 125x beyond the measured range.")
say("  Treat as an order-of-magnitude estimate; confirm on a real full-file pass.")

hr(); say("3. RUNTIME PROJECTION (state-free cascade, 61.4 s / 1,000)"); hr()
rate <- 61.4
for (nm in c("no dedup", "exact (measured 100k)", "exact (extrapolated)",
             "fuzzy (measured 100k)", "fuzzy (extrapolated)")) {
  r <- switch(nm,
    "no dedup" = 1,
    "exact (measured 100k)" = curve$exact[nrow(curve)],
    "exact (extrapolated)"  = fe$ratio,
    "fuzzy (measured 100k)" = curve$fuzzy[nrow(curve)],
    "fuzzy (extrapolated)"  = ff$ratio)
  n <- 12.5e6 / r
  say("  %-24s %10s identities  %6.0f h", nm, format(round(n), big.mark = ","),
      n / 1000 * rate / 3600)
}

hr(); say("4. LARGEST CLUSTERS AFTER THE GUARD"); hr()
gf <- pf_dedup(g, method = "fuzzy", verbose = FALSE)
pf_dedup_report(gf, n = 10)
saveRDS(gf, file.path(PF, "data-dev", "DEDUP-100K.rds"), compress = FALSE)
