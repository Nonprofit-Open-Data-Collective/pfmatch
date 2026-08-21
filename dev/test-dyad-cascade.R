#!/usr/bin/env Rscript
# ============================================================================
# Measure the dyad table inside a full cascade result.
#
# The 50k run is a complete pf_match: scored pairs, selection, tiers. Collapsing
# removes the losing member of each substitutable pair from the pair set and
# RE-RUNS selection and tiering, so margins and tiers move for real. That is the
# mechanism worth measuring: np_tier() demotes YES to MAYBE whenever the margin
# to the runner-up is under min_margin, and when the runner-up is the same body
# that demotion is an artefact.
#
# Reported:
#   1. tier movement, and where it comes from
#   2. policy comparison - operating / arm / top
#   3. substitutable vs related, to show why the split is load-bearing
#   4. accuracy on the adjudicated 100, strict and relaxed
#   5. the precision residual - substitutable pairs whose names share nothing
#
# Caveat stated up front: this pf_match was built against the January BMF, not
# the NCCS unified reference the package now uses. Absolute tier counts are
# therefore not the current cascade's; the deltas are what this measures.
# ============================================================================
suppressWarnings(suppressMessages({library(data.table); library(npmatch)}))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("=", 78), "\n")
sb  <- function() cat(strrep("-", 78), "\n")
ci  <- function(k, n) if (n == 0) "-" else
  sprintf("%.0f-%.0f%%", 100*binom.test(k,n)$conf.int[1], 100*binom.test(k,n)$conf.int[2])
e9 <- function(z) { z <- gsub("[^0-9]", "", as.character(z))
                    fifelse(nchar(z) == 9L, z, NA_character_) }

D <- readRDS(file.path(PF, "data-dev", "PF-DYADS.rds"))
say("dyad table: %s pairs (%s substitutable)",
    format(nrow(D), big.mark=","),
    format(sum(D$dyad_class == "substitutable"), big.mark=","))

say("loading the 50k cascade result ...")
m <- readRDS(file.path(PF, "data-dev", "PF-MATCH-RESULT-50k.rds"))
cfg <- npmatch::np_config()
pr  <- npmatch::np_veto(npmatch::np_score(attr(m$result, "pairs"), cfg, method = "hier"), cfg)
base <- m
base$result <- npmatch::np_tier(npmatch::np_select(pr, cfg), cfg)
attr(base$result, "pairs") <- pr
attr(base$result, "config") <- cfg
base$config <- cfg
say("  %s grants scored", format(nrow(base$result), big.mark=","))

tier_of <- function(x) table(factor(as.character(as.data.frame(x$result)$tier),
                                    levels = c("YES","MAYBE","NO")))
b_tier <- tier_of(base)

## ==================================================================== 1. tiers
hr(); say("1  TIER MOVEMENT"); hr()
run <- function(use, policy, label) {
  cf <- pf_dyad_config(use = use, policy = policy)
  say(""); say(">> %s", label)
  out <- pf_dyad_collapse(base, D, cf, np_config = cfg, rescore = TRUE)
  t <- tier_of(out)
  say("   YES %6d (%+d)   MAYBE %6d (%+d)   NO %6d (%+d)",
      t[["YES"]],   t[["YES"]]   - b_tier[["YES"]],
      t[["MAYBE"]], t[["MAYBE"]] - b_tier[["MAYBE"]],
      t[["NO"]],    t[["NO"]]    - b_tier[["NO"]])
  out
}
say("baseline: YES %d  MAYBE %d  NO %d", b_tier[["YES"]], b_tier[["MAYBE"]], b_tier[["NO"]])

sub_op  <- run("substitutable", "operating", "substitutable only, operating-first (proposed default)")
sub_arm <- run("substitutable", "arm",       "substitutable only, arm-first")
sub_top <- run("substitutable", "top",       "substitutable only, keep the cascade's pick")
both    <- run(c("substitutable","related"), "operating",
               "substitutable + related, operating-first (the unsafe variant)")

