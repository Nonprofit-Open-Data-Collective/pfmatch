#!/usr/bin/env Rscript
# ============================================================================
# Re-cut the development samples from the rebuilt e-file grant file.
#
# Two things this fixes about the originals (~/Documents/grants/create_samples.R):
#
#   1. They were drawn from the GTDC extract, which is missing 93% of 2024 and
#      56% of 2022 (see R/efilepf.R). Every sample inherits that hole.
#   2. They were drawn as random GRANTS and with no seed. Random grants shred
#      filer portfolios -- median 1 grant per filer in the old 50k -- which is
#      why funder-profile, year-over-year persistence and funder-repeat
#      features have been untestable. dev/FEATURE-ENGINEERING.md section 4 and
#      dev/FUNDER-PROFILE-FINDINGS.md section 6 both name this as the blocking
#      defect; PACKAGE-PLAN.md lists it as the top open item.
#
# So this cuts BOTH designs and keeps them distinct:
#
#   ef*        random grants  -- same construction as the originals, so a
#                               benchmark on it is interpretable against the
#                               old one; only the source population changed.
#   effiler*   all grants from a random sample of FILERS -- intact portfolios,
#                               which is what the feature work needs.
#
# It deliberately does NOT overwrite inputs/1k_grants_0*.csv. Those are tracked
# in git and BASELINE-2026-08 is defined as the benchmark over them; replacing
# them would make the frozen reference point unreproducible forever.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("-", 78))

SRC <- "C:/Users/jlecy/Documents/grants/PF-GRANTS-PAID-2009-2025.csv"
OUT <- file.path(Sys.getenv("PFMATCH_DIR", "."), "inputs")
SEED <- 20261021L

hr(); say("reading %s", basename(SRC))
d <- fread(SRC, colClasses = "character", showProgress = FALSE, na.strings = NULL)
say("  %s grants, %s filers", format(nrow(d), big.mark = ","),
    format(uniqueN(d$FILEREIN), big.mark = ","))

## ---- design A: random grants ----------------------------------------------
hr(); say("A. RANDOM GRANTS (same construction as the originals)")
set.seed(SEED)
a <- d[sample(.N, 100000L)]
fwrite(a, file.path(OUT, "ef100k_grants.csv"))
fwrite(a[1:50000], file.path(OUT, "ef50k_grants.csv"))
for (i in 1:5) {
  s <- a[((i - 1L) * 1000L + 1L):(i * 1000L)]
  fwrite(s, file.path(OUT, sprintf("ef1k_grants_%02d.csv", i)))
}
say("  ef100k_grants.csv, ef50k_grants.csv, ef1k_grants_01..05.csv")
pa <- a[, .N, by = .(FILEREIN, TAXYEAR)]
say("  median grants per filer-year: %.0f | filers with >=5: %.0f%%",
    median(pa$N), 100 * mean(pa$N >= 5))

## ---- design B: random filers, whole portfolios -----------------------------
hr(); say("B. RANDOM FILERS (whole portfolios)")
set.seed(SEED)
filers <- unique(d$FILEREIN)
# draw filers until the grant count lands near 100k
perm <- sample(filers)
cnt  <- d[, .N, by = FILEREIN]
setkey(cnt, FILEREIN)
run  <- cumsum(cnt[J(perm)]$N)
keep <- perm[seq_len(which(run >= 100000L)[1])]
b <- d[FILEREIN %in% keep]
say("  %s filers -> %s grants", format(length(keep), big.mark = ","),
    format(nrow(b), big.mark = ","))
fwrite(b, file.path(OUT, "effiler100k_grants.csv"))
pb <- b[, .N, by = .(FILEREIN, TAXYEAR)]
say("  median grants per filer-year: %.0f | filers with >=5: %.0f%%",
    median(pb$N), 100 * mean(pb$N >= 5))
yb <- b[, .(yrs = uniqueN(TAXYEAR)), by = FILEREIN]
say("  filers with >=2 tax years: %.0f%% | median years per filer: %.0f",
    100 * mean(yb$yrs >= 2), median(yb$yrs))

## ---- the contrast, which is the point --------------------------------------
hr(); say("WHY BOTH")
ya <- a[, .(yrs = uniqueN(TAXYEAR)), by = FILEREIN]
say("%-34s %12s %12s", "", "random grants", "random filers")
say("%-34s %12.0f %12.0f", "median grants per filer-year", median(pa$N), median(pb$N))
say("%-34s %11.0f%% %11.0f%%", "filer-years with >=5 grants",
    100 * mean(pa$N >= 5), 100 * mean(pb$N >= 5))
say("%-34s %11.0f%% %11.0f%%", "filers seen in >=2 tax years",
    100 * mean(ya$yrs >= 2), 100 * mean(yb$yrs >= 2))
say("")
say("Persistence -- year-over-year overlap of a funder's grantees -- is")
say("arithmetically forced to zero when a filer contributes one grant per year.")
say("That is why it has never been measurable on a random-grant sample.")

say("")
say("wrote to %s", normalizePath(OUT))
