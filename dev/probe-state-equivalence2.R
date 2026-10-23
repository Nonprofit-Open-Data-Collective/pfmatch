#!/usr/bin/env Rscript
# ============================================================================
# probe-state-equivalence2.R -- causes 1 and 3 from STATE-PARTITION-FINDINGS.
#
# Round 1 got the corpus statistics right (mismatched pairs 34,255 -> 3,110) and
# left three named causes. This attacks two of them:
#
#   CAUSE 1  188 pairs the slice MISSED. Queries were routed by
#            `recip_state_raw`, but np_block() keys on the NORMALIZED `state`.
#            Where they disagree the query is in the wrong shard and its true
#            matches sit in a slice it never sees. Fix: normalize first, then
#            route on the same field the blocker uses.
#
#   CAUSE 3  26 identities agreed on tier but reported a DIFFERENT EIN.
#            Selection is first-row-wins, so tied candidates resolve by row
#            POSITION and a slice orders its rows differently. Fix (tested here
#            as a post-hoc check, not yet as an npmatch change): count how many
#            of the differences are ties, which bounds what a deterministic
#            tie-break could buy.
#
# ARMS, identical queries and identical 7 state-blocked passes:
#   full     3.88M-row reference
#   slice    CA slice, slice-positional index + whole-corpus statistics
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

STATE <- Sys.getenv("PF_STATE", "CA")
NQ    <- as.integer(Sys.getenv("PF_N", "500"))
CFG   <- npmatch::np_config()
P <- Filter(function(p) p$name %in% c("A2-name-state","A3-name-dba","A4-dba-name",
  "A5-dba-dba","B1-token-state","B2-token-concat","D1-acronym"),
  c(pf_staged_passes("lean", concat = TRUE), pf_recovery_passes(state = TRUE)))

hr(sprintf("EQUIVALENCE v2 -- %s, routing on the NORMALIZED state", STATE))
b <- readRDS(file.path(DD, "REF-augmented.rds"))
full_ref <- pf_add_recovery_keys(b$reference)

## ---- CAUSE 1: normalize FIRST, then route ---------------------------------
ids <- as.data.frame(readRDS(file.path(DD, "SHARD-RSS-IDENTITIES.rds")))
ids <- ids[ids$in_scope, , drop = FALSE]
allq <- pf_add_recovery_keys(npmatch::np_normalize(
  npmatch::np_query(ids, pf_map_grants())))
# how often do the two fields disagree? that IS cause 1, measured
raw <- ids$recip_state_raw
nrm <- allq$state
say("queries: %s", format(nrow(allq), big.mark = ","))
say("recip_state_raw vs normalized state:")
say("  agree            %s", format(sum(!is.na(raw) & !is.na(nrm) & raw == nrm), big.mark = ","))
say("  disagree         %s", format(sum(!is.na(raw) & !is.na(nrm) & raw != nrm), big.mark = ","))
say("  raw NA, norm set %s", format(sum(is.na(raw) & !is.na(nrm)), big.mark = ","))
say("  norm NA          %s", format(sum(is.na(nrm)), big.mark = ","))
say("  -> routing on the raw field misplaces %s queries (%.2f%%)",
    format(sum(!is.na(raw) & !is.na(nrm) & raw != nrm), big.mark = ","),
    100*mean(!is.na(raw) & !is.na(nrm) & raw != nrm, na.rm = TRUE))

sel <- which(!is.na(nrm) & nrm == STATE)
sel <- sel[seq_len(min(NQ, length(sel)))]
query <- allq[sel, , drop = FALSE]
say("routed to %s: %d queries", STATE, nrow(query))

run <- function(label, ref, name_freq, token_idf, ref_index) {
  invisible(gc(reset = TRUE, full = TRUE))
  t0 <- tick()
  res <- npmatch::np_cascade(query, ref, config = CFG, method = "hier",
                             passes = P, verbose = FALSE, name_freq = name_freq,
                             token_idf = token_idf, ref_index = ref_index)
  el <- tick() - t0
  pr <- as.data.table(as.data.frame(attr(res, "pairs")))
  rs <- as.data.frame(res); rs <- rs[order(rs$.id), , drop = FALSE]
  tb <- table(factor(as.character(rs$tier), c("YES","MAYBE","NO")))
  say("%-6s %6.1f s | %8s pairs | YES %3d MAYBE %3d NO %3d", label, el,
      format(nrow(pr), big.mark = ","), tb[["YES"]], tb[["MAYBE"]], tb[["NO"]])
  list(pairs = pr, res = rs, sec = el)
}

A <- run("full", full_ref, b$name_freq, b$token_idf, b$ref_index)

sl <- full_ref[full_ref$state == STATE, , drop = FALSE]
ix <- npmatch::np_ref_index(sl)
ix$df_base <- b$ref_index$df_base; ix$df_concat <- b$ref_index$df_concat
ix$n_reference <- b$ref_index$n_reference
say("slice: %s rows, whole-corpus stats grafted (n_reference %s)",
    format(nrow(sl), big.mark = ","), format(ix$n_reference, big.mark = ","))
