#!/usr/bin/env Rscript
# ============================================================================
# The funder NTEE profile, with entropy and persistence as GATES.
#
# dev/PURPOSE-MATCH-FINDINGS.md section 2 rejected a crude version of this: across
# all foundations with >= 5 matched grantees the top NTEE major group holds 0.333
# of grants against a 0.268 base rate. But that is an UNCONDITIONAL average, and
# it says nothing about whether a *concentrated* funder's profile predicts. This
# tests the conditional version: build the profile, measure how concentrated each
# funder is, and check whether the profile discriminates where concentration is
# high.
#
# Step 0 is a power check. If foundations in the dev sample carry too few matched
# grantees, the question cannot be answered here at all.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
BMF <- file.path(PF, "..", "npmatch", "data-raw", "bmf_2026_01_processed.csv")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 78), "\n")
e9  <- function(x) { x <- gsub("[^0-9]", "", as.character(x))
                     ifelse(nchar(x) == 9L, x, NA_character_) }

## ---- rebuild the run -------------------------------------------------------
m   <- readRDS(file.path(PF, "data-dev", "PF-MATCH-RESULT-50k.rds"))
cfg <- npmatch::np_config()
pr0 <- npmatch::np_veto(npmatch::np_score(attr(m$result, "pairs"), cfg, method = "hier"), cfg)
res <- npmatch::np_tier(npmatch::np_select(pr0, cfg), cfg)
x <- m; x$result <- res; attr(x$result, "pairs") <- pr0; attr(x$result, "config") <- cfg
st <- as.data.table(pf_status(x))
g  <- as.data.table(m$grants)
st[, taxyear := g$TAXYEAR[match(grant_id, g$grant_id)]]

## ---- NTEE levels for every BMF EIN ----------------------------------------
b <- fread(BMF, colClasses = "character", showProgress = FALSE,
           select = c("ein", "ntee_code_clean", "nteev2", "ntee_code_major_group"))
b[, ein := e9(ein)]
bad <- function(v) is.na(v) | !nzchar(v) | toupper(v) %in% c("INVALID", "UNDEFINED", "Z99", "Z")
b[, L2 := toupper(substr(ntee_code_clean, 1, 1))]                 # major group letter
b[, L1 := toupper(sub("-.*$", "", nteev2))]                       # industry group, e.g. ART
b[, L34 := toupper(substr(ntee_code_clean, 2, 3))]                # division + subdivision
b[bad(ntee_code_clean), c("L2", "L34") := NA_character_]
b[bad(nteev2) | !grepl("-", nteev2), L1 := NA_character_]
setkey(b, ein)

yes <- st[status == "YES" & !is.na(ein)]
yes[, `:=`(f = e9(filer_ein), r = e9(ein))]
yes <- yes[!is.na(f) & !is.na(r)]
i <- match(yes$r, b$ein)
yes[, `:=`(L1 = b$L1[i], L2 = b$L2[i], L34 = b$L34[i])]

hr(); say("STEP 0 -- IS THERE ENOUGH DATA IN THIS SAMPLE TO ASK THE QUESTION?"); hr()
say("YES-matched grants                       : %s", format(nrow(yes), big.mark = ","))
say("  ...with a usable NTEE major group      : %s (%.0f%%)",
    format(sum(!is.na(yes$L2)), big.mark = ","), 100 * mean(!is.na(yes$L2)))
prof <- yes[!is.na(L2), .(n = .N, n_ein = uniqueN(r), n_yr = uniqueN(taxyear)), by = f]
say("")
say("distinct filing foundations with >=1 usable YES grantee: %s",
    format(nrow(prof), big.mark = ","))
say("%-38s %9s %9s", "foundations with at least", "n", "share")
for (k in c(1, 3, 5, 10, 20)) say("%-38s %9s %8.1f%%", sprintf("  %d matched grantees", k),
    format(sum(prof$n >= k), big.mark = ","), 100 * mean(prof$n >= k))
say("")
say("foundations with grants in >=2 tax years : %s (%.1f%%)",
    format(sum(prof$n_yr >= 2), big.mark = ","), 100 * mean(prof$n_yr >= 2))
say("  ...and >=5 matched grantees            : %s",
    format(sum(prof$n_yr >= 2 & prof$n >= 5), big.mark = ","))

## ---- entropy and persistence ----------------------------------------------
nent <- function(v) {                       # normalised Shannon entropy, 0 = pure
  t <- table(v); p <- as.numeric(t) / sum(t)
  if (length(p) <= 1L) return(0)
  -sum(p * log(p)) / log(length(p))
}
conc <- function(v) max(table(v)) / length(v)

P <- yes[!is.na(L2), .(n = .N, n_ein = uniqueN(r), n_yr = uniqueN(taxyear),
                       H2 = nent(L2), top2 = conc(L2), modal2 = names(which.max(table(L2))),
                       H1 = if (sum(!is.na(L1))) nent(L1[!is.na(L1)]) else NA_real_,
                       codes2 = list(unique(L2)), codes34 = list(unique(paste0(L2, L34)))),
         by = f]
base2 <- max(table(yes$L2[!is.na(yes$L2)])) / sum(!is.na(yes$L2))

