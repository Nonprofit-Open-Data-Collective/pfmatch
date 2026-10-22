#!/usr/bin/env Rscript
# ============================================================================
# Re-run the 1k benchmark against the CURRENT npmatch and report the delta
# against BASELINE-2026-08.
#
# Why this is not just `PF_BASE=bench-* build-baseline.R`: that script reads the
# prebuilt REF-*.rds and WRITES INTO dev/BASELINE-2026-08/. Both are wrong here.
#
#   1. The frozen baseline is the project's reference point ("every matchdb gate
#      reduces to 'this reproduces the baseline'"). It must not be overwritten
#      by an exploratory run. Nothing here writes to that directory.
#   2. The prebuilt references were compiled under normalizer signature
#      v1-421e1e2a6afb024e. The current npmatch is v1-b42811fe6601afe6, moved by
#      600d38b ("name_core key, placeholder flag and 990 abbreviations"). The
#      signature registry covers the normalizer AND "corpus statistics shipped
#      alongside a compiled reference", so the bundles are stale too. Matching a
#      newly-normalized query against an old-normalizer reference would compare
#      two different name spaces and the result would mean nothing. The
#      reference is therefore recompiled here, under the current normalizer.
#
#   PF_ARM=active|augmented   which reference to rebuild and bench
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
PF  <- Sys.getenv("PFMATCH_DIR", ".")
DD  <- file.path(PF, "data-dev")
ARM <- Sys.getenv("PF_ARM", "active")
say <- function(...) message(sprintf(...))      # stderr: unbuffered
hr  <- function() message(strrep("=", 78))

suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))

SRC <- switch(ARM,
  active    = file.path(PF, "..", "npmatch", "data-raw", "bmf_2026_01_processed.csv"),
  augmented = file.path(DD, "BMF-AUGMENTED-unified-fixed.csv"),
  stop("PF_ARM must be 'active' or 'augmented'"))
CACHE <- file.path(DD, sprintf("RECHECK-REF-%s.rds", ARM))

hr(); say("RECHECK vs npmatch %s   arm = %s",
          as.character(utils::packageVersion("npmatch")), ARM); hr()
say("normalizer signature now    : %s", np_normalize_signature())
say("normalizer signature pinned : v1-421e1e2a6afb024e")
say("")

t0 <- proc.time()[["elapsed"]]
ref <- pf_reference(SRC, cache = CACHE, verbose = FALSE)
say("reference recompiled: %s rows in %.1f min",
    format(nrow(ref$reference), big.mark = ","), (proc.time()[["elapsed"]] - t0) / 60)

# identical query construction to build-baseline.R::run_bench()
grants <- pf_read_grants(file.path(PF, "inputs"), pattern = "^1k_grants_.*\\.csv$")
grants <- pf_recover_name_from_street(grants)
passes <- c(pf_staged_passes("lean", concat = TRUE), pf_recovery_passes(state = TRUE))
say("matching %s grants, %d passes ...", format(nrow(grants), big.mark = ","), length(passes))
t1 <- proc.time()[["elapsed"]]
m  <- pf_match_grants(grants, ref, passes = passes, recover = TRUE, verbose = FALSE)
say("  matched in %.1f s", proc.time()[["elapsed"]] - t1)

res <- as.data.frame(m$result)
res <- res[order(res$.id), , drop = FALSE]
now <- table(factor(res$tier, levels = c("YES", "MAYBE", "NO")))

base <- readRDS(file.path(PF, "dev", "BASELINE-2026-08",
                          sprintf("benchmark-1k-%s.rds", ARM)))
was <- table(factor(base$tier, levels = c("YES", "MAYBE", "NO")))

hr(); say("TIER COUNTS"); hr()
say("%-8s %10s %10s %9s %9s", "tier", "baseline", "now", "delta", "now %")
tot_now <- nrow(res); tot_was <- nrow(base)
for (k in c("YES", "MAYBE", "NO"))
  say("%-8s %10d %10d %+9d %8.1f%%", k, was[[k]], now[[k]],
      now[[k]] - was[[k]], 100 * now[[k]] / tot_now)
say("%-8s %10d %10d %+9d", "total", tot_was, tot_now, tot_now - tot_was)
say("")
say("YES rate   : %.1f%%  (baseline %.1f%%)",
    100 * now[["YES"]] / tot_now, 100 * was[["YES"]] / tot_was)
say("YES+MAYBE  : %.1f%%  (baseline %.1f%%)",
    100 * (now[["YES"]] + now[["MAYBE"]]) / tot_now,
    100 * (was[["YES"]] + was[["MAYBE"]]) / tot_was)

# per-identity movement, on the identities both runs reached
hr(); say("PER-IDENTITY MOVEMENT (identities present in both)"); hr()
b <- data.table(.id = base$.id, tier_was = base$tier,
                ein_was = if (!is.null(base$.ein)) base$.ein else NA_character_)
n <- data.table(.id = res$.id,  tier_now = res$tier,
                ein_now = if (!is.null(res$.ein)) res$.ein else NA_character_)
j <- merge(b, n, by = ".id")
say("compared: %s identities", format(nrow(j), big.mark = ","))
say("only in baseline: %d | only in recheck: %d",
    nrow(b) - nrow(j), nrow(n) - nrow(j))
mv <- j[tier_was != tier_now, .N, by = .(tier_was, tier_now)][order(-N)]
say("tier changed: %d (%.2f%%)", sum(mv$N), 100 * sum(mv$N) / nrow(j))
if (nrow(mv)) for (i in seq_len(nrow(mv)))
  say("    %-6s -> %-6s %6d", mv$tier_was[i], mv$tier_now[i], mv$N[i])
same_tier <- j[tier_was == tier_now & tier_now == "YES"]
if (nrow(same_tier))
  say("EIN changed while still YES: %d of %d",
      sum(!is.na(same_tier$ein_was) & same_tier$ein_was != same_tier$ein_now),
      nrow(same_tier))

saveRDS(res, file.path(DD, sprintf("RECHECK-bench-%s.rds", ARM)), compress = "xz")
say("")
say("wrote data-dev/RECHECK-bench-%s.rds (baseline directory untouched)", ARM)
