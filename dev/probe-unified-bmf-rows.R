#!/usr/bin/env Rscript
# The unified BMF carries several rows per EIN. pf_build_dyads() takes one row
# per EIN for names, geography and subsection, so it matters which one.
suppressWarnings(suppressMessages(library(data.table)))
say <- function(...) cat(sprintf(...), "\n")
B <- "../npmatch/data-raw/bmf_unified_geocoded-nteev2fix.csv"
d <- fread(B, colClasses = "character", showProgress = FALSE,
           select = c("ein", "org_name_join", "org_addr_city", "org_addr_state",
                      "subsection_code", "bmf_source"))
say("rows: %s   distinct EINs: %s", format(nrow(d), big.mark=","),
    format(uniqueN(d$ein), big.mark=","))
say("")
say("bmf_source:")
print(d[, .N, by = bmf_source][order(-N)], row.names = FALSE)
say("")
say("rows per EIN:")
print(table(pmin(d[, .N, by = ein]$N, 6L)))
say("")
say("blank fields, by source:")
print(d[, .(rows = .N,
            no_name = sum(!nzchar(org_name_join)),
            no_state = sum(!nzchar(org_addr_state)),
            no_city = sum(!nzchar(org_addr_city)),
            no_subsec = sum(!nzchar(subsection_code))), by = bmf_source],
      row.names = FALSE)
say("")
say("do rows for one EIN disagree on state? (sample of multi-row EINs)")
m <- d[ein %in% d[, .N, by = ein][N > 1][1:20000]$ein]
g <- m[, .(states = uniqueN(org_addr_state[nzchar(org_addr_state)]),
           subs = uniqueN(subsection_code[nzchar(subsection_code)]),
           names = uniqueN(org_name_join[nzchar(org_name_join)])), by = ein]
say("  EINs sampled: %d", nrow(g))
say("  disagree on state      : %d (%.1f%%)", sum(g$states > 1), 100*mean(g$states > 1))
say("  disagree on subsection : %d (%.1f%%)", sum(g$subs > 1), 100*mean(g$subs > 1))
say("  more than one name     : %d (%.1f%%)", sum(g$names > 1), 100*mean(g$names > 1))
