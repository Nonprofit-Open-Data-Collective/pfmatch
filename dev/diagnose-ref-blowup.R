#!/usr/bin/env Rscript
# ============================================================================
# Why the augmented unified reference is ~60x slower: identical-name blocks.
#
# The unified BMF carries every EIN since 1989, and the rows it adds over the
# monthly snapshot are disproportionately group-ruling subordinates -- 15,813
# rows named TOASTMASTERS INTERNATIONAL, 11,336 named INTERNATIONAL ASSOCIATION
# OF LIONS CLUBS. The exact-name-and-state pass blocks on the name key, so a
# query with one of those names draws every one of them as a candidate, and
# scoring is linear in candidates per query while the tail is enormous.
#
# Those rows carry no information the matcher can use: 500 identically-named
# rows in one state cannot be told apart by name or address, so keeping 500
# copies buys nothing and costs everything. Collapse them to one representative
# and record how many EINs it stands for, so the tier logic can still say
# "ambiguous, N identical candidates".
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(library(npmatch)))
setDTthreads(6L)
DR <- "C:/Users/jlecy/Dropbox/00 - URBAN/00-GITHUB/npmatch/data-raw"
PF <- "."
say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() { cat(strrep("-", 78), "\n"); flush.console() }

nk <- function(x) {
  x <- toupper(ifelse(is.na(x), "", x))
  x <- gsub("[^A-Z0-9 ]", " ", x)
  trimws(gsub(" +", " ", x))
}

for (f in c(monthly = file.path(DR, "bmf_2026_01_processed.csv"),
            augmented = file.path(PF, "data-dev", "BMF-AUGMENTED-bmf_unified_geocoded_2026-08-20.csv"))) {
  nm <- names(which(c(monthly = file.path(DR, "bmf_2026_01_processed.csv"),
                      augmented = file.path(PF, "data-dev", "BMF-AUGMENTED-bmf_unified_geocoded_2026-08-20.csv")) == f))
  d <- fread(f, colClasses = "character", showProgress = FALSE,
             select = c("ein", "org_name_join", "org_addr_state", "org_addr_zip5"))
  d[, k := nk(org_name_join)]
  d <- d[nzchar(k)]
  hr(); say("%s -- %s rows", toupper(nm), format(nrow(d), big.mark = ","))

  bs <- d[, .N, by = .(k, org_addr_state)]
  say("distinct (name, state) blocks : %s", format(nrow(bs), big.mark = ","))
  say("largest block                 : %s rows", format(max(bs$N), big.mark = ","))
  say("sum of squared block sizes    : %.3g   <- the cost driver", sum(as.numeric(bs$N)^2))
  say("rows in blocks of size >= 50  : %s (%.1f%%)",
      format(sum(bs$N[bs$N >= 50]), big.mark = ","),
      100 * sum(bs$N[bs$N >= 50]) / nrow(d))
  say("")
  say("top (name, state) blocks:")
  print(head(bs[order(-N)], 6), row.names = FALSE)

  # what collapsing on (name, state, zip5) would do
  cl <- d[, .N, by = .(k, org_addr_state, org_addr_zip5)]
  say("")
  say("collapsing identical (name, state, zip5):")
  say("  reference rows %s -> %s (%.1f%% smaller)",
      format(nrow(d), big.mark = ","), format(nrow(cl), big.mark = ","),
      100 * (1 - nrow(cl) / nrow(d)))
  bs2 <- cl[, .(N = .N), by = .(k, org_addr_state)]
  say("  sum of squared block sizes %.3g -> %.3g (%.0fx cheaper)",
      sum(as.numeric(bs$N)^2), sum(as.numeric(bs2$N)^2),
      sum(as.numeric(bs$N)^2) / max(1, sum(as.numeric(bs2$N)^2)))
  rm(d, bs, cl, bs2); invisible(gc())
}
