#!/usr/bin/env Rscript
# ============================================================================
# Row-level retrieval: was the row that WOULD have scored actually offered?
#
# dev/NO-RESIDUAL-BLOCKING-REPLAY.csv established that the correct EIN was
# retrieved for 18 of 25 audited cases, and concluded the loss was therefore
# "downstream". That conclusion was underdetermined, because it checked EIN
# membership, not which ROW of the EIN came back. The geo terms are computed
# per row, so the distinction decides everything:
#
#   dev/GEO-CREDIT-TRACE.csv showed SALVATION ARMY BIRMINGHAM AREA COMMAND
#   (Birmingham AL, zip5 hit) scoring 0.780 while the production run recorded
#   0.6017 for that identity -- the score of the Brookhaven GA row.
#
# So for each case, score TWO candidate sets of the correct EIN:
#
#   achievable  every reference row carrying the correct EIN
#   offered     only those rows blocking actually retrieved
#
# achievable > offered  -> a row-level RETRIEVAL failure; blocking returned a
#                          weaker row of the right organisation
# achievable == offered -> the scorer had the best row and still lost; the
#                          failure is in scoring, selection or tiering
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(devtools::load_all(
  Sys.getenv("NPMATCH_DIR", "../npmatch"), quiet = TRUE)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
setDTthreads(4L)
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("-", 92))
sq  <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; x }

R  <- readRDS(file.path(PF, "data-dev", "NO-RESIDUAL-REPLAY-CANDS.rds"))
cs <- as.data.table(R$cs); union_rows <- R$union_rows; tgt_rows <- R$tgt_rows
say("cases: %d", nrow(cs))

# the production score for comparison
s <- fread(file.path(PF, "data-dev", "AUDIT-NO-RESIDUAL-100.csv"), colClasses = "character")
cs <- merge(cs, s[, .(id, prod_score = score_a, prod_ein = ein_a)], by = "id")

q <- data.frame(name = cs$recip_name, dba = "", division = "",
                street = cs$recip_street, city = cs$recip_city,
                state = cs$recip_state, zip5 = cs$recip_zip5, zip_plus4 = "",
                stringsAsFactors = FALSE)
q <- np_normalize(q)
q <- pf_add_recovery_keys(q, only_truncated = rep(TRUE, nrow(q)))
q$.id <- cs$id

ref <- pf_reference(file.path(PF, "data-dev",
        "BMF-AUGMENTED-bmf_unified_geocoded_2026-08-20.csv"),
        cache = file.path(PF, "data-dev", "BMF-REF-AUG-2026-08-20.rds"),
        verbose = FALSE)$reference
say("reference: %s rows", format(nrow(ref), big.mark = ","))

allrows <- sort(unique(unlist(tgt_rows)))
sub <- ref[allrows, , drop = FALSE]
pos <- match(seq_len(nrow(ref)), allrows)       # global row -> sub row

cfg <- np_config()
score_set <- function(qi, rows) {
  rows <- rows[!is.na(rows)]
  if (!length(rows)) return(list(best = NA_real_, nm = NA_character_,
                                 city = NA_character_, n = 0L))
  sr <- pos[rows]; sr <- sr[!is.na(sr)]
  if (!length(sr)) return(list(best = NA_real_, nm = NA_character_,
                               city = NA_character_, n = 0L))
  # .x indexes the single-row query frame passed below, so it is always 1
  cmp <- np_compare(q[qi, , drop = FALSE], sub,
                    candidates = data.frame(.x = rep(1L, length(sr)), .y = sr))
  cmp <- np_score(cmp, cfg, method = "hier")
  k <- which.max(cmp$score)
  list(best = cmp$score[k], nm = sq(cmp$name_y[k]),
       city = trimws(paste(sq(cmp$city_y[k]), sq(cmp$state_y[k]))), n = length(sr))
}

out <- vector("list", nrow(cs))
for (i in seq_len(nrow(cs))) {
  cid <- cs$id[i]
  tr  <- tgt_rows[[cid]]
  off <- intersect(union_rows[[cid]], tr)
  A <- score_set(i, tr)
  O <- score_set(i, off)
  out[[i]] <- data.table(
    id = cid, filed = cs$recip_name[i],
    n_ein_rows = length(tr), n_offered = length(off),
    ach = A$best, ach_name = A$nm, ach_loc = A$city,
    off_best = O$best, off_name = O$nm, off_loc = O$city,
    prod = as.numeric(cs$prod_score[i]))
}
d <- rbindlist(out)
d[, gap := ach - fifelse(is.na(off_best), 0, off_best)]
d[, verdict := fcase(
  n_offered == 0L,                         "row never offered",
  !is.na(gap) & gap > 0.01,                "better row existed, not offered",
  default                                = "best row was offered")]

hr()
say("ROW-LEVEL RETRIEVAL ON THE CORRECT EIN")
hr()
print(d[, .N, by = verdict][order(-N)], row.names = FALSE)
hr()
say("%-9s %-26s %5s %5s %6s %6s %6s  %s", "id", "filed", "rows", "offd",
    "achiev", "offerd", "prod", "best achievable row")
setorder(d, -gap)
for (i in seq_len(nrow(d)))
  say("%-9s %-26s %5d %5d %6s %6s %6s  %s / %s", d$id[i],
      substr(d$filed[i], 1, 26), d$n_ein_rows[i], d$n_offered[i],
      ifelse(is.na(d$ach[i]), "  -", sprintf("%.3f", d$ach[i])),
      ifelse(is.na(d$off_best[i]), "  -", sprintf("%.3f", d$off_best[i])),
      ifelse(is.na(d$prod[i]), "  -", sprintf("%.3f", d$prod[i])),
      substr(sq(d$ach_name[i]), 1, 34), sq(d$ach_loc[i]))

hr()
th <- cfg$thresholds
say("WHAT THE ACHIEVABLE BEST WOULD HAVE TIERED AS (yes %.2f / maybe %.2f)",
    th[["yes"]], th[["maybe"]])
hr()
d[, ach_tier := fcase(is.na(ach), "none", ach >= th[["yes"]], "YES",
                      ach >= th[["maybe"]], "MAYBE", default = "NO")]
d[, off_tier := fcase(is.na(off_best), "none", off_best >= th[["yes"]], "YES",
                      off_best >= th[["maybe"]], "MAYBE", default = "NO")]
print(dcast(d[, .N, by = .(off_tier, ach_tier)], off_tier ~ ach_tier,
            value.var = "N", fill = 0), row.names = FALSE)
fwrite(d, file.path(PF, "data-dev", "ROW-LEVEL-REPLAY.csv"))
hr()
say("wrote data-dev/ROW-LEVEL-REPLAY.csv")
