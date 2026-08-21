#!/usr/bin/env Rscript
# ============================================================================
# Two open questions about the dyad ordering policy.
#
# Q1  Why does policy="operating" promote more than policy="top"? Measured
#     +704 vs +398 before the soft-veto guard existed, and three explanations
#     were offered and all three were wrong. keep-top retains the highest score
#     by construction, so it cannot lose on score; the gap has to come from
#     somewhere else.
#
# Q2  Is "operating first" even the right default? It rests on 15 adjudicated
#     cases at 60%, and FEATURE-ENGINEERING.md separately measures is_arm at
#     0.470 pair AUC with the verdict "do not demote arms globally".
#
# The hypothesis worth testing, which nothing has looked at yet:
#
#   rep_of() orders on `order(arm, -score)`. It never looks at the QUERY. So if
#   the grant record itself says "X FOUNDATION", operating-first still picks X.
#   That would be overriding the funder's own words -- and since the score
#   already rewards matching the query, it would also explain Q1: operating
#   diverges from top precisely on the grants where the query names the arm.
#
# A fourth policy falls out of that: keep the member whose name FORM matches the
# query's. Cheap, needs no labels, and testable here.
#
# Output: data-dev/ARM-POLICY-PROBE.csv
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
b <- as.data.table(as.data.frame(base$result))[, .(.id, t0 = tier, e0 = overall_ein,
                                                   n0 = overall_name_y)]
say("baseline: YES %d MAYBE %d NO %d",
    sum(b$t0 == "YES"), sum(b$t0 == "MAYBE"), sum(b$t0 == "NO"))

## --------------------------------------------------- the query's own name form
# pf_recipients() carries recip_name through; the cascade's .id is its grant_id.
g <- as.data.table(base$grants)
qn <- g$recip_name[match(b$.id, g$grant_id)]
b[, q_name := qn]
b[, q_is_arm := pf_is_arm(q_name)]
say("queries whose own recorded name carries a support marker: %d (%.1f%%)",
    sum(b$q_is_arm, na.rm = TRUE), 100*mean(b$q_is_arm, na.rm = TRUE))

## ------------------------------------------------------------- run the policies
runp <- function(policy) {
  o <- suppressMessages(pf_dyad_collapse(base, D, pf_dyad_config(policy = policy),
                                         np_config = cfg))
  a <- as.data.table(as.data.frame(o$result))
  a[, .(.id, tier = tier, ein = overall_ein, nm = overall_name_y,
        collapsed = dyad_collapsed)]
}
hr(); say("TIER OUTCOME BY POLICY (soft-veto guard active)"); hr()
P <- list()
for (p in c("query", "operating", "top", "arm")) {
  P[[p]] <- runp(p)
  t <- table(factor(P[[p]]$tier, c("YES","MAYBE","NO")))
  say("  %-10s YES %6d (%+5d)  MAYBE %6d  NO %6d", p, t[["YES"]],
      t[["YES"]] - sum(b$t0 == "YES"), t[["MAYBE"]], t[["NO"]])
}

## ------------------------------------------------------------------- Q1
hr(); say("Q1  WHERE DOES operating DIVERGE FROM top?"); hr()
cmp <- merge(merge(b, P$operating[, .(.id, t_op = tier, e_op = ein, n_op = nm,
                                      coll = collapsed)], by = ".id"),
             P$top[, .(.id, t_tp = tier, e_tp = ein, n_tp = nm)], by = ".id")
d <- cmp[coll == TRUE]
say("collapsed grants: %d", nrow(d))
say("  the two policies keep a DIFFERENT EIN : %d", sum(d$e_op != d$e_tp))
say("  ...and land on a different tier       : %d", sum(d$t_op != d$t_tp))
say("")
say("tier outcome on the grants where they differ:")
print(d[e_op != e_tp, .N, by = .(operating = t_op, top = t_tp)][order(-N)],
      row.names = FALSE)

sb(); say("DOES THE QUERY NAME EXPLAIN IT?"); sb()
diff <- d[t_op != t_tp]
say("grants where the policies land on different tiers: %d", nrow(diff))
if (nrow(diff)) {
  say("  of those, the QUERY itself names an arm         : %d (%.0f%%)",
      sum(diff$q_is_arm, na.rm = TRUE), 100*mean(diff$q_is_arm, na.rm = TRUE))
  say("  baseline rate across all collapsed grants       : %.0f%%",
      100*mean(d$q_is_arm, na.rm = TRUE))
  say("")
  print(head(diff[, .(.id, query = substr(q_name,1,30), q_is_arm,
                      operating = substr(n_op,1,26), t_op,
                      top = substr(n_tp,1,26), t_tp)], 20), row.names = FALSE)
}

