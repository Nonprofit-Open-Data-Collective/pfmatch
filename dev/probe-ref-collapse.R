#!/usr/bin/env Rscript
# ============================================================================
# probe-ref-collapse.R -- price the reference-row collapse before building it.
#
# dev/PHASE3-LIBRARIES.md 0 lists "collapse identical (name, state, zip5)
# reference rows -- reference -7%, cost driver -8x" as one of two changes that go
# in BEFORE the full run. It was never built and the claim has no committed log.
# dev/diagnose-ref-blowup.R is where it came from, and two things about that
# script mean its numbers cannot be carried forward:
#
#   1. It reads BMF-AUGMENTED-bmf_unified_geocoded_2026-08-20.csv, which
#      BASELINE-2026-08/MANIFEST.md establishes is NOT the artifact
#      REF-augmented.rds was built from.
#   2. It groups on its own uppercase-and-strip name key. The cascade blocks on
#      `name_key` from npmatch's normalizer. A saving measured on a different key
#      than the blocker uses is not a saving the blocker will see.
#
# So this measures the collapse on the normalized reference the cascade actually
# runs against, keyed the way the blocker actually keys.
#
# WHY sum(block^2) IS THE RIGHT COST PROXY
#
# An exact-key pass emits, for each query hitting a block, one candidate per row
# in that block. Total candidate volume is therefore sum over blocks of
# (queries hitting it) x (rows in it), and with queries distributed roughly like
# the reference itself that goes as sum(N^2). It is also the right proxy for
# MEMORY, which is what dev/SHARD-RSS.log says is binding: the ~34 GB fixed cost
# is candidate-side, not reference-side storage.
#
#   PF_REF   active | augmented | unified   (default augmented)
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
setDTthreads(0L)
DD  <- file.path(PF, "data-dev")
W   <- Sys.getenv("PF_REF", "augmented")
say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function(t = NULL) { cat(strrep("=", 78), "\n")
                            if (!is.null(t)) { cat(t, "\n"); cat(strrep("=", 78), "\n") } }

reffile <- switch(W, active = "REF-active.rds", unified = "REF-unified.rds",
                  augmented = "REF-augmented.rds")
hr(sprintf("REFERENCE COLLAPSE -- %s", reffile))
t0 <- proc.time()[["elapsed"]]
b <- readRDS(file.path(DD, reffile))
r <- data.table::as.data.table(b$reference)
say("loaded %s rows in %.0f s", format(nrow(r), big.mark = ","),
    proc.time()[["elapsed"]] - t0)
say("columns: %s", paste(names(r), collapse = " "))

# The blocker's own key. Bail loudly rather than substitute a lookalike: the
# whole point of this probe is to measure on the key the cascade uses.
stopifnot("name_key" %in% names(r))
gcol <- function(nm) if (nm %in% names(r)) r[[nm]] else rep(NA_character_, nrow(r))
r[, `:=`(.nk = name_key, .st = gcol("state"), .z5 = gcol("zip5"))]
r <- r[!is.na(.nk) & nzchar(.nk)]
say("rows with a usable name key: %s", format(nrow(r), big.mark = ","))

sq <- function(x) sum(as.numeric(x)^2)
report <- function(label, dt) {
  bs <- dt[, .N, by = .(.nk, .st)]
  say("%-34s rows %11s | blocks %10s | max %7s | sum(N^2) %.4g",
      label, format(nrow(dt), big.mark = ","), format(nrow(bs), big.mark = ","),
      format(max(bs$N), big.mark = ","), sq(bs$N))
  invisible(list(rows = nrow(dt), blocks = nrow(bs), max = max(bs$N), cost = sq(bs$N)))
}

hr("BEFORE")
before <- report("as built", r)
bs <- r[, .N, by = .(.nk, .st)]
say("")
say("rows in (name, state) blocks of size >= 50: %s (%.2f%%)",
    format(sum(bs$N[bs$N >= 50]), big.mark = ","),
    100 * sum(bs$N[bs$N >= 50]) / nrow(r))
say("")
say("the blocks that dominate sum(N^2):")
print(head(bs[order(-N)], 8), row.names = FALSE)

hr("AFTER collapsing identical (name_key, state, zip5)")
cl <- r[, .(n_identical = .N), by = .(.nk, .st, .z5)]
after <- report("collapsed", cl)
say("")
say("reference rows   %s -> %s  (%.1f%% smaller)",
    format(before$rows, big.mark = ","), format(after$rows, big.mark = ","),
    100 * (1 - after$rows / before$rows))
say("cost driver      %.4g -> %.4g  (%.1fx cheaper)",
    before$cost, after$cost, before$cost / max(1, after$cost))
say("largest block    %s -> %s", format(before$max, big.mark = ","),
    format(after$max, big.mark = ","))

## --- what collapsing would COST, not just save ------------------------------
# Every collapsed group is a set of EINs the matcher could no longer tell apart.
# It could not tell them apart before either -- that is why they collapse -- but
# before, the ambiguity was visible as 500 tied candidates and the margin brake
# held the grant in MAYBE. After, one row wins outright. So the saving is only
# real if `n_identical` is carried and the tier logic still holds those grants.
hr("WHAT THE COLLAPSE HIDES")
multi <- cl[n_identical > 1L]
say("groups holding more than one EIN : %s (%.2f%% of collapsed rows)",
    format(nrow(multi), big.mark = ","), 100 * nrow(multi) / nrow(cl))
say("EINs inside them                 : %s (%.2f%% of the reference)",
    format(sum(multi$n_identical), big.mark = ","),
    100 * sum(multi$n_identical) / before$rows)
say("largest group                    : %s EINs", format(max(cl$n_identical), big.mark = ","))
say("")
say("distribution of group size, where > 1:")
print(table(cut(multi$n_identical, c(1, 2, 3, 5, 10, 50, 500, Inf),
                labels = c("2", "3", "4-5", "6-10", "11-50", "51-500", "500+"))))
say("")
say("the largest collapsed groups (each is one name, one state, one ZIP5):")
print(head(cl[order(-n_identical), .(name = substr(.nk, 1, 44), state = .st,
                                     zip5 = .z5, n_identical)], 10),
      row.names = FALSE)

out <- data.frame(
  ref = W,
  rows_before = before$rows, rows_after = after$rows,
  pct_smaller = 100 * (1 - after$rows / before$rows),
  cost_before = before$cost, cost_after = after$cost,
  cost_ratio = before$cost / max(1, after$cost),
  max_block_before = before$max, max_block_after = after$max,
  groups_multi = nrow(multi), eins_hidden = sum(multi$n_identical),
  stringsAsFactors = FALSE)
fwrite(out, file.path(DD, sprintf("REF-COLLAPSE-%s.csv", W)))
say(""); say("wrote data-dev/REF-COLLAPSE-%s.csv", W)
