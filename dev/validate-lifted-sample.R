#!/usr/bin/env Rscript
# pf_validate_grants() over both evaluation populations, side by side.
# The v1 sample should report the legacy schema and a missing row key; the
# lifted v2 sample should be clean on every check.
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) message(sprintf(...))

for (p in c("^ef1k_grants_[0-9]+\\.csv$", "^efv2_1k_grants_[0-9]+\\.csv$")) {
  message(""); message(strrep("#", 78))
  say("# %s", p); message(strrep("#", 78))
  g <- pf_read_grants(file.path(PF, "inputs"), pattern = p)
  pf_validate_grants(g, verbose = TRUE)
  say("population id %s", pf_population_id(g))
}
