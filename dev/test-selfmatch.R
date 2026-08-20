#!/usr/bin/env Rscript
# How often does the cascade match a grant to its own filing foundation?
suppressWarnings(suppressMessages(library(data.table)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
NPM <- Sys.getenv("NPMATCH_DIR", "../npmatch")
SET <- Sys.getenv("PF_SET", "1k")
PAT <- switch(SET, "1k" = "^1k_grants_.*\\.csv$", "50k" = "^50k_grants\\.csv$",
              "100k" = "^100k_grants\\.csv$", stop("bad PF_SET"))
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")

g   <- pf_recover_name_from_street(pf_read_grants(file.path(PF, "inputs"), pattern = PAT))
ref <- readRDS(file.path(PF, "data-dev", "BMF-REFERENCE-BUNDLE.rds"))
m <- pf_match_grants(g, ref, passes = c(pf_staged_passes("lean"),
                                        pf_recovery_passes(TRUE)),
                     recover = TRUE, verbose = FALSE)
before <- pf_status(m)
m2 <- pf_drop_self_matches(m)
after <- pf_status(m2)

say("\noutcome shift:")
print(table(before = before$status, after = after$status[match(before$grant_id, after$grant_id)]))

chg <- which(before$ein != after$ein | (is.na(before$ein) != is.na(after$ein)))
say("\nqueries whose accepted EIN changed: %d", length(chg))
if (length(chg)) {
  d <- data.table(name = substr(before$recip_name[chg], 1, 32),
                  filer = substr(before$filer_name[chg], 1, 30),
                  was = substr(before$bmf_name[chg], 1, 30),
                  was_status = as.character(before$status[chg]),
                  now = substr(after$bmf_name[match(before$grant_id[chg], after$grant_id)], 1, 30),
                  now_status = as.character(after$status[match(before$grant_id[chg], after$grant_id)]))
  print(head(d, 20), row.names = FALSE)
}
