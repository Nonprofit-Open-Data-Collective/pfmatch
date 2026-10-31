#!/usr/bin/env Rscript
# ============================================================================
# adjudicate-04-ablation.R -- split the deep arm's advantage into "bigger
# model" and "has the web".
#
# Stage 03 measures a two-arm gap: Haiku on the packet scores 81.5% against the
# 27 hand-adjudicated cases, Opus-with-search 92.6%. That 11-point difference
# is NOT attributable, because the arms differ in two ways at once -- the model
# changed AND the web was added. A cheaper configuration might capture most of
# it, or none of it, and the two-arm design cannot say which.
#
# The ablation arm (PF_ADJ_NOSEARCH=1) is Opus at the same effort on the same
# frozen packet with web_search removed. Three arms then decompose it:
#
#   light        -> deep-nosearch   the MODEL effect   (Haiku -> Opus, no web)
#   deep-nosearch -> deep-search    the SEARCH effect  (same model, web added)
#   light        -> deep-search     the total, as stage 03 reports it
#
# WHAT EACH OUTCOME WOULD MEAN, written before the numbers are in so the
# reading is not fitted to them:
#
#   mostly MODEL   Opus on the packet is already most of the way there, and the
#                  search tier is largely buying confidence rather than
#                  accuracy. The cheap cascade should escalate to Opus WITHOUT
#                  search, which removes per-use search billing entirely and is
#                  the single largest cost lever left.
#   mostly SEARCH  the packet is the binding constraint, not the model. Then a
#                  mid-tier model with search beats a frontier model without
#                  it, and the escalation tier should be chosen for its tool
#                  access rather than its size.
#   both           the tiers are doing different jobs and neither substitutes.
#
# A fourth outcome is possible and worth naming: the no-search arm could score
# ABOVE the search arm. Search can mislead -- a plausible directory page for a
# different chapter of the same charity is exactly the trap this tier is full
# of -- and 22 of the search arm's verdicts came back CONTRADICTED. If that
# happens it is a finding about the search prompt, not a reason to drop search.
#
# All three arms read the identical frozen packet, so nothing here is confounded
# by the case text.
#
# OUTPUT  dev/ADJ-EXP-ABLATION.log
# USAGE   Rscript dev/adjudicate-04-ablation.R
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
DD <- file.path(PF, "data-dev")

say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() cat(strrep("=", 78), "\n")
h2  <- function(s) { cat("\n"); cat(strrep("-", 78), "\n"); cat(s, "\n")
                     cat(strrep("-", 78), "\n") }

wilson <- function(k, n, conf = 0.95) {
  if (n == 0) return(c(est = NA, lo = NA, hi = NA))
  z <- qnorm(1 - (1 - conf) / 2); p <- k / n; d <- 1 + z^2 / n
  c(est = p,
    lo = max(0, (p + z^2 / (2 * n) - z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2))) / d),
    hi = min(1, (p + z^2 / (2 * n) + z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2))) / d))
}
rate <- function(k, n) { w <- wilson(k, n)
  sprintf("%2d/%-2d = %5.1f%% (95%% CI %.1f-%.1f)", k, n, 100 * w[["est"]],
          100 * w[["lo"]], 100 * w[["hi"]]) }
e9 <- function(x) { v <- gsub("[^0-9]", "", as.character(x))
                    ifelse(nchar(v) == 9L, v, NA_character_) }
nz <- function(x, alt = "-") { if (is.null(x) || length(x) == 0L) return(alt)
  x <- as.character(x)[1]; if (is.na(x) || !nzchar(x)) alt else x }

need <- c("ADJ-EXP-LIGHT.rds", "ADJ-EXP-DEEP.rds", "ADJ-EXP-DEEP-nosearch.rds",
          "ADJ-EXP-CASES.rds", "ADJ-EXP-TRUTH.rds")
miss <- need[!file.exists(file.path(DD, need))]
if (length(miss))
  stop(sprintf("missing: %s\n  The ablation arm comes from\n  PF_ADJ_NOSEARCH=1 PF_ADJ_TAG=-nosearch Rscript dev/adjudicate-02-deep.R",
               paste(miss, collapse = ", ")), call. = FALSE)

