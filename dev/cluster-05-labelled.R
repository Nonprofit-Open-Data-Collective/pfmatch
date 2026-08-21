#!/usr/bin/env Rscript
# ============================================================================
# Phase 3b - the labelled evidence, joined on the EINs recorded at audit time.
#
# cluster-04 joined the verdicts to a freshly rebuilt candidate list by rank.
# That join is invalid: the reference switched to the NCCS unified BMF after
# the audits were written, so rank 2 today is not rank 2 then. Everything here
# joins on the EINs stored in the audit artefacts themselves.
#
#   data-dev/AUDIT-MAYBE-100.csv   grant_id, rank, ein, cand_name  (audit-time)
#   dev/maybe-verdicts.csv         grant_id, verdict, correct_rank
#   data-dev/MAYBE-ARM-PAIRS.csv   927 arm/operating EIN pairs + 2022 link flags
#
# Questions:
#   A. On the 927 known arm pairs, how much does pooling 2009-2024 raise the
#      49% single-year disclosure rate?
#   B. On the adjudicated cases, when the top pick is wrong, is the truth a
#      linked EIN?
#   C. How many adjudicated errors become non-errors under "either member of a
#      disclosed pair counts"?
# ============================================================================
suppressWarnings(suppressMessages({library(data.table)}))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("=", 78), "\n")
sub <- function() cat(strrep("-", 78), "\n")
ci  <- function(k, n) if (n == 0) "-" else
  sprintf("%.0f-%.0f%%", 100*binom.test(k,n)$conf.int[1], 100*binom.test(k,n)$conf.int[2])
e9 <- function(z) { z <- gsub("[^0-9]", "", as.character(z))
                    fifelse(nchar(z) == 9L, z, NA_character_) }

L <- readRDS(file.path(PF, "data-dev", "CLUSTER-PAIRS.rds"))
P <- L$pairs; P[, key := paste(x, y)]
POOLED <- P$key
Y22    <- P[yr_min <= 2022 & yr_max >= 2022]$key
linked <- function(a, b, keys) {
  ok <- !is.na(a) & !is.na(b) & a != b
  out <- rep(FALSE, length(a))
  out[ok] <- paste(pmin(a[ok],b[ok]), pmax(a[ok],b[ok])) %chin% keys
  out
}
# supporter -> supported, for direction
SUP <- unique(L$sup)[, k := paste(supporter, supported)]$k

## ======================================================== A. the 927 arm pairs
hr(); say("A  DOES POOLING 2009-2024 RAISE THE SINGLE-YEAR DISCLOSURE RATE?"); hr()

ap <- fread(file.path(PF, "data-dev", "MAYBE-ARM-PAIRS.csv"), colClasses = "character")
for (j in c("sa_fwd","sa_rev","sr_any","grp_same","any_src")) ap[, (j) := get(j) == "TRUE"]
ac <- fread(file.path(PF, "data-dev", "ARM-CLUSTERS.csv"), colClasses = "character")
for (j in c("geo_ok","geo_tight")) ac[, (j) := get(j) == "TRUE"]

u <- unique(ap[, .(arm_ein, op_ein, any_src_2022 = any_src)])
u <- merge(u, unique(ac[, .(arm_ein, op_ein, geo_ok, geo_tight)]),
           by = c("arm_ein","op_ein"), all.x = TRUE)
u[is.na(geo_ok),    geo_ok    := FALSE]
u[is.na(geo_tight), geo_tight := FALSE]
u[, pooled := linked(arm_ein, op_ein, POOLED)]
u[, y2022  := linked(arm_ein, op_ein, Y22)]
u[, sa_dir := paste(arm_ein, op_ein) %chin% SUP | paste(op_ein, arm_ein) %chin% SUP]

say("distinct name-detected arm/operating pairs: %d", nrow(u))
say("")
say("%-22s %6s %14s %14s %14s", "subset", "pairs", "2022 (prior)", "pooled", "gain")
f <- function(lbl, d) say("%-22s %6d %8d %5.0f%% %8d %5.0f%% %8d %+5.0f pp",
   lbl, nrow(d), sum(d$any_src_2022), 100*mean(d$any_src_2022),
   sum(d$pooled), 100*mean(d$pooled),
   sum(d$pooled) - sum(d$any_src_2022),
   100*(mean(d$pooled) - mean(d$any_src_2022)))
f("all", u); f("same state", u[geo_ok == TRUE]); f("same city", u[geo_tight == TRUE])
say("")
say("pairs newly linked only because of pooling : %d", sum(u$pooled & !u$any_src_2022))
say("pairs the prior build had that pooling lost: %d", sum(!u$pooled & u$any_src_2022))
say("Schedule A states a direction for          : %d of %d linked (%.0f%%)",
    sum(u$sa_dir), sum(u$pooled), 100*sum(u$sa_dir)/max(sum(u$pooled),1))

## ================================================ B. the adjudicated MAYBE 100
hr(); say("B  ADJUDICATED CASES, JOINED ON AUDIT-TIME EINS"); hr()

