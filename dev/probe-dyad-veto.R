#!/usr/bin/env Rscript
# ============================================================================
# Does the dyad collapse defeat the affiliate_suffix soft veto?
#
# affiliate_suffix soft-vetoes a candidate whose last token is FOUNDATION /
# ENDOWMENT / AUXILIARY / BOOSTERS when the query lacks it. A soft veto caps the
# grant at MAYBE -- it is npmatch's "do not auto-accept this" signal, and it
# exists for exactly the operating-arm problem.
#
# pf_dyad_collapse(policy = "operating") drops the arm. If the arm was the
# soft-vetoed candidate, the veto leaves with it and the grant can promote to
# YES. The question is whether that is the veto being SATISFIED (we stopped
# matching to the FOUNDATION, which is what it asked) or DEFEATED (a
# review-flagged case became an auto-accept on the strength of a policy
# validated at 60% on 15 cases).
#
# The distinction is measurable, and it is the pick:
#
#   pick UNCHANGED -- the cascade already ranked the operating entity first and
#     the collapse only removed a same-body competitor. The veto was about a
#     candidate we were never going to report. Clean.
#
#   pick CHANGED -- the cascade ranked the ARM first, the policy overrode it.
#     Here the promotion rests on the ordering policy, not on the score, and
#     the soft veto was the only thing holding it for review.
#
# Output: data-dev/DYAD-VETO-PROBE.csv
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(devtools::load_all(
  Sys.getenv("NPMATCH_DIR", "../npmatch"), quiet = TRUE)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
setDTthreads(0L)
say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() cat(strrep("=", 78), "\n")
sb  <- function() cat(strrep("-", 78), "\n")
e9 <- function(z) { z <- gsub("[^0-9]", "", as.character(z))
                    fifelse(nchar(z) == 9L, z, NA_character_) }

D <- readRDS(file.path(PF, "data-dev", "PF-DYADS-UNIFIED.rds"))
m <- readRDS(file.path(PF, "data-dev", "PF-MATCH-RESULT-50k.rds"))
cfg <- npmatch::np_config()
say("scoring the 50k pair set ...")
pr <- npmatch::np_veto(npmatch::np_score(attr(m$result, "pairs"), cfg, method = "hier"), cfg)
base <- m
base$result <- npmatch::np_tier(npmatch::np_select(pr, cfg), cfg)
attr(base$result, "pairs") <- pr
base$config <- cfg

out <- suppressMessages(pf_dyad_collapse(base, D, pf_dyad_config(), np_config = cfg))

b <- as.data.table(as.data.frame(base$result))[, .(.id, t0 = tier, e0 = overall_ein,
       n0 = overall_name_y, sv0 = overall_veto_soft, m0 = overall_margin)]
a <- as.data.table(as.data.frame(out$result))[, .(.id, t1 = tier, e1 = overall_ein,
       n1 = overall_name_y, sv1 = overall_veto_soft, dyad_collapsed)]
cmp <- merge(b, a, by = ".id")
pro <- cmp[t0 == "MAYBE" & t1 == "YES"]
say("promotions: %d", nrow(pro))

## ------------------------------------------- was the baseline held by a veto?
pro[, held_by_veto := sv0 %in% TRUE]
pro[, pick_changed := !is.na(e0) & !is.na(e1) & e0 != e1]

hr(); say("WHY WAS THE GRANT IN MAYBE BEFORE THE COLLAPSE?"); hr()
say("promotions where the baseline pick carried a SOFT VETO : %d (%.0f%%)",
    sum(pro$held_by_veto), 100*mean(pro$held_by_veto))
say("promotions held only by the margin brake              : %d (%.0f%%)",
    sum(!pro$held_by_veto), 100*mean(!pro$held_by_veto))
say("")
say("The soft-veto group is the one at issue: those grants were flagged")
say("'do not auto-accept' and are now auto-accepted.")

hr(); say("THE DECISIVE CROSSTAB: DID THE REPORTED EIN CHANGE?"); hr()
tb <- pro[, .N, by = .(held_by_veto, pick_changed)][order(-N)]
print(tb, row.names = FALSE)
say("")
n_clean <- nrow(pro[held_by_veto == TRUE & pick_changed == FALSE])
n_risk  <- nrow(pro[held_by_veto == TRUE & pick_changed == TRUE])
say("veto dropped, pick UNCHANGED (veto satisfied)  : %d", n_clean)
say("veto dropped, pick CHANGED   (policy overrode) : %d  <- the exposure", n_risk)
say("")
say("In the first group the cascade already ranked the operating entity first;")
say("the veto was about a candidate that was never going to be reported.")
say("In the second the cascade ranked the ARM first and the policy overrode it,")
say("so the promotion rests on a rule validated at 60%% on 15 adjudicated cases.")

hr(); say("WHAT THE EXPOSED CASES LOOK LIKE"); hr()
if (n_risk) print(head(pro[held_by_veto == TRUE & pick_changed == TRUE,
    .(.id, was = substr(n0,1,34), now = substr(n1,1,34), margin0 = round(m0,3))], 20),
    row.names = FALSE)

## --------------------------------------------- does any veto survive collapse?
hr(); say("DOES THE COLLAPSE EVER KEEP A SOFT-VETOED CANDIDATE?"); hr()
coll <- cmp[dyad_collapsed == TRUE]
say("collapsed grants                       : %d", nrow(coll))
say("  representative carries a soft veto   : %d", sum(coll$sv1 %in% TRUE))
say("  ...and the grant stayed MAYBE        : %d",
    nrow(coll[sv1 %in% TRUE & t1 == "MAYBE"]))
say("")
say("A veto on the KEPT candidate still holds the grant, as it should. Only a")
say("veto on a DROPPED candidate disappears.")

fwrite(pro, file.path(PF, "data-dev", "DYAD-VETO-PROBE.csv"))
say(""); say("wrote data-dev/DYAD-VETO-PROBE.csv")
