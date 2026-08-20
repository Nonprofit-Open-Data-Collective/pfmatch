#!/usr/bin/env Rscript
# Why does PLANNED PARENTHOOD FEDERATION OF AMERICA lose to PLANNED PARENTHOOD
# EXPOSED? Is it truncation, or something else entirely? Run the real comparator.
suppressWarnings(suppressMessages(library(data.table)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
NPM <- Sys.getenv("NPMATCH_DIR", "../npmatch")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 74), "\n")

a <- fread(file.path(PF, "data-dev", "AUDIT-MAYBE-100.csv"), colClasses = "character")
x <- a[grant_id == "G002178"]
hr(); say("THE CANDIDATE ROWS AS SCORED"); hr()
say("filed: %s | %s, %s %s", x$recip_name[1], x$recip_city[1], x$recip_state[1], x$recip_zip5[1])
print(x[, .(rank, cand_name = substr(cand_name, 1, 42), cand_city, cand_state,
            score, name_sim, geo_zip5, geo_city, geo_state)], row.names = FALSE)

hr(); say("RECONSTRUCT THE NAME KEYS"); hr()
nk <- function(v) {
  d <- np_normalize(np_query(data.frame(id = seq_along(v), name = v, state = "XX",
                                        stringsAsFactors = FALSE),
                             c(.id = "id", name = "name", state = "state")))
  d$name_key
}
q  <- x$recip_name[1]
cn <- x$cand_name
keys <- nk(c(q, cn))
say("query   name_key: '%s'", keys[1])
for (i in seq_along(cn))
  say("  cand %d name_key: '%-40s' JW=%.3f", i, keys[i + 1],
      1 - stringdist::stringdist(keys[1], keys[i + 1], method = "jw", p = 0.1))

hr(); say("SO WHAT DECIDED IT?"); hr()
say("name_sim as scored : %s", paste(x$name_sim, collapse = "  "))
say("score      as scored: %s", paste(x$score, collapse = "  "))
say("")
say("If JW ranks the correct candidate ABOVE the distractor but the pipeline's")
say("name_sim does not, the loss is in np_compare(), not in truncation.")

hr(); say("REFERENCE-SIDE TRUNCATION: HOW COMMON IS MID-PHRASE CUTOFF?"); hr()
b <- fread(file.path(NPM, "data-raw", "bmf_2026_01_processed.csv"),
           select = "org_name_join", colClasses = "character", showProgress = FALSE)
v <- b$org_name_join
# a name ending in a dangling preposition/article is almost certainly cut off
dangle <- grepl("\\b(OF|AND|THE|FOR|IN|TO|AT|A|AN|&)\\s*$", toupper(v))
say("BMF names ending in a dangling function word: %s (%.2f%%)",
    format(sum(dangle), big.mark = ","), 100 * mean(dangle))
say("examples:"); for (s in head(v[dangle], 8)) say("   %s", s)
# spurious mid-word space, e.g. "AMER ICA"
say("")
say("BMF names containing a 3-4 letter token immediately followed by a 2-4 letter")
say("token, both uppercase (the 'AMER ICA' split-word pattern):")
split_pat <- grepl("\\b[A-Z]{3,4} [A-Z]{2,4}\\b$", toupper(v))
say("  %s (%.2f%%)", format(sum(split_pat), big.mark = ","), 100 * mean(split_pat))
for (s in head(v[split_pat], 6)) say("   %s", s)
