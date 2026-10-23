#!/usr/bin/env Rscript
# ============================================================================
# Is the NO residual a RETRIEVAL failure or a SCORING failure?
#
# dev/NO-RESIDUAL-AUDIT.md established that the correct organisation is already
# in the reference for every case checked, and often with the correct city too.
# That leaves two possibilities, which call for completely different fixes:
#
#   retrieval  np_block() never offers the correct row, so no comparator could
#              have saved it -- the fix is in blocking
#   scoring    np_block() offers it and np_compare()/np_score() rank it below a
#              wrong row or below threshold -- the fix is in the comparator
#
# This replays the production passes for the adjudicated cases and reports, per
# pass, whether the correct EIN appears among the candidates. Nothing here
# changes the pipeline; it only instruments it.
#
# Note the architecture already IS "retrieve by rare token, confirm by fuzzy
# match": pass B1/B2 is an inverted name-token index with IDF-weighted pruning
# (min_pair_idf), and np_compare() then confirms with Jaro-Winkler. So the
# question is not whether to build that route but which half of it is failing.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(devtools::load_all(
  Sys.getenv("NPMATCH_DIR", "../npmatch"), quiet = TRUE)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
setDTthreads(6L)
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("-", 84))
sq  <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; x }
e9  <- function(z) { z <- gsub("[^0-9]", "", as.character(z))
                     fifelse(nchar(z) == 9L, z, NA_character_) }

REF   <- file.path(PF, "data-dev", "BMF-AUGMENTED-bmf_unified_geocoded_2026-08-20.csv")
CACHE <- file.path(PF, "data-dev", "BMF-REF-AUG-2026-08-20.rds")

## ---- the cases ---------------------------------------------------------------
v <- fread(file.path(PF, "dev", "no-residual-verdicts.csv"), colClasses = "character")
s <- fread(file.path(PF, "data-dev", "AUDIT-NO-RESIDUAL-100.csv"), colClasses = "character")
cs <- merge(v[verdict == "REAL-ORG" & nzchar(sq(web_ein)), .(id, web_ein, web_name)],
            s[, .(id, recip_name, recip_street, recip_city, recip_state, recip_zip5)],
            by = "id")
cs[, tgt := e9(web_ein)]
cs <- cs[!is.na(tgt)]
say("cases with an adjudicated EIN: %d", nrow(cs))

## ---- query frame, normalized exactly as the pipeline does ---------------------
# np_normalize() reads zip5 / zip_plus4, not `zip`. A frame with the wrong
# column name silently yields a zero-length parse rather than an error about
# the missing column.
q <- data.frame(name = cs$recip_name, dba = "", division = "",
                street = cs$recip_street, city = cs$recip_city,
                state = cs$recip_state, zip5 = cs$recip_zip5, zip_plus4 = "",
                stringsAsFactors = FALSE)
q <- np_normalize(q)
# D1-acronym blocks on name_acro and D2-prefix on name_pre; neither column
# exists until pf_add_recovery_keys() runs. Without this both passes error or
# return nothing, which would wrongly look like a retrieval failure.
q <- pf_add_recovery_keys(q, only_truncated = rep(TRUE, nrow(q)))
q$.id <- cs$id

t0 <- proc.time()[["elapsed"]]
ref <- pf_reference(REF, cache = CACHE, verbose = FALSE)$reference
say("reference: %s rows (%.0f s)", format(nrow(ref), big.mark = ","),
    proc.time()[["elapsed"]] - t0)
if (is.null(ref$name_acro)) ref <- pf_add_recovery_keys(ref)

ref_ein <- e9(ref$.ein)
# every reference ROW index that carries one of our target EINs
tgt_rows <- lapply(cs$tgt, function(t) which(ref_ein == t))
names(tgt_rows) <- cs$id
say("target rows present in reference: %d of %d cases",
    sum(lengths(tgt_rows) > 0), nrow(cs))

## ---- replay each production pass ---------------------------------------------
passes <- c(pf_staged_passes("lean"), pf_recovery_passes(state = TRUE))
say("passes: %s", paste(vapply(passes, `[[`, "", "name"), collapse = ", "))
ri <- np_ref_index(ref)

hit <- matrix(FALSE, nrow = nrow(cs), ncol = length(passes),
              dimnames = list(cs$id, vapply(passes, `[[`, "", "name")))
ncand <- integer(nrow(cs))
union_rows <- vector("list", nrow(cs)); names(union_rows) <- cs$id

for (p in seq_along(passes)) {
  pz <- passes[[p]]
  cand <- tryCatch(
    do.call(np_block, c(list(query = q, reference = ref, ref_index = ri), pz$args)),
    error = function(e) { say("  %s FAILED: %s", pz$name, conditionMessage(e)); NULL })
  if (is.null(cand) || !nrow(cand)) { say("  %-18s 0 pairs", pz$name); next }
  by_q <- split(cand$.y, cand$.x)
  for (k in seq_len(nrow(cs))) {
    rows <- by_q[[as.character(k)]]
    if (is.null(rows)) next
    union_rows[[k]] <- c(union_rows[[k]], rows)
    if (length(intersect(rows, tgt_rows[[k]]))) hit[k, p] <- TRUE
  }
  say("  %-18s %s pairs, correct EIN retrieved for %d of %d cases",
      pz$name, format(nrow(cand), big.mark = ","), sum(hit[, p]), nrow(cs))
}

for (k in seq_len(nrow(cs))) {
  union_rows[[k]] <- unique(union_rows[[k]])
  ncand[k] <- length(union_rows[[k]])
}
retrieved <- vapply(seq_len(nrow(cs)),
                    function(k) length(intersect(union_rows[[k]], tgt_rows[[k]])) > 0, NA)

hr()
say("RETRIEVAL: was the correct row ever offered to the comparator?")
hr()
say("  retrieved by at least one pass : %d of %d", sum(retrieved), nrow(cs))
say("  never retrieved                : %d of %d", sum(!retrieved), nrow(cs))
say("")
say("%-9s %-34s %7s %10s  %s", "id", "filed", "cands", "retrieved", "passes that found it")
for (k in seq_len(nrow(cs)))
  say("%-9s %-34s %7s %10s  %s", cs$id[k], substr(cs$recip_name[k], 1, 34),
      format(ncand[k], big.mark = ","), ifelse(retrieved[k], "yes", "NO"),
      paste(colnames(hit)[hit[k, ]], collapse = " "))

out <- data.table(id = cs$id, filed = cs$recip_name, ein = cs$tgt,
                  n_cand = ncand, retrieved = retrieved,
                  passes = apply(hit, 1, function(r) paste(colnames(hit)[r], collapse = " ")))
fwrite(out, file.path(PF, "data-dev", "NO-RESIDUAL-BLOCKING-REPLAY.csv"))
saveRDS(list(cs = cs, union_rows = union_rows, tgt_rows = tgt_rows),
        file.path(PF, "data-dev", "NO-RESIDUAL-REPLAY-CANDS.rds"))
hr()
say("wrote data-dev/NO-RESIDUAL-BLOCKING-REPLAY.csv")
