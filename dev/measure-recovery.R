#!/usr/bin/env Rscript
# ============================================================================
# Stage 4: what do the acronym and prefix recovery passes actually convert?
#
# The only question that matters: of the grants the staged cascade leaves at NO,
# how many does stage 4 move to YES or MAYBE -- and are those moves correct?
#
# "WHAT MOVED" reports three columns, not one. A recovery count on its own
# cannot come out against stage 4: the status comparison sees a YES re-pointed
# to a different EIN as no change at all, and the NO-tier share, if denominated
# after the pass, shrinks its base by exactly the recoveries. So the gain is
# printed beside the YES it lost and the YES it silently re-pointed, on the
# before-count base. dev/compare-blocking.R already did this; this did not.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
NPM <- Sys.getenv("NPMATCH_DIR", "../npmatch")
SET <- Sys.getenv("PF_SET", "1k")
PAT <- switch(SET, "1k" = "^1k_grants_.*\\.csv$", "50k" = "^50k_grants\\.csv$",
              "100k" = "^100k_grants\\.csv$", stop("bad PF_SET"))
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
source(file.path(PF, "dev", "assert-lib.R"))
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 74), "\n")

g   <- pf_read_grants(file.path(PF, "inputs"), pattern = PAT)
g   <- pf_recover_name_from_street(g)
ref <- readRDS(file.path(PF, "data-dev", "BMF-REFERENCE-BUNDLE.rds"))

run <- function(nm, passes, recover) {
  m <- pf_match_grants(g, ref, passes = passes, recover = recover, verbose = FALSE)
  st <- pf_status(m)
  t <- table(factor(st$status, pf_status_levels()))
  say("  %-20s %10s cand %7.1f s | YES %4d MAYBE %4d NO %4d", nm,
      format(sum(attr(m$result, "stages")$candidates), big.mark = ","),
      m$timing[["match"]], t[["YES"]], t[["MAYBE"]], t[["NO"]])
  list(nm = nm, m = m, st = st, secs = m$timing[["match"]],
       cand = sum(attr(m$result, "stages")$candidates))
}

hr(); say("STAGE 4 ON vs OFF (staged lean base)"); hr()
base <- run("lean",            pf_staged_passes("lean"), recover = FALSE)
rec  <- run("lean + stage 4",  c(pf_staged_passes("lean"),
                                 pf_recovery_passes(state = TRUE)), recover = TRUE)

# The sign belongs to the number. A hard-coded plus renders a negative as
# "+-3.2 s", which reads as a typo where "-3.2 s" is a finding: the time cost
# of an extra pass is not guaranteed positive. `%+s` is not a valid R format,
# so the signed count is built rather than formatted.
sgn <- function(x) paste0(if (x < 0) "-" else "+", format(abs(x), big.mark = ","))
say("\ncost of stage 4: %s candidates (%+.0f%%), %+.1f s (%+.0f%%)",
    sgn(rec$cand - base$cand),
    100 * (rec$cand / base$cand - 1), rec$secs - base$secs,
    100 * (rec$secs / base$secs - 1))

hr(); say("WHAT MOVED"); hr()
k <- base$st$grant_id
j <- match(k, rec$st$grant_id)
# match() returns NA for an id the stage-4 run does not carry, and `"NO" & NA`
# is NA, which which() drops -- the recovery count would then omit exactly the
# identities that went missing. Both arms run over the same grant file, so
# assert the id sets agree instead of trusting the join.
stopifnot(!anyNA(j), setequal(k, rec$st$grant_id))
need_rows(nrow(base$st), n = nrow(rec$st),
          what = "identities in both arms, the base the NO-tier share uses")
a <- as.character(base$st$status)
b <- as.character(rec$st$status[j])
need_vocab(c(a, b), pf_status_levels(), what = "pf_status() vocabulary, both arms")
print(table(before = a, after = b))
moved <- which(a == "NO" & b != "NO")
say("\nNO -> resolved: %d (%.1f%% of the %d-identity NO tier BEFORE stage 4 --",
    length(moved), 100 * length(moved) / sum(a == "NO"), sum(a == "NO"))
say("  the base is fixed at the before count on purpose: denominating on the")
say("  after count shrinks the base by exactly the recoveries and inflates it)")
regress <- which(a == "YES" & b != "YES")
say("YES -> lost:    %d", length(regress))

# The companion column dev/compare-blocking.R already carries and this script
# did not: an identity YES before and after, on a DIFFERENT EIN. Stage 4 can
# generate a candidate that outscores the one the lean cascade accepted, and a
# status comparison reads that as no change. One of the two EINs is wrong.
# Printed whether or not it is zero -- a column that appears only when it fires
# cannot be read as evidence that it was measured.
both  <- which(a == "YES" & b == "YES")
ein_a <- base$st$ein[both]; ein_b <- rec$st$ein[j][both]
churn <- both[!is.na(ein_a) & !is.na(ein_b) & ein_a != ein_b]
say("YES -> re-pointed to a different EIN: %d of %d YES both ways",
    length(churn), length(both))
if (length(churn))
  print(head(data.table(name = substr(base$st$recip_name[churn], 1, 30),
                        was_ein = base$st$ein[churn],
                        was = substr(base$st$bmf_name[churn], 1, 26),
                        now_ein = rec$st$ein[j][churn],
                        now = substr(rec$st$bmf_name[j][churn], 1, 26),
                        pass = rec$st$match_pass[j][churn]), 20), row.names = FALSE)

hr(); say("THE CONVERSIONS (hand-check these)"); hr()
if (length(moved)) {
  i <- match(k[moved], rec$st$grant_id)
  d <- data.table(name = substr(rec$st$recip_name[i], 1, 34),
                  st = rec$st$recip_state[i],
                  bmf = substr(rec$st$bmf_name[i], 1, 40),
                  bst = rec$st$bmf_state[i],
                  zip = rec$st$geo_zip5[i],
                  score = rec$st$score[i],
                  pass = rec$st$match_pass[i],
                  now = b[moved])
  setorder(d, -score)
  print(head(d, 30), row.names = FALSE)
  say("\nby pass:"); print(table(d$pass, d$now))
}
if (length(regress)) {
  say("\nREGRESSIONS (stage 4 displaced a previously accepted match):")
  i <- match(k[regress], rec$st$grant_id)
  print(data.table(name = substr(base$st$recip_name[match(k[regress], base$st$grant_id)], 1, 30),
                   was = substr(base$st$bmf_name[match(k[regress], base$st$grant_id)], 1, 30),
                   now_status = b[regress],
                   now = substr(rec$st$bmf_name[i], 1, 30)), row.names = FALSE)
}
saveRDS(list(base = base$st, rec = rec$st), file.path(PF, "data-dev",
        sprintf("RECOVERY-COMPARE-%s.rds", SET)))
