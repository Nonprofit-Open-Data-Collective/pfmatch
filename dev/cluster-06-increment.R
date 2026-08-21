#!/usr/bin/env Rscript
# ============================================================================
# Phase 4 - the increment over what is already shipped, and the exposure.
#
# R/affiliation.R already clusters a candidate list on name core + geography,
# with no disclosure data at all. The question that decides whether a linked-EIN
# table is worth building is not "how many pairs does disclosure find" but
# "how many does it find that pf_cluster_arms() does not".
#
# Also priced here:
#   - the dollar value of the grants whose top two candidates are linked
#   - a safe gate: direct edge AND a name rule, vs direct edge alone
#   - the hub problem, at candidate level rather than graph level
# ============================================================================
suppressWarnings(suppressMessages({library(data.table); library(npmatch)}))
suppressWarnings(suppressMessages(devtools::load_all(Sys.getenv("PFMATCH_DIR", "."), quiet = TRUE)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("=", 78), "\n")
sub <- function() cat(strrep("-", 78), "\n")
e9 <- function(z) { z <- gsub("[^0-9]", "", as.character(z))
                    fifelse(nchar(z) == 9L, z, NA_character_) }

L <- readRDS(file.path(PF, "data-dev", "CLUSTER-PAIRS.rds"))
P <- L$pairs; P[, key := paste(x, y)]
POOLED <- P$key
E <- readRDS(file.path(PF, "data-dev", "CLUSTER-EVAL.rds"))
t2 <- E$top2

BMF <- file.path(PF, "..", "npmatch", "data-raw", "bmf_2026_01_processed.csv")
bm <- fread(BMF, colClasses = "character", showProgress = FALSE,
            select = c("ein","org_addr_city","org_addr_state"))
setnames(bm, c("ein","city","state")); bm[, ein := gsub("[^0-9]","",ein)]
bm <- unique(bm, by = "ein")
gcol <- function(e, f) bm[[f]][match(e, bm$ein)]

t2[, `:=`(st1 = gcol(e1,"state"), st2 = gcol(e2,"state"),
          ct1 = gcol(e1,"city"),  ct2 = gcol(e2,"city"))]
t2[, same_state := !is.na(st1) & st1 == st2]
t2[, same_city  := same_state & !is.na(ct1) & ct1 == ct2]

## --------------------------------------- the shipped, disclosure-free rule
t2[, `:=`(core1 = pf_arm_core(n1), core2 = pf_arm_core(n2),
          arm1 = pf_is_arm(n1),    arm2 = pf_is_arm(n2))]
t2[, name_rule := core1 == core2 & nchar(core1) >= 8L &
                  lengths(strsplit(core1, " ")) >= 2L &
                  (arm1 != arm2) & same_state]
# a deliberately generous variant: same core, same state, no arm/non-arm split
t2[, name_rule_loose := core1 == core2 & nchar(core1) >= 8L & same_state]

hr(); say("DISCLOSURE VS THE NAME RULE ALREADY IN R/affiliation.R"); hr()
say("top-two pairs examined: %s", format(nrow(t2), big.mark=","))
say("")
for (s in c("MAYBE","YES","NO")) {
  d <- t2[status == s]
  say("%s (n = %s)", s, format(nrow(d), big.mark=","))
  say("   pf_cluster_arms name rule (arm/op + same state) : %5d (%4.1f%%)",
      sum(d$name_rule), 100*mean(d$name_rule))
  say("   generous name rule (same core + same state)     : %5d (%4.1f%%)",
      sum(d$name_rule_loose), 100*mean(d$name_rule_loose))
  say("   disclosed edge (pooled Sch A + Sch R)           : %5d (%4.1f%%)",
      sum(d$lk_pool), 100*mean(d$lk_pool))
  say("   union                                           : %5d (%4.1f%%)",
      sum(d$lk_pool | d$name_rule_loose), 100*mean(d$lk_pool | d$name_rule_loose))
  say("   DISCLOSURE ONLY - the honest increment          : %5d (%4.1f%%)",
      sum(d$lk_pool & !d$name_rule_loose), 100*mean(d$lk_pool & !d$name_rule_loose))
  say("   name rule only - unconfirmed by any filing      : %5d (%4.1f%%)",
      sum(!d$lk_pool & d$name_rule_loose), 100*mean(!d$lk_pool & d$name_rule_loose))
  say("")
}

sub(); say("WHAT THE DISCLOSURE-ONLY PAIRS LOOK LIKE (MAYBE tier)"); sub()
only <- t2[status == "MAYBE" & lk_pool & !name_rule_loose]
print(head(only[, .(top = substr(n1,1,36), runner = substr(n2,1,36),
                    same_city, gap = round(s1-s2,2))], 20), row.names = FALSE)

## ------------------------------------------------------------- a safe gate
hr(); say("GATING THE EDGE: DIRECT LINK ALONE VS LINK + A LOCALITY TEST"); hr()
norm <- function(z) { z <- toupper(as.character(z)); z[is.na(z)] <- ""
  gsub(" +", " ", trimws(gsub("[^A-Z0-9 ]", " ", z))) }
STOP <- c("THE","OF","AND","INC","INCORPORATED","FOUNDATION","FUND","TRUST","CORP",
          "CORPORATION","CO","LTD","LLC","ASSOCIATION","SOCIETY","CENTER","CENTRE",
          "FOR","A","IN","INSTITUTE","SERVICES","SERVICE","INTERNATIONAL","NATIONAL")
tk <- function(z) lapply(strsplit(norm(z), " "), function(w) setdiff(w, STOP))
k1 <- tk(t2$n1); k2 <- tk(t2$n2)
t2[, shared := mapply(function(a,b) length(intersect(a,b)), k1, k2)]

gates <- list(
  `edge only`                      = t2$lk_pool,
  `edge + same state`              = t2$lk_pool & t2$same_state,
  `edge + same city`               = t2$lk_pool & t2$same_city,
  `edge + 1 shared content token`  = t2$lk_pool & t2$shared >= 1,
  `edge + same city + 1 token`     = t2$lk_pool & t2$same_city & t2$shared >= 1,
  `edge + identical name core`     = t2$lk_pool & t2$core1 == t2$core2 & nchar(t2$core1) >= 8L
)
say("%-32s %8s %8s %8s %8s", "gate", "MAYBE", "YES", "NO", "%kept")
for (g in names(gates)) {
  v <- gates[[g]]
  say("%-32s %8d %8d %8d %7.0f%%", g,
      sum(v & t2$status == "MAYBE"), sum(v & t2$status == "YES"),
      sum(v & t2$status == "NO"), 100*sum(v)/sum(t2$lk_pool))
}

## --------------------------------------------------------------- exposure
hr(); say("DOLLAR EXPOSURE"); hr()
m <- readRDS(file.path(PF, "data-dev", "PF-MATCH-RESULT-50k.rds"))
g <- as.data.table(m$grants)[, .(grant_id, amt = suppressWarnings(as.numeric(SIGOCPYAMOUN)))]
t2m <- merge(t2, g, by.x = ".id", by.y = "grant_id", all.x = TRUE)
tot <- sum(g$amt, na.rm = TRUE)
say("total granted in the 50k sample            : $%s", format(round(tot), big.mark=","))
for (s in c("MAYBE","YES","NO")) {
  d <- t2m[status == s]
  say("%-6s grants with a linked top two        : %5d   $%14s  (%.1f%% of all dollars)",
      s, sum(d$lk_pool),
      format(round(sum(d$amt[d$lk_pool], na.rm = TRUE)), big.mark=","),
      100*sum(d$amt[d$lk_pool], na.rm=TRUE)/tot)
}
say("")
say("median grant, linked top two vs not (MAYBE): $%s vs $%s",
    format(round(median(t2m[status=="MAYBE" & lk_pool == TRUE]$amt, na.rm=TRUE)), big.mark=","),
    format(round(median(t2m[status=="MAYBE" & lk_pool == FALSE]$amt, na.rm=TRUE)), big.mark=","))

## ------------------------------------------------------------- the hubs
hr(); say("THE HUB PROBLEM AT CANDIDATE LEVEL"); hr()
deg <- rbind(P[, .(ein = x)], P[, .(ein = y)])[, .N, by = ein]
t2[, `:=`(d1 = deg$N[match(e1, deg$ein)], d2 = deg$N[match(e2, deg$ein)])]
t2[is.na(d1), d1 := 0L][is.na(d2), d2 := 0L]
lp <- t2[lk_pool == TRUE]
say("linked top-two pairs: %d", nrow(lp))
say("  where at least one member has degree >= 26 : %d (%.1f%%)",
    sum(pmax(lp$d1, lp$d2) >= 26), 100*mean(pmax(lp$d1,lp$d2) >= 26))
say("  where at least one member has degree >= 100: %d (%.1f%%)",
    sum(pmax(lp$d1, lp$d2) >= 100), 100*mean(pmax(lp$d1,lp$d2) >= 100))
say("")
say("the highest-degree candidates that a cluster id would swallow:")
hub <- rbind(lp[, .(ein = e1, nm = n1, d = d1)], lp[, .(ein = e2, nm = n2, d = d2)])
print(head(unique(hub, by = "ein")[order(-d)][, .(nm = substr(nm,1,44), degree = d)], 12),
      row.names = FALSE)

fwrite(t2, file.path(PF, "data-dev", "CLUSTER-TOP2.csv"))
say(""); say("wrote data-dev/CLUSTER-TOP2.csv")
