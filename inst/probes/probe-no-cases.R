#!/usr/bin/env Rscript
# ============================================================================
# probe-no-cases.R -- for each NO case, ask the BMF directly: is there a
# plausible row we failed to surface, and what would have been needed to find it?
#
# The cascade's own blocking is what we are auditing, so the probe deliberately
# uses a different mechanism: search the whole BMF for records containing the
# query's two rarest tokens, then rank by full-name similarity. Slow and
# unblocked on purpose -- it is an oracle, not a production path.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
NPM <- Sys.getenv("NPMATCH_DIR", "../npmatch")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))

B   <- readRDS(file.path(PF, "data-dev", "BMF-REFERENCE-BUNDLE.rds"))
ref <- B$reference
idf <- B$token_idf
rk  <- ref$name_key; rk[is.na(rk)] <- ""
d   <- fread(file.path(PF, "data-dev", "AUDIT-NO-100.csv"), colClasses = "character")

# word-boundary alternative that does not rely on \b (see note in dev notes):
# a token is present if the key starts with it or it follows a space.
has_token <- function(v, t) startsWith(v, t) | grepl(paste0(" ", t), v, fixed = TRUE)

sw <- np_stopwords()
res <- rbindlist(lapply(seq_len(nrow(d)), function(i) {
  key <- d$name_key[i]
  if (is.na(key) || !nzchar(key)) return(data.table(grant_id = d$grant_id[i], mode = "no-name"))
  tok <- setdiff(strsplit(key, " ", fixed = TRUE)[[1]], sw)
  tok <- tok[nchar(tok) >= 3]
  if (!length(tok)) return(data.table(grant_id = d$grant_id[i], mode = "no-usable-token"))
  w <- idf[tok]; w[is.na(w)] <- 0
  tok <- tok[order(-w)][seq_len(min(2L, length(tok)))]
  ix <- Reduce(`&`, lapply(tok, function(t) has_token(rk, t)))
  n_hit <- sum(ix)
  if (!n_hit) {                       # back off to the single rarest token
    tok <- tok[1]
    ix <- has_token(rk, tok); n_hit <- sum(ix)
  }
  if (!n_hit) return(data.table(grant_id = d$grant_id[i], mode = "absent",
                                tokens = paste(tok, collapse = "+")))
  h <- which(ix)
  sim <- 1 - stringdist::stringdist(key, rk[h], method = "jw", p = 0.1)
  st  <- d$recip_state[i]
  if (!is.na(st) && nzchar(st)) sim <- sim + ifelse(ref$state[h] %in% st, 0.12, 0)
  h <- h[order(-sim)][seq_len(min(3L, length(h)))]
  data.table(grant_id = d$grant_id[i], mode = "found",
             tokens = paste(tok, collapse = "+"), n_hit = n_hit,
             top_sim = round(max(sim, na.rm = TRUE), 3),
             cand = paste(sprintf("%s [%s %s] %s", ref$name[h], ref$city[h],
                                  ref$state[h], ref$.ein[h]), collapse = "  ||  "))
}), fill = TRUE)

out <- merge(d[, .(grant_id, recip_name, recip_city, recip_state, recip_street,
                   recipient_type, grant_purpose, name_key, best_score)],
             res, by = "grant_id")
setorder(out, -top_sim, na.last = TRUE)
fwrite(out, file.path(PF, "data-dev", "AUDIT-NO-100-PROBE.csv"), na = "")
cat("probe modes:\n"); print(table(out$mode))
for (i in seq_len(nrow(out)))
  cat(sprintf("%-3d %-42s %-14s %-2s  sim=%-5s\n      -> %s\n", i,
              substr(out$recip_name[i], 1, 42), substr(out$recip_city[i], 1, 14),
              out$recip_state[i], out$top_sim[i], substr(out$cand[i], 1, 150)))
