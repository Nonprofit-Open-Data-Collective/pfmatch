#!/usr/bin/env Rscript
# ============================================================================
# compare-blocking.R -- staged (state-blocked + residual sweep) vs the
# state-free baseline, on identical input.
#
# Three questions:
#   1. how much runtime does state blocking actually save?
#   2. what recall does it cost -- i.e. which grants does the baseline match
#      that the staged cascade does not, and are those matches real?
#   3. does the unblocked residual sweep (stage C) recover the cross-state cases
#      state blocking cannot see?
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
NPM <- Sys.getenv("NPMATCH_DIR", "../npmatch")
SET <- Sys.getenv("PF_SET", "1k")
PAT <- switch(SET, "1k" = "^1k_grants_.*\\.csv$", "50k" = "^50k_grants\\.csv$",
              "100k" = "^100k_grants\\.csv$", stop("bad PF_SET"))
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 74), "\n")

g   <- pf_read_grants(file.path(PF, "inputs"), pattern = PAT)
ref <- readRDS(file.path(PF, "data-dev", "BMF-REFERENCE-BUNDLE.rds"))
say("set %s: %s grants, %s in scope | reference %s records", SET,
    format(nrow(g), big.mark = ","), format(sum(g$in_scope), big.mark = ","),
    format(nrow(ref$reference), big.mark = ","))
say("grants with no state (invisible to any blocked pass): %d",
    sum(is.na(g$recip_state) & g$in_scope))

run <- function(label, passes) {
  say("\n### %s ###", label)
  m <- pf_match_grants(g, ref, passes = passes, verbose = TRUE)
  st <- pf_status(m)
  list(label = label, m = m, st = st,
       cand = sum(attr(m$result, "stages")$candidates),
       secs = m$timing[["match"]])
}

base  <- run("STATE-FREE BASELINE", pf_default_passes())
stage <- run("STAGED (A state-exact / B state-token / C unblocked sweep)",
             pf_staged_passes())

hr(); say("1. COST"); hr()
say("%-28s %12s %14s %10s", "cascade", "candidates", "cascade secs", "s/1k")
for (r in list(base, stage))
  say("%-28s %12s %14.1f %10.1f", r$label, format(r$cand, big.mark = ","),
      r$secs, r$secs / r$m$n[["in_scope"]] * 1000)
say("\nspeed-up: %.2fx   candidate reduction: %.2fx",
    base$secs / stage$secs, base$cand / stage$cand)

hr(); say("2. OUTCOMES"); hr()
cmp <- merge(data.table(grant_id = base$st$grant_id, base = base$st$status,
                        base_ein = base$st$ein, base_score = base$st$score),
             data.table(grant_id = stage$st$grant_id, staged = stage$st$status,
                        staged_ein = stage$st$ein, staged_score = stage$st$score,
                        pass = stage$st$match_pass), by = "grant_id")
print(table(baseline = cmp$base, staged = cmp$staged))
for (r in list(base, stage)) {
  t <- table(factor(r$st$status, pf_status_levels()))
  say("%-28s YES %5d  MAYBE %5d  NO %5d  OOS %4d", r$label,
      t[["YES"]], t[["MAYBE"]], t[["NO"]], t[["OOS"]])
}

hr(); say("3. RECALL COST -- baseline YES that the staged run does not accept"); hr()
lost <- cmp[base == "YES" & staged != "YES"]
say("n = %d (%.2f%% of baseline YES)", nrow(lost),
    100 * nrow(lost) / sum(cmp$base == "YES"))
if (nrow(lost)) {
  i <- match(lost$grant_id, base$st$grant_id)
  print(head(data.table(name = substr(base$st$recip_name[i], 1, 34),
                        st = base$st$recip_state[i],
                        bmf = substr(base$st$bmf_name[i], 1, 30),
                        bst = base$st$bmf_state[i],
                        base_score = lost$base_score, now = lost$staged), 20),
        row.names = FALSE)
}
gain <- cmp[base != "YES" & staged == "YES"]
say("\nstaged YES that the baseline did NOT accept: %d", nrow(gain))
say("EIN disagreements where both say YES: %d",
    nrow(cmp[base == "YES" & staged == "YES" & base_ein != staged_ein]))

hr(); say("4. WHAT EACH STAGE CONTRIBUTED"); hr()
stg <- attr(stage$m$result, "stages")
stg$stage <- pf_pass_stage(stg$pass)
print(stg[, c("stage", "pass", "criteria", "candidates", "yes", "maybe", "no", "resolved")],
      row.names = FALSE)
say("\ncandidates by stage:")
print(tapply(stg$candidates, stg$stage, sum))
say("\nresolved (YES) by stage:")
print(tapply(stg$resolved, stg$stage, sum))
say("\nfinal accepted matches by the pass that found them:")
print(sort(table(stage$st$match_pass[stage$st$status == "YES"]), decreasing = TRUE))

hr(); say("5. DID STAGE C EARN ITS KEEP?"); hr()
cs <- stage$st[stage$st$status == "YES" & grepl("^C", stage$st$match_pass), ]
say("YES matches found only by the unblocked sweep: %d", nrow(cs))
if (nrow(cs)) {
  say("  of which state disagrees: %d", sum(cs$state_agree %in% FALSE))
  say("  of which the grant had no state at all: %d", sum(is.na(cs$recip_state)))
  print(head(data.table(name = substr(cs$recip_name, 1, 32), st = cs$recip_state,
                        bmf = substr(cs$bmf_name, 1, 32), bst = cs$bmf_state,
                        zipok = cs$geo_zip5, score = cs$score), 15), row.names = FALSE)
}
saveRDS(list(base = base$st, staged = stage$st, cmp = cmp),
        file.path(PF, "data-dev", sprintf("BLOCKING-COMPARE-%s.rds", SET)))
