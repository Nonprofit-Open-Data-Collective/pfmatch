#!/usr/bin/env Rscript
# ============================================================================
# Persistence: does a foundation fund the same grantees year after year?
#
# Untestable until now. On every prior sample 92% of filer-years held exactly
# one grant, so year-over-year overlap was arithmetically forced to zero -- the
# statistic measured the sampling design, not philanthropy
# (dev/FUNDER-PROFILE-FINDINGS.md section 3). The filer sample fixes that:
# median 7 grants per filer-year, 92% of filers spanning 2+ years.
#
# Measured on the DEDUP IDENTITY rather than a matched EIN, deliberately:
#
#   - it needs no match, so it is not contingent on match quality and cannot
#     inherit the cascade's own preferences;
#   - it is a conservative FLOOR. Two spellings of one grantee in different
#     years are two identities here and would be one EIN, so true persistence
#     is at least this high. If the floor is already useful the feature is
#     real; if the floor is zero the EIN version is worth checking before
#     giving up.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("-", 78))

g <- fread(file.path(PF, "inputs", "effiler100k_grants.csv"),
           colClasses = "character", showProgress = FALSE, na.strings = NULL)
g[, grant_id := sprintf("G%07d", .I)]
say("filer sample: %s grants, %s filers, tax years %s-%s",
    format(nrow(g), big.mark = ","), format(uniqueN(g$FILEREIN), big.mark = ","),
    min(g$TAXYEAR), max(g$TAXYEAR))

prep <- pf_prepare(g, dedup = "exact", verbose = FALSE)
d <- as.data.table(prep$grants)
d <- d[in_scope == TRUE]
say("in scope: %s rows, %s distinct identities",
    format(nrow(d), big.mark = ","), format(uniqueN(d$recipient_uid), big.mark = ","))

## ---- the structural precondition, restated on this sample ------------------
hr(); say("PRECONDITION: IS THERE ANYTHING TO OVERLAP?")
py <- d[, .N, by = .(FILEREIN, TAXYEAR)]
say("median grants per filer-year : %.0f   (every prior sample: 1)", median(py$N))
say("filer-years with 1 grant     : %.0f%%  (every prior sample: 92%%)",
    100 * mean(py$N == 1))
yr <- d[, .(n_yr = uniqueN(TAXYEAR), n = .N), by = FILEREIN]
say("filers with >=2 tax years    : %s of %s (%.0f%%)",
    format(sum(yr$n_yr >= 2), big.mark = ","), format(nrow(yr), big.mark = ","),
    100 * mean(yr$n_yr >= 2))

## ---- persistence ------------------------------------------------------------
hr(); say("YEAR-OVER-YEAR GRANTEE OVERLAP (Jaccard, consecutive filed years)")
eligible <- yr[n_yr >= 2]$FILEREIN
s <- d[FILEREIN %in% eligible]
pers <- s[, {
  ys <- sort(unique(TAXYEAR))
  ov <- vapply(seq_len(length(ys) - 1L), function(k) {
    a <- unique(recipient_uid[TAXYEAR == ys[k]])
    b <- unique(recipient_uid[TAXYEAR == ys[k + 1L]])
    if (!length(a) || !length(b)) NA_real_ else
      length(intersect(a, b)) / length(union(a, b))
  }, numeric(1))
  list(jaccard = mean(ov, na.rm = TRUE), n_yr = length(ys), n = .N,
       med_per_yr = as.numeric(stats::median(table(TAXYEAR))))
}, by = FILEREIN]
pers <- pers[!is.na(jaccard) & !is.nan(jaccard)]
say("filers with a computable overlap: %s", format(nrow(pers), big.mark = ","))
say("")
say("  median Jaccard        : %.3f", median(pers$jaccard))
say("  mean Jaccard          : %.3f", mean(pers$jaccard))
say("  share with ZERO overlap: %.0f%%   (prior samples: 94%%)",
    100 * mean(pers$jaccard == 0))
say("  share above 0.25      : %.0f%%", 100 * mean(pers$jaccard > 0.25))
say("  share above 0.50      : %.0f%%", 100 * mean(pers$jaccard > 0.50))
say("")
say("by portfolio size (median grants per filer-year):")
pers[, bucket := cut(med_per_yr, c(0, 1, 2, 5, 20, Inf),
                     labels = c("1", "2", "3-5", "6-20", "20+"))]
print(pers[, .(filers = .N, med_jaccard = round(median(jaccard), 3),
               pct_zero = round(100 * mean(jaccard == 0))), by = bucket][order(bucket)],
      row.names = FALSE)

## ---- the operational form: is_repeat ---------------------------------------
hr(); say("THE OPERATIONAL FORM: IS THIS GRANTEE A REPEAT FOR THIS FUNDER?")
setorder(s, FILEREIN, TAXYEAR)
fy <- unique(s[, .(FILEREIN, recipient_uid, TAXYEAR)])
fy[, first_yr := min(TAXYEAR), by = .(FILEREIN, recipient_uid)]
fy[, is_repeat := TAXYEAR > first_yr]
say("filer-grantee-year rows      : %s", format(nrow(fy), big.mark = ","))
say("rows that are a REPEAT       : %s (%.1f%%)",
    format(sum(fy$is_repeat), big.mark = ","), 100 * mean(fy$is_repeat))
say("")
say("This is the number that matters for matching. A grantee the funder also")
say("named in an earlier year has an identity the cascade may already have")
say("resolved, so the match can be propagated instead of re-scored.")
rec <- fy[, .(n_yrs = uniqueN(TAXYEAR)), by = .(FILEREIN, recipient_uid)]
say("")
say("distinct filer-grantee pairs : %s", format(nrow(rec), big.mark = ","))
say("  seen in >=2 years          : %s (%.1f%%)",
    format(sum(rec$n_yrs >= 2), big.mark = ","), 100 * mean(rec$n_yrs >= 2))
say("  seen in >=5 years          : %s (%.1f%%)",
    format(sum(rec$n_yrs >= 5), big.mark = ","), 100 * mean(rec$n_yrs >= 5))

fwrite(pers, file.path(PF, "data-dev", "PERSISTENCE-FILER-SAMPLE.csv"))
fwrite(fy,   file.path(PF, "data-dev", "FILER-GRANTEE-YEARS.csv"))
say("")
say("wrote data-dev/PERSISTENCE-FILER-SAMPLE.csv and FILER-GRANTEE-YEARS.csv")
