#!/usr/bin/env Rscript
# ============================================================================
# Fold the reference-tier findings into the gold-set sampling frame.
#
# dev/OPTIMIZATION-PLAN.md §1b asks for ~600 labels stratified across all three
# tiers, and names the YES and NO strata as the new information -- the existing
# 100 verdicts are all drawn from MAYBE, so YES precision is assumed and NO
# recall is unmeasured.
#
# The tiered-reference probe produced exactly those strata as a by-product:
#
#   NO -> YES     36  grants the active BMF cannot reach at all. These are the
#                     NO stratum: the recipient is a legacy or alias row, and
#                     the question "what does the NO boundary cost" is answered
#                     by labelling them.
#   MAYBE -> YES  47  resolved by more context rather than better scoring.
#   risky YES     16  small-reference YES that the big reference answers with a
#                     DIFFERENT EIN. The YES stratum, and the sharpest form of
#                     it: cases where an auto-accept is contested by evidence
#                     the run never saw.
#
# Output: data-dev/LABEL-FRAME-REFTIER.csv
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() cat(strrep("=", 78), "\n")

cmp <- fread(file.path(PF, "data-dev", "TIERED-REFERENCE.csv"),
             colClasses = list(character = c("e_s", "e_b")))
D <- readRDS(file.path(PF, "data-dev", "PF-DYADS-UNIFIED.rds"))

cmp[, stratum := fifelse(t_s == "NO"    & t_b == "YES", "NO_to_YES",
                  fifelse(t_s == "MAYBE" & t_b == "YES", "MAYBE_to_YES",
                  fifelse(t_s == "YES" & !is.na(e_b) & !is.na(e_s) & e_b != e_s,
                          "YES_contested", NA_character_)))]
fr <- cmp[!is.na(stratum)]

# what a labeller needs in front of them, and the dyad context for the pair
fr[, dyad_class := pf_dyad_lookup(D, e_s, e_b)]
fr[, `:=`(
  small_tier = t_s, small_ein = e_s, small_name = n_s, small_score = round(sc_s, 3),
  big_tier   = t_b, big_ein   = e_b, big_name   = n_b, big_score   = round(sc_b, 3),
  same_ein   = !is.na(e_b) & !is.na(e_s) & e_b == e_s)]

hr(); say("SAMPLING FRAME"); hr()
print(fr[, .(cases = .N), by = stratum][order(-cases)], row.names = FALSE)
say("")
say("dyad relationship between the two answers, where one exists:")
print(fr[, .N, by = .(stratum, dyad_class)][order(stratum, -N)], row.names = FALSE)

say("")
say("NO_to_YES -- the recipient the active BMF could not reach:")
print(head(fr[stratum == "NO_to_YES", .(.id, found = substr(big_name, 1, 44),
                                        score = big_score)], 20), row.names = FALSE)

say("")
say("YES_contested -- an auto-accept the bigger reference disagrees with:")
print(fr[stratum == "YES_contested", .(.id, banked = substr(small_name, 1, 30),
                                       contested_by = substr(big_name, 1, 30),
                                       big_tier)], row.names = FALSE)

out <- fr[, .(grant_id = .id, stratum, same_ein, dyad_class,
              small_tier, small_ein, small_name, small_score,
              big_tier, big_ein, big_name, big_score,
              verdict = "", correct_ein = "", evidence = "", note = "")]
setorder(out, stratum, grant_id)
fwrite(out, file.path(PF, "data-dev", "LABEL-FRAME-REFTIER.csv"))
say(""); say("wrote data-dev/LABEL-FRAME-REFTIER.csv  (%d cases)", nrow(out))
say("")
say("Columns verdict / correct_ein / evidence / note are left blank for the")
say("labeller. Evidence classes as in dev/ADJUDICATION-PLAN.md: QUOTE / NTEE /")
say("INFER / NONE. NONE is a first-class verdict -- 24 of the 100 adjudicated")
say("MAYBE cases had no correct candidate at all.")
