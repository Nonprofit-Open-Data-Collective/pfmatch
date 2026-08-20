#!/usr/bin/env Rscript
# An exact name plus a shared ZIP3 currently scores 0.6*1.0 + 0.4*0.55 = 0.82,
# clearing the 0.78 auto-accept gate with no real address corroboration. What
# happens if ZIP3 is weighted below the level that can carry a pair over on its
# own (w < 0.45)?
suppressWarnings(suppressMessages(library(data.table)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
NPM <- Sys.getenv("NPMATCH_DIR", "../npmatch")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 74), "\n")

m <- readRDS(file.path(PF, "data-dev", "PF-MATCH-RESULT-1k.rds"))
pairs <- attr(m$result, "pairs")

run <- function(w) {
  gw <- npmatch::np_default_geo_weights(); gw[["zip3"]] <- w
  cfg <- npmatch::np_config(geo_weights = gw)
  p <- npmatch::np_score(pairs, cfg, method = "hier")
  p <- npmatch::np_veto(p, cfg)
  res <- npmatch::np_tier(npmatch::np_select(p, cfg), cfg)
  x <- m; x$result <- res
  attr(x$result, "pairs") <- p; attr(x$result, "config") <- cfg
  pf_status(x)
}

hr(); say("ZIP3 WEIGHT SWEEP"); hr()
say("%-8s %8s %8s %8s %8s", "zip3 w", "YES", "MAYBE", "NO", "YES->MAYBE")
base <- run(0.55)
for (w in c(0.55, 0.50, 0.44, 0.40, 0.30)) {
  s <- run(w)
  tb <- table(factor(s$status, pf_status_levels()))
  moved <- sum(base$status == "YES" & s$status[match(base$grant_id, s$grant_id)] == "MAYBE")
  say("%-8.2f %8d %8d %8d %8d", w, tb[["YES"]], tb[["MAYBE"]], tb[["NO"]], moved)
}

hr(); say("DOES IT DEMOTE THE KNOWN-BAD ONES? (w = 0.44)"); hr()
s <- run(0.44)
watch <- c("YMCA OF SAN FRANCISCO", "STAGES REPERTORY THEATRE",
           "KINDRED SPIRITS ANIMAL SACTUARY", "QUEERSPACE COLLECTIVE",
           "BRIGHT BEGINNINGS", "BUILDING FUTURES", "CASA DE PAZ",
           "BOY SCOUTS OF AMERICA", "THE COMMON GOOD")
i <- match(watch, base$recip_name)
d <- data.table(name = substr(watch, 1, 32),
                bmf = substr(base$bmf_name[i], 1, 32),
                qz = base$recip_zip5[i], bz = base$bmf_zip5[i],
                was = as.character(base$status[i]), was_sc = base$score[i],
                now = as.character(s$status[match(base$grant_id[i], s$grant_id)]),
                now_sc = s$score[match(base$grant_id[i], s$grant_id)])
print(d[!is.na(was)], row.names = FALSE)

hr(); say("WHAT ELSE MOVES? (a sample of the YES -> MAYBE set at w = 0.44)"); hr()
mv <- which(base$status == "YES" & s$status[match(base$grant_id, s$grant_id)] == "MAYBE")
set.seed(3)
k <- sample(mv, min(15, length(mv)))
print(data.table(name = substr(base$recip_name[k], 1, 32),
                 bmf = substr(base$bmf_name[k], 1, 32),
                 qz = base$recip_zip5[k], bz = base$bmf_zip5[k],
                 sc = base$score[k]), row.names = FALSE)
