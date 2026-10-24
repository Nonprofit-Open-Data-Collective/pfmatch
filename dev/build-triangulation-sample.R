#!/usr/bin/env Rscript
# ============================================================================
# Wire address-triangulation in as a testing sample.
#
# POPULATION NOTE, 2026-10-23. These artifacts are keyed to 6e3e985e05a5f364 --
# the in-scope subset of the FILER sample (data-dev/FILER-SAMPLE-MATCH.rds,
# built from inputs/effiler100k_grants.csv), NOT the 1k benchmark population.
# That is deliberate: triangulation needs whole filer portfolios, which the
# random-grant samples shred, and a 1k sample holds too few repeated renderings
# of one organisation to group.
#
# It was therefore NOT part of the v2 recalibration, and the five artifacts
# below are untouched by it. They sit on the v1 UNDEDUPLICATED build, so before
# scoring a v2 run against them they need the same treatment the 1k sample got
# in dev/lift-sample-to-v2.R: lift the rows onto the deduplicated corpus and
# translate the ids through a crosswalk, never renumber. grant_id is positional
# here too.
#
# Re-running this script against a v2 filer sample would also work, and is
# cleaner, but it discards the ~30 cases already eyeballed.
#
# One organisation is written many ways across grants; some renderings clear and
# others do not. Grouping renderings by ADDRESS is independent of the name
# comparator, which is the thing under test, so the groups are usable even
# though the pipeline produced the tiers.
#
# This writes THREE artifacts, deliberately distinct, because they support
# claims of very different strength:
#
#   TRIANGULATION-GROUPS.csv    (grant_id, group_id) only. No labels, no
#                               assertion about which answer is right. Feeds
#                               pf_consistency(), which asks only whether
#                               renderings of one organisation AGREE. This is
#                               the artifact worth trusting.
#
#   TRIANGULATION-SAMPLE.csv    An adjudication QUEUE: every informative case
#                               with the evidence a reviewer needs. Eyeballing
#                               ~30 of these put precision near 50-60%, so it is
#                               a pre-filtered queue, not an answer key. At that
#                               hit rate it still beats random sampling by a
#                               wide margin for finding real comparator
#                               failures.
#
#   PF-TRUTH-TRIANGULATED.csv   The same cases in pf_truth_schema() shape, with
#                               basis = "triangulated" and confidence = "low".
#                               pf_evaluate() defaults to min_confidence =
#                               "medium", so these are EXCLUDED unless a caller
#                               opts in. Silver must never silently inflate gold.
#
# KNOWN FAILURE MODES, measured, not hypothesised:
#   fiscal sponsors    MULTIPLIERORG x5 inherits Natural Resources Defense
#                      Council; Multiplier hosts many projects at one address.
#   individuals        "EDUCATIONAL GRANT - <person>", "LISANNE FINSTON" sit at
#                      an organisation's address but are payments to people.
#   wrong anchor       "Homes for our Troops" own pick is right, the anchor is
#                      not -- the YES is not automatically the truth.
#
# Gating does not rescue it: requiring one EIN per address is self-defeating
# (the informative cases are exactly those where the sibling chose differently,
# so that gate removes the signal), and stacking gates cut 2,853 informative
# cases to 26. Hence: queue plus consistency metric, not an answer key.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(library(digest)))
setDTthreads(0)
PF  <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("-", 86))
sq  <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; x }
e9  <- function(v) { v <- gsub("[^0-9]", "", as.character(v))
                     ifelse(nchar(v) == 9L, v, NA_character_) }

M <- readRDS(file.path(PF, "data-dev", "FILER-SAMPLE-MATCH.rds"))
g <- as.data.table(M$grants)[in_scope == TRUE]
say("filer-sample grants in scope: %s", format(nrow(g), big.mark = ","))

POP <- if ("OBJECTID" %in% names(g)) pf_population_id(g) else {
  say("NOTE: no OBJECTID on this run; fingerprinting on (FILEREIN, TAXYEAR) instead")
  substr(digest::digest(sort(unique(paste(sq(g$FILEREIN), sq(g$TAXYEAR)))),
                        algo = "md5"), 1, 16)
}
say("population id: %s", POP)

## ---- groups: address only, never the name ----------------------------------
g[, st_key := toupper(gsub("[^A-Z0-9]", "", toupper(sq(recip_street))))]
g[, pobox  := grepl("^P?O?BOX|^POST", st_key)]
g[, addr_key := fifelse(nzchar(st_key) & !pobox & nzchar(sq(recip_zip5)),
                        paste(st_key, sq(recip_zip5), sep = "|"), NA_character_)]
a <- g[!is.na(addr_key)]
a[, nm_key := gsub(" +", " ", trimws(toupper(gsub("[^A-Z0-9 ]", " ", sq(recip_name)))))]
a[, ein9 := e9(ein)]

# a group is worth keeping only if it holds >= 2 DISTINCT renderings: identical
# renderings are what dedup already collapses, and carry no information
grp <- a[, .(n_rows = .N, n_names = uniqueN(nm_key)), by = addr_key][n_names >= 2L]
a <- merge(a, grp[, .(addr_key)], by = "addr_key")
a[, group_id := paste0("TG-", substr(vapply(addr_key, function(s)
    digest::digest(s, algo = "xxhash64"), character(1)), 1, 12))]
say("")
say("groups (>=2 distinct renderings at one street+zip): %s",
    format(uniqueN(a$group_id), big.mark = ","))
