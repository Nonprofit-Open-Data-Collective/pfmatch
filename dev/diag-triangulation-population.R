#!/usr/bin/env Rscript
# Which population are the triangulation artifacts keyed to, and does it still
# exist? They carry 6e3e985e05a5f364, which is neither ef1k nor the lifted
# efv2_1k, so they were built on a larger sample and were NOT part of the
# recalibration.
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("-", 78))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))

tri <- fread(file.path(PF, "data-dev", "PF-TRUTH-TRIANGULATED.csv"),
             colClasses = "character")
grp <- fread(file.path(PF, "data-dev", "TRIANGULATION-GROUPS.csv"),
             colClasses = "character")
hr(); say("triangulation artifacts")
say("  PF-TRUTH-TRIANGULATED  %s rows, population %s",
    format(nrow(tri), big.mark = ","), tri$population[1])
say("  TRIANGULATION-GROUPS   %s rows, %s groups, population %s",
    format(nrow(grp), big.mark = ","), format(uniqueN(grp$group_id), big.mark = ","),
    grp$population[1])
say("  grant_id range         %s .. %s", min(tri$grant_id), max(tri$grant_id))

hr(); say("candidate source populations in inputs/")
pats <- c(ef1k      = "^ef1k_grants_[0-9]+\\.csv$",
          efv2_1k   = "^efv2_1k_grants_[0-9]+\\.csv$",
          effresh   = "^effresh_1k_grants_[0-9]+\\.csv$",
          ef50k     = "^ef50k_grants\\.csv$",
          ef100k    = "^ef100k_grants\\.csv$",
          effiler   = "^effiler100k_grants\\.csv$")
for (nm in names(pats)) {
  f <- list.files(file.path(PF, "inputs"), pattern = pats[[nm]], full.names = TRUE)
  if (!length(f)) { say("  %-10s (absent)", nm); next }
  g <- tryCatch(pf_read_grants(file.path(PF, "inputs"), pattern = pats[[nm]]),
                error = function(e) NULL)
  if (is.null(g)) { say("  %-10s (unreadable)", nm); next }
  id <- pf_population_id(g)
  say("  %-10s %9s rows  %s %s", nm, format(nrow(g), big.mark = ","), id,
      if (identical(id, tri$population[1])) "  <-- MATCH" else "")
}
hr()
