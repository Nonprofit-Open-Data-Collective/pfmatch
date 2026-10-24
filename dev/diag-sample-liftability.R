#!/usr/bin/env Rscript
# ============================================================================
# Can the ef1k evaluation sample be lifted onto the v2 deduplicated corpus
# without losing the hand adjudications attached to it?
#
# The sample is 5,000 grants drawn at random from the UNDEDUPED v1 corpus, and
# 177 rows of PF-TRUTH are keyed to it. Re-cutting a fresh random sample from
# the deduplicated corpus would orphan every one of those labels, so the first
# question is whether the existing rows can be located in the v2 build instead.
#
# The join has to be (OBJECTID, content), because the sample was shuffled and
# the within-filing row order -- which is what TABLE_ID counts -- is not
# recoverable from it. That join is ambiguous wherever one filing reports the
# same name, address and amount twice. This measures how often that happens.
#
# It is harmless when it does: rows with identical content are interchangeable
# both to the matcher, which sees only those fields, and to a truth label,
# which answers "what EIN is this recipient" -- the same question with the same
# answer. But the rate should be known rather than assumed.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("-", 78))

PF <- Sys.getenv("PFMATCH_DIR", ".")
sq <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; x }

f <- list.files(file.path(PF, "inputs"), pattern = "^ef1k_grants_.*\\.csv$",
                full.names = TRUE)
d <- rbindlist(lapply(f, fread, colClasses = "character", na.strings = NULL))
hr(); say("sample: %s rows from %d files", format(nrow(d), big.mark = ","), length(f))
say("filings: %s", format(uniqueN(d$OBJECTID), big.mark = ","))

## ---- how ambiguous is the (OBJECTID, content) key? -------------------------
CC <- c("SIGOCPYRPNAM", "SIGOCPYRBNBN1", "SIGOCPYRBNBN2", "SIGOCPYRFAAL1",
        "SIGOCPYRFAAL2", "SIGOCPYRFACI", "SIGOCPYRFAPO", "SIGOCPYRFAPC",
        "SIGOCAFFRFACO", "SIGOCPYAMOUN", "SIGOCPYPOGOC", "SIGOCPYRFSTA",
        "SIGOCPYRRELA")
CC <- intersect(CC, names(d))
d[, k := do.call(paste, c(lapply(CC, function(x) sq(d[[x]])), sep = "\r"))]
d[, k := paste(sq(OBJECTID), k, sep = "\r")]

n_dup <- sum(duplicated(d$k))
hr(); say("(OBJECTID, content) key")
say("  distinct keys        %s", format(uniqueN(d$k), big.mark = ","))
say("  rows sharing a key   %s  (%.2f%%)", format(n_dup, big.mark = ","),
    100 * n_dup / nrow(d))
if (n_dup) {
  tb <- d[, .N, by = k][N > 1L][order(-N)]
  say("  keys with n>1        %s   (max n = %d)", format(nrow(tb), big.mark = ","), max(tb$N))
  ex <- d[k == tb$k[1]][1:min(2, tb$N[1])]
  say("  example: OBJECTID %s | %s | %s | $%s", ex$OBJECTID[1],
      ex$SIGOCPYRBNBN1[1], ex$SIGOCPYRFACI[1], ex$SIGOCPYAMOUN[1])
}

## ---- do the truth labels sit on ambiguous keys? ----------------------------
tp <- file.path(PF, "data-dev", "PF-TRUTH.csv")
if (file.exists(tp)) {
  tr <- fread(tp, colClasses = "character")
  hr(); say("PF-TRUTH: %d labelled rows", nrow(tr))
  # the truth file keys on object_id + recip_name, which is what it recorded
  amb <- d[, .(n_rows = .N, n_keys = uniqueN(k)), by = OBJECTID]
  tr2 <- merge(tr, amb, by.x = "object_id", by.y = "OBJECTID", all.x = TRUE)
  say("  labels whose filing is in the sample   %d of %d",
      sum(!is.na(tr2$n_rows)), nrow(tr2))
  say("  labels on a filing with repeated content  %d",
      sum(!is.na(tr2$n_rows) & tr2$n_rows > tr2$n_keys))
  say("")
  say("  NOTE truth_id in this file is the OLD content hash (16 hex chars),")
  say("  not OBJECTID|TABLE_ID. build-truth.R was updated; PF-TRUTH.csv was")
  say("  not regenerated, so it must be rebuilt against the v2 population.")
  say("  sample truth_id: %s", tr$truth_id[1])
  say("  population id  : %s", tr$population[1])
}

## ---- year profile, which dedup will move -----------------------------------
hr(); say("sample by tax year (what dedup removes is not spread evenly)")
yt <- d[, .N, by = TAXYEAR][order(TAXYEAR)]
for (i in seq_len(nrow(yt)))
  say("  %-6s %5s  %5.1f%%", yt$TAXYEAR[i], format(yt$N[i], big.mark = ","),
      100 * yt$N[i] / nrow(d))
hr()
