#!/usr/bin/env Rscript
# The dollar distribution is extreme enough that the adjudication answer depends
# on a few hundred rows. Are those rows real grants, or artifacts?
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
SET <- Sys.getenv("PF_SET", "50k")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 78), "\n")
usd <- function(x) paste0("$", formatC(x, format = "f", digits = 0, big.mark = ","))

m  <- readRDS(file.path(PF, "data-dev", sprintf("PF-MATCH-RESULT-%s.rds", SET)))
st <- as.data.table(pf_status(m))
g  <- as.data.table(m$grants)
i  <- match(st$grant_id, g$grant_id)
st[, amount := suppressWarnings(as.numeric(g$SIGOCPYAMOUN[i]))]
st[, purpose := g$SIGOCPYPOGOC[i]]
st[, oos_why := g$oos_reason[i]]
d <- st[!is.na(amount) & amount > 0]

hr(); say("1. THE OOS BUCKET HOLDS 12.8%% OF DOLLARS -- what is in it?"); hr()
o <- d[status == "OOS"]
say("OOS with a positive amount: %d of %d OOS rows | total %s",
    nrow(o), sum(st$status == "OOS"), usd(sum(o$amount)))
print(o[, .(n = .N, total = usd(sum(amount)), median = usd(median(amount)),
            max = usd(max(amount))), by = oos_why], row.names = FALSE)
say("\nlargest OOS grants:")
print(head(o[order(-amount), .(amount = usd(amount), recip = substr(recip_name, 1, 34),
                               state = recip_state, why = oos_why,
                               purpose = substr(purpose, 1, 30))], 12), row.names = FALSE)

hr(); say("2. THE LARGEST UNRESOLVED GRANTS -- real, or artifacts?"); hr()
un <- d[status %in% c("MAYBE", "NO")]
say("MAYBE+NO with a positive amount: %s | total %s",
    format(nrow(un), big.mark = ","), usd(sum(un$amount)))
print(head(un[order(-amount), .(amount = usd(amount), status,
                                recip = substr(recip_name, 1, 32),
                                city = substr(recip_city, 1, 14), st = recip_state,
                                purpose = substr(purpose, 1, 26))], 20), row.names = FALSE)

hr(); say("3. IS THE TAIL A HANDFUL OF FILERS?"); hr()
top <- un[order(-amount)][1:489]
say("the 489 cases that carry 70%% of unresolved dollars come from %d distinct foundations",
    uniqueN(top$filer_ein))
say("top filers among them:")
print(head(top[, .(cases = .N, dollars = usd(sum(amount))), by = .(filer = substr(filer_name, 1, 40))][order(-cases)], 10),
      row.names = FALSE)

hr(); say("4. DUPLICATE-LOOKING ROWS IN THE TAIL"); hr()
dup <- top[, .N, by = .(filer_ein, recip_name, amount)][N > 1]
say("exact (filer, recipient, amount) repeats within the top 489: %d groups, %d rows",
    nrow(dup), sum(dup$N))
if (nrow(dup)) print(head(dup[order(-N)], 8), row.names = FALSE)
