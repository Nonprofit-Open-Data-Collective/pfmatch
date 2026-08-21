#!/usr/bin/env Rscript
# ============================================================================
# Phase 3 - what would a linked-EIN table actually do to the cascade?
#
# Three questions, in order of how much they matter:
#
#   1. How often is the ambiguity the cascade cannot resolve *internal to one
#      body* - i.e. the top two candidates are the same organisation reported
#      under two EINs? That is the share of the tie band a cluster id would
#      dissolve rather than adjudicate.
#   2. On the adjudicated cases, when the cascade's top pick is wrong, is the
#      right answer a linked EIN? That is the share of measured error a
#      relaxed error definition would forgive.
#   3. What does it cost? Linking two candidates that are *not* substitutes -
#      a hospital and an unrelated member of the same system - silently
#      launders a real error into a pass.
#
# Output: data-dev/CLUSTER-EVAL.rds
# ============================================================================
suppressWarnings(suppressMessages({library(data.table); library(npmatch)}))
suppressWarnings(suppressMessages(devtools::load_all(Sys.getenv("PFMATCH_DIR", "."), quiet = TRUE)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("=", 78), "\n")
sub <- function() cat(strrep("-", 78), "\n")
ci  <- function(k, n) if (n == 0) "-" else
  sprintf("%.0f-%.0f%%", 100*binom.test(k,n)$conf.int[1], 100*binom.test(k,n)$conf.int[2])

e9 <- function(z) { z <- gsub("[^0-9]", "", as.character(z))
                    fifelse(nchar(z) == 9L, z, NA_character_) }

## ------------------------------------------------------------ the link table
L  <- readRDS(file.path(PF, "data-dev", "CLUSTER-PAIRS.rds"))
P  <- L$pairs
P[, key := paste(x, y)]
POOLED <- P$key
# the 2022-only comparison set, to price what pooling buys
Y22 <- P[yr_min <= 2022 & yr_max >= 2022]$key
linked <- function(a, b, keys) paste(pmin(a,b), pmax(a,b)) %chin% keys

## --------------------------------------------------------- the candidate list
say("rebuilding the 50k candidate lists ...")
m   <- readRDS(file.path(PF, "data-dev", "PF-MATCH-RESULT-50k.rds"))
cfg <- npmatch::np_config()
pr  <- npmatch::np_veto(npmatch::np_score(attr(m$result, "pairs"), cfg, method = "hier"), cfg)
res <- npmatch::np_tier(npmatch::np_select(pr, cfg), cfg)
x   <- m; x$result <- res; attr(x$result, "pairs") <- pr; attr(x$result, "config") <- cfg
st  <- as.data.table(pf_status(x))

cd <- as.data.table(pr)[veto == FALSE]
setorder(cd, .id, -score)
cd[, rank := seq_len(.N), by = .id]
cd <- cd[rank <= 5L]
cd[, ein9 := e9(.ein)]
cd <- cd[!is.na(ein9)]
cd[, status := st$status[match(.id, st$grant_id)]]

say("grants with 2+ surviving candidates: %s",
    format(uniqueN(cd[, .N, by = .id][N >= 2]$.id), big.mark = ","))

## ============================================================ Q1: the tie band
hr(); say("Q1  IS THE UNRESOLVED AMBIGUITY INTERNAL TO ONE BODY?"); hr()

tie_band <- cfg$tie_band
say("tie band from the config: %.3f", tie_band)
say("")

top2 <- cd[rank <= 2L][, .(n = .N, e1 = ein9[1], e2 = ein9[2],
                           n1 = name_y[1], n2 = name_y[2],
                           s1 = score[1], s2 = score[2],
                           status = status[1]), by = .id][n == 2L]
top2[, close := (s1 - s2) <= tie_band]
top2[, lk_pool := linked(e1, e2, POOLED)]
top2[, lk_2022 := linked(e1, e2, Y22)]

sub(); say("TOP TWO CANDIDATES DIRECTLY DISCLOSED AS RELATED (pooled 2009-2024)"); sub()
tab <- top2[, .(grants = .N,
                linked = sum(lk_pool), pct = round(100*mean(lk_pool), 1),
                linked_2022_only = sum(lk_2022), pct_2022 = round(100*mean(lk_2022), 1)),
            by = .(status)][order(-grants)]
print(tab, row.names = FALSE)
say("")
sub(); say("...restricted to grants where the top two are inside the tie band"); sub()
tab2 <- top2[close == TRUE, .(grants = .N,
                linked = sum(lk_pool), pct = round(100*mean(lk_pool), 1),
                linked_2022_only = sum(lk_2022), pct_2022 = round(100*mean(lk_2022), 1)),
            by = .(status)][order(-grants)]
print(tab2, row.names = FALSE)

## ---------------------------------------------- collapse the whole tie band
say("")
sub(); say("DOES COLLAPSING LINKED CANDIDATES DISSOLVE THE TIE?"); sub()
band <- cd[, .SD[score >= max(score) - tie_band], by = .id]
band <- band[, if (.N >= 2L) .SD, by = .id]
say("grants with 2+ candidates in the tie band: %s", format(uniqueN(band$.id), big.mark=","))

# Union-find restricted to the candidates inside one grant, merging only on a
# DIRECT disclosed edge. No transitivity through EINs that are not themselves
# candidates for this grant - that is what produced the 67k-EIN giant component.
collapse_n <- function(e) {
  k <- length(e); if (k < 2L) return(k)
  parent <- seq_len(k)
  find <- function(i) { while (parent[i] != i) { parent[i] <- parent[parent[i]]; i <- parent[i] }; i }
  for (i in 1:(k-1)) for (j in (i+1):k)
    if (paste(pmin(e[i],e[j]), pmax(e[i],e[j])) %chin% POOLED) {
      ri <- find(i); rj <- find(j); if (ri != rj) parent[rj] <- ri
    }
  length(unique(vapply(seq_len(k), find, 1L)))
}
bs <- band[, .(n_cand = .N, n_group = collapse_n(ein9), status = status[1]), by = .id]
say("")
print(bs[, .(grants = .N,
             mean_cand = round(mean(n_cand), 2),
             mean_group = round(mean(n_group), 2),
             collapsed_any = sum(n_group < n_cand),
             pct_collapsed = round(100*mean(n_group < n_cand), 1),
             now_single = sum(n_group == 1L),
             pct_single = round(100*mean(n_group == 1L), 1)),
         by = status][order(-grants)], row.names = FALSE)

## ==================================================== Q2: the adjudicated set
hr(); say("Q2  ON THE ADJUDICATED CASES, IS THE RIGHT ANSWER A LINKED EIN?"); hr()

v <- fread(file.path(PF, "dev", "maybe-verdicts.csv"), colClasses = "character")
v[, correct_rank := suppressWarnings(as.integer(correct_rank))]
say("adjudicated MAYBE cases: %d", nrow(v))
print(v[, .N, by = verdict][order(-N)], row.names = FALSE)

cd5 <- cd[.id %in% v$grant_id]
setkey(cd5, .id, rank)
top_of  <- cd5[rank == 1L, .(gid = .id, top_ein = ein9, top_nm = name_y)]
v2 <- merge(v, top_of, by.x = "grant_id", by.y = "gid", all.x = TRUE)
crk <- cd5[, .(gid = .id, rank, ein9, name_y)]
v2 <- merge(v2, crk, by.x = c("grant_id", "correct_rank"), by.y = c("gid", "rank"),
            all.x = TRUE)
setnames(v2, c("ein9", "name_y"), c("true_ein", "true_nm"))
v2[, lk := !is.na(true_ein) & !is.na(top_ein) & top_ein != true_ein &
           linked(top_ein, true_ein, POOLED)]
v2[, lk22 := !is.na(true_ein) & !is.na(top_ein) & top_ein != true_ein &
             linked(top_ein, true_ein, Y22)]

sub(); say("CORRECT_DEEPER - the right answer was in the list but not first"); sub()
dd <- v2[verdict == "CORRECT_DEEPER"]
say("cases: %d", nrow(dd))
say("  top pick is disclosed-related to the correct one : %d (%s)",
    sum(dd$lk), ci(sum(dd$lk), nrow(dd)))
say("  ...using 2022 alone                              : %d", sum(dd$lk22))
if (nrow(dd)) print(dd[, .(grant_id, correct_rank, failure_mode,
                           top = substr(top_nm,1,32), truth = substr(true_nm,1,32),
                           linked = lk)], row.names = FALSE)

sub(); say("AMBIGUOUS - the adjudicator could not choose between candidates"); sub()
am <- v2[verdict == "AMBIGUOUS"]
say("cases: %d", nrow(am))
t2a <- top2[.id %in% am$grant_id]
say("  top two disclosed as related : %d of %d (%s)",
    sum(t2a$lk_pool), nrow(t2a), ci(sum(t2a$lk_pool), max(nrow(t2a),1)))
if (nrow(t2a)) print(t2a[, .(.id, top = substr(n1,1,30), runner = substr(n2,1,30),
                             gap = round(s1-s2,3), linked = lk_pool)], row.names = FALSE)

sub(); say("NO_CORRECT - the answer is not in the candidate list at all"); sub()
nc <- v2[verdict == "NO_CORRECT"]
t2n <- top2[.id %in% nc$grant_id]
say("cases: %d ; top two linked in %d of %d - linking cannot help these",
    nrow(nc), sum(t2n$lk_pool), nrow(t2n))

sub(); say("THE FAILURE MODES THE CLUSTER IDEA IS AIMED AT"); sub()
tgt <- c("foundation_vs_operating", "related_entities", "group_subordinates",
         "sub_unit", "self_match", "absent")
for (fm in tgt) {
  ids <- v2[failure_mode == fm]$grant_id
  tt  <- top2[.id %in% ids]
  say("  %-24s cases %2d   top-two linked %2d   (%s)", fm, length(ids),
      sum(tt$lk_pool), ci(sum(tt$lk_pool), max(nrow(tt),1)))
}

## ---------------------------------------- the arm-ordering cases, specifically
af <- file.path(PF, "data-dev", "ARM-ORDERING-CASES.csv")
if (file.exists(af)) {
  sub(); say("THE 15 ADJUDICATED ARM PAIRS (dev/ARM-ORDERING-CASES.csv)"); sub()
  ao <- fread(af, colClasses = "character")
  ao[, `:=`(arm_e = NA_character_, op_e = NA_character_)]
  # recover the EINs by rank inside the grant
  ii <- match(paste(ao$gid, ao$arm_rank), paste(cd$.id, cd$rank))
  jj <- match(paste(ao$gid, ao$op_rank),  paste(cd$.id, cd$rank))
  ao[, `:=`(arm_e = cd$ein9[ii], op_e = cd$ein9[jj])]
  ao[, lk := !is.na(arm_e) & !is.na(op_e) & linked(arm_e, op_e, POOLED)]
  ao[, lk22 := !is.na(arm_e) & !is.na(op_e) & linked(arm_e, op_e, Y22)]
  say("pairs recovered: %d of %d", sum(!is.na(ao$arm_e) & !is.na(ao$op_e)), nrow(ao))
  say("  disclosed as related, pooled : %d (%s)", sum(ao$lk), ci(sum(ao$lk), nrow(ao)))
  say("  disclosed as related, 2022   : %d", sum(ao$lk22))
  say("  cascade ranks the right one first: %d of %d",
      sum(ao$correct_rank == "1"), nrow(ao))
  say("  ...if EITHER member counts        : %d of %d",
      sum(ao$correct_rank %in% c("1","2")), nrow(ao))
  print(ao[, .(gid, arm = substr(arm_nm,1,30), op = substr(op_nm,1,26),
               correct_rank, winner, linked = lk)], row.names = FALSE)
}

## ===================================================== Q3: what does it cost?
hr(); say("Q3  WHAT DOES THE RELAXED ERROR DEFINITION COST?"); hr()

norm <- function(z) { z <- toupper(as.character(z)); z[is.na(z)] <- ""
  z <- gsub("[^A-Z0-9 ]", " ", z); trimws(gsub(" +", " ", z)) }
STOP <- c("THE","OF","AND","INC","INCORPORATED","FOUNDATION","FUND","TRUST",
          "CORP","CORPORATION","CO","LTD","LLC","ASSOCIATION","SOCIETY",
          "CENTER","CENTRE","FOR","A","IN","INSTITUTE","SERVICES","SERVICE")
toks <- function(z) lapply(strsplit(norm(z), " "), function(w) setdiff(w, STOP))

lp <- top2[lk_pool == TRUE]
t1 <- toks(lp$n1); t2 <- toks(lp$n2)
lp[, shared := mapply(function(a,b) length(intersect(a,b)), t1, t2)]
lp[, core_same := pf_arm_core(n1) == pf_arm_core(n2) & nchar(pf_arm_core(n1)) >= 8L]
sub(); say("SHARED CONTENT TOKENS AMONG LINKED TOP-TWO PAIRS"); sub()
print(lp[, .(pairs = .N, pct = round(100*.N/nrow(lp),1)),
         by = .(shared_tokens = pmin(shared, 3L))][order(shared_tokens)], row.names = FALSE)
say("")
say("linked pairs sharing NO content token   : %d (%.1f%%)",
    sum(lp$shared == 0), 100*mean(lp$shared == 0))
say("linked pairs with an identical name core: %d (%.1f%%)",
    sum(lp$core_same), 100*mean(lp$core_same))
say("")
say("examples of linked pairs with no shared token - these are the ones a")
say("relaxed error definition would wrongly forgive:")
print(head(lp[shared == 0, .(top = substr(n1,1,38), runner = substr(n2,1,38), status)], 15),
      row.names = FALSE)

deg <- rbind(P[, .(ein = x)], P[, .(ein = y)])[, .N, by = ein]
sub(); say("DEGREE OF THE CANDIDATE EINS IN THE LINK GRAPH"); sub()
cdd <- deg$N[match(unique(cd$ein9), deg$ein)]; cdd[is.na(cdd)] <- 0L
print(table(cut(cdd, c(0,1,2,3,6,11,26,Inf), right = FALSE,
                labels = c("0","1","2","3-5","6-10","11-25","26+"))))
say("candidate EINs with degree >= 26 (system hubs): %d (%.2f%%)",
    sum(cdd >= 26), 100*mean(cdd >= 26))

saveRDS(list(top2 = top2, band = bs, verdicts = v2, linked_pairs = lp),
        file.path(PF, "data-dev", "CLUSTER-EVAL.rds"), compress = FALSE)
say(""); say("wrote data-dev/CLUSTER-EVAL.rds")
