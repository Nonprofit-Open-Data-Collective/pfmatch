#!/usr/bin/env Rscript
# ============================================================================
# Two proposed BMF expansion sources, measured before anything is built.
#
# (a) Schedule I Part II (SI-P02-T01) -- public charities itemise their grants
#     to US organisations with recipient NAME, full ADDRESS and EIN. That is a
#     name-and-address variant dictionary keyed to EIN, contributed by a
#     different population of filers than the 990-PF file we are matching.
#
# (b) EINs that file a Form 990 but do not appear in the BMF -- revoked,
#     merged, or simply lagging the BMF vintage. If a 990-PF names them, the
#     current pipeline can only return NO.
#
# The question for both: how much do they ADD over the BMF we already have?
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(library(pfmatch)))
setDTthreads(4L)
EF  <- "C:/Users/jlecy/Documents/grants/efile"
BMF <- "C:/Users/jlecy/Dropbox/00 - URBAN/00-GITHUB/npmatch/data-raw/bmf_2026_01_processed.csv"
say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() { cat(strrep("-", 78), "\n"); flush.console() }
e9  <- function(x) { x <- gsub("[^0-9]", "", as.character(x))
                     ifelse(nchar(x) == 9L, x, NA_character_) }
nz  <- function(x) { x[is.na(x)] <- ""; x }
key <- function(x) {                       # cheap comparable name key
  x <- toupper(nz(x)); x <- gsub("['\u2019.]", "", x)
  x <- gsub("[^A-Z0-9 ]", " ", x)
  x <- gsub("\\b(THE|INC|INCORPORATED|CORP|CORPORATION|CO|LTD|LLC|A|AN|OF|AND|FOR)\\b", " ", x)
  trimws(gsub(" +", " ", x))
}

b <- fread(BMF, colClasses = "character", showProgress = FALSE,
           select = c("ein", "org_name_join", "org_addr_city", "org_addr_state",
                      "org_addr_zip5"))
b[, ein := e9(ein)]
b <- b[!is.na(ein)]
b[, nk := key(org_name_join)]
bmf_ein  <- unique(b$ein)
bmf_pair <- unique(paste(b$ein, b$nk))
say("BMF rows %s, distinct EINs %s, distinct EIN+name keys %s",
    format(nrow(b), big.mark = ","), format(length(bmf_ein), big.mark = ","),
    format(length(bmf_pair), big.mark = ","))

## ---------------------------------------------------------------- (a) Sched I
hr(); say("(a) SCHEDULE I PART II AS A VARIANT DICTIONARY"); hr()
si <- fread(file.path(EF, "SI-P02-T01-GRANTS-US-ORGS-GOVTS-2022.CSV"),
            colClasses = "character", showProgress = FALSE,
            select = c("ORG_EIN", "SI_02_GRANT_US_ORG_EIN",
                       "SI_02_GRANT_US_ORG_NAME_L1", "SI_02_GRANT_US_ORG_NAME_L2",
                       "SI_02_GRANT_US_ORG_ADDR_CITY", "SI_02_GRANT_US_ORG_ADDR_STATE",
                       "SI_02_GRANT_US_ORG_ADDR_ZIP", "SI_02_GRANT_US_ORG_IRC_SECTION"))
setnames(si, c("filer", "ein", "n1", "n2", "city", "state", "zip", "irc"))
say("Schedule I grant rows (2022) : %s", format(nrow(si), big.mark = ","))
si[, ein := e9(ein)]
say("  with a usable recipient EIN: %s (%.1f%%)",
    format(sum(!is.na(si$ein)), big.mark = ","), 100 * mean(!is.na(si$ein)))
si <- si[!is.na(ein)]
si[, name := trimws(paste(nz(n1), nz(n2)))]
si[, nk := key(name)]
si <- si[nzchar(nk)]
say("  distinct recipient EINs    : %s", format(uniqueN(si$ein), big.mark = ","))
say("  distinct EIN+name variants : %s", format(uniqueN(paste(si$ein, si$nk)), big.mark = ","))

