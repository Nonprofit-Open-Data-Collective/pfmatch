#!/usr/bin/env Rscript
# ============================================================================
# Arm C/D: substring credit, measured separately from the comparator change.
#
# dev/BENCH-JW-AB.log measured Jaro vs Jaro-Winkler. This measures substring
# credit (config$substring_p) BOTH on the current baseline and on top of
# Jaro-Winkler, so the two changes stay attributable instead of being stacked
# into one delta nobody can decompose.
#
# Substring credit is routed into np_score()'s review-only path, so BY
# CONSTRUCTION it can only lift a pair to MAYBE, never auto-accept. The
# expected signature is a fall in NO and a rise in MAYBE with YES roughly flat.
# A rise in YES would mean the cap is not working, and should be read as a bug
# rather than a gain.
#
# NO TIMINGS -- the machine is shared (dev/BENCHMARK-NOTES.md).
#
# NOTE: written with the Write tool, not a bash heredoc. A heredoc strips one
# backslash level and turns the "\\.csv$" pattern below into "\." which R
# rejects outright. That has now cost three separate runs this session.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(devtools::load_all(
  Sys.getenv("NPMATCH_DIR", "../npmatch"), quiet = TRUE)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
setDTthreads(4L)
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("=", 90))
e9  <- function(z) { z <- gsub("[^0-9]", "", as.character(z))
                     fifelse(nchar(z) == 9L, z, NA_character_) }

grants <- pf_recover_name_from_street(
  pf_read_grants(file.path(PF, "inputs"), pattern = "^ef1k_grants_.*\\.csv$"))
ref <- readRDS(file.path(PF, "data-dev", "BMF-REF-AUG-2026-08-20.rds"))
PASSES <- c(pf_staged_passes("lean", concat = TRUE), pf_recovery_passes(state = TRUE))
hr(); say("SUBSTRING CREDIT -- %s grant rows", format(nrow(grants), big.mark = ",")); hr()

run <- function(jp, sp, tag) {
  m <- pf_match_grants(grants, ref, config = np_config(jw_p = jp, substring_p = sp),
                       passes = PASSES, recover = TRUE, verbose = FALSE)
  r <- as.data.table(m$result); r[, ein9 := e9(overall_ein)]
  tb <- table(factor(r$tier, levels = c("YES", "MAYBE", "NO")))
  say("  %-34s YES=%-5d MAYBE=%-5d NO=%-5d  (%.1f%% / %.1f%%)", tag,
      tb[["YES"]], tb[["MAYBE"]], tb[["NO"]],
      100 * tb[["YES"]] / nrow(r), 100 * (tb[["YES"]] + tb[["MAYBE"]]) / nrow(r))
  out <- r[, .(.id, tier, ein9)]
  setnames(out, ".id", "grant_id")
  out[]
}

say("  %-34s %s", "", "(A and B are in dev/BENCH-JW-AB.log)")
say("  %-34s YES=3051  MAYBE=1054  NO=738    (63.0%% / 84.8%%)", "A: Jaro, no substring [baseline]")
say("  %-34s YES=3126  MAYBE=1176  NO=541    (64.5%% / 88.8%%)", "B: Jaro-Winkler, no substring")
C <- run(NULL, 0.90, "C: Jaro + substring 0.90")
D <- run(0.1,  0.90, "D: Jaro-Winkler + substring 0.90")

v <- fread(file.path(PF, "dev", "no-residual-verdicts.csv"), colClasses = "character")
v <- v[verdict == "REAL-ORG" & nzchar(web_ein), .(grant_id = id, tgt = e9(web_ein))]
hr(); say("RECOVERY ON THE 25 ADJUDICATED CASES (biased toward current failures)"); hr()
say("  %-4s %-16s %-28s %s", "arm", "correct top pick",
    "surfaced w/ CORRECT ein", "surfaced w/ WRONG ein")
for (nm in c("C", "D")) {
  z <- merge(get(nm), v, by = "grant_id")
  ok <- !is.na(z$ein9) & z$ein9 == z$tgt
  say("  %-4s %-16s %-28s %s", nm, sprintf("%d/25", sum(ok)),
      sprintf("%d", sum(ok & z$tier %in% c("YES", "MAYBE"))),
      sprintf("%d", sum(!ok & z$tier %in% c("YES", "MAYBE"))))
}
saveRDS(list(C = C, D = D), file.path(PF, "data-dev", "BENCH-SUBSTRING-AB.rds"))
hr(); say("wrote data-dev/BENCH-SUBSTRING-AB.rds")
