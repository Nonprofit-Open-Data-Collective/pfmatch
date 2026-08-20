#!/usr/bin/env Rscript
# ============================================================================
# The ordering question, on every adjudicated case available: when the candidate
# list contains a co-located operating entity AND its fundraising arm, which one
# received the grant, and does the grant purpose predict it?
#
# Two labelled sources are pooled:
#   dev/maybe-verdicts.csv        100 adjudicated MAYBE cases (correct_rank)
#   dev/enrichment-verdicts.csv    56 hard cases re-read with 990 text
# Arm pairs are detected mechanically, not from the hand-written notes.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 78), "\n")
ci  <- function(k, n) if (n == 0) "-" else
  sprintf("%.0f-%.0f%%", 100 * binom.test(k, n)$conf.int[1], 100 * binom.test(k, n)$conf.int[2])

ARM_TAIL <- paste0("(FOUNDATION|FOUND|ENDOWMENT|FUND|TRUST|AUXILIARY|GUILD|",
                   "BOOSTERS|BOOSTER CLUB|ALUMNI ASSOCIATION|ASSOCIATES|PARTNERS)")
ARM_HEAD <- "(FRIENDS OF( THE)?|SUPPORTERS OF|ASSOCIATES OF)"
norm <- function(x) { x <- toupper(as.character(x)); x[is.na(x)] <- ""
  x <- gsub("[^A-Z0-9 ]", " ", x); x <- gsub("\\bTHE\\b", " ", x)
  trimws(gsub(" +", " ", x)) }
strip_legal <- function(x) trimws(gsub("( INC| INCORPORATED| CORP| CORPORATION| CO| LTD| LLC)+$", "", x))
is_arm  <- function(x) grepl(paste0(" ", ARM_TAIL, "$"), x) | grepl(paste0("^", ARM_HEAD, " "), x)
core_of <- function(x) { x <- strip_legal(x)
  x <- sub(paste0("^", ARM_HEAD, " "), "", x)
  x <- sub(paste0(" ", ARM_TAIL, "$"), "", x)
  trimws(gsub(" +", " ", x)) }

## ---- source 1: the 100 adjudicated MAYBE cases ----------------------------
a1 <- fread(file.path(PF, "data-dev", "AUDIT-MAYBE-100.csv"), colClasses = "character")
v1 <- fread(file.path(PF, "dev", "maybe-verdicts.csv"), colClasses = "character")
s1 <- a1[, .(gid = grant_id, rank = as.integer(rank), nm = cand_name,
             st = cand_state, purpose = grant_purpose, ein)]
s1 <- merge(s1, v1[, .(gid = grant_id, correct_rank = as.integer(correct_rank))],
            by = "gid")
s1[, src := "audit100"]

## ---- source 2: the 56 hard cases re-read with text ------------------------
a2 <- fread(file.path(PF, "data-dev", "HARD-ENRICHED.csv"), colClasses = "character")
v2 <- fread(file.path(PF, "dev", "enrichment-verdicts.csv"), colClasses = "character")
v2 <- v2[outcome %in% c("RESOLVED_ALT", "RESOLVED_PICK")]
s2 <- a2[, .(gid = paste0("E", idx), rank = as.integer(rank), nm = cand_name,
             st = cand_state, purpose, ein = cand_ein, idx = as.integer(idx))]
s2 <- merge(s2, v2[, .(idx = as.integer(idx), correct_rank = as.integer(pick_ein_rank))],
            by = "idx")
s2[, `:=`(src = "enriched56", idx = NULL)]

s <- rbind(s1, s2, fill = TRUE)
s[, `:=`(n = norm(nm))][, `:=`(arm = is_arm(n), core = core_of(n))]
s[, core_ok := nchar(core) >= 8L & lengths(strsplit(core, " ")) >= 2L]

## ---- detect the pair, mechanically ----------------------------------------
pr <- s[core_ok == TRUE, .(n_arm = sum(arm), n_op = sum(!arm),
                           arm_rank = rank[arm][1], op_rank = rank[!arm][1],
                           arm_st = st[arm][1], op_st = st[!arm][1],
                           arm_nm = nm[arm][1], op_nm = nm[!arm][1],
                           correct_rank = correct_rank[1], purpose = purpose[1],
                           src = src[1]),
        by = .(gid, core)]
pr <- pr[n_arm >= 1L & n_op >= 1L & !is.na(arm_rank) & !is.na(op_rank)]
pr <- pr[!is.na(arm_st) & !is.na(op_st) & arm_st == op_st]

hr(); say("ADJUDICATED CASES CONTAINING A CO-LOCATED ARM PAIR"); hr()
say("adjudicated grants pooled          : %d", uniqueN(s$gid))
say("of those, an arm pair is present   : %d", uniqueN(pr$gid))
print(pr[, .N, by = src], row.names = FALSE)

res <- pr[!is.na(correct_rank) & (correct_rank == arm_rank | correct_rank == op_rank)]
res[, winner := fifelse(correct_rank == arm_rank, "ARM", "OPERATING")]
say("")
say("...and the adjudicated answer is one of the two members: %d", nrow(res))
hr(); say("WHICH MEMBER RECEIVED THE GRANT?"); hr()
tb <- table(factor(res$winner, c("OPERATING", "ARM")))
for (k in names(tb)) say("  %-12s %3d  (%.0f%%)", k, tb[[k]], 100 * tb[[k]] / nrow(res))
say("")
say("'operating entity by default' would be right %d of %d = %.0f%%  95%% CI %s",
    tb[["OPERATING"]], nrow(res), 100 * tb[["OPERATING"]] / nrow(res),
    ci(tb[["OPERATING"]], nrow(res)))

hr(); say("DOES THE GRANT PURPOSE PREDICT IT?"); hr()
ENDOW <- "(?i)scholarship|endowment|endowed|annual fund|capital campaign|bequest|memorial fund"
res[, purp_endow := grepl(ENDOW, purpose, perl = TRUE)]
print(res[, .(n = .N, arm_won = sum(winner == "ARM"),
              arm_pct = round(100 * mean(winner == "ARM"))),
          by = .(purpose = fifelse(purp_endow, "scholarship/endowment", "program/general/other"))],
      row.names = FALSE)
say("")
k <- res[purp_endow == TRUE, sum(winner == "ARM")]; n <- res[purp_endow == TRUE, .N]
if (n) say("purpose names a restricted gift -> arm wins %d/%d, 95%% CI %s", k, n, ci(k, n))
k2 <- res[purp_endow == FALSE, sum(winner == "OPERATING")]; n2 <- res[purp_endow == FALSE, .N]
if (n2) say("otherwise -> operating entity wins %d/%d, 95%% CI %s", k2, n2, ci(k2, n2))

hr(); say("WHAT THE CASCADE DOES TODAY, FOR COMPARISON"); hr()
res[, cascade_first := fifelse(arm_rank < op_rank, "ARM", "OPERATING")]
say("cascade ranks the correct member first in %d of %d = %.0f%%",
    sum(res$cascade_first == res$winner), nrow(res),
    100 * mean(res$cascade_first == res$winner))
say("a flat 'always take the operating entity' rule : %.0f%%", 100 * mean(res$winner == "OPERATING"))
say("purpose-conditional rule                       : %.0f%%",
    100 * mean(fifelse(res$purp_endow, "ARM", "OPERATING") == res$winner))
fwrite(res, file.path(PF, "data-dev", "ARM-ORDERING-CASES.csv"))
say("")
say("wrote data-dev/ARM-ORDERING-CASES.csv")
