#!/usr/bin/env Rscript
# ============================================================================
# adjudicate-15-no-arms.R -- Haiku 5.5 against Opus 5.5 on the same 100 cases.
#
# The MAYBE experiment could compare a cheap arm with an expensive one because
# the answer was inside the packet 71% of the time, so both arms had something
# to work with. The NO tier has no such comparison available: the answer is
# outside the packet 100% of the time, so there is no no-search arm worth
# running (see dev/adjudicate-11-no-search.R). What CAN be compared is the same
# task run by a cheaper model, and that is this stage.
#
# WHY THE grant_id JOIN IS VALID HERE AND WAS NOT IN STAGE 14.
#
# Stage 14 joined this run's verdicts to the PRIOR audit's on grant_id and got
# a plausible-looking disagreement -- 4 of 8, kappa 0.256 -- which was entirely
# an artifact: grant_id is positional, assigned by the dedup, and not stable
# across runs. G003722 is EASTER SEAL SOCIETY OF DEL-MAR in that audit and
# JAMIE DANIELS FOUNDATION here.
#
# Here both arms were handed the SAME packet file in the same run, so grant_id
# means the same identity on both sides by construction. That is a real
# difference, not a reassurance -- but it is cheap to prove rather than assert,
# so the filed names are compared row by row and the script stops if any pair
# disagrees. A bad join does not error; it manufactures a finding.
#
# USAGE  Rscript dev/adjudicate-15-no-arms.R
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
DD <- file.path(PF, "data-dev")
source(file.path(PF, "dev", "adjudicate-lib.R"))

say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() cat(strrep("=", 78), "\n")
pct <- function(k, n) sprintf("%d of %d  %.1f%%", k, n, 100 * k / n)

# Wilson, not Wald: at these n a normal interval runs past 0 or 1 and reads as
# precision it does not have.
wilson <- function(k, n, conf = 0.95) {
  if (n == 0) return(c(NA, NA))
  z <- stats::qnorm(1 - (1 - conf) / 2); p <- k / n
  c <- (p + z^2 / (2 * n)) / (1 + z^2 / n)
  h <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / (1 + z^2 / n)
  c(max(0, c - h), min(1, c + h))
}
ci <- function(k, n) { w <- wilson(k, n); sprintf("[%.1f%%, %.1f%%]", 100*w[1], 100*w[2]) }

kappa2 <- function(a, b) {
  ok <- !is.na(a) & !is.na(b)
  a <- as.character(a[ok]); b <- as.character(b[ok])
  if (!length(a)) return(c(n = 0, agree = NA, kappa = NA))
  lv <- union(a, b)
  t  <- table(factor(a, lv), factor(b, lv))
  po <- sum(diag(t)) / sum(t)
  pe <- sum(rowSums(t) * colSums(t)) / sum(t)^2
  c(n = length(a), agree = po, kappa = if (pe == 1) NA else (po - pe) / (1 - pe))
}

hr(); say("NO-TIER EXPERIMENT  stage 15: Haiku 5.5 vs Opus 5.5"); hr()

f_o <- file.path(DD, "ADJ-NO-SCORED.rds")
f_h <- file.path(DD, "ADJ-NO-SCORED-haiku.rds")
for (f in c(f_o, f_h))
  if (!file.exists(f))
    stop(sprintf("%s absent. Run stage 11 then 12 for that arm first.", basename(f)),
         call. = FALSE)
o <- as.data.table(readRDS(f_o)); h <- as.data.table(readRDS(f_h))
say("opus  rows: %d   model: %s", nrow(o), unique(o$model)[1])
say("haiku rows: %d   model: %s", nrow(h), unique(h$model)[1])

## ---- the join, proven rather than assumed ----------------------------------
d <- merge(o, h, by = "grant_id", suffixes = c("_o", "_h"))
nzkey <- function(x) gsub("[^A-Z0-9]", "", toupper(trimws(x)))
bad <- d[nzkey(recip_name_o) != nzkey(recip_name_h)]
if (nrow(bad))
  stop(sprintf("%d of %d rows pair verdicts about DIFFERENT filed names. The join is broken; do not read the numbers below.",
       nrow(bad), nrow(d)), call. = FALSE)
