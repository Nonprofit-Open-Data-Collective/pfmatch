#!/usr/bin/env Rscript
# ============================================================================
# probe-schedi-vs-527.R -- do the missing Schedule I EINs turn up as 527
# political organizations?
#
# 527s register with the IRS by filing Form 8871 (notice of section 527 status)
# and disclose on 8872. They are tax-exempt, they have EINs, and they are NOT in
# the exempt-organization BMF -- which makes them a clean candidate for the
# 279,845 alias EINs that are in neither the BMF nor the 990 e-file universe.
#
# The e-file header test already found the ones that file 990s (2,148, 0.8%) and
# they were exactly this flavour of organization -- Majority Forward, PICO Action
# Fund, GOPAC Education Fund. This asks how many more are reachable via the 527
# registry instead.
#
# Source: https://nccs.urban.org/nccs/catalogs/catalog-pacs.html (Nov 2024)
# ============================================================================
suppressWarnings(suppressMessages({
  library(data.table); library(DBI); library(duckdb) }))
setDTthreads(0)

NPM <- Sys.getenv("NPMATCH_DIR", "../npmatch")
DIR <- Sys.getenv("PF_GRANTS_DIR", file.path(path.expand("~"), "Documents", "grants"))
S3  <- "https://nccsdata.s3.us-east-1.amazonaws.com/public/pacs"
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 72), "\n")
e9  <- function(x) { x <- gsub("[^0-9]", "", as.character(x))
                     x[nchar(x) != 9] <- NA_character_; x }

get <- function(f) {
  p <- file.path(DIR, f)
  if (!file.exists(p) || file.size(p) == 0) {
    say("downloading %s ...", f)
    utils::download.file(file.path(S3, f), p, mode = "wb", quiet = TRUE)
  }
  fread(p, colClasses = "character", showProgress = FALSE, fill = TRUE)
}

o <- get("2024-11-POL-ORGS-FM-8871.csv")   # 69,345 registered 527s
d <- get("2024-11-POL-ORGS-FM-8872.csv")   # 50,904 disclosure filings
say("8871 rows: %s | 8872 rows: %s",
    format(nrow(o), big.mark = ","), format(nrow(d), big.mark = ","))

pac <- unique(c(e9(o$EIN), e9(d$EIN)))
pac <- pac[!is.na(pac)]
say("distinct 527 EINs (8871 + 8872): %s", format(length(pac), big.mark = ","))
pacname <- unique(data.table(ein = e9(o$EIN), name = o$ORGANIZATION_NAME,
                             purpose = o$PURPOSE)[!is.na(ein)], by = "ein")

## ---- the missing alias EINs ------------------------------------------------
con <- DBI::dbConnect(duckdb::duckdb(), file.path(DIR, "schedi_grants.duckdb"),
                      read_only = TRUE)
al <- as.data.table(DBI::dbGetQuery(con,
  "SELECT ein, name_display, state, n_filers FROM alias WHERE ein IS NOT NULL"))
ef <- as.data.table(DBI::dbGetQuery(con, "SELECT ein FROM efilers WHERE ein IS NOT NULL"))
DBI::dbDisconnect(con, shutdown = TRUE)

b <- fread(file.path(NPM, "data-raw", "bmf_unified_geocoded.csv"),
           select = "ein", colClasses = "character", showProgress = FALSE)
bset <- unique(e9(b$ein)); bset <- bset[!is.na(bset)]

u <- unique(al, by = "ein")
u[, `:=`(in_bmf = ein %in% bset, in_efile = ein %in% ef$ein, in_527 = ein %in% pac)]
miss <- u[in_bmf == FALSE]

hr(); say("DO THE MISSING ALIAS EINs APPEAR IN THE 527 REGISTRY?"); hr()
say("alias EINs not in the unified BMF : %s", format(nrow(miss), big.mark = ","))
say("  ... registered as a 527          : %s (%.2f%%)",
    format(sum(miss$in_527), big.mark = ","), 100 * mean(miss$in_527))
say("  ... filed a 990                  : %s (%.2f%%)",
    format(sum(miss$in_efile), big.mark = ","), 100 * mean(miss$in_efile))
say("  ... either                       : %s (%.2f%%)",
    format(sum(miss$in_527 | miss$in_efile), big.mark = ","),
    100 * mean(miss$in_527 | miss$in_efile))
say("  ... still unaccounted for        : %s (%.2f%%)",
    format(sum(!miss$in_527 & !miss$in_efile), big.mark = ","),
    100 * mean(!miss$in_527 & !miss$in_efile))

say("")
say("base rate check -- are 527s enriched among the missing?")
say("  in-BMF alias EINs that are 527s  : %.2f%%", 100 * mean(u[in_bmf == TRUE]$in_527))
say("  missing alias EINs that are 527s : %.2f%%", 100 * mean(miss$in_527))

say("")
say("how much of the 527 registry do the aliases touch at all?")
say("  527 EINs seen anywhere in Schedule I : %s of %s (%.1f%%)",
    format(sum(pac %in% u$ein), big.mark = ","), format(length(pac), big.mark = ","),
    100 * mean(pac %in% u$ein))
say("  527 EINs that ARE in the BMF          : %.1f%%", 100 * mean(pac %in% bset))

hit <- miss[in_527 == TRUE]
if (nrow(hit)) {
  i <- match(hit$ein, pacname$ein)
  hit[, `:=`(pac_name = pacname$name[i], pac_purpose = substr(pacname$purpose[i], 1, 38))]
  hr(); say("MISSING EINs RECOVERED VIA THE 527 REGISTRY"); hr()
  print(head(hit[order(-n_filers), .(schedi_name = substr(name_display, 1, 30),
                                     pac_name = substr(pac_name, 1, 30),
                                     st = state, filers = n_filers)], 25))
}
