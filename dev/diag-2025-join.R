#!/usr/bin/env Rscript
# Why does every sampled 2025 row fail the v1 -> v2 join?
# Dedup removed 0.3% of 2025, so this is a join failure, not a drop.
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("-", 78))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
sq <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; x }
map <- pf_efilepf_map()

CC1 <- c("SIGOCPYRPNAM","SIGOCPYRBNBN1","SIGOCPYRBNBN2","SIGOCPYRFAAL1",
         "SIGOCPYRFAAL2","SIGOCPYRFACI","SIGOCPYRFAPO","SIGOCPYRFAPC",
         "SIGOCAFFRFACO","SIGOCPYAMOUN","SIGOCPYPOGOC","SIGOCPYRFSTA",
         "SIGOCPYRRELA")

## a 2025 row from the sample
s <- rbindlist(lapply(list.files(file.path(PF,"inputs"),
       pattern="^ef1k_grants_[0-9]+\\.csv$", full.names=TRUE),
       fread, colClasses="character", na.strings=NULL))
s25 <- s[TAXYEAR == "2025"]
hr(); say("sampled 2025 rows: %d, filings %d", nrow(s25), uniqueN(s25$OBJECTID))

## the same filings, straight out of the v2 source extract for 2025
src <- file.path(pf_efilepf_dir(), sprintf("%s-2025.CSV", pf_efilepf_table()))
v <- fread(src, colClasses="character", na.strings=NULL, showProgress=FALSE)
say("v2 source 2025: %s rows", format(nrow(v), big.mark=","))
w <- v[OBJECTID %chin% unique(s25$OBJECTID)]
say("rows for those filings in the v2 source: %s", format(nrow(w), big.mark=","))

if (!nrow(w)) {
  say("")
  say("NONE. The filings themselves are absent, so this is not a content")
  say("mismatch. Compare the OBJECTID forms:")
  say("  sample   %s", paste(head(sort(unique(s25$OBJECTID)), 3), collapse=" | "))
  say("  v2 2025  %s", paste(head(sort(unique(v$OBJECTID)), 3), collapse=" | "))
  quit(save="no")
}

## compare one row field by field
hr(); say("field-by-field on one filing")
oid <- s25$OBJECTID[1]
a <- s25[OBJECTID == oid][1]
b <- w[OBJECTID == oid]
say("OBJECTID %s -- %d row(s) in sample, %d in v2 source", oid, nrow(s25[OBJECTID==oid]), nrow(b))
for (c1 in CC1) {
  c2 <- map[[c1]]
  av <- sq(a[[c1]])
  bv <- if (c2 %in% names(b)) sq(b[[c2]]) else "<COLUMN ABSENT>"
  same <- any(av == bv)
  say("  %-14s -> %-32s %s  v1=[%s] v2=[%s]", c1, c2,
      if (same) "match" else "DIFF ", substr(av,1,24),
      substr(paste(unique(bv), collapse=","),1,24))
}
hr()