sb(); say("WHERE THE TIER MOVEMENT COMES FROM (proposed default)"); sb()
b <- as.data.table(as.data.frame(base$result))[, .(.id, tier0 = tier,
                                                   m0 = overall_margin, e0 = overall_ein)]
a <- as.data.table(as.data.frame(sub_op$result))[, .(.id, tier1 = tier,
                                                     m1 = overall_margin, e1 = overall_ein,
                                                     dyad_collapsed, dyad_n_before, dyad_n_after)]
cmp <- merge(b, a, by = ".id")
say("grants with a collapse : %s", format(sum(cmp$dyad_collapsed), big.mark=","))
say("  candidates removed   : %s",
    format(sum(cmp$dyad_n_before - cmp$dyad_n_after, na.rm = TRUE), big.mark=","))
say("")
mv <- cmp[tier0 != tier1, .N, by = .(tier0, tier1)][order(-N)]
print(mv, row.names = FALSE)
say("")
say("every tier change is inside a collapsed grant: %s",
    all(cmp[tier0 != tier1]$dyad_collapsed))
say("median margin before / after on collapsed grants: %.3f / %.3f",
    median(cmp[dyad_collapsed == TRUE]$m0, na.rm=TRUE),
    median(cmp[dyad_collapsed == TRUE]$m1, na.rm=TRUE))

sb(); say("MAYBE -> YES PROMOTIONS, sample"); sb()
pro <- cmp[tier0 == "MAYBE" & tier1 == "YES"]
res0 <- as.data.frame(base$result); res1 <- as.data.frame(sub_op$result)
i0 <- match(pro$.id, res0$.id); i1 <- match(pro$.id, res1$.id)
smp <- data.table(id = pro$.id,
                  kept = substr(res1$overall_name_y[i1], 1, 34),
                  was  = substr(res0$overall_name_y[i0], 1, 34),
                  margin0 = round(pro$m0, 3), margin1 = round(pro$m1, 3))
print(head(smp, 15), row.names = FALSE)

## ================================================================ 3. why split
hr(); say("3  WHY THE substitutable / related SPLIT IS LOAD-BEARING"); hr()
tb <- tier_of(both)
say("collapsing related edges too moves YES by %+d and MAYBE by %+d,",
    tb[["YES"]] - b_tier[["YES"]], tb[["MAYBE"]] - b_tier[["MAYBE"]])
say("i.e. it looks better on every headline number. It gets there by merging")
say("pairs like these, which are not substitutes:")
cb <- as.data.table(as.data.frame(both$result))[dyad_collapsed == TRUE, .(.id)]
so <- as.data.table(as.data.frame(sub_op$result))[dyad_collapsed == TRUE, .(.id)]
only_rel <- setdiff(cb$.id, so$.id)
prd <- as.data.table(pr)[veto == FALSE][.id %chin% only_rel]
setorder(prd, .id, -score)
prd[, rk := seq_len(.N), by = .id]
ex <- merge(prd[rk == 1L, .(.id, n1 = name_y, x1 = .ein)],
            prd[rk == 2L, .(.id, n2 = name_y, x2 = .ein)], by = ".id")
ex[, cls := pf_dyad_lookup(D, e9(x1), e9(x2))]
print(head(ex[cls == "related", .(top = substr(n1,1,36), runner = substr(n2,1,36))], 15),
      row.names = FALSE)
say("")
say("grants collapsed under related-too but not under substitutable-only: %s",
    format(length(only_rel), big.mark=","))

## ============================================================ 4. the labelled 100
hr(); say("4  THE ADJUDICATED 100"); hr()
au <- fread(file.path(PF, "data-dev", "AUDIT-MAYBE-100.csv"), colClasses = "character")
au[, rank := as.integer(rank)][, ein9 := e9(ein)]
v  <- fread(file.path(PF, "dev", "maybe-verdicts.csv"), colClasses = "character")
v[, correct_rank := suppressWarnings(as.integer(correct_rank))]
v <- merge(v, au[rank == 1L, .(grant_id, top_ein = ein9, top_nm = cand_name)],
           by = "grant_id", all.x = TRUE)
