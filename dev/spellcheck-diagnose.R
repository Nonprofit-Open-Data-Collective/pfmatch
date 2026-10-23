#!/usr/bin/env Rscript
# ============================================================================
# How much of the retrieval failure is actually MISSPELLING?
#
# The hypothesis is that some cases fail because a token is misspelled
# ("DOUNDATION" for "FOUNDATION", "BOROUGHS" for "BURROUGHS"), and that exact-
# token blocking therefore cannot reach the right row. Before building a
# correction mechanism, measure how big that slice is -- and distinguish two
# very different kinds of typo:
#
#   common-word typo   DOUNDATION -> FOUNDATION. The misspelled token is near a
#                      very common corpus word. Safe to correct, and nearly
#                      free, because the target is unambiguous.
#   rare-token typo    BOROUGHS -> BURROUGHS. The target is itself rare. This is
#                      the one that matters for blocking (rare tokens are what
#                      generate candidates) and the one most at risk of
#                      "correcting" a name that was spelled that way on purpose.
#
# The second is why the correction must be an ADDITIONAL key and never a
# replacement: BOROUGHS is a real word and a real organisation name.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(library(stringdist)))
suppressWarnings(suppressMessages(library(npmatch)))
setDTthreads(0)
PF  <- Sys.getenv("PFMATCH_DIR", ".")
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("-", 80))
sq  <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; x }

nkey <- function(x) {
  nm <- npmatch:::.np_basic_clean(sq(x))
  nm <- npmatch:::.np_replace_tokens(nm, npmatch:::.np_abbrev)
  npmatch:::.np_strip_lead_the(npmatch:::.np_strip_suffix(nm))
}

## ---- reference token vocabulary with document frequency ---------------------
VOC <- file.path(PF, "data-dev", "REF-TOKEN-VOCAB.rds")
if (file.exists(VOC)) {
  tv <- readRDS(VOC)
} else {
  b <- fread(file.path(PF, "data-dev", "BMF-AUGMENTED-unified-fixed.csv"),
             colClasses = "character", showProgress = FALSE, select = "org_name_join")
  nk <- nkey(b$org_name_join)
  tl <- strsplit(nk, " ", fixed = TRUE)
  fl <- unlist(tl, use.names = FALSE)
  fl <- fl[nchar(fl) >= 2L]
  tb <- table(fl)
  tv <- data.table(token = names(tb), df = as.integer(tb))
  saveRDS(tv, VOC); rm(b, nk, tl, fl, tb); invisible(gc())
}
setkey(tv, token)
say("reference vocabulary: %s distinct tokens", format(nrow(tv), big.mark = ","))

## ---- the audit's filed names -------------------------------------------------
v <- fread(file.path(PF, "dev", "no-residual-verdicts.csv"), colClasses = "character")
s <- fread(file.path(PF, "data-dev", "AUDIT-NO-RESIDUAL-100.csv"), colClasses = "character")
a <- merge(v[verdict == "REAL-ORG", .(id, web_name)],
           s[, .(id, recip_name)], by = "id")
SW <- np_stopwords()

qt <- unique(unlist(lapply(nkey(a$recip_name), function(x) {
  t <- strsplit(x, " ", fixed = TRUE)[[1]]; t[nchar(t) >= 4L & !(t %in% SW)] })))
say("distinct query tokens (len>=4, non-stop): %d", length(qt))

## ---- which query tokens are absent or near-absent from the reference? --------
dfq <- tv[.(qt), df]; dfq[is.na(dfq)] <- 0L
unseen <- qt[dfq == 0L]
say("tokens never seen in the reference at all : %d", length(unseen))

## ---- for each unseen token, is there an edit-distance-1 reference token? -----
# Restrict the search by length (+/-1) so this is tractable without an index.
cand_for <- function(tok) {
  pool <- tv[abs(nchar(token) - nchar(tok)) <= 1L]
  d <- stringdist(tok, pool$token, method = "osa")
  k <- which(d == 1L)
  if (!length(k)) return(NULL)
  r <- pool[k][order(-df)]
  r
}
hr()
say("UNSEEN QUERY TOKENS AND THEIR EDIT-DISTANCE-1 NEIGHBOURS")
hr()
say("%-18s %8s  %s", "query token", "df", "nearest reference tokens (df)")
rows <- list()
for (tok in unseen) {
  r <- cand_for(tok)
  if (is.null(r)) { say("%-18s %8s  -- none at distance 1", tok, "0"); next }
  top <- r[1:min(4L, nrow(r))]
  say("%-18s %8s  %s", tok, "0",
      paste(sprintf("%s(%s)", top$token, format(top$df, big.mark = ",")), collapse = "  "))
  rows[[length(rows) + 1L]] <- data.table(token = tok, best = top$token[1],
                                          best_df = top$df[1], n_cand = nrow(r))
}
u <- rbindlist(rows)

## ---- the two kinds of typo ---------------------------------------------------
if (nrow(u)) {
  u[, kind := fifelse(best_df >= 10000L, "common-word typo", "rare-token typo")]
  hr()
  print(u[, .N, by = kind], row.names = FALSE)
  hr()
  say("AMBIGUITY: how many distance-1 candidates does each have?")
  say("  exactly one candidate      : %d", sum(u$n_cand == 1L))
  say("  two or more candidates     : %d", sum(u$n_cand > 1L))
  say("")
  say("A token with several distance-1 neighbours cannot be 'corrected' to one")
  say("answer. Emitting ALL of them as extra blocking keys sidesteps that -- the")
  say("comparator still has to pick. That is the argument for extra keys over")
  say("correction, independent of the deliberate-misspelling worry.")
}

## ---- how often would correction fire on tokens that are NOT typos? -----------
# A token present in the reference is not a typo, but it may still sit at
# distance 1 from a much commoner token. If correction replaced the original,
# those are the names it would damage.
hr()
say("RISK OF REPLACING RATHER THAN ADDING")
hr()
seen <- qt[dfq > 0L]
risk <- 0L
for (tok in seen) {
  r <- cand_for(tok)
  if (is.null(r)) next
  own <- tv[.(tok), df]
  if (!is.na(own) && r$df[1] > 20L * own) {
    risk <- risk + 1L
    say("  %-18s df=%-7s would be pulled toward %s (df=%s)", tok,
        format(own, big.mark = ","), r$token[1], format(r$df[1], big.mark = ","))
  }
}
say("")
say("%d of %d real tokens sit next to a 20x commoner neighbour.", risk, length(seen))
say("Replacing would lose them; adding a second key keeps both paths open.")