## ------------------------------------------------------------------- Q2
hr(); say("Q2  DOES operating-first OVERRIDE THE FUNDER'S OWN WORDS?"); hr()
arm_q <- d[q_is_arm == TRUE]
say("collapsed grants whose recorded name carries a support marker: %d", nrow(arm_q))
if (nrow(arm_q)) {
  kept_arm <- pf_is_arm(arm_q$n_op)
  say("  operating-first still reports a NON-arm EIN : %d (%.0f%%)  <- overriding the query",
      sum(!kept_arm), 100*mean(!kept_arm))
  say("  keep-top reports an arm                     : %d (%.0f%%)",
      sum(pf_is_arm(arm_q$n_tp)), 100*mean(pf_is_arm(arm_q$n_tp)))
  say("")
  print(head(arm_q[!pf_is_arm(n_op), .(.id, query = substr(q_name,1,34),
                                       operating_reports = substr(n_op,1,34))], 20),
        row.names = FALSE)
}
say("")
noarm_q <- d[q_is_arm == FALSE]
say("collapsed grants whose recorded name has NO support marker: %d", nrow(noarm_q))
if (nrow(noarm_q))
  say("  keep-top reports an arm anyway              : %d (%.0f%%)  <- overriding the query the other way",
      sum(pf_is_arm(noarm_q$n_tp)), 100*mean(pf_is_arm(noarm_q$n_tp)))

sb(); say("A QUERY-MATCHING POLICY, SIMULATED"); sb()
# what would "keep the member whose name form matches the query" report?
d[, want_arm := q_is_arm %in% TRUE]
d[, op_is_arm := pf_is_arm(n_op)][, tp_is_arm := pf_is_arm(n_tp)]
d[, qmatch_ein := fifelse(want_arm,
      fifelse(tp_is_arm, e_tp, e_op),
      fifelse(!tp_is_arm, e_tp, e_op))]
say("query-matching agrees with operating-first : %d (%.0f%%)",
    sum(d$qmatch_ein == d$e_op), 100*mean(d$qmatch_ein == d$e_op))
say("query-matching agrees with keep-top        : %d (%.0f%%)",
    sum(d$qmatch_ein == d$e_tp), 100*mean(d$qmatch_ein == d$e_tp))

## The 15-label section was removed: ARM-ORDERING-CASES.csv carries grant ids
## from an older run, so joining them to this run pairs each case with an
## unrelated grant name. The same stale-id trap as the AUDIT-MAYBE-100 rank
## join. Any comparison against those labels needs the ids re-derived first.
if (FALSE) {
hr(); say("AGAINST THE 15 ADJUDICATED ARM PAIRS"); hr()
af <- file.path(PF, "data-dev", "ARM-ORDERING-CASES.csv")
if (file.exists(af)) {
  ao <- fread(af, colClasses = "character")
  ao[, q_is_arm := pf_is_arm(arm_nm) & FALSE]   # placeholder; use the grant name
  gi <- match(ao$gid, g$grant_id)
  ao[, q_name := g$recip_name[gi]]
  ao[, q_is_arm := pf_is_arm(q_name)]
  ao[, truth_is_arm := winner == "ARM"]
  ok <- !is.na(ao$q_name)
  say("cases with a recoverable grant name: %d of %d", sum(ok), nrow(ao))
  say("")
  say("  query names an arm AND the arm was right   : %d",
      sum(ao$q_is_arm & ao$truth_is_arm, na.rm = TRUE))
  say("  query names an arm, the OPERATING was right: %d",
      sum(ao$q_is_arm & !ao$truth_is_arm, na.rm = TRUE))
  say("  query has no marker, the arm was right     : %d",
      sum(!ao$q_is_arm & ao$truth_is_arm, na.rm = TRUE))
  say("  query has no marker, operating was right   : %d",
      sum(!ao$q_is_arm & !ao$truth_is_arm, na.rm = TRUE))
  say("")
  agree <- sum((ao$q_is_arm & ao$truth_is_arm) |
               (!ao$q_is_arm & !ao$truth_is_arm), na.rm = TRUE)
  say("  query-matching would be right on %d of %d (%.0f%%)",
      agree, sum(ok), 100*agree/max(sum(ok),1))
  say("  operating-always is right on     %d of %d (%.0f%%)",
      sum(!ao$truth_is_arm, na.rm = TRUE), sum(ok),
      100*sum(!ao$truth_is_arm, na.rm = TRUE)/max(sum(ok),1))
  print(ao[, .(gid, query = substr(q_name,1,30), q_is_arm, winner)], row.names = FALSE)
}

fwrite(d, file.path(PF, "data-dev", "ARM-POLICY-PROBE.csv"))
say(""); say("wrote data-dev/ARM-POLICY-PROBE.csv")
}
