#!/usr/bin/env Rscript
# ============================================================================
# The distinctive-name promotion floor, measured on 990-PF grants.
#
# npmatch: if name similarity >= 0.95 AND the normalized name occurs in at most
# `distinct_name_maxfreq` (3) reference records, the pair's score is floored to
# 0.90 when the state agrees, 0.72 when it does not -- overriding whatever the
# address evidence said. 0.90 clears the 0.78 auto-accept gate on its own.
#
# The code comments cite ~97% reliability, but that was measured on the
# SAM/USASpending training set. This asks what it does here.
#
# SECTION 1 USED TO REPORT ONE NUMBER, AND IT COULD ONLY FLATTER THE FLOOR.
# "YES matches that exist ONLY because of the floor: N" counts what the floor
# won and nothing it cost, so the floor could not come out of this script
# looking worse than neutral. Three things are now measured beside it:
#
#   * the reverse direction -- identities that are YES only with the floor OFF.
#     A score floor is a pmax, so it cannot lower a pair's score, but it CAN
#     change which pair np_select() picks, and the selected pair's tier can
#     then fall. This is the column that can embarrass the floor, so it is
#     printed whether or not it is zero.
#   * EIN churn -- identities YES under both settings but matched to a
#     DIFFERENT EIN. The old count saw these as "no change". One of the two
#     EINs is wrong and the pipeline cannot say which, so the floor repointing
#     a cleared match is a cost even where the tier is unmoved.
#   * gross against net -- the dependency count printed next to the net tier
#     deltas it must reconcile with. A floor can only win YES, so the net move
#     IS the gross count; two numbers that disagree mean one of them is over a
#     different population (pairs rather than identities) and must say which.
#
# Both sides are read through pf_status(), the per-grant convention, where an
# identity with no pair is NO rather than absent -- said once here because a
# comparison across conventions is catalogue defect 4 (practice 5).
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
NPM <- Sys.getenv("NPMATCH_DIR", "../npmatch")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
source(file.path(PF, "dev", "assert-lib.R"))
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 74), "\n")

m <- readRDS(file.path(PF, "data-dev", "PF-MATCH-RESULT-1k.rds"))
pairs <- attr(m$result, "pairs")

score_with <- function(floor_same, floor_x) {
  cfg <- npmatch::np_config(distinct_name_floor = floor_same,
                            distinct_name_floor_xstate = floor_x)
  p <- npmatch::np_veto(npmatch::np_score(pairs, cfg, method = "hier"), cfg)
  res <- npmatch::np_tier(npmatch::np_select(p, cfg), cfg)
  x <- m; x$result <- res
  attr(x$result, "pairs") <- p; attr(x$result, "config") <- cfg
  list(st = pf_status(x), pairs = as.data.table(p))
}

on  <- score_with(0.90, 0.72)          # npmatch defaults
off <- score_with(0.00, 0.00)          # promotion disabled (pmax with 0 = no-op)

hr(); say("1. HOW MUCH OF THE YES TIER DEPENDS ON THE FLOOR?"); hr()
tb_on  <- table(factor(on$st$status,  pf_status_levels()))
tb_off <- table(factor(off$st$status, pf_status_levels()))
say("%-22s %7s %7s %7s", "", "YES", "MAYBE", "NO")
say("%-22s %7d %7d %7d", "promotion ON (default)", tb_on[["YES"]], tb_on[["MAYBE"]], tb_on[["NO"]])
say("%-22s %7d %7d %7d", "promotion OFF", tb_off[["YES"]], tb_off[["MAYBE"]], tb_off[["NO"]])

# match() on an id the other arm does not carry yields NA, and
# `"YES" & NA != "YES"` is NA, which which() drops -- so an identity that fell
# out of one arm's status frame would be silently excluded from every count
# below rather than counted as a change. Both arms rescore the SAME stored
# pairs, so the id sets must be identical; assert it rather than rely on it.
k <- match(on$st$grant_id, off$st$grant_id)
stopifnot(!anyNA(k), setequal(on$st$grant_id, off$st$grant_id))
need_rows(nrow(on$st), n = nrow(off$st),
          what = "identities in both arms, the denominator every share below uses")
need_vocab(c(on$st$status, off$st$status), pf_status_levels(),
          what = "pf_status() vocabulary on both arms")
off_st  <- off$st[k, , drop = FALSE]        # off, aligned to on, row for row
on_yes  <- on$st$status  == "YES"
off_yes <- off_st$status == "YES"

dep <- which(on_yes & !off_yes)
say("\nYES identities that exist ONLY because of the floor: %d", length(dep))
say("  as a share of YES, which base matters: %.1f%% of the %d YES WITH the floor,",
    100 * length(dep) / tb_on[["YES"]], tb_on[["YES"]])
say("  %.1f%% of the %d without it. The floor moves its own denominator, so the",
    100 * length(dep) / max(1L, tb_off[["YES"]]), tb_off[["YES"]])
say("  share is quoted on both bases rather than on whichever is flattering.")
say("  of those, they fall to: %s",
    paste(sprintf("%s=%d", names(table(off_st$status[dep])),
                  table(off_st$status[dep])), collapse = "  "))
say("  these are IDENTITIES (pf_status rows), not pairs. A pair count over the")
say("  same set is larger and is not interchangeable with it.")