v <- merge(v, au[rank == 2L, .(grant_id, e2 = ein9)], by = "grant_id", all.x = TRUE)
v <- merge(v, au[, .(grant_id, rank, true_ein = ein9, true_nm = cand_name)],
           by.x = c("grant_id","correct_rank"), by.y = c("grant_id","rank"), all.x = TRUE)
v[, sub_truth := pf_dyad_lookup(D, top_ein, true_ein) == "substitutable"]
v[, sub_top2  := pf_dyad_lookup(D, top_ein, e2)       == "substitutable"]
v[is.na(sub_truth), sub_truth := FALSE][is.na(sub_top2), sub_top2 := FALSE]

err <- v$verdict %in% c("CORRECT_DEEPER","NO_CORRECT","AMBIGUOUS")
forg <- (v$verdict == "CORRECT_DEEPER" & v$sub_truth) |
        (v$verdict == "AMBIGUOUS" & v$sub_top2)
say("errors under the strict definition        : %d of 100", sum(err))
say("forgiven by 'either substitutable member' : %d", sum(forg))
say("errors after                              : %d (%s)",
    sum(err) - sum(forg), ci(sum(err)-sum(forg), 100))
say("")
say("already-correct grants whose runner-up the rule calls a substitute: %d of %d",
    sum(v$verdict == "CORRECT_TOP" & v$sub_top2), sum(v$verdict == "CORRECT_TOP"))
say("")
print(v[forg == TRUE, .(grant_id, verdict, top = substr(top_nm,1,32),
                        truth = substr(true_nm,1,32))], row.names = FALSE)
say("")
say("100 labels cannot separate rules that differ by 3 cases. This is a")
say("consistency check, not a validation; the rule was chosen on graph safety.")

## ============================================================= 5. the residual
hr(); say("5  THE PRECISION RESIDUAL"); hr()
S <- D[dyad_class == "substitutable"]
norm <- function(z) { z <- toupper(as.character(z)); z[is.na(z)] <- ""
  gsub(" +", " ", trimws(gsub("[^A-Z0-9 ]", " ", z))) }
STOP <- c("THE","OF","AND","INC","INCORPORATED","FOUNDATION","FUND","TRUST","CORP",
          "CORPORATION","CO","LTD","LLC","ASSOCIATION","SOCIETY","CENTER","CENTRE",
          "FOR","A","IN","INSTITUTE","SERVICES","SERVICE")
tk <- function(z) lapply(strsplit(norm(z), " "), function(w) setdiff(w, STOP))
k1 <- tk(S$name_a); k2 <- tk(S$name_b)
S[, shared := mapply(function(p,q) length(intersect(p,q)), k1, k2)]
say("substitutable pairs: %s", format(nrow(S), big.mark=","))
print(S[, .(pairs = .N, pct = round(100*.N/nrow(S),1)),
        by = .(shared_tokens = pmin(shared, 3L))][order(shared_tokens)], row.names = FALSE)
say("")
say("pairs sharing no content token: %s (%.1f%%) - the residual risk, and all of",
    format(sum(S$shared == 0), big.mark=","), 100*mean(S$shared == 0))
say("it from the exclusive-support path, since the name path needs a shared core.")
print(head(S[shared == 0, .(a = substr(name_a,1,36), b = substr(name_b,1,36),
                            dyad_reason, same_city)], 15), row.names = FALSE)

saveRDS(list(base = b_tier, sub_op = tier_of(sub_op), sub_arm = tier_of(sub_arm),
             sub_top = tier_of(sub_top), both = tier_of(both),
             moves = mv, labelled = v),
        file.path(PF, "data-dev", "DYAD-CASCADE-TEST.rds"), compress = FALSE)
say(""); say("wrote data-dev/DYAD-CASCADE-TEST.rds")
