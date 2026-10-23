#!/usr/bin/env Rscript
# ============================================================================
# Two EIN-dependent features, on the filer sample.
#
# A. WITHIN-FILER PROPAGATION. The naive version of this is already done by
#    dedup: identities are global, so one identity spanning five years is
#    matched once and the answer applies to all five. Measuring "is this pair
#    resolved in another year" would therefore measure nothing.
#
#    The real lever is the case dedup CANNOT see: one funder writing the same
#    grantee two different ways in two different years, so it becomes two
#    identities, one of which resolves YES and one of which does not. The
#    funder is the block -- a foundation's own grantee list is a far smaller
#    and far more plausible candidate set than the 3.9M-row reference.
#
# B. FUNDER NTEE PROFILE, against a size-matched null. The unconditional
#    version is at chance (dev/FUNDER-PROFILE-FINDINGS.md section 2); the
#    question is whether a concentration gate finds a real subpopulation now
#    that portfolios are intact.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
PF  <- Sys.getenv("PFMATCH_DIR", ".")
BMF <- file.path(PF, "..", "npmatch", "data-raw", "bmf_2026_01_processed.csv")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("-", 78))
e9  <- function(x) { x <- gsub("[^0-9]", "", as.character(x))
                     ifelse(nchar(x) == 9L, x, NA_character_) }

M  <- readRDS(file.path(PF, "data-dev", "FILER-SAMPLE-MATCH.rds"))
gg <- as.data.table(M$grants)[in_scope == TRUE]
say("grants: %s | identities: %s | filers: %s",
    format(nrow(gg), big.mark = ","), format(uniqueN(gg$recipient_uid), big.mark = ","),
    format(uniqueN(gg$FILEREIN), big.mark = ","))

# one row per (filer, identity): the funder's own grantee list
fi <- unique(gg[, .(FILEREIN, recipient_uid, recip_name, recip_state,
                    status, ein)])
fi <- fi[!duplicated(paste(FILEREIN, recipient_uid))]
say("filer-identity pairs: %s", format(nrow(fi), big.mark = ","))
print(fi[, .N, by = status][order(-N)], row.names = FALSE)

## ================================================= A. within-filer propagation
hr(); say("A. CAN A FUNDER'S OWN YES GRANTEES RESOLVE ITS MAYBE/NO ONES?")
nk <- function(x) {
  x <- toupper(ifelse(is.na(x), "", x))
  x <- gsub("[^A-Z0-9 ]", " ", x)
  trimws(gsub(" +", " ", x))
}
fi[, key := nk(recip_name)]
fi <- fi[nzchar(key)]

res <- fi[, {
  y <- which(status == "YES"); o <- which(status != "YES")
  if (!length(y) || !length(o)) NULL else {
    dm <- stringdist::stringdistmatrix(key[o], key[y], method = "jw", p = 0.1)
    bi <- max.col(-dm, ties.method = "first")
    list(uid = recipient_uid[o], status = status[o], name = recip_name[o],
         best_sim = 1 - dm[cbind(seq_along(o), bi)],
         best_yes = recip_name[y][bi], best_ein = ein[y][bi])
  }
}, by = FILEREIN]
say("unresolved identities sitting in a filer that also has YES matches: %s",
    format(nrow(res), big.mark = ","))
say("")
say("%-14s %10s %9s %9s", "JW threshold", "candidates", "of MAYBE", "of NO")
nm <- sum(res$status == "MAYBE"); nn <- sum(res$status == "NO")
for (t in c(0.99, 0.95, 0.92, 0.90, 0.85)) {
  h <- res[best_sim >= t]
  say("%-14.2f %10s %8.1f%% %8.1f%%", t, format(nrow(h), big.mark = ","),
      100 * sum(h$status == "MAYBE") / max(nm, 1),
      100 * sum(h$status == "NO") / max(nn, 1))
}
say("")
say("sample at JW >= 0.92 -- unresolved name, then the funder's own YES:")
set.seed(3)
s <- res[best_sim >= 0.92 & best_sim < 1]
if (nrow(s)) {
  s <- s[sample(.N, min(14L, .N))]
  for (i in seq_len(nrow(s)))
    message(sprintf("  [%-5s %.3f] %-40s -> %s", s$status[i], s$best_sim[i],
                    substr(s$name[i], 1, 40), substr(s$best_yes[i], 1, 40)))
}
fwrite(res, file.path(PF, "data-dev", "FILER-PROPAGATION-CANDIDATES.csv"))

## ======================================================= B. funder NTEE profile
hr(); say("B. FUNDER NTEE PROFILE, AGAINST A SIZE-MATCHED NULL")
b <- fread(BMF, colClasses = "character", showProgress = FALSE,
           select = c("ein", "ntee_code_clean"))
b[, ein := e9(ein)]
b[, L2 := toupper(substr(ntee_code_clean, 1, 1))]
b[is.na(ntee_code_clean) | !nzchar(ntee_code_clean) |
  toupper(ntee_code_clean) %in% c("INVALID", "UNDEFINED", "Z99"), L2 := NA_character_]
setkey(b, ein)

yes <- fi[status == "YES"]
yes[, e := e9(ein)]
yes[, L2 := b$L2[match(e, b$ein)]]
yes <- yes[!is.na(L2)]
say("YES grantees with a usable NTEE: %s of %s (%.0f%%)",
    format(nrow(yes), big.mark = ","), format(sum(fi$status == "YES"), big.mark = ","),
    100 * nrow(yes) / sum(fi$status == "YES"))
pop <- table(yes$L2) / nrow(yes)

prof <- yes[, .(n = .N, top = max(table(L2)) / .N,
                H = { p <- as.numeric(table(L2)) / .N
                      if (length(p) <= 1) 0 else -sum(p * log(p)) / log(length(p)) }),
            by = FILEREIN]
say("funders with >=5 classified grantees : %s (prior sample: 173 of 8,120)",
    format(sum(prof$n >= 5), big.mark = ","))
say("funders with >=20                    : %s", format(sum(prof$n >= 20), big.mark = ","))

set.seed(11)
sim_top <- function(k, reps = 3000)
  replicate(reps, { v <- sample(names(pop), k, replace = TRUE, prob = pop)
                    max(table(v)) / k })
say("")
say("%-10s %8s %11s %11s %11s %8s", "k", "funders", "obs median", "null median",
    "null p95", "above?")
for (k in c(5, 10, 20, 50, 100)) {
  s <- prof[n >= k & n < k * 2]
  if (nrow(s) < 5) next
  nl <- sim_top(k)
  say("%-10d %8d %11.3f %11.3f %11.3f %8s", k, nrow(s), median(s$top),
      median(nl), quantile(nl, 0.95),
      if (median(s$top) > quantile(nl, 0.95)) "YES" else "no")
}
big <- prof[n >= 10]
if (nrow(big)) {
  thr <- vapply(big$n, function(k) quantile(sim_top(min(k, 120), 600), 0.95), numeric(1))
  say("")
  say("funders beating their OWN size-matched null p95: %d of %d (%.0f%%)",
      sum(big$top > thr), nrow(big), 100 * mean(big$top > thr))
  say("  (5%% expected by construction; prior sample measured 7%%)")
}
fwrite(prof, file.path(PF, "data-dev", "FUNDER-PROFILES-FILER-SAMPLE.csv"))
say("")
say("wrote FILER-PROPAGATION-CANDIDATES.csv and FUNDER-PROFILES-FILER-SAMPLE.csv")
