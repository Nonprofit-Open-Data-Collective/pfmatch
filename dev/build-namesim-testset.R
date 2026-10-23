#!/usr/bin/env Rscript
# ============================================================================
# Build a name-similarity test set from the NO-residual audit.
#
# The point is to compare string metrics on the cases pfmatch actually gets
# wrong, not on a synthetic benchmark. But scoring metrics on POSITIVES ALONE
# would be useless: every metric can be made to score true pairs higher by
# being looser, and the looser ones would win. What matters is DISCRIMINATION --
# does the metric put the correct organisation above the wrong ones that are
# competing for the same slot?
#
# So each case carries both:
#   positives  every name variant in either reference for the adjudicated EIN
#   negatives  the near-miss the pipeline actually chose (which is a wrong
#              answer the CURRENT scorer liked), plus same-state reference names
#              sharing a rare token with the filed name -- i.e. exactly the rows
#              a rare-token retrieval route would hand to the comparator
#
# The negatives are therefore not random strings; they are the specific
# confusions this problem generates.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(library(npmatch)))
say <- function(...) message(sprintf(...))
sq  <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; x }
e9  <- function(v) { v <- gsub("[^0-9]", "", as.character(v))
                     ifelse(nchar(v) == 9L, v, NA_character_) }

v <- fread(file.path(PF, "dev", "no-residual-verdicts.csv"), colClasses = "character")
s <- fread(file.path(PF, "data-dev", "AUDIT-NO-RESIDUAL-100.csv"), colClasses = "character")
v <- merge(v, s[, .(id, recip_name, recip_state, recip_city, recip_zip5,
                    ein_a, bmf_near, ein_b, mdb_near)], by = "id")
pos <- v[verdict == "REAL-ORG" & nzchar(sq(web_ein))]
say("cases with an adjudicated EIN: %d", nrow(pos))

## ---- reference name variants ------------------------------------------------
cols <- c("ein", "org_name_join", "org_addr_state")
b <- fread(file.path(PF, "data-dev", "BMF-AUGMENTED-unified-fixed.csv"),
           colClasses = "character", showProgress = FALSE, select = cols)
m <- fread(file.path(PF, "data-dev", "REF-MATCHDB.csv"),
           colClasses = "character", showProgress = FALSE, select = cols)
b[, ein := e9(ein)]; m[, ein := e9(ein)]
ref <- unique(rbind(b, m))
# e9() returns NA for malformed EINs. Keying on a column full of NA makes the
# per-case lookup below join every NA row to every NA row.
ref <- ref[!is.na(ein) & nzchar(sq(org_name_join))]
setkey(ref, ein)
say("reference name rows: %s", format(nrow(ref), big.mark = ","))

## ---- the same normalizer the pipeline compares on ---------------------------
# Comparing raw strings would measure my normalisation choices rather than the
# metrics. np_normalize() produces name_key, which is what np_compare() scores.
# np_normalize() parses the whole record and needs the geo columns, so call the
# name-key pipeline directly. This reproduces normalize.R lines 211-224 exactly;
# if that definition changes, this must change with it.
nkey <- function(x) {
  nm <- npmatch:::.np_basic_clean(sq(x))
  nm <- npmatch:::.np_replace_tokens(nm, npmatch:::.np_abbrev)
  npmatch:::.np_strip_lead_the(npmatch:::.np_strip_suffix(nm))
}

out <- list()
for (i in seq_len(nrow(pos))) {
  x   <- pos[i]
  tgt <- e9(x$web_ein)   # NOT named `ein`: data.table resolves i-expression names against the table first
  p   <- unique(sq(ref[.(tgt), org_name_join, nomatch = 0L]))
  if (!length(p)) next

  # hard negatives: what the two references' scorers actually preferred
  n_near <- unique(setdiff(c(sq(x$bmf_near), sq(x$mdb_near)), c("", p)))

  # hard negatives: same-state rows sharing the filed name's rarest token --
  # the pool a rare-token retrieval route would actually produce
  tk <- strsplit(toupper(gsub("[^A-Z0-9 ]", " ", toupper(sq(x$recip_name)))), " +")[[1]]
  tk <- setdiff(tk[nchar(tk) >= 4L], np_stopwords())
  n_tok <- character(0)
  if (length(tk)) {
    st  <- ref[org_addr_state == x$recip_state]
    rare <- tk[order(vapply(tk, function(t)
             sum(grepl(paste0("\\b", t, "\\b"), st$org_name_join)), 0L))][1]
    if (!is.na(rare)) {
      hit <- st[grepl(paste0("\\b", rare, "\\b"), org_name_join) & ein != tgt]
      n_tok <- unique(sq(hit$org_name_join))
      if (length(n_tok) > 40L) n_tok <- sample(n_tok, 40L)
    }
  }
  neg <- unique(setdiff(c(n_near, n_tok), p))
  if (!length(neg)) next

  out[[length(out) + 1L]] <- rbind(
    data.table(id = x$id, filed = x$recip_name, cand = p,   label = 1L),
    data.table(id = x$id, filed = x$recip_name, cand = neg, label = 0L))
}
d <- rbindlist(out)
say("")
say("cases: %d   positives: %d   negatives: %d",
    uniqueN(d$id), sum(d$label == 1L), sum(d$label == 0L))

set.seed(11)
d[, filed_key := nkey(filed)]
d[, cand_key  := nkey(cand)]
d <- d[nzchar(sq(filed_key)) & nzchar(sq(cand_key))]
fwrite(d, file.path(PF, "data-dev", "NAMESIM-TESTSET.csv"))
say("wrote data-dev/NAMESIM-TESTSET.csv (%s rows)", format(nrow(d), big.mark = ","))
