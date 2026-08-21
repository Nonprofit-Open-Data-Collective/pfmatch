#!/usr/bin/env Rscript
# ============================================================================
# probe-refbuild-cost.R -- what does a reference rebuild actually cost, by part?
#
# probe-idf-atomize.R showed token IDF can be recombined per-spec in 0.03 s
# instead of 41 s. This asks the question that decides whether that matters:
# how much of a rebuild is IDF in the first place?
# ============================================================================
suppressWarnings(suppressMessages({ library(data.table); library(npmatch) }))
setDTthreads(0)

REF <- Sys.getenv("PF_REF", "data-dev/REF-active.rds")
say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() cat(strrep("=", 74), "\n")
tm  <- function(lbl, expr) {
  t <- proc.time()[["elapsed"]]; v <- force(expr)
  s <- proc.time()[["elapsed"]] - t
  say("  %-26s %8.1f s", lbl, s); invisible(list(v = v, s = s))
}

hr(); say("reference rebuild cost by component"); say("corpus: %s", REF); hr()

r  <- tm("readRDS cached bundle", readRDS(REF))
ref <- r$v$reference
say("  rows: %s", format(nrow(ref), big.mark = ","))
invisible(gc())

hr(); say("recompute each component from the normalized reference"); hr()
n1 <- tm("np_normalize",  np_normalize(ref))
invisible(gc())
n2 <- tm("np_name_freq",  np_name_freq(ref$name_key))
n3 <- tm("np_token_idf",  np_token_idf(ref$name_key))
n4 <- tm("np_ref_index",  np_ref_index(ref))

tot <- n1$s + n2$s + n3$s + n4$s
hr(); say("shares of a full rebuild (%.0f s total)", tot); hr()
for (x in list(c("np_normalize", n1$s), c("np_name_freq", n2$s),
               c("np_token_idf", n3$s), c("np_ref_index", n4$s)))
  say("  %-26s %8.1f s   %5.1f%%", x[1], as.numeric(x[2]),
      100 * as.numeric(x[2]) / tot)
say("")
say("  IDF is %.1f%% of a rebuild. Atomizing it saves at most that.",
    100 * n3$s / tot)
say("  A rebuild is %.1f%% of one 1k-identity match batch (226 s, augmented).",
    100 * tot / 226)
