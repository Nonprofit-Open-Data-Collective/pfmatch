#!/usr/bin/env Rscript
suppressWarnings(suppressMessages(library(data.table)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
NPM <- Sys.getenv("NPMATCH_DIR", "../npmatch")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")

p  <- readRDS(file.path(PF, "data-dev", "PROMOTION-PROBE.rds"))
m  <- readRDS(file.path(PF, "data-dev", "PF-MATCH-RESULT-1k.rds"))
st <- p$on; dep <- st$grant_id %in% p$dep_ids
pr <- as.data.table(attr(m$result, "pairs"))
sel <- pr[paste(.id, .ein) %in% paste(st$grant_id[dep], st$ein[dep])]
sel <- sel[!duplicated(paste(.id, .ein))]
j <- match(paste(sel$.id, sel$.ein), paste(st$grant_id, st$ein))
sel[, qname := st$recip_name[j]]

x <- sel[qname == "YOUTH WITH A MISSION"][1]
say("name_key_x = '%s'", x$name_key_x)
say("name_key_y = '%s'", x$name_key_y)
say("name_x     = '%s'", x$name_x)
say("name_y     = '%s'", x$name_y)
say("class(name_key_y) = %s", class(x$name_key_y))

idf <- readRDS(file.path(PF, "data-dev", "BMF-REFERENCE-BUNDLE.rds"))$token_idf
say("\nidf lookups:")
for (t in c("YOUTH", "WITH", "MISSION", "EMBRACE", "KIDS")) {
  v <- idf[t]
  say("  %-10s -> %s", t, ifelse(is.na(v), "NA (absent!)", sprintf("%.2f", v)))
}
say("\nmax(idf) = %.2f | length(idf) = %d", max(idf, na.rm = TRUE), length(idf))
say("names(idf) head: %s", paste(head(names(idf), 5), collapse = ", "))
say("\nis the idf table keyed on TOKENS or on something else?")
say("  any spaces in names(idf)? %s", any(grepl(" ", head(names(idf), 1000))))
