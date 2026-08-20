#!/usr/bin/env Rscript
# Were the "truncated" BMF names in the audit real, or my own display width?
suppressWarnings(suppressMessages(library(data.table)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
NPM <- Sys.getenv("NPMATCH_DIR", "../npmatch")
say <- function(...) cat(sprintf(...), "\n")

b <- fread(file.path(NPM, "data-raw", "bmf_2026_01_processed.csv"),
           select = c("ein", "org_name_raw", "org_name_join"),
           colClasses = "character", showProgress = FALSE)
b[, e := gsub("[^0-9]", "", ein)]

targets <- c("131644147",  # Planned Parenthood Federation of America
             "391102129",  # "EVANGELICAL LUTHERAN CHURCH IN AMERICAN ICA"
             "396084791",  # "Boys And Girls Club Of Greater La C"
             "340965673")  # "Northwest Ohio Hemophilia Foundatio"
for (t in targets) {
  r <- b[e == t]
  if (!nrow(r)) { say("%s : not found", t); next }
  say("%s | raw(%2d) = '%s'", t, nchar(r$org_name_raw[1]), r$org_name_raw[1])
  say("            join = '%s'", r$org_name_join[1])
}

# And the audit CSV as written -- is the stored value full or clipped?
a <- fread(file.path(PF, "data-dev", "AUDIT-MAYBE-100.csv"), colClasses = "character")
say("\nas stored in AUDIT-MAYBE-100.csv (cand_name):")
for (t in targets) {
  v <- unique(a$cand_name[gsub("[^0-9]", "", a$ein) == t])
  if (length(v)) say("  %s -> '%s' (%d chars)", t, v[1], nchar(v[1]))
}
say("\nmax cand_name length in the audit file: %d", max(nchar(a$cand_name), na.rm = TRUE))