sink(file.path(PF, "dev", "ADJ-EXP-ABLATION.log"), split = TRUE)
close_log <- function() while (sink.number() > 0L) sink()

hr(); say("ABLATION -- is the deep arm's edge the model or the web?"); hr()

grab <- function(f, pfx) {
  x <- as.data.table(readRDS(file.path(DD, f)))
  out <- x[, .(grant_id, verdict, ein = e9(ein), confidence, evidence_class,
               evidence, api_ok)]
  setnames(out, setdiff(names(out), "grant_id"),
           paste0(pfx, "_", setdiff(names(out), "grant_id")))
  if (!is.null(x$searches)) out[[paste0(pfx, "_searches")]] <- x$searches
  if (!is.null(x$search_confirmed))
    out[[paste0(pfx, "_sc")]] <- x$search_confirmed
  out
}
L <- grab("ADJ-EXP-LIGHT.rds", "l")
N <- grab("ADJ-EXP-DEEP-nosearch.rds", "n")
S <- grab("ADJ-EXP-DEEP.rds", "s")
cs <- as.data.table(readRDS(file.path(DD, "ADJ-EXP-CASES.rds")))
tr <- as.data.table(readRDS(file.path(DD, "ADJ-EXP-TRUTH.rds")))

d <- merge(merge(L, N, by = "grant_id"), S, by = "grant_id")
d <- merge(d, cs[, .(grant_id, stratum, batch_order, tie, overall_margin,
                     recip_name, recip_state)], by = "grant_id")
d <- merge(d, tr[, .(grant_id, truth_verdict, correct_ein, truth_in_packet,
                     adjudicable)], by = "grant_id", all.x = TRUE)
setorder(d, batch_order)
say("cases with all three arms: %d", nrow(d))
bad <- d[l_api_ok == FALSE | n_api_ok == FALSE | s_api_ok == FALSE]
if (nrow(bad)) say("  %d incomplete, excluded", nrow(bad))
d <- d[l_api_ok == TRUE & n_api_ok == TRUE & s_api_ok == TRUE]
say("no-search arm searches (must be 0): %d", sum(d$n_searches, na.rm = TRUE))
say("search arm searches: %d", sum(d$s_searches, na.rm = TRUE))

d[, target := NA_character_]
d[adjudicable == TRUE & truth_verdict == "ORG_FOUND" & truth_in_packet == TRUE,
  target := "MATCH"]
d[adjudicable == TRUE & truth_verdict == "ORG_FOUND" & truth_in_packet == FALSE,
  target := "NONE"]
d[adjudicable == TRUE & grepl("^NO_ORG", truth_verdict), target := "NONE"]
grade <- function(v, ein, target, correct) {
  ifelse(is.na(target), NA_character_,
  ifelse(target == "MATCH",
    ifelse(v == "MATCH"     & !is.na(ein) & ein == correct, "CORRECT",
    ifelse(v == "AMBIGUOUS" & !is.na(ein) & ein == correct, "AMBIGUOUS_RIGHT",
    ifelse(v == "NONE", "MISS", "WRONG"))),
    ifelse(v == "NONE", "CORRECT",
    ifelse(v == "AMBIGUOUS", "AMBIGUOUS_WRONG", "WRONG"))))
}
for (a in c("l", "n", "s"))
  d[[paste0(a, "_grade")]] <- grade(d[[paste0(a, "_verdict")]],
      d[[paste0(a, "_ein")]], d$target, d$correct_ein)
B <- d[!is.na(target)]
A <- d[stratum == "A-estimation"]

## ============================================================================
h2("1. ACCURACY on the hand-adjudicated cases -- the decomposition")
## ============================================================================
say("%d scorable cases (%d target MATCH, %d target NONE)\n", nrow(B),
    sum(B$target == "MATCH"), sum(B$target == "NONE"))
arms <- list(c("l", "light  Haiku, packet only"),
             c("n", "deep-  Opus, packet only"),
             c("s", "deep+  Opus + web search"))
