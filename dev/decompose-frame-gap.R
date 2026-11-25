## Why does the production frame clear 17 points below the 1k benchmark?
##
## §3a of dev/PERFORMANCE-REPORT-20261106.md asserts the gap and attributes it to
## the frame being "deliberately enriched for the hardest thing the matcher does"
## -- address groups carrying two or more distinct recipient names. That is
## directionally right and was never decomposed. This splits it.
##
## Run from the repository root:  Rscript dev/decompose-frame-gap.R
##
## Both frames were matched against the same reference (REF-augmented.rds), so
## the comparison is not confounded by that. It IS confounded by corpus: these
## are two different draws (596,539 grant rows against 4,903), not one corpus
## split two ways. See the limit recorded at the end.

if (!file.exists("DESCRIPTION"))
  stop("run this from the repository root", call. = FALSE)

suppressMessages(library(data.table))
if (requireNamespace("pkgload", quietly = TRUE)) pkgload::load_all(".", quiet = TRUE)
say <- function(...) cat(sprintf(...), "\n", sep = "")

tri <- readRDS("data-dev/TRI-V2-MATCH.rds")
s <- as.data.table(tri$status); rm(tri); invisible(gc())
b <- as.data.table(readRDS("dev/BASELINE-2026-10C/benchmark-1k-augmented.rds"))
say("production frame  %s identities", format(nrow(s), big.mark = ","))
say("1k benchmark      %s identities (augmented arm)", format(nrow(b), big.mark = ","))
stopifnot(nrow(s) == 91008L, nrow(b) == 4748L)

## `n_close` is the count of candidates inside the close band; NA means nothing
## was retrieved at all, which is a different failure and is kept separate.
band <- function(x) {
  y <- cut(x, c(-Inf, 1, 2, 5, 10, Inf), labels = c("1", "2", "3-5", "6-10", "11+"))
  ifelse(is.na(y), "none", as.character(y))
}
s[, `:=`(cb = band(n_close), yes = status == "YES")]
b[, `:=`(cb = band(n_close), yes = tier   == "YES")]

## -- 1. which tier absorbs the gap? ---------------------------------------
cat("\n== tier shares ==\n")
ts <- merge(
  s[, .(prod_pct = round(100 * .N / nrow(s), 2)), by = .(tier = status)],
  b[, .(bench_pct = round(100 * .N / nrow(b), 2)), by = tier], by = "tier")
ts[, gap_pt := round(prod_pct - bench_pct, 2)]
print(ts[order(-prod_pct)])
say("")
say("The YES deficit reappears as NO, not as MAYBE. If the frame merely offered")
say("too many plausible candidates to choose between, MAYBE would absorb it.")

## -- 2. direct standardization on candidate crowding ----------------------
d <- merge(s[, .(p_n = .N, p_rate = mean(yes)), by = cb],
           b[, .(b_n = .N, b_rate = mean(yes)), by = cb], by = "cb", all = TRUE)
for (j in c("p_n", "b_n")) d[is.na(get(j)), (j) := 0L]
for (j in c("p_rate", "b_rate")) d[is.na(get(j)), (j) := 0]
d[, `:=`(p_w = p_n / sum(p_n), b_w = b_n / sum(b_n))]
setorder(d, cb)

cat("\n== clear rate by candidate crowding ==\n")
print(d[, .(n_close = cb,
            prod_n = p_n, prod_share = round(100 * p_w, 1),
            prod_clear = round(100 * p_rate, 1),
            bench_n = b_n, bench_share = round(100 * b_w, 1),
            bench_clear = round(100 * b_rate, 1))])

