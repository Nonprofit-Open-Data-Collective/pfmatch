#!/usr/bin/env Rscript
# ============================================================================
# How exposed is the "both references agree, so it is right" assumption?
#
# PLAYWORKS showed the failure mode. The filed grant is PLAYWORKS in Washington
# DC; both references chose a real but unrelated Newton MA org named exactly
# PLAYWORKS; and the correct org carries its own row named "PLAYWORKS
# WASHINGTON DC" in Washington DC. The name matched exactly, the place did not,
# and the place lost. That was found by accident.
#
# The YES->YES same-EIN cell is 2,564 identities -- 53% of the file -- and has
# never been sampled, on the implicit assumption that agreement between the two
# references meant correctness. The references are not independent (matchdb
# shares the BMF lineage and BOTH runs are scored by the same npmatch engine),
# so agreement is correlated error, not corroboration.
#
# This scans the whole cell for the same signature:
#
#   the CHOSEN ein has no reference row in the filed city, AND
#   some OTHER ein has a row with the SAME name_key that does
#
# A hit is not a proven error -- a filed city can be a branch, a lockbox or a
# development office. It bounds how much of the cell is exposed to this one
# specific failure.
#
# PERFORMANCE NOTE: the first version of this script did the two lookups inside
# `a[, ... , by = seq_len(nrow(a))]`, i.e. 2,564 keyed joins against a 3.9M-row
# table. It ran 90 minutes without finishing and was killed. It is now two
# vectorised merges. (How much of that 90 minutes was the pattern and how much
# was a 15-worker job competing for the machine was never established -- see
# dev/BENCHMARK-NOTES.md.) Note also that keyed i-joins of the form
# `ref[.(ein), ...]` resolve `ein` against the TABLE's own column first, which
# silently self-joins; merge() is used throughout to avoid that.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(library(npmatch)))
setDTthreads(0)
PF  <- Sys.getenv("PFMATCH_DIR", ".")
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("-", 88))
sq  <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; x }
e9  <- function(v) { v <- gsub("[^0-9]", "", as.character(v))
                     ifelse(nchar(v) == 9L, v, NA_character_) }
nkey <- function(x) {
  nm <- npmatch:::.np_basic_clean(sq(x))
  nm <- npmatch:::.np_replace_tokens(nm, npmatch:::.np_abbrev)
  npmatch:::.np_strip_lead_the(npmatch:::.np_strip_suffix(nm))
}
ncity <- function(x) gsub("[^A-Z]", "", toupper(sq(x)))

t0 <- proc.time()[["elapsed"]]
j <- fread(file.path(PF, "data-dev", "TWO-TIER-SIMULATION.csv"), colClasses = "character")
agree <- j[cell == "YES->YES  same EIN"]
say("agreement cell: %s identities", format(nrow(agree), big.mark = ","))

suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
g <- pf_read_grants(file.path(PF, "inputs"), pattern = "^ef1k_grants_")
g <- as.data.table(pf_prepare_grants(pf_recover_name_from_street(g)))
a <- merge(agree[, .(id, ein = e9(ein_a))],
           g[, .(id = grant_id, recip_name, recip_city, recip_state)], by = "id")
a <- a[!is.na(ein) & nzchar(sq(recip_name)) & nzchar(sq(recip_city))]
a[, nk := nkey(recip_name)][, qcity := ncity(recip_city)]
a <- a[nzchar(nk) & nzchar(qcity)]
say("usable (EIN + name + city): %s", format(nrow(a), big.mark = ","))

b <- fread(file.path(PF, "data-dev", "BMF-AUGMENTED-unified-fixed.csv"),
           colClasses = "character", showProgress = FALSE,
           select = c("ein", "org_name_join", "org_addr_city"))
b[, ein := e9(ein)]
b <- b[!is.na(ein) & nzchar(sq(org_name_join))]
b[, nk := nkey(org_name_join)][, rcity := ncity(org_addr_city)]
b <- b[nzchar(nk) & nzchar(rcity)]
say("reference rows usable: %s", format(nrow(b), big.mark = ","))