say("arm                          strict CORRECT")
for (a in arms) say("  %-26s %s", a[2], rate(sum(B[[paste0(a[1], "_grade")]] == "CORRECT"), nrow(B)))
kl <- sum(B$l_grade == "CORRECT"); kn <- sum(B$n_grade == "CORRECT")
ks <- sum(B$s_grade == "CORRECT"); n <- nrow(B)
say("\ndecomposition of the %+.1f-point total gap", 100 * (ks - kl) / n)
say("  model effect   light -> deep-   %+5.1f pt  (%d -> %d cases)",
    100 * (kn - kl) / n, kl, kn)
say("  search effect  deep- -> deep+   %+5.1f pt  (%d -> %d cases)",
    100 * (ks - kn) / n, kn, ks)
say("  total          light -> deep+   %+5.1f pt  (%d -> %d cases)",
    100 * (ks - kl) / n, kl, ks)

# McNemar on the discordant pairs: with n=27 the interval on each rate is wide,
# but the PAIRED comparison only uses the cases the two arms disagree on, which
# is the right test for "did adding search change anything".
mcn <- function(x, y, lab) {
  b <- sum(x == "CORRECT" & y != "CORRECT")   # first right, second wrong
  c_ <- sum(x != "CORRECT" & y == "CORRECT")
  p <- if (b + c_ == 0) NA else stats::binom.test(c_, b + c_, 0.5)$p.value
  say("  %-28s %d gained, %d lost, exact p = %s", lab, c_, b,
      if (is.na(p)) "n/a (no discordant pairs)" else sprintf("%.3f", p))
}
say("\npaired test on discordant cases only (McNemar, exact)")
mcn(B$l_grade, B$n_grade, "light -> deep-  (model)")
mcn(B$n_grade, B$s_grade, "deep- -> deep+  (search)")
mcn(B$l_grade, B$s_grade, "light -> deep+  (total)")
say("\nAt n=%d a single case is %.1f points, so read the direction and the", n, 100/n)
say("paired counts, not the point estimates.")

say("\nconfident-and-wrong, the error never reviewed again")
for (a in arms) {
  g <- B[[paste0(a[1], "_grade")]]; cf <- B[[paste0(a[1], "_confidence")]]
  say("  %-26s %s", a[2], rate(sum(g == "WRONG" & cf == "high"), nrow(B)))
}

## ============================================================================
h2("2. CLEARANCE -- would the no-search arm have cleared the same cases?")
## ============================================================================
say("Stratum A, %d simple-random cases. This is the Q1 figure, recomputed", nrow(A))
say("per arm. A no-search arm that clears as many is the cheaper reviewer.\n")
for (a in arms) {
  v <- A[[paste0(a[1], "_verdict")]]
  say("  %-26s MATCH %s", a[2], rate(sum(v == "MATCH"), nrow(A)))
}
say("\nverdict mix")
for (a in arms) {
  v <- A[[paste0(a[1], "_verdict")]]
  say("  %-26s MATCH %4.1f%%  NONE %4.1f%%  AMBIGUOUS %4.1f%%", a[2],
      100 * mean(v == "MATCH"), 100 * mean(v == "NONE"), 100 * mean(v == "AMBIGUOUS"))
}

## ============================================================================
h2("3. WHERE SEARCH CHANGED THE ANSWER")
## ============================================================================
ch <- d[n_verdict != s_verdict | (!is.na(n_ein) & !is.na(s_ein) & n_ein != s_ein)]
say("search changed the verdict or the EIN on %d of %d cases (%.0f%%)",
    nrow(ch), nrow(d), 100 * nrow(ch) / nrow(d))
if (nrow(ch)) {
  say("\nby what search concluded:")
  print(table(search_confirmed = ch$s_sc, search_verdict = ch$s_verdict))
  k <- B[n_verdict != s_verdict | (!is.na(n_ein) & !is.na(s_ein) & n_ein != s_ein)]
  if (nrow(k)) {
    say("\non the %d of those with a known answer:", nrow(k))
    say("  search fixed a no-search error : %d", sum(k$n_grade != "CORRECT" & k$s_grade == "CORRECT"))
    say("  search broke a no-search right : %d", sum(k$n_grade == "CORRECT" & k$s_grade != "CORRECT"))
    say("  both wrong, differently        : %d", sum(k$n_grade != "CORRECT" & k$s_grade != "CORRECT"))
  }
}