v <- unique(si[, .(ein, nk, city, state, zip)])
v[, in_bmf_ein  := ein %in% bmf_ein]
v[, in_bmf_pair := paste(ein, nk) %in% bmf_pair]
say("")
say("%-52s %10s %8s", "", "n", "share")
f <- function(x, lbl) say("%-52s %10s %7.1f%%", lbl, format(sum(x), big.mark = ","), 100 * mean(x))
f(v$in_bmf_ein,  "EIN already in the BMF")
f(!v$in_bmf_ein, "EIN NOT in the BMF")
f(v$in_bmf_pair, "EIN+name already matches a BMF name key")
f(!v$in_bmf_pair & v$in_bmf_ein, "NEW NAME VARIANT for an EIN we already have")
say("")
new_var <- v[!in_bmf_pair & in_bmf_ein]
say("New name variants attachable to a known EIN : %s, covering %s distinct EINs",
    format(nrow(new_var), big.mark = ","), format(uniqueN(new_var$ein), big.mark = ","))
say("  i.e. %.1f%% of BMF EINs would gain at least one alias from one year of",
    100 * uniqueN(new_var$ein) / length(bmf_ein))
say("  Schedule I alone.")
say("")
say("Sample of variants Schedule I supplies that the BMF does not:")
set.seed(4)
s <- new_var[sample(.N, min(12L, .N))]
bn <- b[match(s$ein, b$ein)]$org_name_join
for (i in seq_len(nrow(s)))
  cat(sprintf("  %-9s BMF: %-40s  SchI: %s\n", s$ein[i],
              substr(nz(bn[i]), 1, 40), substr(s$nk[i], 1, 40)))

## ------------------------------------------------------- (b) filers not in BMF
hr(); say("(b) EINs THAT FILE A 990 BUT ARE ABSENT FROM THE BMF"); hr()
h <- fread(file.path(EF, "F9-P00-T00-HEADER-2022.CSV"), colClasses = "character",
           showProgress = FALSE, select = c("ORG_EIN", "RETURN_TYPE"))
setnames(h, c("ein", "rt"))
h[, ein := e9(ein)]
h <- unique(h[!is.na(ein)])
say("distinct 2022 Form 990 filers : %s", format(nrow(h), big.mark = ","))
h[, in_bmf := ein %in% bmf_ein]
say("  present in the BMF          : %s (%.1f%%)",
    format(sum(h$in_bmf), big.mark = ","), 100 * mean(h$in_bmf))
say("  ABSENT from the BMF         : %s (%.1f%%)",
    format(sum(!h$in_bmf), big.mark = ","), 100 * mean(!h$in_bmf))
if (sum(!h$in_bmf)) print(h[in_bmf == FALSE, .N, by = rt][order(-N)], row.names = FALSE)

## ---------------------------------------------------- combined reach estimate
hr(); say("COMBINED: HOW MUCH WOULD THE REFERENCE GROW?"); hr()
add_ein <- unique(c(v[in_bmf_ein == FALSE]$ein, h[in_bmf == FALSE]$ein))
say("EINs addable to the reference : %s (%.2f%% on top of %s BMF EINs)",
    format(length(add_ein), big.mark = ","),
    100 * length(add_ein) / length(bmf_ein), format(length(bmf_ein), big.mark = ","))
say("Alias rows addable            : %s (%.1f%% on top of %s BMF name keys)",
    format(nrow(new_var), big.mark = ","),
    100 * nrow(new_var) / length(bmf_pair), format(length(bmf_pair), big.mark = ","))
say("")
say("One year of Schedule I only. 2009-2024 are available; aliases accumulate")
say("across years while the EIN set does not, so the alias figure is a floor.")
fwrite(new_var, "C:/Users/jlecy/Documents/grants/efile/BMF-ALIAS-CANDIDATES-2022.csv")
say("wrote BMF-ALIAS-CANDIDATES-2022.csv")
