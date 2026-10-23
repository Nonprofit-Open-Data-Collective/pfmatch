#!/usr/bin/env Rscript
# Confirm the suspected column shift: fwrite(append = TRUE) writes POSITIONALLY,
# and the v2 path appends a year's missing column at the END of the frame rather
# than in its published position. 2025 is the only year that triggers it.
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("-", 78))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))

dir <- pf_efilepf_dir(); tb <- pf_efilepf_table()

## ---- column order as published, per year -----------------------------------
hr(); say("published column order")
n09 <- names(fread(file.path(dir, sprintf("%s-2009.CSV", tb)), nrows = 0L))
n24 <- names(fread(file.path(dir, sprintf("%s-2024.CSV", tb)), nrows = 0L))
n25 <- names(fread(file.path(dir, sprintf("%s-2025.CSV", tb)), nrows = 0L))
say("  2009 %d cols | 2024 %d cols | 2025 %d cols", length(n09), length(n24), length(n25))
say("  2024 vs 2009 identical order : %s", identical(n09, n24))
say("  2025 missing from 2009 set   : %s", paste(setdiff(n09, n25), collapse = ", "))
say("  2025 extra over 2009 set     : %s",
    if (length(setdiff(n25, n09))) paste(setdiff(n25, n09), collapse = ", ") else "(none)")
pos <- match(setdiff(n09, n25), n09)
say("  that column sits at position %d of %d in every other year;", pos, length(n09))
say("  the build appends it at position %d for 2025.", length(n25) + 1L)

## ---- what actually landed in the built corpus ------------------------------
V2 <- "C:/Users/jlecy/Documents/grants/PF-GRANTS-PAID-V2-2009-2025.csv"
hr(); say("the built corpus, 2025 rows")
hdr <- names(fread(V2, nrows = 0L))
# 2025 is last in the file, so the tail is 2025
tl <- fread(V2, colClasses = "character", na.strings = NULL,
            skip = 17253199L - 3000L, nrows = 20L, header = FALSE,
            col.names = hdr, showProgress = FALSE)
say("  TAX_YEAR values in the tail: %s", paste(unique(tl$TAX_YEAR), collapse = ", "))
show <- c("TAX_YEAR", "PF_15_G_PAID_RECIP_NAME_ORG_L1", "PF_15_G_PAID_RECIP_ADDR_CITY",
          "PF_15_G_PAID_RECIP_ADDR_STATE", "PF_15_G_PAID_AMT",
          "PF_15_G_PAID_RECIP_STAT", "PF_15_G_PAID_RELATIONSHIP")
show <- intersect(show, hdr)
print(head(tl[, ..show], 4), row.names = FALSE)

## ---- the same rows as published --------------------------------------------
hr(); say("the same filing as PUBLISHED, for comparison")
oid <- tl$OBJECTID[1]
raw <- fread(file.path(dir, sprintf("%s-2025.CSV", tb)), colClasses = "character",
             na.strings = NULL, showProgress = FALSE)
r <- raw[OBJECTID == oid]
s2 <- intersect(show, names(r))
print(head(r[, ..s2], 4), row.names = FALSE)

hr()
say("If the built row's STATE holds an amount, or its AMT holds a relationship")
say("code, the 2025 block is written one or more columns out of register.")
