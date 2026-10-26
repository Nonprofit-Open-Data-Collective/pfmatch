#!/usr/bin/env Rscript
# ============================================================================
# rebuild-corpus-v2.R -- rebuild the full grant corpus under the ef2 schema,
# deduplicated, as the population every later measurement is taken over.
#
# The corpus in place (PF-GRANTS-PAID-2009-2025.csv, built 2026-10-21) is the
# v1/GTDC downgrade: 22 columns, no TABLE_ID, no EIN2, no amended or partial
# flags. Those are exactly the columns supersession is decided on, so that file
# cannot be deduplicated and cannot carry the published row key. It is kept,
# because BASELINE-2026-10 is defined over samples cut from it.
#
# This writes a SECOND corpus beside it rather than replacing it:
#
#   PF-GRANTS-PAID-2009-2025.csv        v1 names, 17,560,767 rows, undeduped
#   PF-GRANTS-PAID-V2-2009-2025.csv     v2 names, deduplicated      <- new
#
# Two files on disk is the point. The recalibration is a comparison between
# them, and a comparison needs both sides.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("=", 78))

source(file.path(PF, "dev", "grants-path.R"))
HOME <- pf_grants_home()
OUT  <- file.path(HOME, "PF-GRANTS-PAID-V2-2009-2025.csv")

hr(); say("rebuild-corpus-v2  %s", format(Sys.time()))
say("source cache : %s", pf_efilepf_dir())
say("out          : %s", OUT)
hr()

t0 <- proc.time()[["elapsed"]]
log <- pf_efilepf_build(out = OUT, schema = "v2", dedup = TRUE, verbose = TRUE)
el <- (proc.time()[["elapsed"]] - t0) / 60

hr()
say("built in %.1f min; %.2f GB", el, file.size(OUT) / 2^30)
if (is.data.frame(log)) {
  fwrite(log, file.path(HOME, "efilepf-build-log-v2.csv"))
  print(log, row.names = FALSE)
}

## ---- verify ----------------------------------------------------------------
# Read back only the key and the dedup columns: the whole file does not need to
# be in memory to establish that the row key is unique and the dedup ran.
hr(); say("verifying the written file")
k <- fread(OUT, select = c("OBJECTID", "TABLE_ID", "EIN2", "TAX_YEAR",
                           "dedup_action", "dedup_flag"),
           colClasses = "character", showProgress = FALSE)
say("  rows            %s", format(nrow(k), big.mark = ","))
say("  filings         %s", format(uniqueN(k$OBJECTID), big.mark = ","))
say("  row key unique  %s",
    if (!anyDuplicated(k[, paste(OBJECTID, TABLE_ID, sep = "|")])) "TRUE" else "FALSE")
print(k[, .N, by = dedup_action], row.names = FALSE)
say("  flagged rows    %s", format(sum(k$dedup_flag == "TRUE"), big.mark = ","))
say("")
say("against the undeduped corpus: 17,560,767 -> %s  (%.2f%% removed)",
    format(nrow(k), big.mark = ","), 100 * (1 - nrow(k) / 17560767))
hr(); say("done  %s", format(Sys.time()))
