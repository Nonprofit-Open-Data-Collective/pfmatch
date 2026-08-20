#!/usr/bin/env Rscript
# Two diagnostics the first pass needs before its numbers mean anything.
#
# (1) Is the observed funder concentration above CHANCE? A funder drawing k
#     grants at random from the population NTEE distribution has an expected
#     top-group share well above the population base rate when k is small.
#     Comparing observed 0.333 to a base rate of 0.145 is not a comparison.
# (2) Is the zero year-over-year persistence real, or forced by the sample
#     carrying ~1 grant per funder per year?
suppressWarnings(suppressMessages(library(data.table)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
BMF <- file.path(PF, "..", "npmatch", "data-raw", "bmf_2026_01_processed.csv")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 78), "\n")
e9  <- function(x) { x <- gsub("[^0-9]", "", as.character(x))
                     ifelse(nchar(x) == 9L, x, NA_character_) }
set.seed(42)

m   <- readRDS(file.path(PF, "data-dev", "PF-MATCH-RESULT-50k.rds"))
cfg <- npmatch::np_config()
pr0 <- npmatch::np_veto(npmatch::np_score(attr(m$result, "pairs"), cfg, method = "hier"), cfg)
res <- npmatch::np_tier(npmatch::np_select(pr0, cfg), cfg)
x <- m; x$result <- res; attr(x$result, "pairs") <- pr0; attr(x$result, "config") <- cfg
st <- as.data.table(pf_status(x))
g  <- as.data.table(m$grants)
st[, taxyear := g$TAXYEAR[match(grant_id, g$grant_id)]]

b <- fread(BMF, colClasses = "character", showProgress = FALSE,
           select = c("ein", "ntee_code_clean"))
b[, ein := e9(ein)]
b[, L2 := toupper(substr(ntee_code_clean, 1, 1))]
b[is.na(ntee_code_clean) | !nzchar(ntee_code_clean) |
  toupper(ntee_code_clean) %in% c("INVALID", "UNDEFINED", "Z99"), L2 := NA_character_]
setkey(b, ein)

yes <- st[status == "YES" & !is.na(ein)]
yes[, `:=`(f = e9(filer_ein), r = e9(ein))]
yes <- yes[!is.na(f) & !is.na(r)]
yes[, L2 := b$L2[match(r, b$ein)]]
yes <- yes[!is.na(L2)]
pop <- table(yes$L2) / nrow(yes)

## ---- (1) observed concentration vs a null of random draws ------------------
obs <- yes[, .(n = .N, top = max(table(L2)) / .N,
               H = { t <- table(L2); p <- as.numeric(t) / sum(t)
                     if (length(p) <= 1) 0 else -sum(p * log(p)) / log(length(p)) }), by = f]

sim_top <- function(k, reps = 4000) {
  d <- replicate(reps, {
    v <- sample(names(pop), k, replace = TRUE, prob = pop)
    max(table(v)) / k })
  d
}
hr(); say("(1) IS FUNDER CONCENTRATION ABOVE CHANCE?"); hr()
say("Null: the funder draws k grantees at random from the population NTEE")
say("major-group distribution. Comparing observed top-group share to that,")
say("not to the population base rate of %.3f.", max(pop))
say("")
say("%-10s %8s %11s %11s %11s %9s", "k grants", "funders", "obs median", "null median",
    "null p95", "above?")
for (k in c(3, 5, 7, 10, 15, 20)) {
  s <- obs[n == k]
  if (nrow(s) < 5) { s <- obs[n >= k & n <= k + 2]; if (nrow(s) < 5) next }
  nl <- sim_top(k)
  say("%-10d %8d %11.3f %11.3f %11.3f %9s", k, nrow(s), median(s$top),
      median(nl), quantile(nl, 0.95),
      if (median(s$top) > quantile(nl, 0.95)) "YES" else "no")
}
say("")
say("Share of funders whose observed top-share exceeds the null 95th percentile")
say("for their own portfolio size -- i.e. genuinely concentrated funders:")
for (k in c(5, 10)) {
  s <- obs[n >= k]
  if (!nrow(s)) next
  thr <- vapply(s$n, function(kk) quantile(sim_top(min(kk, 60), 800), 0.95), numeric(1))
  say("  portfolios of >= %2d grants : %d of %d (%.0f%%)", k,
      sum(s$top > thr), nrow(s), 100 * mean(s$top > thr))
}

## ---- (2) is zero persistence real or forced? -------------------------------
hr(); say("(2) IS THE ZERO YEAR-OVER-YEAR OVERLAP REAL?"); hr()
py <- yes[, .(n = .N), by = .(f, taxyear)]
multi <- py[, .(n_yr = .N, med_per_yr = median(n), tot = sum(n)), by = f][n_yr >= 2]
say("funders with grants in >= 2 tax years        : %s", format(nrow(multi), big.mark = ","))
say("  median grants per funder-year              : %.0f", median(multi$med_per_yr))
say("  funder-years holding exactly ONE grant     : %.0f%%", 100 * mean(py$n == 1))
say("")
say("A funder-year with one grant can only overlap the next year if that single")
say("grantee repeats. Zero Jaccard is close to arithmetically forced here.")
say("")
pairs_ok <- multi[med_per_yr >= 3]
say("funders with >= 3 grants in a typical year   : %s", format(nrow(pairs_ok), big.mark = ","))
if (nrow(pairs_ok) >= 5) {
  s <- yes[f %in% pairs_ok$f]
  pj <- s[, {
    yr <- sort(unique(taxyear))
    ov <- vapply(seq_len(length(yr) - 1L), function(k) {
      a <- unique(r[taxyear == yr[k]]); bb <- unique(r[taxyear == yr[k + 1]])
      if (!length(a) || !length(bb)) NA_real_ else
        length(intersect(a, bb)) / length(union(a, bb))
    }, numeric(1))
    list(j = mean(ov, na.rm = TRUE))
  }, by = f]
  pj <- pj[!is.na(j) & !is.nan(j)]
  say("  median Jaccard among those               : %.3f  (n = %d)", median(pj$j), nrow(pj))
  say("  share with ANY repeat grantee            : %.0f%%", 100 * mean(pj$j > 0))
} else say("  too few to measure.")
say("")
say("Whatever this says, it is a statement about the SAMPLE. A real filer files")
say("its whole Part XIV table each year; the dev file keeps a random handful.")
