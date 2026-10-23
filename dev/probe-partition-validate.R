#!/usr/bin/env Rscript
# ============================================================================
# probe-partition-validate.R -- does the partitioned run reproduce the frozen
# baseline's verdicts?
#
# The bar, per the decision on 2026-08-22, is NO TIER REGRESSIONS -- not exact
# pair equality. The reasons are measured rather than assumed:
#
#   * The pair-set residual is per-query, not systematic: 73 of 496 queries in
#     the CA probe, with the only-in-full side collapsing to four identities
#     (dev/STATE-PARTITION-FINDINGS.md Part 4).
#   * 20 of the 25 EIN disagreements were exact score ties, and those are now
#     resolved by a stated rule rather than by row order
#     (npmatch@f14f1d9, BASELINE-2026-08 revision 2).
#
# So this compares the partitioned run against the RE-FROZEN benchmark, on the
# five 1k grant files and the active reference -- the same input the freeze uses,
# so the comparison is like-for-like.
#
#   PF_REF   active | augmented   (default active, matching benchmark-1k-active)
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- "."
suppressWarnings(suppressMessages(devtools::load_all("../npmatch", quiet = TRUE)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
setDTthreads(0L)
DD <- file.path(PF, "data-dev")
W  <- Sys.getenv("PF_REF", "active")
say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function(t = NULL) { cat(strrep("=", 78), "\n")
                            if (!is.null(t)) { cat(t, "\n"); cat(strrep("=", 78), "\n") } }
tick <- function() proc.time()[["elapsed"]]
ws <- function() {
  v <- tryCatch(system2("powershell", c("-NoProfile","-Command",
    sprintf("(Get-Process -Id %d).PeakWorkingSet64", Sys.getpid())),
    stdout = TRUE, stderr = FALSE), error = function(e) NA_character_)
  suppressWarnings(as.numeric(v[length(v)]))/1e9
}

hr(sprintf("PARTITION VALIDATION -- %s reference, vs BASELINE-2026-08 rev 2", W))
BASE <- Sys.getenv("PF_BASE_FILE", "")
base <- if (nzchar(BASE)) readRDS(BASE) else
  readRDS(file.path(PF, "dev", "BASELINE-2026-08", sprintf("benchmark-1k-%s.rds", W)))
say("comparison target: %s", if (nzchar(BASE)) BASE else "BASELINE-2026-08")
say("baseline: %d identities", nrow(base))

g <- pf_read_grants(file.path(PF, "inputs"), pattern = "^1k_grants_.*[.]csv$")
g <- pf_recover_name_from_street(g)
ref <- readRDS(file.path(DD, switch(W, active = "REF-active.rds",
                                    augmented = "REF-augmented.rds")))
ref$reference <- pf_add_recovery_keys(ref$reference)
say("reference: %s rows | working set %.2f GB",
    format(nrow(ref$reference), big.mark = ","), ws())

t0 <- tick()
part <- pf_partition_reference(ref, min_rows = 5000L, verbose = FALSE)
say("partitioned into %d shards in %.0f s (largest %s rows)", length(part),
    tick() - t0, format(max(vapply(part, function(s) nrow(s$reference), 1L)),
                        big.mark = ","))
sz <- sort(vapply(part, function(s) nrow(s$reference), 1L), decreasing = TRUE)
say("  top shards: %s", paste(sprintf("%s=%s", names(head(sz, 5)),
                                      format(head(sz, 5), big.mark = ",")),
                              collapse = "  "))

t0 <- tick()
m <- pf_run_partitioned(g, part, ref, verbose = TRUE)
el <- tick() - t0
res <- as.data.frame(m$result); res <- res[order(res$.id), , drop = FALSE]
say("")
say("partitioned run: %.0f s | process peak %.2f GB", el, ws())

## ---- compare ---------------------------------------------------------------
hr("VERDICTS")
b <- base[order(base$.id), , drop = FALSE]
say("identities   baseline %d | partitioned %d", nrow(b), nrow(res))
tb <- table(factor(as.character(b$tier), c("YES","MAYBE","NO")))
tp <- table(factor(as.character(res$tier), c("YES","MAYBE","NO")))
say("baseline     YES %4d  MAYBE %4d  NO %4d", tb[["YES"]], tb[["MAYBE"]], tb[["NO"]])
say("partitioned  YES %4d  MAYBE %4d  NO %4d", tp[["YES"]], tp[["MAYBE"]], tp[["NO"]])

mm <- merge(b[, c(".id","tier","overall_ein","overall_score")],
            res[, c(".id","tier","overall_ein","overall_score")],
            by = ".id", suffixes = c(".b", ".p"))
say("")
say("identities in both: %d", nrow(mm))
say("  same tier : %d (%.2f%%)", sum(as.character(mm$tier.b) == as.character(mm$tier.p)),
    100*mean(as.character(mm$tier.b) == as.character(mm$tier.p)))
say("  same EIN  : %d (%.2f%%)", sum(mm$overall_ein.b == mm$overall_ein.p, na.rm = TRUE),
    100*mean(mm$overall_ein.b == mm$overall_ein.p, na.rm = TRUE))

hr("TIER MOVEMENT -- the bar")
mv <- table(baseline = factor(as.character(mm$tier.b), c("YES","MAYBE","NO")),
            partitioned = factor(as.character(mm$tier.p), c("YES","MAYBE","NO")))
print(mv)
regress <- sum(mv["YES","MAYBE"], mv["YES","NO"], mv["MAYBE","NO"])
gain    <- sum(mv["MAYBE","YES"], mv["NO","YES"], mv["NO","MAYBE"])
say("")
say("REGRESSIONS (YES->MAYBE/NO, MAYBE->NO) : %d", regress)
say("gains       (MAYBE/NO->YES, NO->MAYBE) : %d", gain)
lost <- setdiff(b$.id, res$.id); added <- setdiff(res$.id, b$.id)
say("identities only in baseline            : %d", length(lost))
say("identities only in partitioned         : %d", length(added))
say("")
say("VERDICT: %s", if (regress == 0 && length(lost) == 0) "PASSES the no-regression bar"
                   else "FAILS")

fwrite(data.table(ref = W, seconds = el, shards = length(part),
                  same_tier = sum(as.character(mm$tier.b) == as.character(mm$tier.p)),
                  n = nrow(mm), regressions = regress, gains = gain,
                  only_baseline = length(lost), only_partitioned = length(added)),
       file.path(DD, sprintf("PARTITION-VALIDATE-%s.csv", W)))
saveRDS(res, file.path(DD, sprintf("PARTITION-RESULT-%s.rds", W)), compress = FALSE)
say("wrote data-dev/PARTITION-VALIDATE-%s.csv", W)
