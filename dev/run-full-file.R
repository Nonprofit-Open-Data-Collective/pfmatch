#!/usr/bin/env Rscript
# ============================================================================
# run-full-file.R -- the production pipeline, end to end, checkpointed.
#
#   PF_GRANTS=<glob>   which grant file(s) to run   (default: the 100k sample)
#   PF_BATCH=25000     identities per checkpoint
#   PF_OUT=<dir>       checkpoint + output directory
#
# Safe to interrupt and re-run: completed batches are skipped.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
NPM <- Sys.getenv("NPMATCH_DIR", "../npmatch")
PAT <- Sys.getenv("PF_GRANTS", "^100k_grants\\.csv$")
BATCH <- as.integer(Sys.getenv("PF_BATCH", "25000"))
OUT <- Sys.getenv("PF_OUT", file.path(PF, "data-dev", "fullrun"))
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("=", 74), "\n")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

hr(); say("STAGE 0 -- prepare + dedup (preprocessing, not timed)"); hr()
t0 <- proc.time()[["elapsed"]]
g <- pf_read_grants(file.path(PF, "inputs"), pattern = PAT)
g <- pf_recover_name_from_street(g)
say("grant rows ....... %s", format(nrow(g), big.mark = ","))
say("in scope ......... %s (%.1f%%)", format(sum(g$in_scope), big.mark = ","),
    100 * mean(g$in_scope))
say("out of sample .... %s", format(sum(!g$in_scope), big.mark = ","))

g <- pf_dedup(g, method = "fuzzy", verbose = TRUE)
recips <- pf_recipients(g[g$in_scope, , drop = FALSE])
say("distinct identities to match: %s (%.2fx collapse)",
    format(nrow(recips), big.mark = ","), sum(g$in_scope) / nrow(recips))
say("preprocessing elapsed: %.1f s", proc.time()[["elapsed"]] - t0)

hr(); say("STAGE 0b -- BMF reference (cached)"); hr()
REF_RDS <- file.path(PF, "data-dev", "BMF-REFERENCE-BUNDLE.rds")
ref <- readRDS(REF_RDS)
say("reference: %s records", format(nrow(ref$reference), big.mark = ","))

hr(); say("STAGES 1-5 -- checkpointed cascade"); hr()
status <- pf_run_batches(recips, ref, dir = file.path(OUT, "batches"),
                         batch_size = BATCH)

hr(); say("RESULTS"); hr()
pf_batch_report(status)

# ---- propagate identity-level results back onto every grant row -------------
g2 <- pf_propagate_matches(g, status)
g2$status[!g2$in_scope] <- "OOS"
say("\nper-GRANT-ROW outcome after cluster propagation:")
tb <- table(factor(g2$status, pf_status_levels()))
for (s in pf_status_levels())
  say("  %-6s %8d  (%4.1f%%)", s, tb[[s]], 100 * tb[[s]] / nrow(g2))

say("\noutcome by recipient type (grant rows):")
print(pf_crosstab(data.frame(
  recipient_type = factor(as.character(g2$recipient_type), pf_type_levels()),
  status = factor(g2$status, pf_status_levels())))[, c("label", pf_status_levels(),
                 "n", "pct_YES_of_attempted", "pct_YESMAYBE_attempted")],
  row.names = FALSE, right = FALSE)

fwrite(status, file.path(OUT, "IDENTITY-MATCHES.csv"), na = "")
fwrite(g2[, intersect(c("grant_id", "FILEREIN", "recip_name", "recip_city",
                        "recip_state", "recipient_type", "recipient_uid",
                        "status", "ein", "bmf_name", "score", "match_pass"),
                      names(g2))],
       file.path(OUT, "GRANT-MATCHES.csv"), na = "")
say("\nwrote %s", file.path(OUT, "IDENTITY-MATCHES.csv"))
say("wrote %s", file.path(OUT, "GRANT-MATCHES.csv"))
