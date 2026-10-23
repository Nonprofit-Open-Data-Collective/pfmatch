#!/usr/bin/env Rscript
# ============================================================================
# lift-sample-to-v2.R -- carry the ef1k evaluation sample onto the v2
# deduplicated corpus, keeping the hand adjudications attached to it.
#
# WHY LIFT RATHER THAN RE-CUT. The sample is 5,000 grants drawn at random from
# the undeduped v1 corpus, and it is not just data: 177 rows of PF-TRUTH are
# keyed to it, each one a hand adjudication, and BASELINE-2026-10 is defined
# over it. A fresh random draw from the deduplicated corpus would orphan every
# label and make the new clear rate incomparable to the old one in two ways at
# once -- different population AND different grants -- leaving no way to
# attribute a change to either.
#
# Lifting changes exactly one thing: rows the dedup established were superseded
# leave the sample. Everything else is the same grant, now carrying the full
# published schema. So the difference between the two measurements is
# attributable to deduplication alone, which is the question being asked.
#
# THE JOIN is (OBJECTID, content). It cannot be TABLE_ID, because the sample
# was shuffled when it was cut and the within-filing row order TABLE_ID counts
# is not recoverable from it. Measured by dev/diag-sample-liftability.R, that
# key is unique over all 5,000 rows -- no filing in the sample reports the same
# name, address and amount twice -- so the join is exact, not approximate.
#
# THE TRAP THIS SCRIPT EXISTS TO AVOID. `grant_id` is POSITIONAL: pf_prepare_
# grants() numbers rows G000001.. in read order, and every verdict file this
# project has recorded keys on it. Drop one superseded row and every grant_id
# after it denotes a different grant. Re-running the label consolidation
# against the lifted sample would therefore reattach all 177 adjudications to
# the wrong grants, silently and plausibly. So this writes an explicit
# crosswalk from the v1 grant_id to the v2 one, and checks its own row order
# against pf_read_grants() rather than assuming the two agree.
#
# The original inputs/ef1k_grants_0*.csv are NOT touched. BASELINE-2026-10 is
# defined as the benchmark over them; replacing them would make the reference
# point unreproducible, which is the same reasoning dev/cut-efilepf-samples.R
# applied to the GT-era samples it declined to overwrite.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("=", 78))

PF   <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
HOME <- "C:/Users/jlecy/Documents/grants"
V2   <- file.path(HOME, "PF-GRANTS-PAID-V2-2009-2025.csv")
OUT  <- file.path(PF, "inputs")
CHUNK <- 1000000L

sq  <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; x }
map <- pf_efilepf_map()                      # v1 name -> v2 name
CC1 <- c("SIGOCPYRPNAM", "SIGOCPYRBNBN1", "SIGOCPYRBNBN2", "SIGOCPYRFAAL1",
         "SIGOCPYRFAAL2", "SIGOCPYRFACI", "SIGOCPYRFAPO", "SIGOCPYRFAPC",
         "SIGOCAFFRFACO", "SIGOCPYAMOUN", "SIGOCPYPOGOC", "SIGOCPYRFSTA",
         "SIGOCPYRRELA")
CC2 <- unname(map[CC1])
keyof <- function(d, cols)
  do.call(paste, c(list(sq(d[["OBJECTID"]])),
                   lapply(cols, function(k) sq(d[[k]])), sep = "\r"))

hr(); say("lift-sample-to-v2  %s", format(Sys.time())); hr()

## ---- the sample, in pf_read_grants() order ---------------------------------
# list.files() sorts, and pf_read_grants() rbinds in that order, so reading the
# same way reproduces the numbering. That is an assumption about another
# function's internals, so it is CHECKED below rather than trusted.
fs <- list.files(OUT, pattern = "^ef1k_grants_[0-9]+\\.csv$", full.names = TRUE)
src <- rbindlist(lapply(seq_along(fs), function(i) {
  x <- fread(fs[i], colClasses = "character", na.strings = NULL)
  x[, part := i][]
}))
src[, row_v1 := .I]
src[, k := keyof(src, intersect(CC1, names(src)))]
if (anyDuplicated(src$k))
  stop("the (OBJECTID, content) key is not unique in the sample; the lift ",
       "would be ambiguous.", call. = FALSE)

prep1 <- as.data.table(pf_read_grants(OUT, pattern = "^ef1k_grants_[0-9]+\\.csv$"))
if (nrow(prep1) != nrow(src))
  stop("row count disagrees with pf_read_grants(): ", nrow(src), " vs ", nrow(prep1),
       call. = FALSE)
if (!identical(sq(prep1$OBJECTID), sq(src$OBJECTID)))
  stop("row ORDER disagrees with pf_read_grants(). grant_id is positional, so ",
       "the crosswalk would be wrong. Align the read before continuing.",
       call. = FALSE)
src[, grant_id_v1 := prep1$grant_id]
say("sample      %s rows, %d parts, %s filings -- order verified against pf_read_grants()",
    format(nrow(src), big.mark = ","), uniqueN(src$part),
    format(uniqueN(src$OBJECTID), big.mark = ","))

want <- unique(src$OBJECTID)

## ---- stream the v2 corpus, keeping only the sampled filings ----------------
if (!file.exists(V2))
  stop("the v2 corpus is not built yet: run dev/rebuild-corpus-v2.R first.\n  ",
       V2, call. = FALSE)
hdr <- names(fread(V2, nrows = 0L))
say("v2 corpus   %.2f GB, %d columns", file.size(V2) / 2^30, length(hdr))
miss <- setdiff(c(CC2, "OBJECTID", "TABLE_ID"), hdr)
if (length(miss)) stop("v2 corpus is missing: ", paste(miss, collapse = ", "), call. = FALSE)

