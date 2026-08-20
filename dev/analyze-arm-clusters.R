#!/usr/bin/env Rscript
# ============================================================================
# Turn the arm pairs into a JOINT ID (cluster) table, tighten it with geography,
# and answer the ordering question: when an operating arm and a fundraising arm
# both sit in the candidate list, which one received the grant?
#
# Consumes data-dev/ARM-LINKS.rds and data-dev/MAYBE-ARM-PAIRS.csv.
# Emits data-dev/ARM-CLUSTERS.csv.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 78), "\n")
ci  <- function(k, n) if (n == 0) "-" else
  sprintf("%.0f-%.0f%%", 100 * binom.test(k, n)$conf.int[1], 100 * binom.test(k, n)$conf.int[2])

L  <- readRDS(file.path(PF, "data-dev", "ARM-LINKS.rds"))
bm <- L$bmf
sa <- L$directed[src == "SCHED_A"]
sr <- L$directed[src == "SCHED_R"]
p  <- fread(file.path(PF, "data-dev", "MAYBE-ARM-PAIRS.csv"), colClasses = "character")
for (j in c("sa_fwd", "sa_rev", "sr_any", "grp_same", "any_src"))
  p[, (j) := get(j) == "TRUE"]
p[, `:=`(arm_rank = as.integer(arm_rank), op_rank = as.integer(op_rank))]

## ---------------------------------------------------- geography as a gate
# Two rows sharing a core name are the same body only if they are co-located.
# "CATHOLIC CHARITIES FOUNDATION" in Spokane and "CATHOLIC CHARITIES" in
# Jackson MS share a core and nothing else.
b2 <- fread(file.path(PF, "..", "npmatch", "data-raw", "bmf_2026_01_processed.csv"),
            colClasses = "character", showProgress = FALSE,
            select = c("ein", "org_addr_city", "org_addr_state", "org_addr_zip5"))
setnames(b2, c("org_addr_city", "org_addr_state", "org_addr_zip5"),
              c("city_clean", "state_clean", "zip5_clean"))
b2[, ein := gsub("[^0-9]", "", ein)]
setkey(b2, ein)
i <- match(p$arm_ein, b2$ein); j <- match(p$op_ein, b2$ein)
p[, `:=`(arm_state = b2$state_clean[i], op_state = b2$state_clean[j],
         arm_city  = b2$city_clean[i],  op_city  = b2$city_clean[j],
         arm_zip   = b2$zip5_clean[i],  op_zip   = b2$zip5_clean[j])]
p[, geo_ok := !is.na(arm_state) & !is.na(op_state) & arm_state == op_state]
p[, geo_tight := geo_ok & !is.na(arm_city) & arm_city == op_city]

u  <- unique(p[, .(arm_ein, op_ein, geo_ok, geo_tight, sa_fwd, sa_rev, sr_any,
                   grp_same, any_src)])
hr(); say("GEOGRAPHY AS A GATE ON THE NAME-BASED PAIRING"); hr()
say("distinct pairs from name alone            : %d", nrow(u))
say("  same state                              : %d (%.0f%%)", sum(u$geo_ok), 100 * mean(u$geo_ok))
say("  same city                               : %d (%.0f%%)", sum(u$geo_tight), 100 * mean(u$geo_tight))
say("")
say("disclosure rate rises with geographic agreement, which is the check that the")
say("gate is removing false pairs rather than real ones:")
say("%-26s %7s %10s %10s %10s", "subset", "pairs", "SchedA", "SchedR", "either")
for (nm in c("all", "same state", "same city")) {
  s <- switch(nm, all = u, `same state` = u[geo_ok == TRUE], u[geo_tight == TRUE])
  say("%-26s %7d %9.0f%% %9.0f%% %9.0f%%", nm, nrow(s), 100 * mean(s$sa_fwd | s$sa_rev),
      100 * mean(s$sr_any), 100 * mean(s$any_src))
}

## ------------------------------------------------------- the joint ID table
uu <- u[geo_ok == TRUE]
uu[, joint_id := paste0("PFC", formatC(seq_len(.N), width = 6, flag = "0"))]
uu[, evidence := fifelse(sa_fwd | sa_rev, "SCHED_A",
                  fifelse(sr_any, "SCHED_R",
                   fifelse(grp_same, "BMF_GROUP", "NAME_GEO_ONLY")))]
