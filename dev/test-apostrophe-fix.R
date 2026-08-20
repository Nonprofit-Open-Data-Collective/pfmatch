#!/usr/bin/env Rscript
# Test the ACTUAL proposed fix rather than the de-spacing proxy: delete the
# apostrophe (rather than letting it become a space) before normalization, so
# the grant side collapses possessives the same way the NCCS BMF already does.
suppressWarnings(suppressMessages(library(data.table)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
NPM <- Sys.getenv("NPMATCH_DIR", "../npmatch")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))

ref <- readRDS(file.path(PF, "data-dev", "BMF-REFERENCE-BUNDLE.rds"))$reference
rkey <- ref$name_key
m <- readRDS(file.path(PF, "data-dev", "PF-MATCH-RESULT-1k.rds"))
g <- m$grants
st <- pf_status(m)

apos <- (grepl("'", g$recip_name, fixed = TRUE) |
         grepl("\u2019", g$recip_name, fixed = TRUE)) & g$in_scope
qa <- g$recip_name[apos]
status_now <- st$status[match(g$grant_id[apos], st$grant_id)]

norm_key <- function(v) {
  d <- data.frame(grant_id = seq_along(v), recip_name = v, recip_name_alt = NA,
                  recip_street = NA, recip_unit = NA, recip_city = NA,
                  recip_state = NA, recip_zip5 = NA, stringsAsFactors = FALSE)
  npmatch::np_normalize(npmatch::np_query(d, pf_map_grants()))$name_key
}

key_now <- norm_key(qa)
# the fix: strip the apostrophe entirely first, so LUKE'S -> LUKES not LUKE S
key_fix <- norm_key(gsub("['\u2019]", "", qa))

hit_now <- key_now %in% rkey
hit_fix <- key_fix %in% rkey

cat(sprintf("apostrophe names, in scope: %d\n", length(qa)))
cat(sprintf("  exact BMF name_key hit today          : %3d (%.1f%%)\n",
            sum(hit_now), 100 * mean(hit_now)))
cat(sprintf("  exact BMF name_key hit with the fix   : %3d (%.1f%%)\n",
            sum(hit_fix), 100 * mean(hit_fix)))
cat(sprintf("  NEWLY reachable by an exact-name pass : %3d\n", sum(hit_fix & !hit_now)))

cat("\nof those newly reachable, current outcome:\n")
print(table(factor(status_now[hit_fix & !hit_now], c("YES", "MAYBE", "NO"))))

cat("\nsample of names the fix newly reaches:\n")
new <- which(hit_fix & !hit_now)
for (i in head(new, 12))
  cat(sprintf("  %-42s  %-30s -> %s\n", substr(qa[i], 1, 42),
              substr(key_now[i], 1, 30), substr(key_fix[i], 1, 30)))

# how much of the whole sample does this touch?
cat(sprintf("\napostrophe names as a share of in-scope grants: %.1f%%\n",
            100 * length(qa) / sum(g$in_scope)))
cat(sprintf("newly reachable as a share of in-scope grants: %.1f%%\n",
            100 * sum(hit_fix & !hit_now) / sum(g$in_scope)))
cat(sprintf("newly reachable as a share of the NO tier    : %.1f%%\n",
            100 * sum(hit_fix & !hit_now & status_now == "NO") / sum(st$status == "NO")))