hr(); say("CONCENTRATION, BY PORTFOLIO SIZE"); hr()
say("population base rate for the single commonest major group: %.3f", base2)
say("")
say("%-18s %8s %10s %12s %10s", "portfolio size", "funders", "median H", "median top", "median #grp")
for (k in list(c(2,2), c(3,4), c(5,9), c(10,19), c(20,1e6))) {
  s <- P[n >= k[1] & n <= k[2]]
  if (!nrow(s)) next
  say("%-18s %8s %10.3f %12.3f %10.0f",
      if (k[1] == k[2]) sprintf("  %d", k[1]) else sprintf("  %d-%s", k[1],
        if (k[2] > 1e5) "+" else as.character(k[2])),
      format(nrow(s), big.mark = ","), median(s$H2), median(s$top2),
      median(lengths(s$codes2)))
}
say("")
say("Low H means a thematically concentrated funder. The gate the proposal needs")
say("is a population of funders with LOW H and ENOUGH grants to trust it.")
gate <- P[n >= 5 & H2 <= 0.5]
say("")
say("funders with >=5 matched grantees AND H2 <= 0.5 : %s (%.1f%% of all funders)",
    format(nrow(gate), big.mark = ","), 100 * nrow(gate) / nrow(P))
if (nrow(gate)) say("  their median top-group share            : %.3f  (base %.3f)",
                    median(gate$top2), base2)

## ---- persistence -----------------------------------------------------------
hr(); say("PERSISTENCE: DO FUNDERS REPEAT GRANTEES ACROSS YEARS?"); hr()
mult <- yes[f %in% P[n_yr >= 2]$f]
if (nrow(mult)) {
  pers <- mult[, {
    yrs <- sort(unique(taxyear))
    ov <- vapply(seq_len(length(yrs) - 1L), function(k) {
      a <- unique(r[taxyear == yrs[k]]); bb <- unique(r[taxyear == yrs[k + 1]])
      if (!length(a) || !length(bb)) NA_real_ else length(intersect(a, bb)) / length(union(a, bb))
    }, numeric(1))
    list(jaccard = mean(ov, na.rm = TRUE), n_yr = length(yrs), n = .N)
  }, by = f]
  pers <- pers[!is.nan(jaccard) & !is.na(jaccard)]
  say("funders with >=2 years and a computable overlap : %s", format(nrow(pers), big.mark = ","))
  if (nrow(pers)) {
    say("  median year-over-year grantee Jaccard         : %.3f", median(pers$jaccard))
    say("  share with zero overlap                       : %.0f%%", 100 * mean(pers$jaccard == 0))
    big <- pers[n >= 5]
    if (nrow(big)) say("  among those with >=5 grants: n=%d, median %.3f",
                       nrow(big), median(big$jaccard))
  }
}

## ---- does the profile discriminate on adjudicated cases? -------------------
hr(); say("DOES THE PROFILE HELP ON THE ADJUDICATED CASES?"); hr()
a1 <- fread(file.path(PF, "data-dev", "AUDIT-MAYBE-100.csv"), colClasses = "character")
v1 <- fread(file.path(PF, "dev", "maybe-verdicts.csv"), colClasses = "character")
d <- merge(a1[, .(gid = grant_id, rank = as.integer(rank), ein = e9(ein),
                  f = e9(fdn_ein))],
           v1[, .(gid = grant_id, cr = as.integer(correct_rank))], by = "gid")
a2 <- fread(file.path(PF, "data-dev", "HARD-ENRICHED.csv"), colClasses = "character")
v2 <- fread(file.path(PF, "dev", "enrichment-verdicts.csv"), colClasses = "character")
v2 <- v2[outcome %in% c("RESOLVED_ALT", "RESOLVED_PICK")]
s2 <- a2[, .(gid = paste0("E", idx), rank = as.integer(rank), ein = e9(cand_ein),
             idx = as.integer(idx), grant_id)]
s2[, f := e9(st$filer_ein[match(grant_id, st$grant_id)])]
d <- rbind(d, merge(s2, v2[, .(idx = as.integer(idx), cr = as.integer(pick_ein_rank))],
                    by = "idx")[, .(gid, rank, ein, f, cr)])
d <- d[!is.na(ein) & !is.na(cr) & !is.na(f)]
d[, correct := rank == cr]
j <- match(d$ein, b$ein)
d[, `:=`(L2 = b$L2[j])]

# leave-one-out profile for the filer
pl <- P[, .(f, H2, n, modal2)]
d <- merge(d, pl, by = "f", all.x = TRUE)
d[, has_profile := !is.na(n) & n >= 3L]
say("adjudicated candidate rows                     : %d", nrow(d))
say("  whose FILER has >=3 matched grantees elsewhere: %d rows, %d grants",
    sum(d$has_profile), uniqueN(d$gid[d$has_profile]))
say("  whose filer has >=5                           : %d rows, %d grants",
    sum(!is.na(d$n) & d$n >= 5), uniqueN(d$gid[!is.na(d$n) & d$n >= 5]))
say("")
if (uniqueN(d$gid[d$has_profile]) >= 10) {
  s <- d[has_profile == TRUE & !is.na(L2)]
  s[, hit := L2 == modal2]
  say("candidates matching the funder's modal major group:")
  say("  correct candidates   : %d of %d (%.0f%%)",
      s[correct == TRUE, sum(hit)], s[, sum(correct)], 100 * s[correct == TRUE, mean(hit)])
  say("  distractors          : %d of %d (%.0f%%)",
      s[correct == FALSE, sum(hit)], s[, sum(!correct)], 100 * s[correct == FALSE, mean(hit)])
} else {
  say("NOT ENOUGH ADJUDICATED CASES WITH A FUNDER PROFILE TO TEST.")
  say("Only %d adjudicated grants have a filer carrying >=3 matched grantees",
      uniqueN(d$gid[d$has_profile]))
  say("elsewhere in the sample. This is the random-grant sampling problem again:")
  say("the dev file draws grants, not filers, so portfolios arrive shredded.")
}
fwrite(P[, .(f, n, n_ein, n_yr, H2, top2, modal2)],
       file.path(PF, "data-dev", "FUNDER-PROFILES.csv"))
say("")
say("wrote data-dev/FUNDER-PROFILES.csv")