obs_p <- d[, sum(p_w * p_rate)]; obs_b <- d[, sum(b_w * b_rate)]
std_p <- d[, sum(b_w * p_rate)]          # production rates, benchmark mix
gap   <- obs_b - obs_p
cat("\n== decomposition ==\n")
say("production, as is                              %6.2f%%", 100 * obs_p)
say("benchmark, as is                               %6.2f%%", 100 * obs_b)
say("total gap                                      %6.2f pt", 100 * gap)
say("production rates on the BENCHMARK crowding mix %6.2f%%", 100 * std_p)
say("  crowding composition                         %6.2f pt (%.0f%%)",
    100 * (std_p - obs_p), 100 * (std_p - obs_p) / gap)
say("  clears worse within a stratum                %6.2f pt (%.0f%%)",
    100 * (obs_b - std_p), 100 * (obs_b - std_p) / gap)

say("")
say("A SECOND close candidate is fatal in BOTH frames: %.1f%% / %.1f%% clear at",
    100 * d[cb == "2", p_rate], 100 * d[cb == "2", b_rate])
say("n_close == 2 against %.1f%% / %.1f%% at n_close == 1, and 0.0%% above that.",
    100 * d[cb == "1", p_rate], 100 * d[cb == "1", b_rate])
say("That is the tie and margin policy acting as a veto, not a property of")
say("either population. %.1f%% of the production frame sits in that dead zone",
    100 * d[cb != "1", sum(p_w)])
say("against %.1f%% of the benchmark, which is where the composition points are.",
    100 * d[cb != "1", sum(b_w)])

## -- 3. the remaining two thirds: which blocking pass retrieved it? -------
cat("\n== blocking pass mix ==\n")
pm <- merge(s[, .(prod_pct = round(100 * .N / nrow(s), 1)), by = .(pass = match_pass)],
            b[, .(bench_pct = round(100 * .N / nrow(b), 1)), by = pass],
            by = "pass", all = TRUE)
print(pm[order(-prod_pct)])
say("")
say("A1-name-zip5 is the strongest key there is -- exact name plus ZIP5. The")
say("benchmark clears half its identities on it; the production frame under a")
say("third, leaning on token-level matching instead. That follows from how the")
say("frame is drawn: address groups carrying two or more DISTINCT recipient")
say("names select for names that do not render consistently, so the exact-name")
say("keys that carry the benchmark are the keys that fail here.")

## -- 4. the consequence: scores pile up under the cutoff ------------------
cat("\n== production, one close candidate and NOT cleared ==\n")
u <- s[cb == "1" & !yes]
say("identities: %s of the %s uncrowded (%.1f%%)", format(nrow(u), big.mark = ","),
    format(s[cb == "1", .N], big.mark = ","), 100 * nrow(u) / s[cb == "1", .N])
print(u[, .(identities = .N, pct = round(100 * .N / nrow(u), 1)), by = .(tier = status)])
cat("\nscore quantiles (cutoffs: YES 0.78, MAYBE 0.65):\n")
print(u[, .(q25 = round(quantile(score, .25, na.rm = TRUE), 3),
            median = round(median(score, na.rm = TRUE), 3),
            q75 = round(quantile(score, .75, na.rm = TRUE), 3))])
say("median name similarity %.3f, near-exact on only %.0f%%, state agrees on %.1f%%",
    median(u$name_sim, na.rm = TRUE), 100 * mean(u$name_sim >= 0.999, na.rm = TRUE),
    100 * mean(u$state_agree %in% TRUE))
ub <- b[cb == "1" & !yes]
say("")
say("the benchmark's uncrowded misses: %s identities, median score %.3f,",
    format(nrow(ub), big.mark = ","), median(ub$overall_score, na.rm = TRUE))
say("median name similarity %.3f -- the SAME shape. There are simply far fewer.",
    median(ub$overall_name_sim, na.rm = TRUE))

cat("\n== limit on this decomposition ==\n")
say("These are two different corpora, not one corpus split two ways, so the")
say("11-point within-stratum term mixes the n_names > 1 filter with whatever")
say("else differs between the draws. Separating them needs that filter applied")
say("to the benchmark population as a control, which has not been run.")
