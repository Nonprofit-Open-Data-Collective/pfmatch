#!/usr/bin/env Rscript
# matchdb has strictly more true names per EIN than the augmented BMF, so a
# 2.9-point DROP in the clear rate cannot be loss of signal. The question is
# which of two things it is:
#
#   (a) competition -- the right EIN is still the top pick, but an extra name
#       row pulled a rival into the tie band, so np_tier() demotes YES to
#       MAYBE. That is a selection/tiering problem, not a reference problem,
#       and matchdb would still be the better reference.
#   (b) displacement -- an extra name row outscores the right answer and the
#       top pick actually changes. That is a precision cost and a real reason
#       to gate the spec harder.
#
# Told apart by comparing the chosen EIN per identity across the two runs.
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
PF <- Sys.getenv("PFMATCH_DIR", ".")
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("-", 78))

a <- as.data.table(readRDS(file.path(PF, "data-dev", "BENCH-EFILEPF-augmented.rds")))
b <- as.data.table(readRDS(file.path(PF, "data-dev", "BENCH-MATCHDB.rds")))
say("augmented BMF: %s identities | matchdb: %s identities",
    format(nrow(a), big.mark = ","), format(nrow(b), big.mark = ","))

idc  <- intersect(c(".id", "id", "grant_id"), names(a))[1]
einc <- intersect(c("overall_ein", ".ein", "ein"), names(a))[1]
say("keying on %s, EIN column %s", idc, einc)

# matchdb carries EINs as "EIN-81-3871444" and the BMF side as "81-3871444",
# so a raw string comparison reports 100% churn and means nothing. Compare
# on digits only.
e9 <- function(v) { v <- gsub("[^0-9]", "", as.character(v))
                    ifelse(nchar(v) == 9L, v, NA_character_) }
A <- a[, .(id = get(idc), tier_a = tier, ein_a = e9(get(einc)))]
B <- b[, .(id = get(idc), tier_b = tier, ein_b = e9(get(einc)))]
j <- merge(A, B, by = "id")
say("compared on %s identities present in both", format(nrow(j), big.mark = ","))
say("only in augmented: %d | only in matchdb: %d", nrow(A) - nrow(j), nrow(B) - nrow(j))

hr(); say("TIER MOVEMENT, augmented -> matchdb")
mv <- j[tier_a != tier_b, .N, by = .(tier_a, tier_b)][order(-N)]
say("changed: %s of %s (%.1f%%)", format(sum(mv$N), big.mark = ","),
    format(nrow(j), big.mark = ","), 100 * sum(mv$N) / nrow(j))
print(mv, row.names = FALSE)

hr(); say("THE DECISIVE QUESTION: DID THE ANSWER CHANGE, OR JUST THE TIER?")
dem <- j[tier_a == "YES" & tier_b == "MAYBE"]
say("YES -> MAYBE demotions: %s", format(nrow(dem), big.mark = ","))
if (nrow(dem)) {
  same <- dem[!is.na(ein_a) & !is.na(ein_b) & ein_a == ein_b]
  say("  same EIN still chosen : %s (%.0f%%)  <- competition, tier rule demoted it",
      format(nrow(same), big.mark = ","), 100 * nrow(same) / nrow(dem))
  say("  different EIN chosen  : %s (%.0f%%)  <- displacement, a real precision cost",
      format(nrow(dem) - nrow(same), big.mark = ","),
      100 * (nrow(dem) - nrow(same)) / nrow(dem))
}
say("")
kept <- j[tier_a == "YES" & tier_b == "YES"]
if (nrow(kept)) {
  ch <- kept[!is.na(ein_a) & !is.na(ein_b) & ein_a != ein_b]
  say("identities YES in BOTH: %s | of those the EIN CHANGED on %s (%.1f%%)",
      format(nrow(kept), big.mark = ","), format(nrow(ch), big.mark = ","),
      100 * nrow(ch) / nrow(kept))
  say("  (EIN churn among retained YES is the clearest precision signal there is)")
}
say("")
gain <- j[tier_a != "YES" & tier_b == "YES"]
say("promotions INTO YES that matchdb earned: %s", format(nrow(gain), big.mark = ","))
say("  net YES change: %+d", nrow(gain) - nrow(dem) - nrow(j[tier_a == "YES" & tier_b == "NO"]))

fwrite(j, file.path(PF, "data-dev", "MATCHDB-VS-AUGMENTED.csv"))
say("")
say("wrote data-dev/MATCHDB-VS-AUGMENTED.csv")
