#!/usr/bin/env Rscript
# ============================================================================
# The promotions are the risky part, so audit them directly.
#
# Collapsing turns MAYBE into YES by removing a same-body runner-up, which
# raises the margin above min_margin. A YES is an auto-accept: it leaves the
# review queue. So every promotion has to be a pair a reviewer would also have
# called one body - otherwise the module is manufacturing false confidence,
# which is strictly worse than leaving the grant in MAYBE.
#
# Run after dev/test-dyad-cascade.R.
# ============================================================================
suppressWarnings(suppressMessages({library(data.table); library(npmatch)}))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("=", 78), "\n")
sb  <- function() cat(strrep("-", 78), "\n")
e9 <- function(z) { z <- gsub("[^0-9]", "", as.character(z))
                    fifelse(nchar(z) == 9L, z, NA_character_) }

D <- readRDS(file.path(PF, "data-dev", "PF-DYADS.rds"))
m <- readRDS(file.path(PF, "data-dev", "PF-MATCH-RESULT-50k.rds"))
cfg <- npmatch::np_config()
pr  <- npmatch::np_veto(npmatch::np_score(attr(m$result, "pairs"), cfg, method = "hier"), cfg)
base <- m
base$result <- npmatch::np_tier(npmatch::np_select(pr, cfg), cfg)
attr(base$result, "pairs") <- pr
base$config <- cfg

out <- suppressMessages(pf_dyad_collapse(base, D, pf_dyad_config(), np_config = cfg))

b <- as.data.table(as.data.frame(base$result))[, .(.id, tier0 = tier,
       e0 = overall_ein, n0 = overall_name_y, m0 = overall_margin, s0 = overall_score)]
a <- as.data.table(as.data.frame(out$result))[, .(.id, tier1 = tier,
       e1 = overall_ein, n1 = overall_name_y, m1 = overall_margin, s1 = overall_score,
       dyad_collapsed, dyad_id)]
cmp <- merge(b, a, by = ".id")
pro <- cmp[tier0 == "MAYBE" & tier1 == "YES"]

hr(); say("THE PROMOTIONS"); hr()
say("MAYBE -> YES : %s", format(nrow(pro), big.mark=","))
say("all inside a collapsed grant: %s", all(pro$dyad_collapsed))
say("")

# the removed partner, recovered from the dyad table
DD <- D[dyad_class == "substitutable"]
setkey(DD, dyad_id)
i <- match(pro$dyad_id, DD$dyad_id)
pro[, `:=`(pa = DD$ein_a[i], pb = DD$ein_b[i],
           na = DD$name_a[i], nb = DD$name_b[i],
           reason = DD$dyad_reason[i], same_city = DD$same_city[i],
           n_years = DD$n_years[i])]
pro[, dropped_nm := fifelse(e9(e1) == pa, nb, na)]

sb(); say("WHY EACH PROMOTED PAIR WAS CALLED ONE BODY"); sb()
print(pro[, .(grants = .N, pct = round(100*.N/nrow(pro),1)), by = reason][order(-grants)],
      row.names = FALSE)
say("")
say("same city  : %d (%.0f%%)", sum(pro$same_city, na.rm=TRUE),
    100*mean(pro$same_city, na.rm=TRUE))
say("disclosed in 5+ tax years: %d (%.0f%%)", sum(pro$n_years >= 5, na.rm=TRUE),
    100*mean(pro$n_years >= 5, na.rm=TRUE))

sb(); say("NAME AGREEMENT BETWEEN THE KEPT AND THE DROPPED CANDIDATE"); sb()
norm <- function(z) { z <- toupper(as.character(z)); z[is.na(z)] <- ""
  gsub(" +", " ", trimws(gsub("[^A-Z0-9 ]", " ", z))) }
STOP <- c("THE","OF","AND","INC","INCORPORATED","FOUNDATION","FUND","TRUST","CORP",
          "CORPORATION","CO","LTD","LLC","ASSOCIATION","SOCIETY","CENTER","CENTRE",
          "FOR","A","IN","INSTITUTE","SERVICES","SERVICE")
tk <- function(z) lapply(strsplit(norm(z), " "), function(w) setdiff(w, STOP))
k1 <- tk(pro$n1); k2 <- tk(pro$dropped_nm)
pro[, shared := mapply(function(p,q) length(intersect(p,q)), k1, k2)]
pro[, core_same := pf_arm_core(n1) == pf_arm_core(dropped_nm) &
                   nchar(pf_arm_core(n1)) >= 8L]
print(pro[, .(promotions = .N, pct = round(100*.N/nrow(pro),1)),
          by = .(shared_tokens = pmin(shared, 3L))][order(shared_tokens)],
      row.names = FALSE)
