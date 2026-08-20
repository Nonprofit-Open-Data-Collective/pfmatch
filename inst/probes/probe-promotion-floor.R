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
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
NPM <- Sys.getenv("NPMATCH_DIR", "../npmatch")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
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
k <- match(on$st$grant_id, off$st$grant_id)
dep <- which(on$st$status == "YES" & off$st$status[k] != "YES")
say("\nYES matches that exist ONLY because of the floor: %d (%.1f%% of YES)",
    length(dep), 100 * length(dep) / tb_on[["YES"]])
say("  of those, they fall to: %s",
    paste(sprintf("%s=%d", names(table(off$st$status[k][dep])),
                  table(off$st$status[k][dep])), collapse = "  "))

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
                sc_on = on$st$score[s], sc_off = off$st$score[k][s])
print(d, row.names = FALSE)
saveRDS(list(dep_ids = on$st$grant_id[dep], on = on$st, off = off$st),
        file.path(PF, "data-dev", "PROMOTION-PROBE.rds"))