## ---- 1. does the CHOSEN ein have a row in the filed city? -------------------
ec <- unique(b[, .(ein, rcity)])
a[, chosen_ok := FALSE]
hit <- merge(a[, .(.row = .I, ein, qcity)], ec,
             by.x = c("ein", "qcity"), by.y = c("ein", "rcity"))
a$chosen_ok[hit$.row] <- TRUE
say("chosen EIN has a row in the filed city: %s (%.1f%%)",
    format(sum(a$chosen_ok), big.mark = ","), 100 * mean(a$chosen_ok))

## ---- 2. does some OTHER ein hold a name EXTENDING the filed one, there? ----
# The first version required nk == nk exactly, and a positive control on the
# PLAYWORKS case it was designed from showed that finds nothing: the rival row
# is "PLAYWORKS WASHINGTON DC", an EXTENSION of the filed "PLAYWORKS", not an
# equal. Exact-equality scanning therefore had zero sensitivity to the pattern
# and its 0-of-2,564 result was vacuous.
#
# Match on prefix instead. A reference name that extends the filed name must
# share its first token, so block on (city, first token) -- selective enough to
# keep the join small -- and apply the prefix test to the survivors.
tok1 <- function(x) sub(" .*$", "", x)
a[, t1 := tok1(nk)]
b[, t1 := tok1(nk)]
nc <- unique(b[, .(t1, rcity, nk, ein)])
riv <- merge(a[chosen_ok == FALSE, .(id, nk, t1, qcity, ein)], nc,
             by.x = c("t1", "qcity"), by.y = c("t1", "rcity"),
             allow.cartesian = TRUE, suffixes = c("", "_r"))
say("candidate rival rows after (city, first-token) blocking: %s",
    format(nrow(riv), big.mark = ","))
# a rival name must CONTAIN the filed name as a prefix (or vice versa), and the
# filed name must be long enough for that to mean anything
riv <- riv[ein_r != ein & nchar(nk) >= 5L &
           (startsWith(nk_r, nk) | startsWith(nk, nk_r))]
riv <- riv[, .(rival = ein_r[1], rival_name = nk_r[1],
               n_rival = uniqueN(ein_r)), by = .(id)]
a <- merge(a, riv, by = "id", all.x = TRUE)
a[, risk := !chosen_ok & !is.na(rival)]

hr()
say("THE PLAYWORKS SIGNATURE IN THE AGREEMENT CELL")
hr()
say("  chosen EIN has a row in the filed city        : %s (%.1f%%)",
    format(sum(a$chosen_ok), big.mark = ","), 100 * mean(a$chosen_ok))
say("  chosen EIN does not, no same-name rival there : %s (%.1f%%)",
    format(sum(!a$chosen_ok & is.na(a$rival)), big.mark = ","),
    100 * mean(!a$chosen_ok & is.na(a$rival)))
say("  chosen EIN does not, a RIVAL does      [RISK] : %s (%.1f%%)",
    format(sum(a$risk), big.mark = ","), 100 * mean(a$risk))
hr()

r <- a[risk == TRUE]
if (nrow(r)) {
  setorder(r, -n_rival, recip_name)
  say("worst cases (most rival EINs holding the filed name in the filed city):")
  say("  %-9s %-26s %-14s %-3s %-10s %-28s %s", "id", "filed name", "filed city",
      "st", "rival ein", "rival name", "#riv")
  for (i in seq_len(min(30L, nrow(r))))
    say("  %-9s %-26s %-14s %-3s %-10s %-28s %d", r$id[i],
        substr(r$recip_name[i], 1, 26), substr(r$recip_city[i], 1, 14),
        r$recip_state[i], r$rival[i], substr(sq(r$rival_name[i]), 1, 28),
        r$n_rival[i])
}

fwrite(a[, .(id, recip_name, recip_city, recip_state, ein, chosen_ok,
             rival, rival_name, n_rival, risk)],
       file.path(PF, "data-dev", "AGREEMENT-RISK-SCAN.csv"))
hr()
say("wrote data-dev/AGREEMENT-RISK-SCAN.csv  (%.0f s)", proc.time()[["elapsed"]] - t0)
say("")
say("A hit is not a proven error. It is a case where the name and the place")
say("point at different organisations and the pipeline followed the name, which")
say("is exactly what went wrong on PLAYWORKS. These need adjudication, not")
say("assumption -- in either direction.")