say("")
say("identical name core: %d (%.0f%%)", sum(pro$core_same, na.rm=TRUE),
    100*mean(pro$core_same, na.rm=TRUE))
say("no shared content token: %d (%.1f%%)  <- the ones to eyeball",
    sum(pro$shared == 0), 100*mean(pro$shared == 0))

sb(); say("EVERY PROMOTION WITH NO SHARED TOKEN"); sb()
print(pro[shared == 0, .(kept = substr(n1,1,36), dropped = substr(dropped_nm,1,36),
                         reason, same_city)], row.names = FALSE)

sb(); say("A RANDOM SAMPLE OF THE REST"); sb()
set.seed(1)
print(pro[shared > 0][sample(.N, min(20L, .N))][
      , .(kept = substr(n1,1,34), dropped = substr(dropped_nm,1,34),
          m0 = round(m0,3), m1 = round(m1,3))], row.names = FALSE)

## ---------------------------------------------------------------------------
# Why does operating-first promote more than keeping the top scorer?
#
# +704 for operating-first against +398 for keep-top is not a score effect:
# keep-top retains the highest score by construction, so it cannot be beaten on
# score. np_tier() has two other gates - min_margin and overall_veto_soft - and
# a soft veto demotes YES to MAYBE regardless of score. If the arm carries a
# soft veto more often than the operating entity (its name has an extra
# qualifier the query does not), then dropping the arm clears the gate and
# keeping it does not. This tests that.
sb(); say("WHY operating-first PROMOTES MORE THAN keep-top"); sb()
prd <- as.data.table(pr)[veto == FALSE]
prd[, ein9 := e9(.ein)]
prd <- unique(prd[!is.na(ein9)], by = c(".id", "ein9"))
pk  <- paste(prd$.id, prd$ein9)
gk  <- function(ids, eins, col) prd[[col]][match(paste(ids, eins), pk)]
pro[, dropped_ein := fifelse(e9(e1) == pa, pb, pa)]
pro[, `:=`(kept_soft     = gk(.id, e9(e1),        "veto_soft"),
           dropped_soft  = gk(.id, dropped_ein,   "veto_soft"),
           kept_score    = gk(.id, e9(e1),        "score"),
           dropped_score = gk(.id, dropped_ein,   "score"))]
say("promoted grants where the KEPT candidate carries a soft veto   : %d (%.0f%%)",
    sum(pro$kept_soft %in% TRUE), 100*mean(pro$kept_soft %in% TRUE))
say("promoted grants where the DROPPED candidate carried a soft veto: %d (%.0f%%)",
    sum(pro$dropped_soft %in% TRUE), 100*mean(pro$dropped_soft %in% TRUE))
say("")
say("kept candidate scored LOWER than the one dropped: %d (%.0f%%)",
    sum(pro$kept_score < pro$dropped_score, na.rm = TRUE),
    100*mean(pro$kept_score < pro$dropped_score, na.rm = TRUE))
say("")
say("If the dropped-soft rate is well above the kept-soft rate, the soft veto")
say("is the mechanism and the policy is doing more than reporting a preference.")

sb(); say("DID THE PICK ITSELF CHANGE ON PROMOTED GRANTS?"); sb()
say("promotions where the reported EIN also changed: %d (%.0f%%)",
    sum(pro$e0 != pro$e1), 100*mean(pro$e0 != pro$e1))
say("(the operating-first policy; where it did not change, the cascade had")
say("already ranked the operating entity first)")

sb(); say("PROMOTED GRANTS THAT ARE IN THE ADJUDICATED 100"); sb()
au <- fread(file.path(PF, "data-dev", "AUDIT-MAYBE-100.csv"), colClasses = "character")
v  <- fread(file.path(PF, "dev", "maybe-verdicts.csv"), colClasses = "character")
lab <- merge(pro[, .(.id, kept = n1, dropped = dropped_nm)], v,
             by.x = ".id", by.y = "grant_id")
say("labelled promotions: %d", nrow(lab))
if (nrow(lab)) print(lab[, .(.id, verdict, correct_rank, kept = substr(kept,1,28),
                             dropped = substr(dropped,1,28))], row.names = FALSE)

fwrite(pro[, .(.id, tier0, tier1, kept_ein = e1, kept = n1, dropped = dropped_nm,
               reason, same_city, n_years, shared, core_same,
               margin_before = m0, margin_after = m1)],
       file.path(PF, "data-dev", "DYAD-PROMOTIONS.csv"))
say(""); say("wrote data-dev/DYAD-PROMOTIONS.csv")