B <- run("slice", sl, b$name_freq, b$token_idf, ix)

## ---- diff ------------------------------------------------------------------
hr("PAIR SETS")
kx <- paste(A$pairs$.id, A$pairs$.ein); ky <- paste(B$pairs$.id, B$pairs$.ein)
only_full <- setdiff(kx, ky); only_slice <- setdiff(ky, kx)
say("pairs          full %8s | slice %8s", format(nrow(A$pairs), big.mark=","),
    format(nrow(B$pairs), big.mark=","))
say("in both        %8s", format(length(intersect(kx, ky)), big.mark=","))
say("only in full   %8s   <- cause 1 if the slice cannot see them", format(length(only_full), big.mark=","))
say("only in slice  %8s   <- cause 2", format(length(only_slice), big.mark=","))
say("IDENTICAL: %s", identical(sort(kx), sort(ky)))

# Are the only-in-full pairs out-of-state? If routing is now correct they should
# be none, or else genuinely cross-state rows a state pass should not have made.
if (length(only_full)) {
  of <- A$pairs[paste(A$pairs$.id, A$pairs$.ein) %chin% only_full]
  st <- if (!is.null(of$state_y)) of$state_y else rep(NA_character_, nrow(of))
  say("")
  say("of the %d only-in-full pairs, reference state:", length(only_full))
  print(head(sort(table(st, useNA = "ifany"), decreasing = TRUE), 6))
}

## ---- CAUSE 2: is the residual concentrated, or spread? ---------------------
# The `pending` hypothesis says a handful of queries tier differently at some
# pass, and everything downstream of that follows: they are withheld from (or
# admitted to) later passes, so whole blocks of candidates appear or vanish. If
# so the diff lands on very few .ids. If it is spread over hundreds, the cause is
# something systematic in blocking instead, and the two-phase design does not fix
# it.
hr("IS THE RESIDUAL CONCENTRATED? (the pending hypothesis)")
idf <- sub(" .*$", "", only_full); ids_ <- sub(" .*$", "", only_slice)
cf <- sort(table(idf), decreasing = TRUE)
cs <- sort(table(ids_), decreasing = TRUE)
say("only-in-full  %5d pairs over %4d distinct identities", length(only_full), length(cf))
if (length(cf)) say("   top 5 identities hold %d (%.0f%%)", sum(head(cf, 5)),
                    100*sum(head(cf, 5))/length(only_full))
say("only-in-slice %5d pairs over %4d distinct identities", length(only_slice), length(cs))
if (length(cs)) say("   top 5 identities hold %d (%.0f%%)", sum(head(cs, 5)),
                    100*sum(head(cs, 5))/length(only_slice))
say("")
say("queries affected at all: %d of %d (%.1f%%)",
    length(union(names(cf), names(cs))), nrow(A$res),
    100*length(union(names(cf), names(cs)))/nrow(A$res))
say("")
say("worst offenders (identity, only-full, only-slice, query name):")
worst <- head(sort(table(c(idf, ids_)), decreasing = TRUE), 6)
for (i in seq_along(worst)) {
  id <- names(worst)[i]
  nmq <- query$name[match(id, query$.id)]
  say("  %-10s  full-only %5d | slice-only %5d | %s", id,
      as.integer(cf[id]) %||% 0L, as.integer(cs[id]) %||% 0L,
      substr(if (is.na(nmq)) "" else nmq, 1, 40))
}

## ---- CAUSE 3: how much of the residual is ties? ----------------------------
hr("TIER AND EIN AGREEMENT")
m <- merge(A$res[, c(".id","tier","overall_ein","overall_score")],
           B$res[, c(".id","tier","overall_ein","overall_score")],
           by = ".id", suffixes = c(".f", ".s"))
say("identities compared %d", nrow(m))
say("  same tier         %d", sum(as.character(m$tier.f) == as.character(m$tier.s)))
say("  same EIN          %d", sum(m$overall_ein.f == m$overall_ein.s, na.rm = TRUE))
d <- m[!is.na(m$overall_ein.f) & !is.na(m$overall_ein.s) &
       m$overall_ein.f != m$overall_ein.s, , drop = FALSE]
if (nrow(d)) {
  eq <- abs(d$overall_score.f - d$overall_score.s) < 1e-9
  say("")
  say("EIN differs on %d identities:", nrow(d))
  say("  scores IDENTICAL (a tie broken by row order) : %d (%.0f%%)  <- cause 3",
      sum(eq), 100*mean(eq))
  say("  scores differ    (a real candidate-set change): %d", sum(!eq))
  say("")
  say("  -> a deterministic tie-break can close at most %d of the %d",
      sum(eq), nrow(d))
}
fwrite(data.table(only_full = length(only_full), only_slice = length(only_slice),
                  same_tier = sum(as.character(m$tier.f) == as.character(m$tier.s)),
                  same_ein = sum(m$overall_ein.f == m$overall_ein.s, na.rm = TRUE),
                  n = nrow(m)), file.path(DD, "STATE-EQUIVALENCE2.csv"))
