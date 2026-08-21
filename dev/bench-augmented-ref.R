#!/usr/bin/env Rscript
# Validate the augmented unified reference on the 5,000-grant benchmark before
# committing ten workers to it. Baseline (plain monthly BMF, all fixes in):
#   2,821 YES / 1,006 MAYBE / 1,093 NO / 80 OOS
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(library(pfmatch)))
setDTthreads(6L)
PF  <- "."
REF <- file.path(PF, "data-dev", "BMF-AUGMENTED-bmf_unified_geocoded_2026-08-20.csv")
CACHE <- file.path(PF, "data-dev", "BMF-REF-AUG-2026-08-20.rds")
say <- function(...) message(sprintf(...))   # stderr is unbuffered
hr  <- function() message(strrep("-", 78))

g <- rbindlist(lapply(sprintf("inputs/1k_grants_0%d.csv", 1:5),
                      function(p) fread(p, colClasses = "character", showProgress = FALSE)),
               use.names = TRUE, fill = TRUE)
g[, grant_id := sprintf("G%06d", .I)]
say("benchmark grants: %s", format(nrow(g), big.mark = ","))

prep <- pf_prepare(g, dedup = "fuzzy", verbose = FALSE)
say("identities: %s", format(nrow(prep$recipients), big.mark = ","))

ref <- pf_reference(REF, cache = CACHE, verbose = FALSE)
say("reference: %s rows", format(nrow(ref$reference), big.mark = ","))

t0 <- proc.time()[["elapsed"]]
lnk <- pf_link(prep, ref, dir = file.path(PF, "data-dev", "batches-augbench"),
               batch_size = 1000L, verbose = TRUE)
el <- proc.time()[["elapsed"]] - t0

# pf_link() returns a pf_linked object; pf_status() wants the pf_match inside it.
st <- as.data.table(lnk$status)
tb <- st[, .N, by = status]
hr(); say("AUGMENTED UNIFIED REFERENCE vs BASELINE"); hr()
base <- c(YES = 2821L, MAYBE = 1006L, NO = 1093L, OOS = 80L)
say("%-8s %8s %8s %9s %8s", "tier", "now", "baseline", "delta", "share")
tot <- sum(tb$N)
for (s in names(base)) {
  n <- tb[status == s]$N; if (!length(n)) n <- 0L
  say("%-8s %8s %8s %+9d %7.1f%%", s, format(n, big.mark = ","),
      format(base[[s]], big.mark = ","), n - base[[s]], 100 * n / tot)
}
say("")
say("match time %.1f s over %s identities (%.1f s per 1,000)",
    el, format(nrow(prep$recipients), big.mark = ","),
    el / nrow(prep$recipients) * 1000)

hr(); say("DID THE ALIAS ROWS DO THE WORK?"); hr()
pr <- as.data.table(attr(lnk$status, "pairs"))
if (!is.null(pr) && "row_source" %in% names(ref$reference)) {
  src <- ref$reference$row_source[match(st$ein, ref$reference$ein)]
  say("YES matches whose reference row came from Schedule I: %s",
      format(sum(st$status == "YES" & src %in% "schedi", na.rm = TRUE), big.mark = ","))
}
say("")
say("state agreement on YES: %.1f%%",
    100 * mean(st[status == "YES"]$geo_state %in% 1, na.rm = TRUE))
fwrite(st, file.path(PF, "data-dev", "BENCH-AUG-STATUS.csv"))
