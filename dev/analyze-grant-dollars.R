#!/usr/bin/env Rscript
# ============================================================================
# Grant size by match outcome, and the adjudication budget question:
# how many MAYBE / NO cases must be reviewed to cover 70% of grant dollars?
#
# Dollars are extremely skewed, so the answer to "how many cases" depends
# entirely on sorting large-to-small. Both framings are reported:
#   (a) 70% of the UNRESOLVED dollars (MAYBE + NO only)
#   (b) 70% of ALL grant dollars, given YES already covers some of it
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
SET <- Sys.getenv("PF_SET", "50k")
PAT <- switch(SET, "1k" = "^1k_grants_.*\\.csv$", "50k" = "^50k_grants\\.csv$",
              "100k" = "^100k_grants\\.csv$", stop("bad PF_SET"))
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 78), "\n")
usd <- function(x) paste0("$", formatC(x, format = "f", digits = 0, big.mark = ","))

# ---- outcome + amount, joined by grant_id ----------------------------------
m  <- readRDS(file.path(PF, "data-dev", sprintf("PF-MATCH-RESULT-%s.rds", SET)))
st <- as.data.table(pf_status(m))
g  <- as.data.table(m$grants)
st[, amount := suppressWarnings(as.numeric(g$SIGOCPYAMOUN[match(grant_id, g$grant_id)]))]

say("set %s: %s grants", SET, format(nrow(st), big.mark = ","))
say("amount missing or non-numeric : %s", format(sum(is.na(st$amount)), big.mark = ","))
say("amount == 0                   : %s", format(sum(st$amount %in% 0), big.mark = ","))
say("amount < 0                    : %s", format(sum(st$amount < 0, na.rm = TRUE), big.mark = ","))
d <- st[!is.na(amount) & amount > 0]
say("usable for the dollar analysis: %s (%.1f%% of rows, %s total)",
    format(nrow(d), big.mark = ","), 100 * nrow(d) / nrow(st), usd(sum(d$amount)))

hr(); say("1. GRANT SIZE BY OUTCOME"); hr()
qs <- c(.05, .25, .50, .75, .95)
tab <- d[, .(n = .N,
             p05 = quantile(amount, .05), p25 = quantile(amount, .25),
             p50 = quantile(amount, .50), p75 = quantile(amount, .75),
             p95 = quantile(amount, .95),
             mean = mean(amount), total = sum(amount)),
         by = .(status = factor(status, pf_status_levels()))]
setorder(tab, status)
allr <- d[, .(status = factor("ALL", levels = c(pf_status_levels(), "ALL")), n = .N,
              p05 = quantile(amount, .05), p25 = quantile(amount, .25),
              p50 = quantile(amount, .50), p75 = quantile(amount, .75),
              p95 = quantile(amount, .95), mean = mean(amount), total = sum(amount))]
tab <- rbind(tab, allr, fill = TRUE)
say("%-7s %8s %10s %10s %10s %10s %12s %12s", "status", "n", "p05", "p25", "p50", "p75", "p95", "mean")
for (i in seq_len(nrow(tab))) with(tab[i], say("%-7s %8s %10s %10s %10s %10s %12s %12s",
    as.character(status), format(n, big.mark = ","), usd(p05), usd(p25), usd(p50),
    usd(p75), usd(p95), usd(mean)))

say("\nshare of all grant dollars by outcome:")
for (i in seq_len(nrow(tab) - 1L)) with(tab[i], say("  %-6s %14s  (%5.1f%% of dollars, %5.1f%% of cases)",
    as.character(status), usd(total), 100 * total / allr$total, 100 * n / allr$n))

hr(); say("2. ADJUDICATION BUDGET"); hr()
budget <- function(sub, target_dollars, label) {
  s <- sort(sub$amount, decreasing = TRUE)
  cs <- cumsum(s)
  k <- which(cs >= target_dollars)[1]
  if (is.na(k)) {
    say("  %-34s cannot reach it (pool holds only %s)", label, usd(sum(s)))
    return(invisible(NULL))
  }
  say("  %-34s %6s of %6s cases (%4.1f%%)  threshold %s",
      label, format(k, big.mark = ","), format(length(s), big.mark = ","),
      100 * k / length(s), usd(s[k]))
}

say("(a) 70%% of the UNRESOLVED dollars, reviewing that tier alone")
for (tier in c("MAYBE", "NO")) {
  sub <- d[status == tier]
  budget(sub, 0.70 * sum(sub$amount), sprintf("within %s (%s total)", tier, usd(sum(sub$amount))))
}
un <- d[status %in% c("MAYBE", "NO")]
budget(un, 0.70 * sum(un$amount), sprintf("MAYBE+NO pooled (%s)", usd(sum(un$amount))))

say("\n(b) 70%% of ALL grant dollars, counting what YES already covers")
yes_usd <- d[status == "YES", sum(amount)]
tot <- sum(d$amount)
say("  YES already covers %s = %.1f%% of all dollars", usd(yes_usd), 100 * yes_usd / tot)
gap <- 0.70 * tot - yes_usd
if (gap <= 0) {
  say("  ... which is already past 70%%. No adjudication needed to hit the target.")
  say("  Surplus above the 70%% line: %s", usd(-gap))
} else {
  budget(un, gap, sprintf("extra MAYBE+NO needed (%s gap)", usd(gap)))
}

hr(); say("3. THE CURVE -- cases reviewed vs dollars covered (MAYBE+NO, large first)"); hr()
s <- sort(un$amount, decreasing = TRUE); cs <- cumsum(s) / sum(s)
say("%10s %12s %14s", "cases", "% of cases", "% of unresolved $")
for (p in c(0.01, 0.02, 0.05, 0.10, 0.20, 0.30, 0.50)) {
  k <- ceiling(p * length(s))
  say("%10s %11.0f%% %13.1f%%", format(k, big.mark = ","), 100 * p, 100 * cs[k])
}
for (tgt in c(0.50, 0.70, 0.80, 0.90, 0.95)) {
  k <- which(cs >= tgt)[1]
  say("  reach %2.0f%% of unresolved dollars -> review %s cases (%.1f%%)",
      100 * tgt, format(k, big.mark = ","), 100 * k / length(s))
}
