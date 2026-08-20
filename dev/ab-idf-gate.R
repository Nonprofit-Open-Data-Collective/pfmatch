#!/usr/bin/env Rscript
# Clean A/B for distinct_name_min_idf: same pairs, same everything, only the
# gate varies. Rescoring the stored pairs avoids re-blocking, so nothing else
# can move.
suppressWarnings(suppressMessages(library(data.table)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 74), "\n")

m <- readRDS(file.path(PF, "data-dev", "PF-MATCH-RESULT-1k.rds"))
pairs <- attr(m$result, "pairs")
if (is.null(pairs$name_idf)) {
  say("stored pairs predate the name_idf column -- rerun PF_SET=1k first"); quit(save = "no")
}
say("pairs carry name_idf: %s non-missing of %s",
    format(sum(!is.na(pairs$name_idf)), big.mark = ","), format(nrow(pairs), big.mark = ","))

run <- function(thr) {
  cfg <- npmatch::np_config(distinct_name_min_idf = thr)
  p <- npmatch::np_veto(npmatch::np_score(pairs, cfg, method = "hier"), cfg)
  res <- npmatch::np_tier(npmatch::np_select(p, cfg), cfg)
  x <- m; x$result <- res
  attr(x$result, "pairs") <- p; attr(x$result, "config") <- cfg
  pf_status(x)
}
off <- run(0); on <- run(10)

hr(); say("A/B: distinct_name_min_idf 0 vs 10 (identical pairs)"); hr()
for (nm in c("off", "on")) {
  s <- get(nm); t <- table(factor(s$status, pf_status_levels()))
  say("min_idf = %-3s  YES %5d  MAYBE %5d  NO %5d", if (nm == "off") "0" else "10",
      t[["YES"]], t[["MAYBE"]], t[["NO"]])
}
k <- match(off$grant_id, on$grant_id)
moved <- which(off$status == "YES" & on$status[k] != "YES")
say("\nYES -> demoted by the gate: %d", length(moved))
if (length(moved))
  print(data.table(name = substr(off$recip_name[moved], 1, 32),
                   bmf = substr(off$bmf_name[moved], 1, 32),
                   qcity = substr(off$recip_city[moved], 1, 14),
                   bcity = substr(on$bmf_city[k][moved], 1, 14),
                   now = as.character(on$status[k][moved])), row.names = FALSE)
gained <- sum(off$status != "YES" & on$status[k] == "YES")
say("\nYES gained (should be 0): %d", gained)