say("join verified: %d rows, every pair the same filed name", nrow(d))
a <- d[stratum_o == "A-estimation"]
say("stratum A (the only stratum that estimates a rate): %d", nrow(a))

## ---- 1. the load-bearing number: recoveries --------------------------------
hr(); say("1. RECOVERIES -- what each arm established, checked by lookup"); hr()
say("Both arms are scored by the same stage 12 code against the same reference")
say("EIN set, so this compares the models and not the scorers.")
say("")
# merge() suffixes only the columns the two frames SHARE, so the Opus side of a
# shared column is ein_in_ref_o and not ein_in_ref. Reading the unsuffixed name
# returns NULL, sum(NULL %in% TRUE) is 0, and the arm reads as having found
# nothing whatever -- which is how the first version of this line was caught.
# Asserted rather than trusted, because the failure is silent.
stopifnot(!is.null(a$ein_in_ref_o), !is.null(a$ein_in_ref_h))
ro <- a$ein_in_ref_o %in% TRUE; rh <- a$ein_in_ref_h %in% TRUE
say("  Opus  recoverable: %s  %s", pct(sum(ro), nrow(a)), ci(sum(ro), nrow(a)))
say("  Haiku recoverable: %s  %s", pct(sum(rh), nrow(a)), ci(sum(rh), nrow(a)))
say("")
say("  both arms       : %d", sum(ro & rh))
say("  Opus only       : %d", sum(ro & !rh))
say("  Haiku only      : %d", sum(!ro & rh))
say("  neither         : %d", sum(!ro & !rh))
if (sum(ro & !rh)) {
  say("\n  found by Opus, missed by Haiku:")
  for (i in which(ro & !rh))
    say("    %-9s %-42s haiku said org_found=%s, ein_source=%s",
        a$grant_id[i], substr(a$recip_name_o[i], 1, 42), a$org_found_h[i], a$ein_source_h[i])
}
if (sum(!ro & rh)) {
  say("\n  found by Haiku, missed by Opus:")
  for (i in which(!ro & rh))
    say("    %-9s %-42s opus said org_found=%s, ein_source=%s",
        a$grant_id[i], substr(a$recip_name_o[i], 1, 42), a$org_found_o[i], a$ein_source_o[i])
}

## ---- 2. do they name the SAME EIN ------------------------------------------
hr(); say("2. AGREEMENT ON THE EIN ITSELF"); hr()
both <- a[!is.na(ein_o) & !is.na(ein_h)]
same <- both[ein_o == ein_h]
say("  cases where both named an EIN: %d", nrow(both))
say("  identical EIN               : %s", pct(nrow(same), nrow(both)))
if (nrow(both) > nrow(same)) {
  say("\n  the disagreements -- which one is in the reference decides them:")
  for (i in which(both$ein_o != both$ein_h))
    say("    %-9s %-34s opus %s (in_ref=%s) | haiku %s (in_ref=%s)",
        both$grant_id[i], substr(both$recip_name_o[i], 1, 34),
        both$ein_o[i], both$ein_in_ref_o[i], both$ein_h[i], both$ein_in_ref_h[i])
}

## ---- 3. the taxonomy -------------------------------------------------------
hr(); say("3. THE TAXONOMY -- do the two arms classify the tier the same way"); hr()
say("These are the vignette's breakdowns. If the cheap arm reproduces them the")
say("published shares do not rest on the expensive model.")
say("")
for (v in c("entity_class", "bmf_expectation", "outside_reason", "miss_hypothesis")) {
  stopifnot(!is.null(a[[paste0(v, "_o")]]), !is.null(a[[paste0(v, "_h")]]))
  k <- kappa2(a[[paste0(v, "_o")]], a[[paste0(v, "_h")]])
  say("  %-18s n=%3d  agreement %5.1f%%  kappa %.3f", v, k[["n"]],
      100 * k[["agree"]], k[["kappa"]])
}
say("")
say("  entity_class side by side (the vignette's headline breakdown):")
cls <- sort(unique(c(a$entity_class_o, a$entity_class_h)))
cls <- cls[!is.na(cls)]
ec <- data.frame(class = cls,
                 opus  = as.integer(table(factor(a$entity_class_o, cls))),
                 haiku = as.integer(table(factor(a$entity_class_h, cls))))
