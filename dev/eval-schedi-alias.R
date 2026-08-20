#!/usr/bin/env Rscript
# ============================================================================
# eval-schedi-alias.R -- would a Schedule I alias table surface recipients the
# BMF cannot?
#
# The proposition: 990 Schedule I records (name, address, EIN) as written by a
# grantmaker about a grantee -- the same speech act, and the same register, as
# 990-PF Part XIV. So its name variants should align with how 990-PF filers
# write recipient names far better than the BMF's legal names do.
#
# Three tests, in order of what they can prove:
#
#   PRECISION  On grants the cascade already resolved with high confidence (YES),
#              does the alias table agree with the accepted EIN? If it disagrees
#              often, it is noise and nothing below matters.
#   RECALL     On the NO tier -- where no candidate surfaced at all -- how many
#              names hit an alias and yield an EIN? This is the headline number.
#   INCREMENT  How many of those EINs are in the BMF? An alias that points at an
#              EIN the BMF does not contain cannot be used as a match, only as a
#              flag.
#
# Needs: dev/build-schedi-db.R to have run, and data-dev/PF-MATCH-REPORT-50k.csv.
# ============================================================================
suppressWarnings(suppressMessages({
  library(DBI); library(duckdb); library(data.table) }))
setDTthreads(0)

PF  <- Sys.getenv("PFMATCH_DIR", ".")
NPM <- Sys.getenv("NPMATCH_DIR", "../npmatch")
DIR <- Sys.getenv("PF_GRANTS_DIR", file.path(path.expand("~"), "Documents", "grants"))
DB  <- Sys.getenv("PF_SCHEDI_DB",  file.path(DIR, "schedi.duckdb"))
BMF <- file.path(NPM, "data-raw", "bmf_2026_01_processed.csv")
say <- function(...) cat(sprintf(...), "\n")

ein9 <- function(x) { x <- gsub("[^0-9]", "", as.character(x)); x[nchar(x) != 9] <- NA; x }
# match the normalization used in build-schedi-db.R exactly
nrm  <- function(x) {
  x <- toupper(as.character(x)); x[is.na(x)] <- ""
  gsub(" +", " ", trimws(gsub("[^A-Z0-9 ]", "", x)))
}

con <- dbConnect(duckdb::duckdb(), DB, read_only = TRUE)
on.exit(dbDisconnect(con, shutdown = TRUE))

alias <- as.data.table(dbGetQuery(con,
  "SELECT ein, name_norm, state, zip5, n_obs, n_filers, name_display
   FROM alias"))
say("alias table: %s rows, %s distinct EINs",
    format(nrow(alias), big.mark = ","), format(uniqueN(alias$ein), big.mark = ","))

## collapse to a name -> EIN lookup, keeping only unambiguous names.
## A name used for two different EINs cannot be a blocking key on its own.
byname <- alias[, .(n_eins = uniqueN(ein), ein = ein[which.max(n_filers)],
                    n_filers = sum(n_filers), n_obs = sum(n_obs)), by = name_norm]
uniq <- byname[n_eins == 1L]
say("names that map to exactly one EIN: %s of %s (%.1f%%)",
    format(nrow(uniq), big.mark = ","), format(nrow(byname), big.mark = ","),
    100 * nrow(uniq) / nrow(byname))

## ---- the 50k benchmark as the test set -------------------------------------
r <- fread(file.path(PF, "data-dev", "PF-MATCH-REPORT-50k.csv"),
           colClasses = "character", na.strings = NULL, showProgress = FALSE)
r[, `:=`(nm = nrm(recip_name), accepted = ein9(ein))]
r <- r[nzchar(nm)]
say("benchmark rows: %s", format(nrow(r), big.mark = ","))
print(r[, .N, by = status][order(-N)])

i <- match(r$nm, uniq$name_norm)
r[, alias_ein := uniq$ein[i]]
r[, alias_filers := uniq$n_filers[i]]

## ---- 1. PRECISION against the YES tier -------------------------------------
say(""); say("=== 1. PRECISION: does the alias agree with confident matches? ===")
y <- r[status == "YES" & !is.na(alias_ein) & !is.na(accepted)]
say("YES grants with an alias hit: %s", format(nrow(y), big.mark = ","))
say("  alias EIN == accepted EIN : %.1f%%", 100 * mean(y$alias_ein == y$accepted))
print(y[, .(grants = .N, agree = round(100 * mean(alias_ein == accepted), 1)),
        by = .(corroboration = cut(as.numeric(alias_filers), c(0, 1, 4, 19, Inf),
                                   labels = c("1 filer", "2-4", "5-19", "20+")))][order(corroboration)])

## ---- 2. RECALL on the NO tier ----------------------------------------------
say(""); say("=== 2. RECALL: does it reach the NO tier? ===")
print(r[, .(grants = .N,
            alias_hit = sum(!is.na(alias_ein)),
            pct = round(100 * mean(!is.na(alias_ein)), 1)), by = status][order(-grants)])

## ---- 3. INCREMENT: are those EINs usable? ----------------------------------
say(""); say("=== 3. are the surfaced EINs in the BMF? ===")
b <- fread(BMF, select = "ein", colClasses = "character", showProgress = FALSE)
bset <- unique(ein9(b$ein))
no <- r[status == "NO" & !is.na(alias_ein)]
say("NO-tier grants with an alias EIN : %s", format(nrow(no), big.mark = ","))
say("  ... whose EIN is in the BMF     : %.1f%%", 100 * mean(no$alias_ein %in% bset))
say("  ... corroborated by >1 filer    : %.1f%%", 100 * mean(as.numeric(no$alias_filers) > 1))
say("  ... both                        : %.1f%%",
    100 * mean(no$alias_ein %in% bset & as.numeric(no$alias_filers) > 1))

say(""); say("=== sample of NO-tier names the alias table resolves ===")
s <- no[as.numeric(alias_filers) >= 3 & alias_ein %in% bset][order(-as.numeric(alias_filers))]
if (nrow(s)) {
  bn <- fread(BMF, select = c("ein", "org_name_display"), colClasses = "character",
              showProgress = FALSE)
  bn[, e := ein9(ein)]
  s[, bmf_name := bn$org_name_display[match(alias_ein, bn$e)]]
  print(head(s[, .(recip_name = substr(recip_name, 1, 34),
                   state = recip_state, alias_ein, filers = alias_filers,
                   bmf_name = substr(bmf_name, 1, 40))], 25))
} else say("  none")