say("\nconfidence shift -- does search make the model surer, or just righter?")
for (a in arms) {
  cf <- factor(d[[paste0(a[1], "_confidence")]], c("high", "medium", "low"))
  say("  %-26s high %4.1f%%  medium %4.1f%%  low %4.1f%%", a[2],
      100 * mean(cf == "high", na.rm = TRUE), 100 * mean(cf == "medium", na.rm = TRUE),
      100 * mean(cf == "low", na.rm = TRUE))
}

## ============================================================================
h2("4. WHAT THIS MEANS FOR THE CASCADE")
## ============================================================================
# Costs: the no-search arm's token cost is the search arm's minus the search
# results it no longer reads back, so it is measured rather than assumed.
nsf <- as.data.table(readRDS(file.path(DD, "ADJ-EXP-DEEP-nosearch.rds")))
sf  <- as.data.table(readRDS(file.path(DD, "ADJ-EXP-DEEP.rds")))
source(file.path(PF, "dev", "adjudicate-lib.R"))
cn <- adj_cost(nsf$model[1], sum(nsf$in_tokens), sum(nsf$out_tokens),
               sum(nsf$cache_read), sum(nsf$cache_write)) / nrow(nsf)
csr <- adj_cost(sf$model[1], sum(sf$in_tokens), sum(sf$out_tokens),
                sum(sf$cache_read), sum(sf$cache_write)) / nrow(sf)
say("measured token cost per case")
say("  deep, no search : $%.6f", cn)
say("  deep, search    : $%.6f  (+%.0f%%), PLUS %.1f searches/case billed per use",
    csr, 100 * (csr / cn - 1), mean(sf$searches, na.rm = TRUE))
MB <- 1008713
say("\nover the projected %s MAYBE identities, escalating 18%%:", format(MB, big.mark = ","))
say("  escalate to deep, no search : $%s", format(round(MB * 0.000674 + 0.18 * MB * cn), big.mark = ","))
say("  escalate to deep, search    : $%s  + ~%s searches",
    format(round(MB * 0.000674 + 0.18 * MB * csr), big.mark = ","),
    format(round(0.18 * MB * mean(sf$searches, na.rm = TRUE)), big.mark = ","))

say("\nAccuracy of the cascade on the %d known answers, escalating the light", nrow(B))
say("arm's low-confidence cases to each candidate escalation tier:")
esc <- B$l_confidence == "low"
for (a in list(c("n", "deep, no search"), c("s", "deep, search")))
  say("  escalate low -> %-16s %s", a[2],
      rate(sum(ifelse(esc, B[[paste0(a[1], "_grade")]], B$l_grade) == "CORRECT"), nrow(B)))
say("  light only, no escalation  %s", rate(sum(B$l_grade == "CORRECT"), nrow(B)))

## ---- worked cases ----------------------------------------------------------
h2("5. CASES WHERE SEARCH WAS DECISIVE, with the known answer where there is one")
show <- ch[order(-(s_sc == "CONFIRMED"))][seq_len(min(10L, nrow(ch)))]
for (k in seq_len(nrow(show))) {
  r <- show[k]
  say("\n%s  %s (%s)%s", r$grant_id, nz(r$recip_name), nz(r$recip_state),
      if (!is.na(r$target)) "   [known answer]" else "")
  say("  deep- %s %s (%s): %s", nz(r$n_verdict), nz(r$n_ein, ""), nz(r$n_confidence),
      substr(nz(r$n_evidence, ""), 1, 100))
  say("  deep+ %s %s (%s/%s): %s", nz(r$s_verdict), nz(r$s_ein, ""),
      nz(r$s_confidence), nz(r$s_sc), substr(nz(r$s_evidence, ""), 1, 100))
  if (!is.na(r$target))
    say("  TRUTH %s -> %s  | deep- %s, deep+ %s", r$truth_verdict, r$target,
        nz(r$n_grade), nz(r$s_grade))
}

hr(); say("wrote dev/ADJ-EXP-ABLATION.log"); hr()
close_log()