print(ec[order(-ec$opus), ], row.names = FALSE)
say("")
# Deliberately NOT labelled as the vignette's 58.2%. That figure counts the
# entity_class values that are not organisations at all; this counts every case
# the BMF should not list, which also takes in the structural floor -- churches,
# group-ruling subordinates, fiscally sponsored projects. Those ARE
# organisations without an exemption of their own, so the two measure different
# things and the larger number is not a revision of the smaller one.
say("  'the BMF should not list it', structural floor included:")
no_o <- sum(!(a$bmf_expectation_o %in% "LISTED")); no_h <- sum(!(a$bmf_expectation_h %in% "LISTED"))
say("    Opus  %s  %s", pct(no_o, nrow(a)), ci(no_o, nrow(a)))
say("    Haiku %s  %s", pct(no_h, nrow(a)), ci(no_h, nrow(a)))

## ---- 4. confidence ---------------------------------------------------------
hr(); say("4. CONFIDENCE -- is the cheap arm's self-report usable"); hr()
say("The MAYBE search arm's confidence ROSE as accuracy fell, which made it")
say("worse than useless. Opus on this tier was the inverse. The test is whether")
say("a low-confidence verdict is in fact more often wrong.")
for (arm in c("o", "h")) {
  cf <- a[[paste0("confidence_", arm)]]
  rr <- a[[paste0("ein_in_ref_", arm)]] %in% TRUE
  say("\n  %s:", if (arm == "o") "Opus" else "Haiku")
  for (lv in c("high", "medium", "low")) {
    m <- cf %in% lv
    if (!any(m)) next
    say("    %-7s n=%3d   established an EIN in the reference: %s", lv, sum(m),
        pct(sum(m & rr), sum(m)))
  }
}

## ---- 5. cost ---------------------------------------------------------------
hr(); say("5. COST -- what the cheap arm actually saves"); hr()
# Read from the SEARCH files, not the SCORED ones: stage 12 keeps a subset of
# columns and `model` and the token counts are not in it. Reading them off the
# scored frame gave model = NULL, and adj_cost() indexed its price table with
# nothing -- an error here, but the same slip on a numeric column would have
# silently produced a cost of zero.
for (arm in list(list("Opus", "ADJ-NO-SEARCH.rds"), list("Haiku", "ADJ-NO-SEARCH-haiku.rds"))) {
  nm <- arm[[1]]
  x  <- as.data.table(readRDS(file.path(DD, arm[[2]])))
  mdl <- unique(x$model)[1]
  stopifnot(!is.null(mdl), !is.na(mdl), !is.null(ADJ_PRICES[[mdl]]))
  has_long <- !is.null(x$in_tokens_long)
  short <- list(input = sum(x$in_tokens), output = sum(x$out_tokens),
                cache_read = sum(x$cache_read), cache_write = sum(x$cache_write))
  long <- if (has_long)
    list(input = sum(x$in_tokens_long), output = sum(x$out_tokens_long),
         cache_read = sum(x$cache_read_long), cache_write = sum(x$cache_write_long))
    else list(input = 0, output = 0, cache_read = 0, cache_write = 0)
  cost <- adj_cost_tiered(mdl, short, long)
  say("  %-6s $%.3f over %d cases ($%.5f/case)   %d searches (%.1f/case)",
      nm, cost, nrow(x), cost / nrow(x), sum(x$searches), mean(x$searches))
  if (has_long && (long$input > 0 || long$cache_read > 0))
    say("         %d case(s) crossed the %s-token prompt step and were billed at the long rate",
        sum(x$long_request %in% TRUE), format(ADJ_LONG_PROMPT, big.mark = ","))
}
say("")
say("Web search is billed per use and is NOT in those figures. An arm that")
say("searches more is not cheaper by the ratio of its token prices.")
hr()