# The companion columns. Each is printed whether or not it is zero: a column
# that appears only when it is non-empty cannot be read as evidence that it was
# measured, and the floor's cost is exactly what this section used to omit.
cost_set <- which(!on_yes & off_yes)
say("\nYES identities the floor COSTS (YES only with it off): %d", length(cost_set))
if (length(cost_set)) {
  say("  *** a pmax floor cannot lower a score, so these are selection moves:")
  say("  *** the floor raised a different pair past the one that was winning.")
  print(data.table(name = substr(on$st$recip_name[cost_set], 1, 33),
                   with_floor = as.character(on$st$status[cost_set]),
                   bmf_with = substr(on$st$bmf_name[cost_set], 1, 28),
                   bmf_without = substr(off_st$bmf_name[cost_set], 1, 28)),
        row.names = FALSE)
} else say("  none -- the floor took nothing out of YES on this population.")

both <- which(on_yes & off_yes)
churn <- both[!is.na(on$st$ein[both]) & !is.na(off_st$ein[both]) &
              on$st$ein[both] != off_st$ein[both]]
say("\nYES both ways but on a DIFFERENT EIN: %d of %d", length(churn), length(both))
say("  The old section 1 counted these as no change. They are not: one of the")
say("  two EINs is wrong and nothing downstream can tell which.")
if (length(churn))
  print(head(data.table(name = substr(on$st$recip_name[churn], 1, 30),
                        ein_with = on$st$ein[churn],
                        bmf_with = substr(on$st$bmf_name[churn], 1, 26),
                        ein_without = off_st$ein[churn],
                        bmf_without = substr(off_st$bmf_name[churn], 1, 26)), 20),
        row.names = FALSE)

# Gross against net. A pmax floor can only add YES, so the net YES move must
# equal gross gains minus gross losses; where it does not, one of the two
# counts is over a different population and the figure must not be published
# until it says which. This is the check that 121-against-116 needed.
net <- tb_on[["YES"]] - tb_off[["YES"]]
say("\nreconciliation: net YES move %+d = gained %d - cost %d = %+d",
    net, length(dep), length(cost_set), length(dep) - length(cost_set))
if (net != length(dep) - length(cost_set))
  say("*** THESE DISAGREE. Do not publish either until the populations are named.")
say("MAYBE %+d, NO %+d with the floor on -- a dependency count that does not",
    tb_on[["MAYBE"]] - tb_off[["MAYBE"]], tb_on[["NO"]] - tb_off[["NO"]])
say("match where these identities land is a count over the wrong population.")

hr(); say("2. WHAT EVIDENCE DO THE FLOOR-DEPENDENT MATCHES ACTUALLY HAVE?"); hr()
pr <- on$pairs
sel <- pr[paste(.id, .ein) %in% paste(on$st$grant_id[dep], on$st$ein[dep])]
z <- function(v) { v <- as.numeric(v); v[is.na(v)] <- 0; v }
say("geo evidence on the floor-dependent pairs:")
say("  ZIP5 exact ....... %4d (%.0f%%)", sum(z(sel$geo_zip5) == 1), 100 * mean(z(sel$geo_zip5) == 1))
say("  ZIP3 only ........ %4d (%.0f%%)", sum(z(sel$geo_zip3) == 1 & z(sel$geo_zip5) == 0),
    100 * mean(z(sel$geo_zip3) == 1 & z(sel$geo_zip5) == 0))
say("  state only ....... %4d (%.0f%%)", sum(z(sel$geo_state) == 1 & z(sel$geo_zip3) == 0),
    100 * mean(z(sel$geo_state) == 1 & z(sel$geo_zip3) == 0))
say("  no geo at all .... %4d (%.0f%%)",
    sum(z(sel$geo_state) == 0 & z(sel$geo_zip3) == 0 & z(sel$geo_zip5) == 0),
    100 * mean(z(sel$geo_state) == 0 & z(sel$geo_zip3) == 0 & z(sel$geo_zip5) == 0))
say("\nname_freq (how many BMF records share the name) among promoted pairs:")
print(table(as.numeric(sel$name_freq)))

hr(); say("3. IS maxfreq = 3 THE RIGHT CUTOFF?"); hr()
say("across ALL scored pairs, YES rate by name_freq:")
allp <- on$pairs
ji <- match(paste(allp$.id, allp$.ein), paste(on$st$grant_id, on$st$ein))
allp[, is_sel := !is.na(ji)]
allp[, nf := as.numeric(name_freq)]
top <- allp[is_sel == TRUE]
top[, tier := as.character(on$st$status[ji[!is.na(ji)]])]
print(top[!is.na(nf), .(n = .N, pct_yes = round(100 * mean(tier == "YES"), 1)),
          by = .(name_freq = pmin(nf, 6))][order(name_freq)], row.names = FALSE)

hr(); say("4. A SAMPLE TO HAND-CHECK"); hr()
set.seed(19)
s <- dep[sample(length(dep), min(30, length(dep)))]
d <- data.table(name = substr(on$st$recip_name[s], 1, 33),
                qcity = substr(on$st$recip_city[s], 1, 14), qst = on$st$recip_state[s],
                qz = on$st$recip_zip5[s],
                bmf = substr(on$st$bmf_name[s], 1, 33),
                bcity = substr(on$st$bmf_city[s], 1, 14), bst = on$st$bmf_state[s],
                bz = on$st$bmf_zip5[s],
                sc_on = on$st$score[s], sc_off = off_st$score[s])
print(d, row.names = FALSE)
saveRDS(list(dep_ids = on$st$grant_id[dep],
             cost_ids = on$st$grant_id[cost_set],       # YES only without the floor
             churn_ids = on$st$grant_id[churn],    # YES both ways, different EIN
             on = on$st, off = off$st),
        file.path(PF, "data-dev", "PROMOTION-PROBE.rds"))
