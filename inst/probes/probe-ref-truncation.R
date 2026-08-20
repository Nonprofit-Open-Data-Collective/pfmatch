#!/usr/bin/env Rscript
# How truncated is the BMF name field, and what does that cost the comparator?
suppressWarnings(suppressMessages(library(data.table)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
NPM <- Sys.getenv("NPMATCH_DIR", "../npmatch")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 74), "\n")

hr(); say("1. IS THE BMF NAME FIELD CAPPED?"); hr()
b <- fread(file.path(NPM, "data-raw", "bmf_2026_01_processed.csv"),
           select = c("ein", "org_name_raw", "org_name_join"),
           colClasses = "character", showProgress = FALSE)
n <- nchar(b$org_name_raw)
say("org_name_raw length: max %d | mean %.1f", max(n), mean(n))
say("length histogram near the top:")
for (L in (max(n) - 6):max(n))
  say("   %2d chars : %7s records (%.2f%%)", L, format(sum(n == L), big.mark = ","),
      100 * mean(n == L))
cap <- max(n)
say("\nrecords AT the cap (i.e. probably cut off): %s (%.1f%%)",
    format(sum(n == cap), big.mark = ","), 100 * mean(n == cap))
say("examples:")
for (x in head(b$org_name_raw[n == cap], 8)) say("   %s", x)

hr(); say("2. HOW OFTEN DOES A TRUNCATED BMF NAME END MID-WORD?"); hr()
atcap <- b$org_name_raw[n == cap]
midword <- !grepl("\\s$", atcap) & !grepl("\\s[A-Z]$", atcap)
say("of the %s at the cap, %.0f%% end without a trailing space",
    format(length(atcap), big.mark = ","), 100 * mean(!grepl("\\s$", atcap)))

hr(); say("3. WHAT DOES TRUNCATION DO TO THE COMPARATOR?"); hr()
pairs <- list(
  c("PLANNED PARENTHOOD FEDERATION OF AMERICA", "PLANNED PARENTHOOD FEDERATION OF"),
  c("PLANNED PARENTHOOD FEDERATION OF AMERICA", "PLANNED PARENTHOOD EXPOSED"),
  c("COMMUNITY FOUNDATION OF WESTERN NORTH CAROLINA", "COMMUNITY FOUNDATION OF WESTERN"),
  c("EVANGELICAL LUTHERAN CHURCH IN AMERICA", "EVANGELICAL LUTHERAN CHURCH IN AMER"),
  c("BOYS AND GIRLS CLUB OF GREATER LA CROSSE", "BOYS AND GIRLS CLUB OF GREATER LA C"),
  c("MULTIPLE MYELOMA RESEARCH FOUNDATION", "MULTIPLE MYELOMA RESEARCH FOUNDATIO"))
say("%-44s %-36s %6s %6s", "query name_key", "reference name_key", "JW", "prefJW")
for (p in pairs) {
  q <- npmatch:::.np_strip_lead_the(npmatch:::.np_strip_suffix(
        npmatch:::.np_replace_tokens(npmatch:::.np_basic_clean(p[1]), npmatch:::.np_abbrev)))
  r <- npmatch:::.np_strip_lead_the(npmatch:::.np_strip_suffix(
        npmatch:::.np_replace_tokens(npmatch:::.np_basic_clean(p[2]), npmatch:::.np_abbrev)))
  jw <- 1 - stringdist::stringdist(q, r, method = "jw", p = 0.1)
  # prefix-aligned: cut the longer to the shorter, then compare
  k <- min(nchar(q), nchar(r))
  pjw <- 1 - stringdist::stringdist(substr(q, 1, k), substr(r, 1, k), method = "jw", p = 0.1)
  say("%-44s %-36s %6.3f %6.3f", substr(q, 1, 44), substr(r, 1, 36), jw, pjw)
}

hr(); say("4. HOW MANY BMF RECORDS WOULD A PREFIX RULE PUT AT RISK?"); hr()
# if we treat "reference is a prefix of query" as a match, how ambiguous is that?
setDT(b)
b[, nk := npmatch:::.np_strip_lead_the(npmatch:::.np_strip_suffix(
     npmatch:::.np_replace_tokens(npmatch:::.np_basic_clean(org_name_join), npmatch:::.np_abbrev)))]
b[, trunc := nchar(org_name_raw) == cap]
say("distinct truncated name_keys: %s", format(uniqueN(b$nk[b$trunc]), big.mark = ","))
tb <- table(b$nk[b$trunc])
say("  truncated keys held by exactly one EIN: %.1f%%", 100 * mean(tb == 1))
say("  most collided truncated key: %s (%d EINs)", names(which.max(tb)), max(tb))
saveRDS(list(cap = cap, n_at_cap = sum(n == cap)),
        file.path(PF, "data-dev", "REF-TRUNCATION-PROBE.rds"))