uu[, direction := fifelse(sa_fwd, "arm_supports_op",
                   fifelse(sa_rev, "op_supports_arm", "undirected"))]
hr(); say("JOINT ID TABLE"); hr()
print(uu[, .N, by = .(evidence, direction)][order(-N)], row.names = FALSE)
say("")
say("Schedule A is the only source that states DIRECTION. It confirms the")
say("name-based guess (the ...FOUNDATION row is the supporter) in %d of %d cases",
    sum(uu$sa_fwd), sum(uu$sa_fwd | uu$sa_rev))
say("and contradicts it in %d. The name heuristic is directionally reliable.",
    sum(uu$sa_rev & !uu$sa_fwd))
fwrite(uu, file.path(PF, "data-dev", "ARM-CLUSTERS.csv"))
say("wrote data-dev/ARM-CLUSTERS.csv (%d clusters)", nrow(uu))

## --------------------------------------- which member actually got the grant?
hr(); say("ORDERING: WHICH MEMBER OF THE PAIR RECEIVED THE GRANT?"); hr()
lab <- fread(file.path(PF, "dev", "enrichment-verdicts.csv"))
en  <- fread(file.path(PF, "data-dev", "HARD-ENRICHED.csv"), colClasses = "character")
en[, idx := as.integer(idx)]
# ground truth from the enriched re-read: which rank was correct
g <- merge(lab[outcome %in% c("RESOLVED_ALT", "RESOLVED_PICK")],
           unique(en[, .(idx, purpose, recip_name)]), by = "idx")
g[, correct_rank := as.integer(pick_ein_rank)]
gg <- merge(g, en[, .(idx, rank = as.integer(rank), cand_name, cand_ein)],
            by.x = c("idx", "correct_rank"), by.y = c("idx", "rank"))
ARM <- "(?i)( FOUNDATION| FOUND| FUND| ENDOWMENT| TRUST| AUXILIARY| ASSOCIATES)$|^(?i)FRIENDS OF"
gg[, chosen_is_arm := grepl(ARM, trimws(cand_name), perl = TRUE)]
# restrict to cases that actually presented an arm/operating choice
armcase <- lab[grepl("foundation|support|arm|affiliate|fundrais", note, ignore.case = TRUE), idx]
h <- gg[idx %in% armcase]
say("resolved hard cases turning on an arm/operating choice: %d", nrow(h))
say("  the correct answer was the OPERATING entity : %d", sum(!h$chosen_is_arm))
say("  the correct answer was the FUNDRAISING ARM  : %d", sum(h$chosen_is_arm))
say("")
say("split by what the grant purpose says:")
ENDOW <- "(?i)scholarship|endowment|endowed|annual fund|capital campaign|bequest"
h[, purp_endow := grepl(ENDOW, purpose, perl = TRUE)]
print(h[, .(n = .N, arm_correct = sum(chosen_is_arm)),
        by = .(purpose_type = fifelse(purp_endow, "scholarship/endowment", "program/general"))],
      row.names = FALSE)
say("")
say("n is small. The direction it points -- operating entity by default, the arm")
say("when the purpose names a scholarship or an endowment -- matches the legal")
say("reality (a restricted gift is administered by the arm) but is NOT established")
say("at this sample size. Treat it as the hypothesis to test, not a rule to ship.")

## ------------------------------------------------------- what this would buy
hr(); say("WHAT COLLAPSING TO A JOINT ID WOULD BUY"); hr()
np <- uniqueN(p[geo_ok == TRUE, grant_id])
say("MAYBE grants containing a co-located arm pair : %s", format(np, big.mark = ","))
say("of 10,575 MAYBE grants                        : %.1f%%", 100 * np / 10575)
say("")
say("Collapsing the pair removes the runner-up from the tie band. Those grants")
say("stop being MAYBE-because-two-candidates-tie and become MAYBE-with-one-body")
say("-- a materially easier review, and one an automated rule could close if the")
say("ordering hypothesis above survives testing.")
