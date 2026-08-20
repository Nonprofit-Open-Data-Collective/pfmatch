#!/usr/bin/env Rscript
# ============================================================================
# Stage 4: what do the acronym and prefix recovery passes actually convert?
#
# The only question that matters: of the grants the staged cascade leaves at NO,
# how many does stage 4 move to YES or MAYBE -- and are those moves correct?
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

say("\ncost of stage 4: +%s candidates (+%.0f%%), +%.1f s (+%.0f%%)",
    format(rec$cand - base$cand, big.mark = ","),
    100 * (rec$cand / base$cand - 1), rec$secs - base$secs,
    100 * (rec$secs / base$secs - 1))

hr(); say("WHAT MOVED"); hr()
k <- base$st$grant_id
a <- as.character(base$st$status)
b <- as.character(rec$st$status[match(k, rec$st$grant_id)])
print(table(before = a, after = b))
moved <- which(a == "NO" & b != "NO")
say("\nNO -> resolved: %d (%.1f%% of the NO tier)", length(moved),
    100 * length(moved) / sum(a == "NO"))
regress <- which(a == "YES" & b != "YES")
say("YES -> lost:    %d", length(regress))

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
