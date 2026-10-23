#!/usr/bin/env Rscript
# ============================================================================
# Can a YES rendering label its own MAYBE siblings? -- feasibility only.
#
# THE IDEA. One organisation is written many ways across grants. Some renderings
# clear, others do not. If renderings of the same organisation can be grouped
# WITHOUT using the pipeline's answer, a confident YES in the group supplies a
# label for its MAYBE/NO siblings -- ground truth at a scale hand adjudication
# cannot reach.
#
# THE CIRCULARITY TRAP, and how this avoids it. Grouping by the matched EIN, or
# by dedup identity, only proves self-consistency: dev/test-persistence-lever.R
# already measured 0 of 17,706 repeat pairs differing in status, because dedup
# collapses renderings BEFORE matching, so the group shares one answer by
# construction.
#
# So: group on ADDRESS, test the NAME. The address is independent of the name
# comparator, which is the thing under test. (The mirror design -- group on
# name, test geo -- is equally valid and not done here.)
#
# WHAT THIS CAN AND CANNOT ESTABLISH. It is a CONSISTENCY test, not a
# correctness test. It can only find organisations the pipeline already got
# right at least once, so it measures the name comparator's VARIANCE across
# renderings. An organisation the pipeline gets wrong the same way every time is
# invisible to it. Labels it produces are SILVER -- basis = "triangulated" --
# and must stay separable from hand adjudication.
#
# THE FALSE-GROUPING RISK is real: a shared office building, a fiscal sponsor, a
# community foundation hosting many funds, and a lockbox all put distinct
# organisations at one address. This probe therefore measures how many addresses
# carry MANY distinct organisations before trusting any grouping.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
PF  <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("-", 84))
sq  <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; x }

M  <- readRDS(file.path(PF, "data-dev", "FILER-SAMPLE-MATCH.rds"))
g  <- as.data.table(M$grants)[in_scope == TRUE]
say("filer-sample grants in scope: %s", format(nrow(g), big.mark = ","))
say("status mix: %s", paste(sprintf("%s=%s", names(table(g$status)),
    as.integer(table(g$status))), collapse = "  "))

## ---- the grouping key: address only, never the name ------------------------
# Require a real street address: a PO box or a blank street groups unrelated
# organisations wholesale.
g[, st_key := toupper(gsub("[^A-Z0-9]", "", toupper(sq(recip_street))))]
g[, pobox := grepl("^P?O?BOX|^POST", st_key)]
g[, addr_key := fifelse(nzchar(st_key) & !pobox & nzchar(sq(recip_zip5)),
                        paste(st_key, sq(recip_zip5), sep = "|"), NA_character_)]
say("")
say("grants with a usable street+zip key: %s (%.0f%%)",
    format(sum(!is.na(g$addr_key)), big.mark = ","), 100 * mean(!is.na(g$addr_key)))

a <- g[!is.na(addr_key)]
a[, nm_key := toupper(gsub("[^A-Z0-9 ]", " ", sq(recip_name)))]
a[, nm_key := gsub(" +", " ", trimws(nm_key))]

## ---- how dangerous is address grouping? ------------------------------------
hr(); say("FALSE-GROUPING RISK: distinct name renderings per address")
grp <- a[, .(n_rows = .N, n_names = uniqueN(nm_key),
             n_eins = uniqueN(ein[!is.na(ein) & nzchar(ein)]),
             n_tiers = uniqueN(status)), by = addr_key]
say("addresses: %s", format(nrow(grp), big.mark = ","))
print(grp[, .(addresses = .N), by = .(distinct_names = pmin(n_names, 5L))][
        order(distinct_names)], row.names = FALSE)
say("")
say("addresses where the pipeline assigned >1 DISTINCT ein: %s (%.1f%%)",
    format(sum(grp$n_eins > 1L), big.mark = ","), 100 * mean(grp$n_eins > 1L))
say("  -> that is the shared-building / fiscal-sponsor population. Any address")
say("     with more than one confident EIN cannot anchor a label.")

## ---- the triangulation-eligible population ---------------------------------
hr(); say("TRIANGULATION YIELD")
# eligible: >=2 distinct name renderings, >=1 YES, >=1 non-YES, and the YES
# side agreeing on a single EIN
cand <- a[, {
  yes <- status == "YES" & !is.na(ein) & nzchar(ein)
  .(n_rows = .N, n_names = uniqueN(nm_key),
    n_yes = sum(yes), n_other = sum(status != "YES"),
    yes_eins = uniqueN(ein[yes]),
    anchor = if (sum(yes)) ein[yes][1] else NA_character_)
}, by = addr_key]
elig <- cand[n_names >= 2L & n_yes >= 1L & n_other >= 1L & yes_eins == 1L]
say("addresses with >=2 name renderings           : %s",
    format(sum(cand$n_names >= 2L), big.mark = ","))
say("  ... and at least one YES and one non-YES   : %s",
    format(sum(cand$n_names >= 2L & cand$n_yes >= 1L & cand$n_other >= 1L), big.mark = ","))
say("  ... and the YES side agrees on ONE ein     : %s  <- eligible",
    format(nrow(elig), big.mark = ","))
lab <- merge(a[status != "YES"], elig[, .(addr_key, anchor)], by = "addr_key")
say("")
say("SILVER LABELS this would produce (non-YES rows inheriting an anchor): %s",
    format(nrow(lab), big.mark = ","))
print(lab[, .N, by = status][order(-N)], row.names = FALSE)

## ---- does the anchor even appear in the sibling's candidates? --------------
# Without the candidate lists we cannot check rank here, but we CAN check
# whether the sibling's own top pick already equals the anchor -- i.e. whether
# the grouping would teach us anything the run did not already say.
lab[, agrees := !is.na(ein) & nzchar(ein) & ein == anchor]
hr(); say("WOULD IT TEACH ANYTHING?")
say("  sibling's top pick ALREADY equals the anchor : %s (%.0f%%)",
    format(sum(lab$agrees), big.mark = ","), 100 * mean(lab$agrees))
say("  sibling disagrees or has no ein              : %s (%.0f%%)",
    format(sum(!lab$agrees), big.mark = ","), 100 * mean(!lab$agrees))
say("")
say("  The second number is the informative one: a label the run does not")
say("  already assert. The first is confirmation only.")

ex <- lab[agrees == FALSE][order(addr_key)]
if (nrow(ex)) {
  hr(); say("EXAMPLES (sibling disagrees with its YES anchor)")
  show <- ex[1:min(12L, nrow(ex))]
  for (i in seq_len(nrow(show)))
    say("  %-34s %-7s own=%-10s anchor=%-10s", substr(show$recip_name[i], 1, 34),
        show$status[i], sq(show$ein[i]), show$anchor[i])
}
fwrite(lab, file.path(PF, "data-dev", "TRIANGULATION-CANDIDATES.csv"))
hr(); say("wrote data-dev/TRIANGULATION-CANDIDATES.csv")
