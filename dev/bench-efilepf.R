#!/usr/bin/env Rscript
# The 1k benchmark on the REBUILT grant file: current npmatch, current
# normalizer, complete source population.
#
# This is not comparable to BASELINE-2026-08 and is not meant to be. Three
# things changed at once -- the grant population (the GTDC extract was missing
# 93% of 2024), the normalizer (v1-421e1e2a6afb024e -> v1-b42811fe6601afe6),
# and the sample draw (seeded). The recheck in dev/recheck-vs-npmatch-release.R
# already isolated the normalizer's contribution on the OLD population:
# +5 YES augmented, +10 active. Whatever differs here beyond that is the
# population.
#
#   PF_ARM=active|augmented
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
PF  <- Sys.getenv("PFMATCH_DIR", ".")
DD  <- file.path(PF, "data-dev")
ARM <- Sys.getenv("PF_ARM", "augmented")
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("=", 78))
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))

CACHE <- file.path(DD, sprintf("RECHECK-REF-%s.rds", ARM))
stopifnot(file.exists(CACHE))

hr(); say("1k BENCHMARK ON THE REBUILT GRANT FILE   arm = %s", ARM); hr()
say("npmatch %s   normalizer %s",
    as.character(utils::packageVersion("npmatch")), np_normalize_signature())

grants <- pf_read_grants(file.path(PF, "inputs"), pattern = "^ef1k_grants_.*\\.csv$")
grants <- pf_recover_name_from_street(grants)
say("grants: %s  tax years %s-%s", format(nrow(grants), big.mark = ","),
    min(grants$TAXYEAR, na.rm = TRUE), max(grants$TAXYEAR, na.rm = TRUE))

ref <- readRDS(CACHE)
say("reference: %s rows", format(nrow(ref$reference), big.mark = ","))

passes <- c(pf_staged_passes("lean", concat = TRUE), pf_recovery_passes(state = TRUE))
t0 <- proc.time()[["elapsed"]]
m <- pf_match_grants(grants, ref, passes = passes, recover = TRUE, verbose = FALSE)
say("matched in %.1f s", proc.time()[["elapsed"]] - t0)

res <- as.data.frame(m$result)
tb  <- table(factor(res$tier, levels = c("YES", "MAYBE", "NO")))
tot <- nrow(res)

hr(); say("RESULT"); hr()
say("%-8s %9s %8s", "tier", "n", "share")
for (k in names(tb)) say("%-8s %9d %7.1f%%", k, tb[[k]], 100 * tb[[k]] / tot)
say("%-8s %9d", "identities", tot)
say("")
say("CLEAR RATE (YES)  : %.1f%%", 100 * tb[["YES"]] / tot)
say("YES+MAYBE         : %.1f%%", 100 * (tb[["YES"]] + tb[["MAYBE"]]) / tot)
say("")
say("for orientation, same arm on the OLD grant population:")
say("  BASELINE-2026-08 (old npmatch) : 62.9%% YES")
say("  recheck (current npmatch)      : 63.1%% YES")
say("  -- different grant population, so a difference here is not a regression")

# where the new population differs: year mix
say("")
yr <- as.data.table(grants)[, .N, by = TAXYEAR][order(TAXYEAR)]
say("tax-year mix of the new sample (the old one stopped at 2024 and")
say("under-represented 2022-2024 badly):")
print(yr, row.names = FALSE)

saveRDS(res, file.path(DD, sprintf("BENCH-EFILEPF-%s.rds", ARM)), compress = "xz")
say("")
say("wrote data-dev/BENCH-EFILEPF-%s.rds", ARM)
