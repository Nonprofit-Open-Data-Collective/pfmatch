#!/usr/bin/env Rscript
# ============================================================================
# Parameterise the BMF-vs-matchdb trade-off, and simulate the two-tier cascade.
#
# The two-tier proposal needs no new matching. Tier 1 is the augmented-BMF run,
# tier 2 is the matchdb run restricted to the identities tier 1 did not clear.
# Both runs exist over the same 5,000 grants, so the cascade is a join.
#
# What it cannot tell us without adjudication, and which is stated rather than
# glossed: whether a given EIN is RIGHT. Everything below counts agreement and
# movement, not correctness. The one quantity the user named as unrecoverable
# -- a tier-1 YES on the wrong EIN -- is invisible here by construction, since
# tier 2 never sees those identities.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
PF <- Sys.getenv("PFMATCH_DIR", ".")
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("=", 78))
sub <- function() message(strrep("-", 78))

e9 <- function(v) { v <- gsub("[^0-9]", "", as.character(v))
                    ifelse(nchar(v) == 9L, v, NA_character_) }
rd <- function(f) {
  d <- as.data.table(readRDS(file.path(PF, "data-dev", f)))
  d[, .(id = .id, tier, ein = e9(overall_ein), score = overall_score,
        margin = overall_margin, n_close, runner = runner_up_score)]
}
A <- rd("BENCH-EFILEPF-augmented.rds")   # tier 1 candidate: augmented BMF
B <- rd("BENCH-MATCHDB.rds")             # tier 2 candidate: matchdb

hr(); say("1. THE TWO REFERENCES, SIDE BY SIDE"); hr()
say("%-22s %12s %12s", "", "augmented BMF", "matchdb")
say("%-22s %12s %12s", "identities reached",
    format(nrow(A), big.mark = ","), format(nrow(B), big.mark = ","))
for (k in c("YES", "MAYBE", "NO"))
  say("%-22s %11s%% %11s%%", k,
      sprintf("%.1f", 100 * mean(A$tier == k)), sprintf("%.1f", 100 * mean(B$tier == k)))

j <- merge(A, B, by = "id", all = TRUE, suffixes = c("_a", "_b"))
j[is.na(tier_a), tier_a := "UNREACHED"][is.na(tier_b), tier_b := "UNREACHED"]
say("")
say("union of identities: %s", format(nrow(j), big.mark = ","))

hr(); say("2. PARAMETERISED MOVEMENT, BMF -> matchdb"); hr()
j[, cell := fcase(
  tier_a == "YES"   & tier_b == "YES"   & !is.na(ein_a) & ein_a == ein_b, "YES->YES  same EIN",
  tier_a == "YES"   & tier_b == "YES",                                    "YES->YES  EIN CHANGED",
  tier_a == "YES"   & tier_b == "MAYBE",                                  "YES->MAYBE  demoted",
  tier_a == "YES"   & tier_b %in% c("NO", "UNREACHED"),                   "YES->NO    lost",
  tier_a == "MAYBE" & tier_b == "YES",                                    "MAYBE->YES cleared",
  tier_a == "NO"    & tier_b == "YES",                                    "NO->YES    recovered",
  tier_a == "UNREACHED" & tier_b == "YES",                                "new->YES   recovered",
  tier_a == "MAYBE" & tier_b == "MAYBE",                                  "MAYBE->MAYBE",
  tier_a == "MAYBE" & tier_b %in% c("NO", "UNREACHED"),                   "MAYBE->NO",
  tier_a == "NO"    & tier_b == "MAYBE",                                  "NO->MAYBE  surfaced",
  tier_a == "NO"    & tier_b %in% c("NO", "UNREACHED"),                   "NO->NO",
  default = "other")]
ct <- j[, .N, by = cell][order(-N)]
ct[, pct := sprintf("%.1f%%", 100 * N / nrow(j))]
print(ct, row.names = FALSE)

gain <- j[cell %in% c("MAYBE->YES cleared", "NO->YES    recovered", "new->YES   recovered"), .N]
lose <- j[cell %in% c("YES->MAYBE  demoted", "YES->NO    lost"), .N]
churn <- j[cell == "YES->YES  EIN CHANGED", .N]
say("")
say("gross YES gained : %s", format(gain, big.mark = ","))
say("gross YES lost   : %s", format(lose, big.mark = ","))
say("net              : %+d", gain - lose)
say("EIN churn on retained YES: %s (%.1f%% of YES->YES)", format(churn, big.mark = ","),
    100 * churn / j[tier_a == "YES" & tier_b == "YES", .N])

hr(); say("3. TWO-TIER CASCADE: BMF FIRST, matchdb ON WHAT IS LEFT"); hr()
say("Tier 1 = augmented BMF on everything. Tier 2 = matchdb, but only on the")
say("identities tier 1 left as MAYBE or NO. Tier-1 YES is never revisited.")
say("")
t1 <- A[, .N, by = tier][order(-N)]
say("TIER 1 outcome over %s identities:", format(nrow(A), big.mark = ","))
for (k in c("YES", "MAYBE", "NO"))
  say("  %-6s %6s (%.1f%%)", k, format(sum(A$tier == k), big.mark = ","),
      100 * mean(A$tier == k))

for (scope in list(c("MAYBE"), c("MAYBE", "NO"))) {
  lbl <- paste(scope, collapse = " + ")
  elig <- j[tier_a %in% scope]
  cleared <- elig[tier_b == "YES", .N]
  surfaced <- elig[tier_a == "NO" & tier_b == "MAYBE", .N]
  demoted <- elig[tier_a == "MAYBE" & tier_b == "NO", .N]
  sub(); say("TIER 2 SCOPE = %s   (%s identities, %.0f%% of the file)",
             lbl, format(nrow(elig), big.mark = ","), 100 * nrow(elig) / nrow(j))
  say("  newly cleared to YES        : %s", format(cleared, big.mark = ","))
  say("  NO -> MAYBE (new candidates): %s", format(surfaced, big.mark = ","))
  if ("MAYBE" %in% scope && "NO" %in% scope)
    say("  MAYBE -> NO (candidates lost): %s", format(demoted, big.mark = ","))
  finalyes <- sum(A$tier == "YES") + cleared
  say("  FINAL clear rate            : %.1f%%  (tier 1 alone: %.1f%%)",
      100 * finalyes / nrow(j), 100 * sum(A$tier == "YES") / nrow(j))
  say("  cost: tier-2 matching on %.0f%% of the file", 100 * nrow(elig) / nrow(j))
}

hr(); say("4. WHAT THE TWO-TIER CASCADE CANNOT RECOVER"); hr()
wrong1 <- j[tier_a == "YES" & tier_b == "YES" & ein_a != ein_b, .N]
say("tier-1 YES whose EIN matchdb disagrees with : %s", format(wrong1, big.mark = ","))
say("  Tier 2 never sees these, so if tier 1 is the one that is wrong, the")
say("  error is permanent. Which side is right is NOT established here --")
say("  that needs adjudication, and it is the single most important number")
say("  still missing from this comparison.")
say("")
say("tier-1 YES that matchdb demotes or loses    : %s",
    format(j[tier_a == "YES" & tier_b %in% c("MAYBE", "NO", "UNREACHED"), .N], big.mark = ","))
say("  Also invisible to a two-tier cascade, and also unadjudicated.")

fwrite(j, file.path(PF, "data-dev", "TWO-TIER-SIMULATION.csv"))
say("")
say("wrote data-dev/TWO-TIER-SIMULATION.csv")
