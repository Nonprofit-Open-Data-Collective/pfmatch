#!/usr/bin/env Rscript
# ============================================================================
# Choose the substitutability rule.
#
# Two failure modes have to be traded off:
#   - the one-to-many supporter. "X is a 509(a)(3) supporting organization of Y"
#     is not exclusive: the YMCA Retirement Fund supports 907 local YMCAs.
#   - the federated sibling. Identical name core catches 337 chapters of
#     ALPHA LAMBDA DELTA, which are not substitutes for one another.
#
# Both show up as DEGREE. An exclusive arm relation has degree 1-3; anything
# with degree 50 is a network, and merging inside a network is wrong.
#
# Evaluated against:
#   coverage  - MAYBE top-two pairs reached, on the 50k run
#   safety    - max and tail degree in the resulting graph
#   truth     - the adjudicated 100, forgiven errors vs cases touched where the
#               cascade was already right
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("=", 78), "\n")
sub <- function() cat(strrep("-", 78), "\n")
e9 <- function(z) { z <- gsub("[^0-9]", "", as.character(z))
                    fifelse(nchar(z) == 9L, z, NA_character_) }

d <- as.data.table(unclass(readRDS(file.path(PF, "data-dev", "PF-DYADS.rds"))))

## ------------------------------------------------------------- ingredients
sa <- d[!is.na(sched_a_dir)]
sa[, supporter := fifelse(sched_a_dir == "a_supports_b", ein_a, ein_b)]
fo <- sa[, .(fan_out = .N), by = supporter]
d[, sup_ein := fifelse(is.na(sched_a_dir), NA_character_,
                fifelse(sched_a_dir == "a_supports_b", ein_a, ein_b))]
d[, fan_out := fo$fan_out[match(sup_ein, fo$supporter)]]
d[, core_same := pf_arm_core(name_a) == pf_arm_core(name_b) &
                 nchar(pf_arm_core(name_a)) >= 8L &
                 lengths(strsplit(pf_arm_core(name_a), " ")) >= 2L]
d[is.na(core_same), core_same := FALSE]
d[, ss := same_state %in% TRUE]
d[, sc := same_city  %in% TRUE]
d[, demoted := grepl("demoted", dyad_reason)]

# a degree cap, applied to the candidate edge set: an EIN that is a substitute
# for more than `cap` others is a network hub, not a body with an arm
cap_edges <- function(v, cap) {
  if (!any(v)) return(v)
  s <- d[v]
  dg <- rbind(s[, .(ein = ein_a)], s[, .(ein = ein_b)])[, .N, by = ein]
  bad <- dg[N > cap]$ein
  v & !(d$ein_a %chin% bad | d$ein_b %chin% bad)
}

RULES <- list(
  `A. sched A only (shipped v1)`   = (!is.na(d$sched_a_dir) | d$core_same) & !d$demoted,
  `B. + fan-out <= 3`              = ((!is.na(d$sched_a_dir) & d$fan_out <= 3L) | d$core_same) & !d$demoted,
  `C. B + name core needs state`   = ((!is.na(d$sched_a_dir) & d$fan_out <= 3L) | (d$core_same & d$ss)) & !d$demoted,
  `D. C + degree cap 5`            = cap_edges(((!is.na(d$sched_a_dir) & d$fan_out <= 3L) | (d$core_same & d$ss)) & !d$demoted, 5L),
  `E. C + degree cap 3`            = cap_edges(((!is.na(d$sched_a_dir) & d$fan_out <= 3L) | (d$core_same & d$ss)) & !d$demoted, 3L),
  `F. name core + same city only`  = d$core_same & d$sc & !d$demoted
)
for (r in names(RULES)) { v <- RULES[[r]]; v[is.na(v)] <- FALSE; RULES[[r]] <- v }

hr(); say("RULE SIZE AND SAFETY"); hr()
say("%-30s %9s %6s %7s %9s", "rule", "pairs", "max", "mean", "deg>10")
for (r in names(RULES)) {
  v <- RULES[[r]]; s <- d[v]
  dg <- rbind(s[, .(ein = ein_a)], s[, .(ein = ein_b)])[, .N, by = ein]
  say("%-30s %9s %6d %7.2f %9d", r, format(sum(v), big.mark=","),
      max(dg$N), mean(dg$N), sum(dg$N > 10))
}

## ------------------------------------------------------- coverage on the 50k
hr(); say("COVERAGE ON THE 50K RUN"); hr()
t2 <- fread(file.path(PF, "data-dev", "CLUSTER-TOP2.csv"),
            colClasses = list(character = c("e1","e2")))
