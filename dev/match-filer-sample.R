#!/usr/bin/env Rscript
# Match the filer sample so the EIN-dependent features can be measured:
# the funder NTEE profile with its size-matched null, the grantee prior, and
# the one that matters most -- whether a MAYBE can be resolved by a YES the
# same funder already earned for the same grantee in another year.
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) message(sprintf(...))

g <- fread(file.path(PF, "inputs", "effiler100k_grants.csv"),
           colClasses = "character", showProgress = FALSE, na.strings = NULL)
g[, grant_id := sprintf("G%07d", .I)]
prep <- pf_prepare(g, dedup = "exact", verbose = FALSE)
say("identities to match: %s", format(nrow(prep$recipients), big.mark = ","))

ref <- readRDS(file.path(PF, "data-dev", "RECHECK-REF-augmented.rds"))
say("reference: %s rows", format(nrow(ref$reference), big.mark = ","))

t0 <- proc.time()[["elapsed"]]
# resume = FALSE deliberately: the checkpoint stamp check currently rejects its
# own freshly written checkpoints (test-batch.R:109, pre-existing), so resuming
# would silently recompute anyway. Explicit beats accidental.
st <- pf_run_batches(prep$recipients, ref,
                     dir = file.path(PF, "data-dev", "batches-filer"),
                     batch_size = 25000L, resume = FALSE, verbose = TRUE)
say("matched in %.1f min", (proc.time()[["elapsed"]] - t0) / 60)
print(table(st$status))
gg <- pf_propagate_matches(prep$grants, st)
saveRDS(list(status = st, grants = gg),
        file.path(PF, "data-dev", "FILER-SAMPLE-MATCH.rds"), compress = FALSE)
say("wrote data-dev/FILER-SAMPLE-MATCH.rds")
