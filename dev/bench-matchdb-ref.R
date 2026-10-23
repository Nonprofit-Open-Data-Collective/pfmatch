#!/usr/bin/env Rscript
# Benchmark the matchdb reference on the same ef1k grants as the production
# reference, so the only thing that differs is the reference side.
#
# Written with the Write tool, not a heredoc: a bash heredoc strips one
# backslash level, so "\\.csv$" arrives as "\.csv$" and R rejects it. That is a
# standing hazard in this repo and it has bitten twice now.
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) message(sprintf(...))

t0 <- proc.time()[["elapsed"]]
ref <- pf_reference(file.path(PF, "data-dev", "REF-MATCHDB.csv"),
                    cache = file.path(PF, "data-dev", "REF-MATCHDB.rds"),
                    verbose = FALSE)
say("reference: %s rows (loaded in %.1f min)",
    format(nrow(ref$reference), big.mark = ","), (proc.time()[["elapsed"]] - t0) / 60)

grants <- pf_read_grants(file.path(PF, "inputs"), pattern = "^ef1k_grants_")
grants <- pf_recover_name_from_street(grants)
passes <- c(pf_staged_passes("lean", concat = TRUE), pf_recovery_passes(state = TRUE))
t1 <- proc.time()[["elapsed"]]
m <- pf_match_grants(grants, ref, passes = passes, recover = TRUE, verbose = FALSE)
el <- proc.time()[["elapsed"]] - t1
say("matched %s grants in %.1f min", format(nrow(grants), big.mark = ","), el / 60)

res <- as.data.frame(m$result)
tb  <- table(factor(res$tier, levels = c("YES", "MAYBE", "NO")))
tot <- nrow(res)
say("")
say("%-8s %9s %8s", "tier", "n", "share")
for (k in names(tb)) say("%-8s %9d %7.1f%%", k, tb[[k]], 100 * tb[[k]] / tot)
say("identities %d", tot)
say("")
say("CLEAR RATE : %.1f%%   (augmented BMF, same grants: 63.0%%)",
    100 * tb[["YES"]] / tot)
say("YES+MAYBE  : %.1f%%   (augmented BMF: 84.8%%)",
    100 * (tb[["YES"]] + tb[["MAYBE"]]) / tot)

## which variant class carried each YES -------------------------------------
rr <- as.data.table(ref$reference)
if ("row_source" %in% names(rr) && ".ein" %in% names(res)) {
  # an EIN can appear under several classes; take the class of the row whose
  # name actually matched where that is recoverable, else the EIN's classes
  key <- unique(rr[, .(ein = .ein, row_source)])
  y <- data.table(ein = res$.ein[res$tier == "YES"])
  j <- merge(y, key, by = "ein", all.x = TRUE, allow.cartesian = TRUE)
  say("")
  say("variant classes present on the EINs behind each YES:")
  print(j[, .N, by = row_source][order(-N)], row.names = FALSE)
  say("  (an EIN often carries several classes, so these sum above the YES count)")
}
saveRDS(res, file.path(PF, "data-dev", "BENCH-MATCHDB.rds"), compress = "xz")
say("wrote data-dev/BENCH-MATCHDB.rds")
