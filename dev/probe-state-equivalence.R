#!/usr/bin/env Rscript
# ============================================================================
# probe-state-equivalence.R -- can a state slice reproduce the unsliced answer?
#
# The first partition probe got 6.6x less memory and DIFFERENT answers, and the
# tell was that the slice produced MORE pairs than the full reference (128,731
# against 111,254). This asks whether that is fixable, by running both arms in
# one process and diffing the candidate sets exactly.
#
# WHAT ACTUALLY GATES THE BLOCKING -- and it is not what I first assumed.
# `token_idf` and `name_freq` are consumed by np_compare() for SCORING. The
# blocking gates read from the ref_index instead (npmatch/R/block.R):
#
#   ref_df  <- ref_index$df_concat / $df_base   -> max_ref_freq pruning, and IDF
#   n_ref   <- nrow(reference)                  -> idf = log(n_ref / ref_df)
#
# Both are corpus statistics, and both change when the reference is sliced. The
# index also cannot simply be reused: its `row` entries are POSITIONS into the
# reference, so a slice needs its own. Hence the hybrid built below --
# slice-positional rows, whole-corpus statistics.
#
# n_ref needs npmatch to read it from the index (branch block-corpus-stats); it
# is a no-op wherever the index was built from the reference it is used with.
#
# ARMS (identical queries, identical 7 state-blocked passes)
#   full     3.88M-row reference
#   naive    CA slice, everything rebuilt on the slice   (the first probe)
#   global   CA slice, whole-corpus stats grafted on     (the candidate design)
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- "."
suppressWarnings(suppressMessages(devtools::load_all("../npmatch", quiet = TRUE)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
setDTthreads(0L)
DD <- file.path(PF, "data-dev")
say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function(t = NULL) { cat(strrep("=", 78), "\n")
                            if (!is.null(t)) { cat(t, "\n"); cat(strrep("=", 78), "\n") } }
tick <- function() proc.time()[["elapsed"]]
ws <- function() {
  v <- tryCatch(system2("powershell", c("-NoProfile","-Command",
    sprintf("(Get-Process -Id %d).PeakWorkingSet64", Sys.getpid())),
    stdout = TRUE, stderr = FALSE), error = function(e) NA_character_)
  suppressWarnings(as.numeric(v[length(v)]))/1e9
}

STATE <- Sys.getenv("PF_STATE", "CA")
NQ    <- as.integer(Sys.getenv("PF_N", "500"))
CFG   <- npmatch::np_config()
ALL   <- c(pf_staged_passes("lean", concat = TRUE), pf_recovery_passes(state = TRUE))
P     <- ALL[vapply(ALL, function(p) p$name %in% c(
  "A2-name-state","A3-name-dba","A4-dba-name","A5-dba-dba",
  "B1-token-state","B2-token-concat","D1-acronym"), logical(1))]

hr(sprintf("STATE-PARTITION EQUIVALENCE -- %s, %d queries, %d state-blocked passes",
           STATE, NQ, length(P)))

b <- readRDS(file.path(DD, "REF-augmented.rds"))
full_ref <- pf_add_recovery_keys(b$reference)
say("full reference: %s rows", format(nrow(full_ref), big.mark = ","))

ids <- as.data.frame(readRDS(file.path(DD, "SHARD-RSS-IDENTITIES.rds")))
sel <- ids$in_scope & !is.na(ids$recip_state_raw) & ids$recip_state_raw == STATE
q   <- ids[sel, , drop = FALSE][seq_len(NQ), , drop = FALSE]
query <- pf_add_recovery_keys(npmatch::np_normalize(
  npmatch::np_query(q, pf_map_grants())))
say("queries: %d", nrow(q))

run <- function(label, ref, name_freq, token_idf, ref_index) {
  invisible(gc(reset = TRUE, full = TRUE))
  t0 <- tick()
  res <- npmatch::np_cascade(query, ref, config = CFG, method = "hier",
                             passes = P, verbose = FALSE, name_freq = name_freq,
                             token_idf = token_idf, ref_index = ref_index)
  el <- tick() - t0
  pk <- sum(gc()[, "max used"] * c(56, 8))/1e9
  pr <- as.data.table(as.data.frame(attr(res, "pairs")))
  rs <- as.data.frame(res); rs <- rs[order(rs$.id), , drop = FALSE]
  tb <- table(factor(as.character(rs$tier), c("YES","MAYBE","NO")))
  say("%-8s %6.1f s | peak %6.2f GB | %8s pairs | YES %3d MAYBE %3d NO %3d",
      label, el, pk, format(nrow(pr), big.mark = ","),
      tb[["YES"]], tb[["MAYBE"]], tb[["NO"]])
  list(pairs = pr, res = rs, sec = el, peak = pk, tb = tb)
}

## ---- arm 1: full reference -------------------------------------------------
A <- run("full", full_ref, b$name_freq, b$token_idf, b$ref_index)

## ---- the slice -------------------------------------------------------------
keep <- which(full_ref$state == STATE)
sl   <- full_ref[keep, , drop = FALSE]
say("%s slice: %s rows (%.1f%% of the reference)", STATE,
    format(nrow(sl), big.mark = ","), 100*nrow(sl)/nrow(full_ref))

## ---- arm 2: naive slice (everything rebuilt locally) -----------------------
s_nf <- npmatch::np_name_freq(sl$name_key)
s_ti <- npmatch::np_token_idf(sl$name_key)
s_ix <- npmatch::np_ref_index(sl)
B <- run("naive", sl, s_nf, s_ti, s_ix)

## ---- arm 3: slice + whole-corpus statistics --------------------------------
# Rows must be slice-positional; the statistics must be global. np_ref_index()
# gives the first, the full bundle's index gives the second.
g_ix <- s_ix
g_ix$df_base     <- b$ref_index$df_base
g_ix$df_concat   <- b$ref_index$df_concat
g_ix$n_reference <- b$ref_index$n_reference
say("grafted corpus stats: n_reference %s, %s base tokens, %s concat tokens",
    format(g_ix$n_reference, big.mark = ","),
    format(length(g_ix$df_base), big.mark = ","),
    format(length(g_ix$df_concat), big.mark = ","))
C <- run("global", sl, b$name_freq, b$token_idf, g_ix)

## ---- diff ------------------------------------------------------------------
key <- function(p) paste(p$.id, p$.ein)
cmp <- function(x, y, nm) {
  kx <- key(x$pairs); ky <- key(y$pairs)
  say("")
  say("%s vs full", nm)
  say("  pairs          %8s vs %8s   (%+d)", format(nrow(y$pairs), big.mark=","),
      format(nrow(x$pairs), big.mark=","), nrow(y$pairs) - nrow(x$pairs))
  say("  in both        %8s", format(length(intersect(kx, ky)), big.mark=","))
  say("  only in full   %8s", format(length(setdiff(kx, ky)), big.mark=","))
  say("  only in slice  %8s", format(length(setdiff(ky, kx)), big.mark=","))
  say("  PAIR SETS IDENTICAL: %s", identical(sort(kx), sort(ky)))
  # tier agreement on the shared identities
  m <- merge(x$res[, c(".id","tier","overall_ein")],
             y$res[, c(".id","tier","overall_ein")], by = ".id",
             suffixes = c(".full", ".slice"))
  say("  identities compared %d | same tier %d | same EIN %d",
      nrow(m), sum(as.character(m$tier.full) == as.character(m$tier.slice)),
      sum(m$overall_ein.full == m$overall_ein.slice, na.rm = TRUE))
  say("  VERDICT: %s", if (identical(sort(kx), sort(ky)) &&
      all(as.character(m$tier.full) == as.character(m$tier.slice)) &&
      isTRUE(all.equal(m$overall_ein.full, m$overall_ein.slice)))
      "EQUIVALENT" else "DIFFERS")
}
hr("DOES THE SLICE REPRODUCE THE UNSLICED RUN?")
cmp(A, B, "naive slice")
cmp(A, C, "slice + global corpus stats")

hr("COST")
say("%-8s %8s %10s", "arm", "seconds", "peak GB")
for (nm in c("full","naive","global")) {
  o <- switch(nm, full = A, naive = B, global = C)
  say("%-8s %8.1f %10.2f", nm, o$sec, o$peak)
}
fwrite(data.table(
  arm = c("full","naive","global"),
  seconds = c(A$sec, B$sec, C$sec), peak_gb = c(A$peak, B$peak, C$peak),
  pairs = c(nrow(A$pairs), nrow(B$pairs), nrow(C$pairs)),
  yes = c(A$tb[["YES"]], B$tb[["YES"]], C$tb[["YES"]])),
  file.path(DD, "STATE-EQUIVALENCE.csv"))
say(""); say("wrote data-dev/STATE-EQUIVALENCE.csv")
