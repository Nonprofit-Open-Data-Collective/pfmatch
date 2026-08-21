#!/usr/bin/env Rscript
# ============================================================================
# Phase 5 - the finding that fell out of the adjudicated set.
#
# The AMBIGUOUS bucket is not mostly operating-vs-arm. It is mostly two BMF
# rows carrying the SAME name for the same body - "Purdue University" twice,
# "Texas State University" twice, "Univ Of North Carolina At Charlotte" twice.
# No affiliation disclosure can link an organisation to itself, so a linked-EIN
# table is the wrong instrument for the largest part of the tie band.
#
# This sizes that population against the disclosure population.
# ============================================================================
suppressWarnings(suppressMessages({library(data.table); library(npmatch)}))
suppressWarnings(suppressMessages(devtools::load_all(Sys.getenv("PFMATCH_DIR", "."), quiet = TRUE)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("=", 78), "\n")
sub <- function() cat(strrep("-", 78), "\n")

t2 <- fread(file.path(PF, "data-dev", "CLUSTER-TOP2.csv"), colClasses = list(character = c("e1","e2")))
norm <- function(z) { z <- toupper(as.character(z)); z[is.na(z)] <- ""
  z <- gsub("\\b(INC|INCORPORATED|CORP|CORPORATION|CO|LTD|LLC|THE)\\b", " ", z)
  gsub(" +", " ", trimws(gsub("[^A-Z0-9 ]", " ", z))) }
t2[, `:=`(q1 = norm(n1), q2 = norm(n2))]
t2[, same_name := q1 == q2 & nchar(q1) >= 6L]

hr(); say("TWO EINS, ONE NAME: THE OTHER HALF OF THE TIE BAND"); hr()
for (s in c("MAYBE","YES","NO")) {
  d <- t2[status == s]
  say("%-6s n=%6s  identical normalised name %5d (%4.1f%%)  of which disclosed-linked %4d (%2.0f%%)",
      s, format(nrow(d), big.mark=","), sum(d$same_name), 100*mean(d$same_name),
      sum(d$same_name & d$lk_pool),
      100*sum(d$same_name & d$lk_pool)/max(sum(d$same_name),1))
}
say("")
say("A disclosure edge cannot exist between an organisation and itself, so the")
say("identical-name population is unreachable by any linked-EIN table.")
say("")

sub(); say("THE THREE POPULATIONS IN THE MAYBE TIE BAND, DISJOINT"); sub()
d <- t2[status == "MAYBE"]
d[, bucket := fifelse(same_name, "same name, two EINs",
              fifelse(lk_pool & name_rule_loose, "arm pair, name AND disclosure",
              fifelse(lk_pool, "disclosure only",
              fifelse(name_rule_loose, "name only, unconfirmed", "neither"))))]
b <- d[, .(grants = .N, pct = round(100*.N/nrow(d), 1)), by = bucket][order(-grants)]
print(b, row.names = FALSE)
say("")
say("same-name examples (different EINs, indistinguishable names):")
print(head(d[same_name == TRUE, .(name = substr(n1,1,42), e1, e2,
                                  same_city, gap = round(s1-s2,2))], 15), row.names = FALSE)

sub(); say("HOW OFTEN IS THE SAME-NAME PAIR ALSO SAME-CITY?"); sub()
sn <- d[same_name == TRUE]
say("same city  : %d (%.0f%%)  - almost certainly one body, two BMF rows",
    sum(sn$same_city), 100*mean(sn$same_city))
say("same state : %d (%.0f%%)", sum(sn$same_state), 100*mean(sn$same_state))
say("different state: %d (%.0f%%) - chapters or unrelated namesakes",
    sum(!sn$same_state), 100*mean(!sn$same_state))