hit <- list(); i <- 0L; seen <- 0L
repeat {
  ch <- fread(V2, colClasses = "character", na.strings = NULL,
              skip = 1L + i * CHUNK, nrows = CHUNK, header = FALSE,
              col.names = hdr, showProgress = FALSE)
  if (!nrow(ch)) break
  seen <- seen + nrow(ch); i <- i + 1L
  h <- ch[OBJECTID %chin% want]
  if (nrow(h)) hit[[length(hit) + 1L]] <- h
  say("  chunk %2d  %11s rows scanned, %6s kept", i, format(seen, big.mark = ","),
      format(sum(vapply(hit, nrow, 0L)), big.mark = ","))
  n <- nrow(ch); rm(ch)
  if (n < CHUNK) break
}
v2 <- rbindlist(hit); rm(hit); invisible(gc())
say("scanned %s rows; %s belong to a sampled filing",
    format(seen, big.mark = ","), format(nrow(v2), big.mark = ","))

## ---- match ------------------------------------------------------------------
v2[, k := keyof(v2, CC2)]
dup2 <- sum(duplicated(v2$k))
if (dup2) say("  NOTE %s v2 rows share a (OBJECTID, content) key; lowest TABLE_ID wins",
              format(dup2, big.mark = ","))
setorder(v2, k, TABLE_ID)
v2u <- v2[!duplicated(k)]

m <- merge(src[, .(k, part, row_v1, grant_id_v1)], v2u, by = "k", all.x = TRUE)
setorder(m, row_v1)
got  <- m[!is.na(OBJECTID)]
lost <- m[is.na(OBJECTID)]

hr(); say("LIFT RESULT")
say("  sampled grants              %s", format(nrow(src), big.mark = ","))
say("  found in the v2 corpus      %s  (%.2f%%)", format(nrow(got), big.mark = ","),
    100 * nrow(got) / nrow(src))
say("  absent -- removed by dedup  %s  (%.2f%%)", format(nrow(lost), big.mark = ","),
    100 * nrow(lost) / nrow(src))
say("")
say("  corpus-wide the dedup removed 1.75%% of rows. A sample rate far from")
say("  that would mean the sample is not representative of what it touches.")

if (nrow(lost)) {
  # subset src by position rather than merging: src already carries
  # grant_id_v1, so a join on it produces .x/.y suffixes and loses the name.
  l <- src[match(lost$row_v1, src$row_v1)]
  setorder(l, row_v1)
  say(""); say("  lost rows by tax year:")
  ly <- l[, .N, by = TAXYEAR][order(TAXYEAR)]
  for (j in seq_len(nrow(ly))) say("    %-6s %4d", ly$TAXYEAR[j], ly$N[j])
  fwrite(l[, .(grant_id_v1, OBJECTID, TAXYEAR, FILEREIN,
               recip = SIGOCPYRBNBN1, city = SIGOCPYRFACI,
               state = SIGOCPYRFAPO, amount = SIGOCPYAMOUN)],
         file.path(PF, "dev", "LIFT-LOST-ROWS.csv"))
  say("  -> dev/LIFT-LOST-ROWS.csv")
}

## ---- write the lifted sample, original order and partition -----------------
# Order is preserved so the v2 grant_id sequence is the v1 sequence with the
# dropped rows closed up -- which is exactly what the crosswalk records.
keep <- setdiff(names(got), c("k", "row_v1", "grant_id_v1", "part"))
hr(); say("writing")
for (p in sort(unique(got$part))) {
  o <- got[part == p][order(row_v1), ..keep]
  f <- file.path(OUT, sprintf("efv2_1k_grants_%02d.csv", p))
  fwrite(o, f)
  say("  %-28s %5s rows", basename(f), format(nrow(o), big.mark = ","))
}

## ---- the crosswalk, and a check that it is right ---------------------------
prep2 <- as.data.table(pf_read_grants(OUT, pattern = "^efv2_1k_grants_[0-9]+\\.csv$"))
if (nrow(prep2) != nrow(got))
  stop("the written sample reads back at ", nrow(prep2), " rows, not ", nrow(got),
       call. = FALSE)
if (!identical(sq(prep2$OBJECTID), sq(got$OBJECTID[order(got$part, got$row_v1)])))
  stop("the written sample does not read back in the order it was written; ",
       "the crosswalk would be wrong.", call. = FALSE)

g2 <- got[order(part, row_v1)]
xw <- data.table(
  grant_id_v1 = g2$grant_id_v1,
  grant_id_v2 = prep2$grant_id,
  object_id   = g2$OBJECTID,
  table_id    = g2$TABLE_ID,
  truth_id    = paste(sq(g2$OBJECTID), sq(g2$TABLE_ID), sep = "|"),
  recip_v1    = src$SIGOCPYRBNBN1[match(g2$grant_id_v1, src$grant_id_v1)],
  recip_v2    = g2[[map[["SIGOCPYRBNBN1"]]]],
  part        = g2$part)
if (!identical(sq(xw$recip_v1), sq(xw$recip_v2)))
  stop("recipient name disagrees across the lift on ",
       sum(sq(xw$recip_v1) != sq(xw$recip_v2)), " rows; the join is wrong.",
       call. = FALSE)
if (anyDuplicated(xw$truth_id))
  stop("OBJECTID|TABLE_ID is not unique in the lifted sample.", call. = FALSE)
fwrite(xw, file.path(PF, "data-dev", "LIFT-CROSSWALK-V2.csv"))
say("  %-28s %5s rows  (recipient name agrees on every one)",
    "LIFT-CROSSWALK-V2.csv", format(nrow(xw), big.mark = ","))

say("")
say("population id  v1 %s", pf_population_id(prep1))
say("population id  v2 %s", pf_population_id(prep2))
hr(); say("done  %s", format(Sys.time()))