a <- fread(file.path(PF, "data-dev", "AUDIT-MAYBE-100.csv"), colClasses = "character")
a[, rank := as.integer(rank)][, ein9 := e9(ein)]
v <- fread(file.path(PF, "dev", "maybe-verdicts.csv"), colClasses = "character")
v[, correct_rank := suppressWarnings(as.integer(correct_rank))]

top <- a[rank == 1L, .(grant_id, top_ein = ein9, top_nm = cand_name,
                       recip = recip_name, purpose = grant_purpose)]
r2  <- a[rank == 2L, .(grant_id, e2 = ein9, n2 = cand_name)]
v <- merge(v, top, by = "grant_id", all.x = TRUE)
v <- merge(v, r2,  by = "grant_id", all.x = TRUE)
tr <- a[, .(grant_id, rank, true_ein = ein9, true_nm = cand_name)]
v <- merge(v, tr, by.x = c("grant_id","correct_rank"), by.y = c("grant_id","rank"),
           all.x = TRUE)
v[, lk_top2  := linked(top_ein, e2, POOLED)]
v[, lk_truth := linked(top_ein, true_ein, POOLED)]
v[, lk_truth22 := linked(top_ein, true_ein, Y22)]

say("cases with a recovered rank-1 EIN: %d of %d", sum(!is.na(v$top_ein)), nrow(v))
say("")
sub(); say("CORRECT_DEEPER - the truth was in the list, below the top pick"); sub()
dd <- v[verdict == "CORRECT_DEEPER"]
say("cases %d ; truth EIN recovered %d", nrow(dd), sum(!is.na(dd$true_ein)))
say("  top pick disclosed-related to the truth : %d of %d (%s)",
    sum(dd$lk_truth), sum(!is.na(dd$true_ein)),
    ci(sum(dd$lk_truth), max(sum(!is.na(dd$true_ein)),1)))
print(dd[, .(grant_id, failure_mode, top = substr(top_nm,1,30),
             truth = substr(true_nm,1,30), linked = lk_truth)], row.names = FALSE)

sub(); say("AMBIGUOUS - the adjudicator could not choose"); sub()
am <- v[verdict == "AMBIGUOUS"]
say("cases %d ; top two both recovered %d", nrow(am), sum(!is.na(am$e2)))
say("  top two disclosed as related : %d of %d (%s)",
    sum(am$lk_top2), sum(!is.na(am$e2)), ci(sum(am$lk_top2), max(sum(!is.na(am$e2)),1)))
print(am[, .(grant_id, failure_mode, top = substr(top_nm,1,30),
             runner = substr(n2,1,30), linked = lk_top2)], row.names = FALSE)

sub(); say("CORRECT_TOP - the control group. A link here is a FALSE alarm risk"); sub()
ct <- v[verdict == "CORRECT_TOP"]
say("cases %d ; top two linked %d (%.0f%%) - these are grants where the cascade",
    nrow(ct), sum(ct$lk_top2), 100*mean(ct$lk_top2))
say("was already right and a cluster would merge the right answer with a relative.")
if (any(ct$lk_top2))
  print(ct[lk_top2 == TRUE, .(grant_id, top = substr(top_nm,1,32),
                              runner = substr(n2,1,32))], row.names = FALSE)

sub(); say("BY FAILURE MODE"); sub()
fm <- v[failure_mode != "", .(cases = .N,
                              top2_linked = sum(lk_top2),
                              truth_linked = sum(lk_truth)),
        by = failure_mode][order(-cases)]
print(fm, row.names = FALSE)

## ============================================ C. the relaxed error definition
hr(); say("C  WHAT DOES 'EITHER MEMBER COUNTS' CHANGE ON THE LABELLED SET?"); hr()

v[, err_strict := verdict %in% c("CORRECT_DEEPER", "NO_CORRECT", "AMBIGUOUS")]
v[, forgiven := (verdict == "CORRECT_DEEPER" & lk_truth) |
                (verdict == "AMBIGUOUS" & lk_top2)]
say("adjudicated cases                       : %d", nrow(v))
say("counted as an error today               : %d (%.0f%%)",
    sum(v$err_strict), 100*mean(v$err_strict))
say("forgiven by a disclosed-pair rule       : %d", sum(v$forgiven))
say("error rate after the relaxation         : %d (%.0f%%)",
    sum(v$err_strict) - sum(v$forgiven),
    100*(sum(v$err_strict) - sum(v$forgiven))/nrow(v))
say("")
say("of the %d errors, how many are even the right SHAPE for this fix?",
    sum(v$err_strict))
say("  NO_CORRECT (truth absent from the list) : %d - unreachable",
    sum(v$verdict == "NO_CORRECT"))
say("  CORRECT_DEEPER                          : %d", sum(v$verdict == "CORRECT_DEEPER"))
say("  AMBIGUOUS                               : %d", sum(v$verdict == "AMBIGUOUS"))

saveRDS(list(arm_pairs = u, verdicts = v),
        file.path(PF, "data-dev", "CLUSTER-LABELLED.rds"), compress = FALSE)
say(""); say("wrote data-dev/CLUSTER-LABELLED.rds")
