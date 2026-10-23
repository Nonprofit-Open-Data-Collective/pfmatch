#!/usr/bin/env Rscript
# ============================================================================
# cut-fresh-v2-sample.R -- an independent 5,000-grant sample drawn from the
# deduplicated v2 corpus, as a control on the lifted one.
#
# WHY THIS EXISTS. dev/lift-sample-to-v2.R carries the existing evaluation
# sample onto the new corpus so the 177 adjudications survive. That is the
# right call for comparability, but it leaves one thing unchecked: the sample
# was drawn at random from the UNDEDUPED population, which contains superseded
# filings, so it over-represents filers who amended. Pruning the superseded
# rows after the fact does not undo that -- the surviving rows are still a draw
# from the wrong frame.
#
# The bias is expected to be tiny, because only 1.75% of rows are superseded.
# But "expected to be tiny" is a prediction, and this measures it: a clean
# random draw from the deduplicated corpus, run through the same arm. If the
# two clear rates agree within sampling error the lift is representative and
# the headline number stands on it; if they do not, the lifted sample is
# measuring the wrong population and the gap is the correction.
#
# No labels attach to this sample, so it yields a clear rate and nothing else.
# That is all it is for.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("=", 78))

PF    <- Sys.getenv("PFMATCH_DIR", ".")
HOME  <- "C:/Users/jlecy/Documents/grants"
V2    <- file.path(HOME, "PF-GRANTS-PAID-V2-2009-2025.csv")
OUT   <- file.path(PF, "inputs")
N     <- as.integer(Sys.getenv("PF_FRESH_N", "5000"))
SEED  <- as.integer(Sys.getenv("PF_FRESH_SEED", "20261023"))
CHUNK <- 1000000L

hr(); say("cut-fresh-v2-sample  %s", format(Sys.time())); hr()
if (!file.exists(V2))
  stop("the v2 corpus is not built: run dev/rebuild-corpus-v2.R first.", call. = FALSE)
hdr <- names(fread(V2, nrows = 0L))
say("corpus  %.2f GB, %d columns", file.size(V2) / 2^30, length(hdr))

## ---- pass 1: how many rows ---------------------------------------------------
# One column of 17M strings is cheap; the whole frame is not.
n_total <- nrow(fread(V2, select = "OBJECTID", colClasses = "character",
                      showProgress = FALSE))
say("rows    %s", format(n_total, big.mark = ","))
set.seed(SEED)
idx <- sort(sample.int(n_total, N))
say("drawing %s rows, seed %d", format(N, big.mark = ","), SEED)

## ---- pass 2: pull the drawn rows --------------------------------------------
hit <- list(); i <- 0L; base <- 0L
repeat {
  ch <- fread(V2, colClasses = "character", na.strings = NULL,
              skip = 1L + i * CHUNK, nrows = CHUNK, header = FALSE,
              col.names = hdr, showProgress = FALSE)
  nn <- nrow(ch); if (!nn) break
  want <- idx[idx > base & idx <= base + nn] - base
  if (length(want)) hit[[length(hit) + 1L]] <- ch[want]
  base <- base + nn; i <- i + 1L
  say("  chunk %2d  %11s scanned, %5s drawn", i, format(base, big.mark = ","),
      format(sum(vapply(hit, nrow, 0L)), big.mark = ","))
  rm(ch)
  if (nn < CHUNK) break
}
s <- rbindlist(hit); rm(hit); invisible(gc())
if (nrow(s) != N) stop("drew ", nrow(s), " rows, expected ", N, call. = FALSE)

## ---- write, in the same 5-part shape as the other samples -------------------
hr(); say("writing")
part <- rep(seq_len(5L), length.out = nrow(s))
for (p in seq_len(5L)) {
  f <- file.path(OUT, sprintf("effresh_1k_grants_%02d.csv", p))
  fwrite(s[part == p], f)
  say("  %-30s %5s rows", basename(f), format(sum(part == p), big.mark = ","))
}

## ---- profile, against the lifted sample --------------------------------------
hr(); say("tax-year profile")
yt <- s[, .N, by = TAX_YEAR][order(TAX_YEAR)]
for (j in seq_len(nrow(yt)))
  say("  %-6s %5s  %5.1f%%", yt$TAX_YEAR[j], format(yt$N[j], big.mark = ","),
      100 * yt$N[j] / nrow(s))
say("")
say("filings %s | flagged rows %s",
    format(uniqueN(s$OBJECTID), big.mark = ","),
    format(sum(s$dedup_flag == "TRUE"), big.mark = ","))
hr(); say("done  %s", format(Sys.time()))
