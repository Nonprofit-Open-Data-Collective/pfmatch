#!/usr/bin/env Rscript
# Two qualifications on the adjudication estimate:
#  (1) some high-dollar "recipients" are pointers to an attachment, not names --
#      no amount of review resolves them to an EIN;
#  (2) the OOS bucket is 1.2% of cases but 12.8% of dollars, and one grant is
#      most of that.
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
SET <- Sys.getenv("PF_SET", "50k")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 78), "\n")
usd <- function(x) paste0("$", formatC(x, format = "f", digits = 0, big.mark = ","))

m  <- readRDS(file.path(PF, "data-dev", sprintf("PF-MATCH-RESULT-%s.rds", SET)))
st <- as.data.table(pf_status(m)); g <- as.data.table(m$grants)
i <- match(st$grant_id, g$grant_id)
st[, amount := suppressWarnings(as.numeric(g$SIGOCPYAMOUN[i]))]
d <- st[!is.na(amount) & amount > 0]

# a "recipient" that is really a pointer to an attachment, or a non-name
ph <- "SEE ATTACH|SEE SCHED|SEE PART|SEE STATEMENT|SEE LIST|ATTACHED LIST|^VARIOUS|^SEVERAL|^MISC|AVAILABLE UPON|SEE EXHIBIT|SCHEDULE ATTACHED|SEE ABOVE|NOT APPLICABLE|SEE FOOTNOTE"
d[, placeholder := grepl(ph, toupper(recip_name))]

hr(); say("1. PLACEHOLDER RECIPIENTS -- unresolvable by review"); hr()
say("all grants        : %s cases (%.2f%%), %s (%.1f%% of dollars)",
    format(sum(d$placeholder), big.mark = ","), 100 * mean(d$placeholder),
    usd(d[placeholder == TRUE, sum(amount)]),
    100 * d[placeholder == TRUE, sum(amount)] / sum(d$amount))
print(d[placeholder == TRUE, .(n = .N, dollars = usd(sum(amount)))
        , by = .(status = factor(status, pf_status_levels()))][order(status)], row.names = FALSE)

un <- d[status %in% c("MAYBE", "NO")]
top <- un[order(-amount)][1:489]
say("\nwithin the top 489 unresolved cases: %d placeholders (%.1f%%) worth %s (%.1f%% of that slice)",
    sum(top$placeholder), 100 * mean(top$placeholder),
    usd(top[placeholder == TRUE, sum(amount)]),
    100 * top[placeholder == TRUE, sum(amount)] / sum(top$amount))
say("examples:")
print(head(top[placeholder == TRUE, .(amount = usd(amount), status,
                                      recip = substr(recip_name, 1, 36))], 8), row.names = FALSE)

hr(); say("2. THE ADJUDICATION BUDGET, EXCLUDING PLACEHOLDERS"); hr()
adj <- un[placeholder == FALSE]
say("adjudicable unresolved cases: %s of %s | %s of %s",
    format(nrow(adj), big.mark = ","), format(nrow(un), big.mark = ","),
    usd(sum(adj$amount)), usd(sum(un$amount)))
s <- sort(adj$amount, decreasing = TRUE); cs <- cumsum(s) / sum(s)
for (tgt in c(0.50, 0.70, 0.80, 0.90)) {
  k <- which(cs >= tgt)[1]
  say("  %2.0f%% of adjudicable unresolved dollars -> %s cases (%.1f%%), threshold %s",
      100 * tgt, format(k, big.mark = ","), 100 * k / length(s), usd(s[k]))
}

hr(); say("3. THE OOS BUCKET IS SMALL BY COUNT AND LARGE BY DOLLARS"); hr()
o <- d[status == "OOS"]
tot <- sum(d$amount)
say("OOS: %d cases (%.2f%% of cases) but %s (%.1f%% of dollars)",
    nrow(o), 100 * nrow(o) / nrow(d), usd(sum(o$amount)), 100 * sum(o$amount) / tot)
big <- o[order(-amount)][1]
say("the single largest OOS grant is %s to %s -- %.1f%% of ALL grant dollars in this file",
    usd(big$amount), big$recip_name, 100 * big$amount / tot)
say("excluding it, OOS is %s = %.1f%% of dollars",
    usd(sum(o$amount) - big$amount), 100 * (sum(o$amount) - big$amount) / tot)
say("\nOOS is dropped as out-of-sample because these organizations have no BMF row.")
say("That is correct for EIN recovery, but a dollar-weighted analysis of this")
say("file cannot ignore 12.8%% of its dollars without saying so.")
