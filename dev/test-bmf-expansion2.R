#!/usr/bin/env Rscript
# Quality gates for the Schedule I expansion. An alias that is wrong does more
# damage than an alias that is missing, because it manufactures a confident EIN
# match. Two candidate gates, both cheap:
#   corroboration -- the alias is reported by >= 2 distinct filers
#   plausibility  -- the alias shares content tokens with the BMF name, or the
#                    EIN is independently known to file a 990
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(4L)
EF  <- "C:/Users/jlecy/Documents/grants/efile"
BMF <- "C:/Users/jlecy/Dropbox/00 - URBAN/00-GITHUB/npmatch/data-raw/bmf_2026_01_processed.csv"
say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() { cat(strrep("-", 78), "\n"); flush.console() }
e9  <- function(x) { x <- gsub("[^0-9]", "", as.character(x))
                     ifelse(nchar(x) == 9L, x, NA_character_) }
nz  <- function(x) { x[is.na(x)] <- ""; x }
key <- function(x) {
  x <- toupper(nz(x)); x <- gsub("['\u2019.]", "", x)
  x <- gsub("[^A-Z0-9 ]", " ", x)
  x <- gsub("\\b(THE|INC|INCORPORATED|CORP|CORPORATION|CO|LTD|LLC|A|AN|OF|AND|FOR)\\b", " ", x)
  trimws(gsub(" +", " ", x))
}

b <- fread(BMF, colClasses = "character", showProgress = FALSE,
           select = c("ein", "org_name_join"))
b[, ein := e9(ein)][, nk := key(org_name_join)]
b <- b[!is.na(ein)]
setkey(b, ein)

si <- fread(file.path(EF, "SI-P02-T01-GRANTS-US-ORGS-GOVTS-2022.CSV"),
            colClasses = "character", showProgress = FALSE,
            select = c("ORG_EIN", "SI_02_GRANT_US_ORG_EIN",
                       "SI_02_GRANT_US_ORG_NAME_L1", "SI_02_GRANT_US_ORG_NAME_L2"))
setnames(si, c("filer", "ein", "n1", "n2"))
si[, ein := e9(ein)]
si <- si[!is.na(ein)]
si[, nk := key(trimws(paste(nz(n1), nz(n2))))]
si <- si[nzchar(nk)]

# how many distinct filers report each EIN+alias?
al <- si[, .(n_filers = uniqueN(filer), n_rows = .N), by = .(ein, nk)]
al[, bmf_nk := b$nk[match(ein, b$ein)]]
al[, in_bmf_ein := !is.na(bmf_nk)]
al[, is_new := in_bmf_ein & nk != bmf_nk]

tokset <- function(x) strsplit(x, " ", fixed = TRUE)
ta <- tokset(al$nk); tb <- tokset(nz(al$bmf_nk))
al[, shared := mapply(function(p, q) length(intersect(p, q)), ta, tb)]
al[, min_len := pmin(lengths(ta), lengths(tb))]
al[, containment := ifelse(min_len > 0, shared / min_len, 0)]

new <- al[is_new == TRUE]
hr(); say("QUALITY OF THE 2022 SCHEDULE I ALIASES"); hr()
say("candidate new aliases for known EINs : %s", format(nrow(new), big.mark = ","))
say("")
say("%-46s %10s %8s", "gate", "aliases", "share")
g <- function(x, lbl) say("%-46s %10s %7.1f%%", lbl, format(sum(x), big.mark = ","), 100 * mean(x))
g(new$n_filers >= 2, "corroborated by >= 2 distinct filers")
g(new$n_filers >= 3, "corroborated by >= 3 distinct filers")
g(new$shared >= 1,   "shares >= 1 content token with the BMF name")
g(new$shared >= 2,   "shares >= 2 content tokens")
g(new$containment >= 0.999, "full containment in the BMF name")
g(new$n_filers >= 2 | new$shared >= 1, "EITHER corroborated OR token-overlapping")
g(new$n_filers >= 2 & new$shared >= 1, "BOTH")
say("")
say("Aliases with NO token overlap and only ONE reporting filer are the danger")
say("class -- a contact person, a programme label, a keying error:")
bad <- new[shared == 0 & n_filers == 1]
say("  %s of %s (%.1f%%)", format(nrow(bad), big.mark = ","),
    format(nrow(new), big.mark = ","), 100 * nrow(bad) / nrow(new))
