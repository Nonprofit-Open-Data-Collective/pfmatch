#!/usr/bin/env Rscript
# ============================================================================
# address-only-match.R -- can a grant with no recipient name be matched on its
# address alone, and how often is the answer unique?
#
# The question has two halves and they must not be conflated:
#   (1) does the address resolve to ANY BMF record?      -- recall
#   (2) does it resolve to EXACTLY ONE organization?     -- usability
# An address shared by 40 nonprofits (a PO box, a big office tower, a fiscal
# sponsor) answers (1) and is worthless for (2).
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
NPM <- Sys.getenv("NPMATCH_DIR", "../npmatch")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")

grants <- pf_read_grants(file.path(PF, "inputs"), pattern = "^1k_grants_.*\\.csv$")
ref <- readRDS(file.path(PF, "data-dev", "BMF-REFERENCE-BUNDLE.rds"))$reference

nn <- grants[!grants$has_name, , drop = FALSE]
say("grants: %d | with no recipient name: %d (%.1f%%)", nrow(grants), nrow(nn),
    100 * nrow(nn) / nrow(grants))
say("  of those, carrying a usable address: %d", sum(nn$has_address))
say("  street present: %d | city: %d | state: %d | zip5: %d",
    sum(!is.na(nn$recip_street)), sum(!is.na(nn$recip_city)),
    sum(!is.na(nn$recip_state)), sum(!is.na(nn$recip_zip5)))
if (sum(nn$has_address) == 0) { say("nothing to match; stopping"); quit(save = "no") }

# normalize the address side of the name-less grants the same way as the reference
q <- npmatch::np_normalize(npmatch::np_query(nn, pf_map_grants()))

# ---- how discriminating is a BMF address in general? ------------------------
rk <- paste(ref$street_key, ref$zip5)
ok <- !is.na(ref$street_key) & nzchar(ref$street_key) & !is.na(ref$zip5)
tb <- table(rk[ok])
say("\nBMF records with a usable street+zip5: %s over %s distinct addresses",
    format(sum(ok), big.mark = ","), format(length(tb), big.mark = ","))
say("  addresses holding exactly one organization: %.1f%%", 100 * mean(tb == 1))
say("  median orgs per address: %.0f | 99th pct: %.0f | max: %s",
    stats::median(tb), stats::quantile(tb, .99), format(max(tb), big.mark = ","))
say("  the ten most crowded addresses hold %s records between them",
    format(sum(sort(tb, decreasing = TRUE)[1:10]), big.mark = ","))

# ---- match the name-less grants on street+zip5 ------------------------------
qk <- paste(q$street_key, q$zip5)
usable <- !is.na(q$street_key) & nzchar(q$street_key) & !is.na(q$zip5)
n_hit <- rep(0L, nrow(q))
n_hit[usable] <- as.integer(tb[qk[usable]])
n_hit[is.na(n_hit)] <- 0L

say("\nADDRESS-ONLY MATCH (exact street_key + zip5), n = %d name-less grants", nrow(q))
say("  usable street+zip5 on the grant side : %d", sum(usable))
say("  address found in the BMF             : %d", sum(n_hit > 0))
say("    resolving to exactly ONE org       : %d", sum(n_hit == 1))
say("    resolving to 2-5 orgs              : %d", sum(n_hit >= 2 & n_hit <= 5))
say("    resolving to >5 orgs               : %d", sum(n_hit > 5))

# looser fallback: zip5 + city only, to show what the ceiling looks like
say("\nfor reference, ZIP5 alone (never usable as an identifier, shown as a ceiling):")
tz <- table(ref$zip5[!is.na(ref$zip5)])
zh <- as.integer(tz[q$zip5]); zh[is.na(zh)] <- 0L
say("  median orgs sharing a grant's ZIP5: %.0f", stats::median(zh[zh > 0]))

# ---- what do the unique hits actually look like? ----------------------------
uni <- which(n_hit == 1)
if (length(uni)) {
  say("\nthe unique-address matches:")
  for (i in uni) {
    j <- which(rk == qk[i] & ok)[1]
    say("  [%s] %s, %s %s", nn$grant_id[i], q$street_key[i], q$city[i], q$zip5[i])
    say("      -> %s (%s, %s) ein %s", ref$name[j], ref$city[j], ref$state[j], ref$.ein[j])
    say("      purpose: %s", substr(nn$SIGOCPYPOGOC[i], 1, 70))
  }
}
# ---- and the crowded ones, to make the ambiguity concrete -------------------
crowd <- which(n_hit > 5)
if (length(crowd)) {
  say("\nexample of a crowded address (why address-only cannot stand alone):")
  i <- crowd[1]; j <- head(which(rk == qk[i] & ok), 4)
  say("  grant address: %s %s -> %d BMF organizations, including:", q$street_key[i], q$zip5[i], n_hit[i])
  for (k in j) say("      %s", ref$name[k])
}
