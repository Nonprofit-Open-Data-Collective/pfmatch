#!/usr/bin/env Rscript
# Clean A/B for distinct_name_main_only: same pairs, only the gate varies.
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 74), "\n")

m <- readRDS(file.path(PF, "data-dev", "PF-MATCH-RESULT-1k.rds"))
pairs <- attr(m$result, "pairs")

run <- function(main_only, min_idf) {
  cfg <- npmatch::np_config(distinct_name_main_only = main_only,
                            distinct_name_min_idf = min_idf)
  p <- npmatch::np_veto(npmatch::np_score(pairs, cfg, method = "hier"), cfg)
  res <- npmatch::np_tier(npmatch::np_select(p, cfg), cfg)
  x <- m; x$result <- res
  attr(x$result, "pairs") <- p; attr(x$result, "config") <- cfg
  pf_status(x)
}

hr(); say("A/B GRID (identical pairs, only the promotion gates vary)"); hr()
say("%-34s %7s %7s %7s", "config", "YES", "MAYBE", "NO")
cfgs <- list(
  "neither gate"            = c(FALSE, 0),
  "min_idf = 10 only"       = c(FALSE, 10),
  "main_only only"          = c(TRUE,  0),
  "both (shipped default)"  = c(TRUE,  10))
res <- list()
for (nm in names(cfgs)) {
  s <- run(as.logical(cfgs[[nm]][1]), as.numeric(cfgs[[nm]][2]))
  res[[nm]] <- s
  t <- table(factor(s$status, pf_status_levels()))
  say("%-34s %7d %7d %7d", nm, t[["YES"]], t[["MAYBE"]], t[["NO"]])
}

base <- res[["neither gate"]]
hr(); say("WHAT main_only DEMOTES"); hr()
on <- res[["main_only only"]]
k <- match(base$grant_id, on$grant_id)
mv <- which(base$status == "YES" & on$status[k] != "YES")
say("YES -> demoted: %d", length(mv))
pr <- as.data.table(pairs)
j <- match(paste(base$grant_id[mv], base$ein[mv]), paste(pr$.id, pr$.ein))
d <- data.table(name = substr(base$recip_name[mv], 1, 28),
                matched_y = substr(pr$name_y[j], 1, 24),
                legal_y = substr(pr$name_key_y[j], 1, 28),
                ver = pr$name_ver_y[j],
                qcity = substr(base$recip_city[mv], 1, 13),
                bcity = substr(base$bmf_city[mv], 1, 13))
print(head(d[order(ver)], 25), row.names = FALSE)

hr(); say("ARE THE KNOWN ERRORS CAUGHT?"); hr()
watch <- c("COMMUNITY CHURCH", "CHRIST CHURCH", "1", "HOUSE OF HOPE",
           "CONGREGATION AGUDATH ISRAEL")
for (nm in names(res)) {
  s <- res[[nm]]; i <- match(watch, s$recip_name)
  say("%-24s %s", nm, paste(sprintf("%s=%s", substr(watch, 1, 12),
      as.character(s$status[i])), collapse = "  "))
}
