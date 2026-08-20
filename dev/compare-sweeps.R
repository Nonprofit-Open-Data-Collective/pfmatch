#!/usr/bin/env Rscript
# Four cascade configurations on identical input: what does each unit of extra
# candidate generation actually buy?
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
say("set %s: %s grants, %s in scope", SET, format(nrow(g), big.mark = ","),
    format(sum(g$in_scope), big.mark = ","))

cfgs <- list(
  "state-free baseline" = pf_default_passes(),
  "staged: none"        = pf_staged_passes("none"),
  "staged: lean"        = pf_staged_passes("lean"),
  "staged: full"        = pf_staged_passes("full"))

res <- lapply(names(cfgs), function(nm) {
  say("\n>>> %s", nm)
  m <- pf_match_grants(g, ref, passes = cfgs[[nm]], verbose = FALSE)
  st <- pf_status(m)
  t <- table(factor(st$status, pf_status_levels()))
  list(nm = nm, st = st, secs = m$timing[["match"]],
       cand = sum(attr(m$result, "stages")$candidates),
       yes = t[["YES"]], maybe = t[["MAYBE"]], no = t[["NO"]], n = m$n[["in_scope"]])
})
names(res) <- names(cfgs)

hr(); say("COST vs YIELD"); hr()
say("%-22s %11s %8s %7s %7s %7s %10s", "config", "candidates", "secs", "YES", "MAYBE", "NO", "cand/YES")
for (r in res)
  say("%-22s %11s %8.1f %7d %7d %7d %10.0f", r$nm, format(r$cand, big.mark = ","),
      r$secs, r$yes, r$maybe, r$no, r$cand / r$yes)

b <- res[["state-free baseline"]]
say("\nrelative to the state-free baseline:")
for (r in res[-1])
  say("  %-22s %5.2fx faster  %5.2fx fewer candidates  YES %+d  MAYBE %+d",
      r$nm, b$secs / r$secs, b$cand / r$cand, r$yes - b$yes, r$maybe - b$maybe)

hr(); say("DO THE CONFIGS AGREE ON WHICH GRANTS ARE YES?"); hr()
key <- b$st$grant_id
mat <- sapply(res, function(r) as.character(r$st$status[match(key, r$st$grant_id)]))
for (nm in names(res)[-1]) {
  lost <- sum(mat[, "state-free baseline"] == "YES" & mat[, nm] != "YES")
  gain <- sum(mat[, "state-free baseline"] != "YES" & mat[, nm] == "YES")
  ein_b <- b$st$ein[match(key, b$st$grant_id)]
  ein_r <- res[[nm]]$st$ein[match(key, res[[nm]]$st$grant_id)]
  disagree <- sum(mat[, "state-free baseline"] == "YES" & mat[, nm] == "YES" &
                  !is.na(ein_b) & !is.na(ein_r) & ein_b != ein_r)
  say("  %-22s baseline-YES lost %3d | new YES %3d | EIN disagreements %d",
      nm, lost, gain, disagree)
}

hr(); say("PROJECTION TO 12.5M GRANTS (identities after ~1.8x dedup = 7.0M)"); hr()
for (r in res) {
  rate <- r$secs / r$n * 1000
  say("  %-22s %6.1f s/1k -> %5.0f h  (%.0f h with 16-way parallelism)",
      r$nm, rate, 7.0e6 / 1000 * rate / 3600, 7.0e6 / 1000 * rate / 3600 / 16)
}
saveRDS(res, file.path(PF, "data-dev", sprintf("SWEEP-COMPARE-%s.rds", SET)))
