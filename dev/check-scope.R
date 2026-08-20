#!/usr/bin/env Rscript
# What the loosened scope rule changes: who is now matched that was not before.
suppressWarnings(suppressMessages(library(data.table)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
NPM <- Sys.getenv("NPMATCH_DIR", "../npmatch")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")

for (set in c("^1k_grants_.*\\.csv$", "^50k_grants\\.csv$")) {
  g <- pf_read_grants(file.path(PF, "inputs"), pattern = set)
  say("\n=== %s : %d grants ===", sub("\\^|\\\\.*$", "", set), nrow(g))
  say("in scope        : %d (%.1f%%)", sum(g$in_scope), 100 * mean(g$in_scope))
  say("out of sample   : %d (%.1f%%)", sum(!g$in_scope), 100 * mean(!g$in_scope))
  print(table(g$oos_reason, useNA = "no"))
  say("flags carried through (now matched, previously dropped):")
  say("  flag_individual : %d", sum(g$flag_individual & g$in_scope))
  say("  flag_government : %d", sum(g$flag_government & g$in_scope))
  say("  no name         : %d (of which %d have an address)",
      sum(!g$has_name), sum(!g$has_name & g$has_address))
  say("recipient types now in scope:")
  print(table(g$recipient_type[g$in_scope]))
}
