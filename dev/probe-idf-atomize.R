#!/usr/bin/env Rscript
# ============================================================================
# probe-idf-atomize.R -- can token IDF be precomputed and recombined per spec,
# and is it worth it?
#
# Three candidate designs, timed on the real reference corpus:
#
#   A  live      np_token_idf(name_key)                      -- what runs today
#   C  stored    same, but tokens pre-split/deduped/stopworded and stored
#                (the "store tokens as a parseable string" proposal)
#   B  atomized  per-cell document-frequency vectors aligned to a global
#                vocabulary; IDF for any union of cells = rowSums + log
#
# Also times the alternative that already exists: readRDS() of the cached
# bundle, which is the current way of "not recomputing".
#
#   PF_REF=<path>   reference bundle rds (default data-dev/REF-active.rds)
#   PF_CELLS=8      how many cells to partition the corpus into
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)

REF   <- Sys.getenv("PF_REF", "data-dev/REF-active.rds")
NCELL <- as.integer(Sys.getenv("PF_CELLS", "8"))
say   <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr    <- function() cat(strrep("=", 74), "\n")
tm    <- function(expr) { t <- proc.time()[["elapsed"]]
                          v <- force(expr)
                          list(v = v, s = proc.time()[["elapsed"]] - t) }

hr(); say("corpus: %s", REF); hr()

r <- tm(readRDS(REF))
say("readRDS bundle           %8.1f s   (%.2f GB on disk)",
    r$s, file.size(REF) / 1e9)
bundle <- r$v
nk <- toupper(as.character(bundle$reference$name_key))
nk[is.na(nk)] <- ""
rm(bundle); invisible(gc())
say("name_key rows            %s", format(length(nk), big.mark = ","))

# npmatch's stopword list, inlined so the probe does not need the package loaded
sw <- tryCatch(npmatch::np_stopwords(),
               error = function(e) c("THE", "OF", "AND", "FOR", "INC", "A"))
say("stopwords                %d", length(sw))

# ---------------------------------------------------------------------------
# A -- live, exactly as np_token_idf() does it, decomposed into its three steps
# ---------------------------------------------------------------------------
hr(); say("A  live np_token_idf(), step by step"); hr()

a1 <- tm(strsplit(nk, " ", fixed = TRUE))
say("  strsplit                %8.2f s", a1$s)
toks <- a1$v

a2 <- tm(lapply(toks, function(t) unique(t[nchar(t) >= 2L & !(t %in% sw)])))
say("  unique + stopword drop  %8.2f s", a2$s)
ut <- a2$v

a3 <- tm({ df <- table(unlist(ut, use.names = FALSE))
           setNames(log(length(nk) / as.numeric(df)), names(df)) })
say("  unlist + table + log    %8.2f s", a3$s)
idf_live <- a3$v
say("  --------------------------------------")
say("  TOTAL A                 %8.2f s   (%s vocab)",
    a1$s + a2$s + a3$s, format(length(idf_live), big.mark = ","))

# ---------------------------------------------------------------------------
# C -- "store the tokens as a parseable string"
#      The stored form is pre-deduped and pre-stopworded, so recompiling skips
#      step 2 but still pays strsplit and table.
# ---------------------------------------------------------------------------
hr(); say("C  tokens stored as a pre-cleaned string"); hr()

stored <- vapply(ut, paste, character(1), collapse = " ")
say("  (stored column: %.2f GB in memory)", as.numeric(object.size(stored)) / 1e9)

c1 <- tm(strsplit(stored, " ", fixed = TRUE))
say("  strsplit stored         %8.2f s", c1$s)
c2 <- tm({ df <- table(unlist(c1$v, use.names = FALSE))
           setNames(log(length(stored) / as.numeric(df)), names(df)) })
say("  unlist + table + log    %8.2f s", c2$s)
say("  --------------------------------------")
say("  TOTAL C                 %8.2f s", c1$s + c2$s)

# ---------------------------------------------------------------------------
# B -- atomized: per-cell df vectors on a shared vocabulary.
#      Build cost is paid once at DB build; the per-spec cost is a rowSums.
# ---------------------------------------------------------------------------
hr(); say("B  per-cell df vectors, %d cells", NCELL); hr()

set.seed(1)
cell <- sample.int(NCELL, length(nk), replace = TRUE)

b0 <- tm({
  vocab <- names(idf_live)                       # global vocabulary, built once
  lens  <- lengths(ut)
  flat  <- unlist(ut, use.names = FALSE)
  j     <- match(flat, vocab)                    # token -> vocab index
  cc    <- rep.int(cell, lens)                   # cell of each token occurrence
  # dense vocab x cell document-frequency matrix
  M <- matrix(0L, nrow = length(vocab), ncol = NCELL)
  tab <- table(j, cc)
  M[cbind(as.integer(rownames(tab))[row(tab)], as.integer(colnames(tab))[col(tab)])] <-
    as.integer(tab)
  list(vocab = vocab, M = M, N = tabulate(cell, NCELL))
})
say("  BUILD (one-time)        %8.2f s   (%.1f MB matrix)",
    b0$s, as.numeric(object.size(b0$v$M)) / 1e6)

pick <- 1:5                                      # a spec = union of 5 cells
b1 <- tm({
  df <- rowSums(b0$v$M[, pick, drop = FALSE])
  N  <- sum(b0$v$N[pick])
  keep <- df > 0
  setNames(log(N / df[keep]), b0$v$vocab[keep])
})
say("  PER-SPEC recombine      %8.4f s  <-- the number that matters", b1$s)

# correctness: recombination must equal computing IDF on those rows directly
sel <- cell %in% pick
d1 <- tm({ df <- table(unlist(ut[sel], use.names = FALSE))
           setNames(log(sum(sel) / as.numeric(df)), names(df)) })
say("  direct on same subset   %8.2f s", d1$s)

x <- b1$v; y <- d1$v
ok <- setequal(names(x), names(y)) &&
      max(abs(x[names(y)] - y)) < 1e-9
say("  identical to direct?    %s   (%s tokens)",
    if (ok) "YES" else "NO", format(length(y), big.mark = ","))

hr(); say("summary"); hr()
say("  readRDS the cached bundle          %8.2f s", r$s)
say("  A  recompute live                  %8.2f s", a1$s + a2$s + a3$s)
say("  C  recompute from stored tokens    %8.2f s", c1$s + c2$s)
say("  B  recombine from per-cell df      %8.4f s", b1$s)
say("")
say("  B speedup over A: %.0fx", (a1$s + a2$s + a3$s) / max(b1$s, 1e-6))