set.seed(7)
s <- bad[sample(.N, min(8L, .N))]
for (i in seq_len(nrow(s)))
  cat(sprintf("    %-9s BMF: %-38s  alias: %s\n", s$ein[i],
              substr(nz(s$bmf_nk[i]), 1, 38), substr(s$nk[i], 1, 38)))
say("")
say("...against the class that passes both gates:")
good <- new[shared >= 1 & n_filers >= 2]
s <- good[sample(.N, min(8L, .N))]
for (i in seq_len(nrow(s)))
  cat(sprintf("    %-9s BMF: %-38s  alias: %s\n", s$ein[i],
              substr(nz(s$bmf_nk[i]), 1, 38), substr(s$nk[i], 1, 38)))

hr(); say("EINs ABSENT FROM THE BMF -- ARE THEY REAL OR MIS-KEYED?"); hr()
h <- fread(file.path(EF, "F9-P00-T00-HEADER-2022.CSV"), colClasses = "character",
           showProgress = FALSE, select = "ORG_EIN")
setnames(h, "ein"); h[, ein := e9(ein)]
filers <- unique(h$ein[!is.na(h$ein)])
miss <- al[in_bmf_ein == FALSE, .(n_filers = sum(n_filers), n_alias = .N), by = ein]
say("distinct EINs on Schedule I but not in the BMF : %s", format(nrow(miss), big.mark = ","))
miss[, files_990 := ein %in% filers]
say("  ...that independently file a 2022 Form 990   : %s (%.1f%%)",
    format(sum(miss$files_990), big.mark = ","), 100 * mean(miss$files_990))
say("  ...reported by >= 2 distinct filers          : %s (%.1f%%)",
    format(sum(miss$n_filers >= 2), big.mark = ","), 100 * mean(miss$n_filers >= 2))
say("  ...either                                    : %s (%.1f%%)",
    format(sum(miss$files_990 | miss$n_filers >= 2), big.mark = ","),
    100 * mean(miss$files_990 | miss$n_filers >= 2))
say("")
say("An EIN reported once, by one filer, absent from both the BMF and the 990")
say("filer list is most likely a keying error and should not enter the")
say("reference: %s of %s (%.1f%%).",
    format(sum(!miss$files_990 & miss$n_filers < 2), big.mark = ","),
    format(nrow(miss), big.mark = ","),
    100 * mean(!miss$files_990 & miss$n_filers < 2))

hr(); say("RECOMMENDED EXPANSION, AFTER GATING"); hr()
keep_alias <- new[shared >= 1 | n_filers >= 2]
keep_ein   <- miss[files_990 | n_filers >= 2]
say("aliases to add  : %s (from %s ungated)",
    format(nrow(keep_alias), big.mark = ","), format(nrow(new), big.mark = ","))
say("  covering EINs : %s", format(uniqueN(keep_alias$ein), big.mark = ","))
say("EINs to add     : %s (from %s ungated)",
    format(nrow(keep_ein), big.mark = ","), format(nrow(miss), big.mark = ","))
fwrite(keep_alias[, .(ein, alias = nk, n_filers, shared)],
       file.path(EF, "BMF-ALIASES-GATED-2022.csv"))
fwrite(keep_ein, file.path(EF, "BMF-NEW-EINS-GATED-2022.csv"))
say("wrote BMF-ALIASES-GATED-2022.csv and BMF-NEW-EINS-GATED-2022.csv")