say("grant rows inside them                            : %s",
    format(nrow(a), big.mark = ","))

groups_out <- a[, .(grant_id, group_id, population = POP,
                    recip_name, recip_city, recip_state, recip_zip5)]
fwrite(groups_out, file.path(PF, "data-dev", "TRIANGULATION-GROUPS.csv"))
say("wrote data-dev/TRIANGULATION-GROUPS.csv  (no labels: grouping only)")

## ---- the queue: informative cases with their evidence ----------------------
anch <- a[, {
  yes <- status == "YES" & !is.na(ein9)
  .(n_yes = sum(yes), n_other = sum(status != "YES"),
    yes_eins = uniqueN(ein9[yes]), all_eins = uniqueN(ein9[!is.na(ein9)]),
    anchor = if (sum(yes)) ein9[yes][1] else NA_character_,
    anchor_name = if (sum(yes)) sq(bmf_name[yes])[1] else "",
    anchor_score = if (sum(yes)) suppressWarnings(max(as.numeric(score[yes]), na.rm = TRUE)) else NA_real_)
}, by = group_id]
elig <- anch[n_yes >= 1L & n_other >= 1L & yes_eins == 1L]
q <- merge(a[status != "YES"], elig, by = "group_id")
q[, informative := !(!is.na(ein9) & ein9 == anchor)]
q <- q[informative == TRUE]

# risk flags a reviewer must see, from the measured failure modes
q[, flag_person := grepl("EDUCATIONAL GRANT|SCHOLARSHIP", toupper(sq(recip_name))) |
                   (!is.na(looks_personal) & looks_personal %in% TRUE)]
# NOT `all_eins > 1`: that is definitionally true for every informative case,
# since the sibling disagreeing with the anchor is precisely the signal. Using
# it would flag 2,770 of 2,853 and tell a reviewer nothing -- the same
# self-defeating logic as the "one EIN per address" gate.
# A shared or fiscal-sponsor address shows itself by carrying MANY distinct
# payee names: Multiplier hosts dozens of projects at one street.
q <- merge(q, a[, .(n_names_at_addr = uniqueN(nm_key)), by = group_id],
           by = "group_id")
q[, flag_shared := n_names_at_addr >= 4L]
q[, flag_weak_anchor := is.na(anchor_score) | anchor_score < 0.90]
q[, flag_single_anchor := n_yes < 2L]
say("")
say("informative queue cases: %s", format(nrow(q), big.mark = ","))
say("  flagged possible individual payee  : %s", format(sum(q$flag_person), big.mark = ","))
say("  flagged shared / fiscal-sponsor    : %s", format(sum(q$flag_shared), big.mark = ","))
say("  flagged weak anchor (score < 0.90) : %s", format(sum(q$flag_weak_anchor), big.mark = ","))
say("  flagged single anchor rendering    : %s", format(sum(q$flag_single_anchor), big.mark = ","))
q[, n_flags := flag_person + flag_shared + flag_weak_anchor + flag_single_anchor]
say("")
print(q[, .(cases = .N), by = n_flags][order(n_flags)], row.names = FALSE)
say("  -> 0 flags is the cleanest slice; review that first.")

qcols <- c("group_id", "grant_id", "recip_name", "recip_street", "recip_city", "n_names_at_addr",
           "recip_state", "recip_zip5", "status", "ein9", "score",
           "anchor", "anchor_name", "anchor_score", "n_yes", "n_other",
           "flag_person", "flag_shared", "flag_weak_anchor",
           "flag_single_anchor", "n_flags")
qout <- q[, intersect(qcols, names(q)), with = FALSE]
qout[, c("verdict", "note") := ""]
setorder(qout, n_flags, group_id)
fwrite(qout, file.path(PF, "data-dev", "TRIANGULATION-SAMPLE.csv"))
say("wrote data-dev/TRIANGULATION-SAMPLE.csv  (adjudication QUEUE, %d cases)", nrow(qout))

## ---- the same cases in truth-table shape, marked LOW ------------------------
tri <- data.table(
  truth_id = paste0("TRI-", substr(vapply(paste(q$group_id, q$grant_id),
                     function(s) digest::digest(s, algo = "xxhash64"),
                     character(1)), 1, 12)),
  grant_id = q$grant_id, population = POP, object_id = NA_character_,
  recip_name = q$recip_name, verdict = "ORG_FOUND",
  correct_ein = q$anchor, wrong_ein = NA_character_,
  basis = "triangulated", confidence = "low",
  source = "TRIANGULATION-SAMPLE.csv",
  note = sprintf("anchor %s (%s) from %d YES rendering(s) at the same street+zip; %d flag(s)",
                 q$anchor, substr(sq(q$anchor_name), 1, 40), q$n_yes, q$n_flags))
fwrite(tri, file.path(PF, "data-dev", "PF-TRUTH-TRIANGULATED.csv"))
hr()
say("wrote data-dev/PF-TRUTH-TRIANGULATED.csv  (%d rows, basis=triangulated, confidence=low)",
    nrow(tri))
say("")
say("pf_evaluate() defaults to min_confidence = \"medium\", so these are EXCLUDED")
say("unless a caller passes min_confidence = \"low\". That is deliberate: measured")
say("precision is near 50-60%%, so they are a QUEUE and a consistency signal, not")
say("an answer key. Adjudicated rows should be rewritten with their real basis.")
