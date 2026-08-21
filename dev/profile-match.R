#!/usr/bin/env Rscript
# Profile the cascade instead of guessing at it. Three hypotheses for the 34x
# gap against the documented 33.5 s per 1,000 have now been measured and killed:
# query composition, stage-4 key building, and the per-pair name_idf loop. Time
# to look at where the time actually goes.
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(library(pfmatch)))
setDTthreads(0L)
say <- function(...) message(sprintf(...))

N     <- as.integer(Sys.getenv("PF_N", "300"))
STAGE <- "C:/Users/jlecy/Documents/grants/staging"
prep <- readRDS(file.path(STAGE, "PREPARED-FULL.rds"))
r <- as.data.frame(prep$recipients)
set.seed(1)
q <- r[sort(sample(nrow(r), N)), , drop = FALSE]
rm(prep, r); invisible(gc())
say("queries: %d", nrow(q))

ref <- readRDS("data-dev/BMF-REFERENCE-BUNDLE.rds")
say("reference: %s rows", format(nrow(ref$reference), big.mark = ","))

out <- file.path(STAGE, "match.Rprof")
Rprof(out, interval = 0.02, line.profiling = FALSE, memory.profiling = FALSE)
invisible(utils::capture.output(
  pf_match_grants(q, ref, passes = pf_staged_passes("lean"),
                  recover = FALSE, verbose = TRUE)))
Rprof(NULL)

s <- summaryRprof(out)
say("")
say("=== TOTAL %.1f s for %d queries (%.0f s per 1,000) ===",
    s$sampling.time, nrow(q), s$sampling.time / nrow(q) * 1000)
say("")
say("BY SELF TIME (top 18)")
b <- head(s$by.self, 18)
for (i in seq_len(nrow(b)))
  message(sprintf("  %-46s %7.1f s  %5.1f%%", rownames(b)[i], b$self.time[i], b$self.pct[i]))
say("")
say("BY TOTAL TIME (top 12)")
b <- head(s$by.total[order(-s$by.total$total.pct), ], 12)
for (i in seq_len(nrow(b)))
  message(sprintf("  %-46s %7.1f s  %5.1f%%", rownames(b)[i], b$total.time[i], b$total.pct[i]))
