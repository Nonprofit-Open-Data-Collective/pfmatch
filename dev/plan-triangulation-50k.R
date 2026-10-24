#!/usr/bin/env Rscript
# ============================================================================
# plan-triangulation-50k.R -- size the run for 50,000 informative cases.
#
# Reads the corpus-wide index and applies the two filters the original
# triangulation applies but the index build did not:
#
#   P.O. BOXES OUT. A shared box groups unrelated organisations into one
#   spurious "address", which is the opposite of what triangulation needs --
#   the whole premise is that a shared street address means a shared
#   organisation. dev/build-triangulation-sample.R drops them; so must this.
#
#   MEGA-ADDRESSES OUT. The index reports one key with 10,363 distinct payee
#   names. That is a fiscal sponsor, a donor-advised-fund custodian or a bank
#   trust department, not one organisation written many ways. The existing
#   queue already treats >= 4 names at an address as a risk flag; at four
#   figures it is not a risk, it is a certainty.
#
# COST MODEL. pf_run_batches() matches IDENTITIES -- distinct renderings --
# not grant rows, so a group costs about its n_names. Measured on the original
# filer run: 50,980 identities in 108.3 min, 0.127 s/identity.
#
# YIELD is the unknown and cannot be read off the grant file: a case is
# informative only when one rendering cleared, another did not, and they
# disagree. That needs a match. So this script SIZES A PILOT rather than
# guessing, and the pilot measures yield per size bucket.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("=", 84))

PF  <- Sys.getenv("PFMATCH_DIR", ".")
idx <- readRDS(file.path(PF, "data-dev", "GROUP-INDEX.rds"))
setDT(idx)
SEC_PER_ID <- 108.3 * 60 / 50980          # measured, dev/LOG-match-filer.txt

hr(); say("plan-triangulation-50k   target 50,000 informative cases"); hr()
say("index: %s address keys", format(nrow(idx), big.mark = ","))

m <- idx[n_names > 1L]
say("  multi-rendering groups          %s", format(nrow(m), big.mark = ","))

## ---- filter 1: P.O. boxes ---------------------------------------------------
m[, street := sub("[|].*$", "", key)]
m[, pobox := grepl("^P?O?BOX|^POST", street)]
say("  ... P.O. box keys dropped       %s  (%.1f%%)",
    format(sum(m$pobox), big.mark = ","), 100 * mean(m$pobox))
m <- m[pobox == FALSE]

## ---- filter 2: mega-addresses ----------------------------------------------
CAP <- 25L
say("  ... >= %d names at one address  %s  (fiscal sponsors, DAF custodians)",
    CAP, format(sum(m$n_names >= CAP), big.mark = ","))
say("      they hold %s grants between them -- %.0f%% of the universe's rows",
    format(sum(m$n_grants[m$n_names >= CAP]), big.mark = ","),
    100 * sum(m$n_grants[m$n_names >= CAP]) / sum(m$n_grants))
m <- m[n_names < CAP]

hr(); say("ELIGIBLE UNIVERSE AFTER FILTERS")
say("  groups                          %s", format(nrow(m), big.mark = ","))
say("  grant rows                      %s", format(sum(m$n_grants), big.mark = ","))
say("  identities (the match bill)     %s", format(sum(m$n_names), big.mark = ","))
say("  multi-year groups               %s  (%.1f%%)",
    format(sum(m$n_years > 1L), big.mark = ","), 100 * mean(m$n_years > 1L))
say("  matching ALL of it would take   %.1f hours", sum(m$n_names) * SEC_PER_ID / 3600)

## ---- the efficiency curve ---------------------------------------------------
br  <- c(2, 3, 5, 10, 25, 100, Inf)
lab <- c("2", "3-4", "5-9", "10-24", "25-99", "100+")
m[, bucket := cut(n_grants, breaks = br, right = FALSE, labels = lab)]
d <- m[, .(groups = .N, identities = sum(n_names),
           ids_per_group = mean(n_names)), by = bucket][order(bucket)]
hr(); say("COST PER GROUP BY SIZE   (identities are what the matcher charges for)")
say("  %-7s %10s %13s %14s %10s", "size", "groups", "identities", "ids/group", "hours")
for (j in seq_len(nrow(d)))
  say("  %-7s %10s %13s %14.1f %10.1f", d$bucket[j],
      format(d$groups[j], big.mark = ","), format(d$identities[j], big.mark = ","),
      d$ids_per_group[j], d$identities[j] * SEC_PER_ID / 3600)

## ---- the pilot ---------------------------------------------------------------
# Stratified, not plain random: yield almost certainly varies with group size,
# and knowing the curve is what lets the full run buy cases at the cheapest
# point rather than at the average.
# 600 per bucket estimates a per-group case rate to well within the precision
# this decision needs, and the two largest buckets cost ~7x the smallest per
# group, so halving the pilot halves 77 minutes of matching.
PILOT_PER_BUCKET <- as.integer(Sys.getenv("PF_PILOT_N", "600"))
set.seed(20261023L)
pilot <- m[, .SD[sample(.N, min(.N, PILOT_PER_BUCKET))], by = bucket]
hr(); say("PILOT  (stratified, %d groups per size bucket)", PILOT_PER_BUCKET)
say("  groups                          %s", format(nrow(pilot), big.mark = ","))
say("  grant rows to extract           %s", format(sum(pilot$n_grants), big.mark = ","))
say("  identities to match             %s", format(sum(pilot$n_names), big.mark = ","))
say("  estimated match time            %.1f min",
    sum(pilot$n_names) * SEC_PER_ID / 60)
saveRDS(pilot, file.path(PF, "data-dev", "TRI-PILOT-GROUPS.rds"))
say("  -> data-dev/TRI-PILOT-GROUPS.rds")

hr(); say("WHAT THE PILOT DECIDES")
say("  Current yield is 0.66 informative cases per group (2,853 from 4,326),")
say("  measured on PARTIAL groups -- the old sample only held renderings from")
say("  sampled filers. Corpus-first groups are complete, so yield should rise,")
say("  but by how much is exactly what cannot be assumed.")
say("")
say("  At 0.66/group, 50,000 cases needs ~75,800 groups. Reading that off the")
say("  table above at the cheap end (sizes 2 and 3-4) puts the full run near")
say("  %.1f hours; drawn at the universe average it is far more.",
    sum(head(d$identities, 2)) * SEC_PER_ID / 3600 * 75800 / sum(head(d$groups, 2)))
say("  The pilot replaces both of those arithmetic guesses with a measurement.")
hr()