key <- paste(d$ein_a, d$ein_b)
hit <- function(v) {
  k <- key[v]
  paste(pmin(t2$e1, t2$e2), pmax(t2$e1, t2$e2)) %chin% k
}
say("%-30s %8s %8s %8s", "rule", "MAYBE", "YES", "NO")
cov <- list()
for (r in names(RULES)) {
  h <- hit(RULES[[r]]); cov[[r]] <- h
  say("%-30s %8d %8d %8d", r, sum(h & t2$status == "MAYBE"),
      sum(h & t2$status == "YES"), sum(h & t2$status == "NO"))
}
say("")
say("(all disclosed edges, for reference : MAYBE %d  YES %d  NO %d)",
    sum(t2$lk_pool & t2$status=="MAYBE"), sum(t2$lk_pool & t2$status=="YES"),
    sum(t2$lk_pool & t2$status=="NO"))

## ------------------------------------------------------------ against truth
hr(); say("AGAINST THE ADJUDICATED 100"); hr()
a <- fread(file.path(PF, "data-dev", "AUDIT-MAYBE-100.csv"), colClasses = "character")
a[, rank := as.integer(rank)][, ein9 := e9(ein)]
v <- fread(file.path(PF, "dev", "maybe-verdicts.csv"), colClasses = "character")
v[, correct_rank := suppressWarnings(as.integer(correct_rank))]
v <- merge(v, a[rank == 1L, .(grant_id, top_ein = ein9, top_nm = cand_name)],
           by = "grant_id", all.x = TRUE)
v <- merge(v, a[rank == 2L, .(grant_id, e2 = ein9, n2 = cand_name)],
           by = "grant_id", all.x = TRUE)
v <- merge(v, a[, .(grant_id, rank, true_ein = ein9, true_nm = cand_name)],
           by.x = c("grant_id","correct_rank"), by.y = c("grant_id","rank"), all.x = TRUE)

inrule <- function(x1, x2, v_) {
  k <- key[v_]
  ok <- !is.na(x1) & !is.na(x2) & x1 != x2
  out <- rep(FALSE, length(x1))
  out[ok] <- paste(pmin(x1[ok],x2[ok]), pmax(x1[ok],x2[ok])) %chin% k
  out
}
say("%-30s %9s %9s %11s", "rule", "forgiven", "touched", "already-right")
say("%-30s %9s %9s %11s", "", "errors", "AMBIG", "touched")
for (r in names(RULES)) {
  vv <- RULES[[r]]
  lk_truth <- inrule(v$top_ein, v$true_ein, vv)
  lk_top2  <- inrule(v$top_ein, v$e2,       vv)
  forgiven <- (v$verdict == "CORRECT_DEEPER" & lk_truth) |
              (v$verdict == "AMBIGUOUS" & lk_top2)
  say("%-30s %9d %9d %11d", r, sum(forgiven),
      sum(v$verdict == "AMBIGUOUS" & lk_top2),
      sum(v$verdict == "CORRECT_TOP" & lk_top2))
}
say("")
say("'already-right touched' is the false-alarm proxy: grants the cascade got")
say("right whose runner-up the rule calls a substitute. Those stay correct, but")
say("a rule that touches many of them is asserting more than it knows.")

## ----------------------------------------------------- what the cap removes
hr(); say("WHAT THE DEGREE CAP REMOVES (rule C -> rule D)"); hr()
gone <- RULES[["C. B + name core needs state"]] & !RULES[["D. C + degree cap 5"]]
say("edges removed: %s", format(sum(gone), big.mark=","))
s <- d[RULES[["C. B + name core needs state"]]]
dg <- rbind(s[, .(ein = ein_a)], s[, .(ein = ein_b)])[, .N, by = ein][N > 5]
nm <- rbind(d[, .(ein = ein_a, nm = name_a)], d[, .(ein = ein_b, nm = name_b)])
nm <- unique(nm, by = "ein")
dg[, name := nm$nm[match(ein, nm$ein)]]
print(head(dg[order(-N)][, .(name = substr(name,1,46), degree = N)], 15), row.names = FALSE)

saveRDS(list(rules = RULES, coverage = cov),
        file.path(PF, "data-dev", "DYAD-RULE-SWEEP.rds"), compress = FALSE)
say(""); say("wrote data-dev/DYAD-RULE-SWEEP.rds")
