#!/usr/bin/env Rscript
# ============================================================================
# Run pf_efilepf_dedup() over the whole 990-PF grants-paid corpus.
#
# Exercises every branch, including `kept_flagged` -- contexts where several
# filings disagree and no amendment settles which supersedes. Only ~10 such
# contexts exist corpus-wide, so a single year does not reach that path and the
# 2023 test left it unverified.
#
# Also re-checks the two invariants that matter:
#   * no PARTIAL filing is dropped in favour of a non-partial (short-period and
#     full-year returns cover different periods and are both real)
#   * OBJECTID + TABLE_ID remains unique, so every surviving grant row is still
#     addressable by the published key
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
PF  <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("-", 86))
fmt <- function(x) format(x, big.mark = ",")
sq  <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; x }

fs <- list.files(pf_efilepf_dir(), pattern = "GRANT-PAID.*CSV$", full.names = TRUE)
say("reading %d raw ef2 files ...", length(fs))
d <- rbindlist(lapply(fs, function(f)
  fread(f, colClasses = "character", showProgress = FALSE)), fill = TRUE)
say("corpus: %s grant rows, %s filings", fmt(nrow(d)), fmt(uniqueN(d$OBJECTID)))

hr()
out <- pf_efilepf_dedup(d, verbose = TRUE)
hr()

## ---- invariants -------------------------------------------------------------
o <- as.data.table(out)
say("INVARIANTS")
say("  OBJECTID + TABLE_ID unique            : %s",
    !anyDuplicated(paste(o$OBJECTID, o$TABLE_ID)))
say("  no grant row invented                 : %s", nrow(o) <= nrow(d))
say("  all kept OBJECTIDs came from the input: %s",
    all(o$OBJECTID %in% d$OBJECTID))

fil <- unique(d[, .(OBJECTID,
                    par = pfmatch:::.pf_flagged(RETURN_PARTIAL_X),
                    amd = pfmatch:::.pf_flagged(RETURN_AMENDED_X),
                    ctx = paste(sq(EIN2), sq(TAX_YEAR),
                                pfmatch:::.pf_flagged(RETURN_GROUP_X),
                                pfmatch:::.pf_flagged(RETURN_PARTIAL_X), sep = "|"))])
fil[, kept := OBJECTID %in% unique(o$OBJECTID)]
lostp <- fil[kept == FALSE & par == TRUE]
bad <- sum(vapply(seq_len(nrow(lostp)), function(i) {
  sib <- fil[ctx == lostp$ctx[i] & kept == TRUE]
  nrow(sib) > 0L && any(!sib$par)
}, logical(1)))
say("  partial filings dropped               : %s", fmt(nrow(lostp)))
say("  ... dropped for a NON-partial [MUST BE 0]: %s", bad)

hr(); say("WHAT WAS DROPPED, AND WHY")
drop <- fil[kept == FALSE]
say("  total filings dropped : %s", fmt(nrow(drop)))
say("  of them amended       : %s", fmt(sum(drop$amd)))
say("  of them partial       : %s", fmt(sum(drop$par)))

hr(); say("THE FLAGGED CONTEXTS (kept in full, needing review)")
fl <- o[dedup_flag == TRUE]
say("  grant rows flagged : %s", fmt(nrow(fl)))
say("  filings flagged    : %s", fmt(uniqueN(fl$OBJECTID)))
say("  contexts flagged   : %s", fmt(uniqueN(paste(fl$EIN2, fl$TAX_YEAR))))
if (nrow(fl)) {
  ex <- unique(fl[, .(EIN2, TAX_YEAR, OBJECTID)])[order(EIN2, TAX_YEAR)]
  n <- min(12L, nrow(ex))
  say("")
  say("  %-16s %-9s %s", "EIN2", "year", "OBJECTID")
  for (i in seq_len(n)) say("  %-16s %-9s %s", ex$EIN2[i], ex$TAX_YEAR[i], ex$OBJECTID[i])
}

saveRDS(attr(out, "pf_dedup"), file.path(PF, "data-dev", "EFILEPF-DEDUP-AUDIT.rds"))
fwrite(unique(fl[, .(EIN2, TAX_YEAR, OBJECTID, dedup_action)]),
       file.path(PF, "data-dev", "EFILEPF-DEDUP-FLAGGED.csv"))
hr()
say("wrote data-dev/EFILEPF-DEDUP-AUDIT.rds and EFILEPF-DEDUP-FLAGGED.csv")
say("")
say("rows removed: %s (%.2f%% of the corpus)", fmt(nrow(d) - nrow(o)),
    100 * (nrow(d) - nrow(o)) / nrow(d))
