#!/usr/bin/env Rscript
# What is actually in a grant row that has no recipient name?
suppressWarnings(suppressMessages(library(data.table)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
NPM <- Sys.getenv("NPMATCH_DIR", "../npmatch")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")

g <- pf_read_grants(file.path(PF, "inputs"), pattern = "^(1k_grants_.*|50k_grants)\\.csv$")
g <- g[!duplicated(paste(g$FILEREIN, g$TAXYEAR, g$SIGOCPYAMOUN, g$SIGOCPYPOGOC,
                         g$SIGOCPYRFAAL1, g$SIGOCPYRFACI)), ]
nn <- g[!g$has_name, , drop = FALSE]
say("name-less grant rows: %d of %d", nrow(nn), nrow(g))

fld <- c(street = "recip_street", city = "recip_city", state = "recip_state_raw",
         zip = "recip_zip5", purpose = "SIGOCPYPOGOC", amount = "SIGOCPYAMOUN",
         status = "SIGOCPYRFSTA", rela = "SIGOCPYRRELA")
say("\nhow many name-less rows carry anything at all in each other field:")
for (n in names(fld)) {
  v <- nn[[fld[[n]]]]
  say("  %-8s %4d of %d (%.0f%%)", n, sum(!is.na(v) & nzchar(trimws(v))), nrow(nn),
      100 * mean(!is.na(v) & nzchar(trimws(v))))
}

say("\nrows that are COMPLETELY empty apart from the filer header: %d",
    sum(rowSums(sapply(fld, function(f) {
      v <- nn[[f]]; !is.na(v) & nzchar(trimws(v))
    })) == 0))

say("\nthe name-less rows that DO carry an address:")
wa <- nn[nn$has_address, , drop = FALSE]
if (nrow(wa)) {
  for (i in seq_len(nrow(wa)))
    say("  [%s] street=%-30s city=%-16s %s %s | amt=%s | purpose=%s",
        wa$grant_id[i], substr(paste(wa$recip_street[i]), 1, 30),
        substr(paste(wa$recip_city[i]), 1, 16), wa$recip_state_raw[i],
        wa$recip_zip5[i], wa$SIGOCPYAMOUN[i], substr(paste(wa$SIGOCPYPOGOC[i]), 1, 40))
} else say("  (none)")

say("\nsample of name-less rows WITHOUT an address (what they look like):")
wo <- nn[!nn$has_address, , drop = FALSE]
for (i in head(seq_len(nrow(wo)), 8))
  say("  [%s] filer=%-34s amt=%-9s purpose='%s'", wo$grant_id[i],
      substr(paste(wo$FILERNAME1[i]), 1, 34), wo$SIGOCPYAMOUN[i],
      substr(paste(wo$SIGOCPYPOGOC[i]), 1, 30))
