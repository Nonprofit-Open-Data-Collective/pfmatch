#!/usr/bin/env Rscript
# ============================================================================
# How exposed is the "both references agree, so it is right" assumption?
#
# PLAYWORKS showed the failure mode: the filed grant is PLAYWORKS in Washington
# DC; both references chose a real but unrelated Newton MA org named exactly
# PLAYWORKS; and the correct org carries its own variant row named
# "PLAYWORKS WASHINGTON DC" in Washington DC. The name matched exactly and the
# geography did not, and geography lost.
#
# That was found by accident. This scans the whole YES->YES same-EIN cell --
# 2,564 identities, 53% of the file, never sampled -- for the same signature:
#
#   the CHOSEN EIN does not match the filed city, AND
#   some OTHER EIN has a reference row with the same name_key that DOES
#
# A hit is not proof of an error; it is a case where the evidence points the
# other way and the pipeline went with the name. Counting them bounds how much
# of the agreement cell is exposed to this specific failure.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(library(npmatch)))
setDTthreads(0)
PF  <- Sys.getenv("PFMATCH_DIR", ".")
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("-", 84))
sq  <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; x }
e9  <- function(v) { v <- gsub("[^0-9]", "", as.character(v))
                     ifelse(nchar(v) == 9L, v, NA_character_) }
nkey <- function(x) {
  nm <- npmatch:::.np_basic_clean(sq(x))
  nm <- npmatch:::.np_replace_tokens(nm, npmatch:::.np_abbrev)
  npmatch:::.np_strip_lead_the(npmatch:::.np_strip_suffix(nm))
}
norm_city <- function(x) gsub("[^A-Z]", "", toupper(sq(x)))

j <- fread(file.path(PF, "data-dev", "TWO-TIER-SIMULATION.csv"), colClasses = "character")
agree <- j[cell == "YES->YES  same EIN"]
say("agreement cell: %s identities", format(nrow(agree), big.mark = ","))

suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
g <- pf_read_grants(file.path(PF, "inputs"), pattern = "^ef1k_grants_")
g <- as.data.table(pf_prepare_grants(pf_recover_name_from_street(g)))
gk <- g[, .(id = grant_id, recip_name, recip_city, recip_state)]
a <- merge(agree[, .(id, ein = e9(ein_a))], gk, by = "id")
a <- a[!is.na(ein) & nzchar(sq(recip_name)) & nzchar(sq(recip_city))]
a[, nk := nkey(recip_name)][, qcity := norm_city(recip_city)]
a <- a[nzchar(nk)]
say("usable (EIN + name + city): %s", format(nrow(a), big.mark = ","))

b <- fread(file.path(PF, "data-dev", "BMF-AUGMENTED-unified-fixed.csv"),
           colClasses = "character", showProgress = FALSE,
           select = c("ein", "org_name_join", "org_addr_city", "org_addr_state"))
b[, ein := e9(ein)]
b <- b[!is.na(ein) & nzchar(sq(org_name_join))]
b[, nk := nkey(org_name_join)][, rcity := norm_city(org_addr_city)]
b <- b[nzchar(nk)]
say("reference rows: %s", format(nrow(b), big.mark = ","))

## ---- does the CHOSEN ein have any row in the filed city? --------------------
setkey(b, ein)
chosen_city_ok <- function(ein, qcity) {
  r <- b[.(ein), rcity, nomatch = 0L]
  length(r) > 0L && qcity %in% r
}
# vectorised: join the chosen EIN's cities to the query
cc <- b[, .(ein, rcity)]
setkey(cc, ein, rcity)
a[, chosen_ok := !is.na(cc[.(ein, qcity), which = TRUE][1]), by = seq_len(nrow(a))]

## ---- does some OTHER ein have the same name in the filed city? --------------
nn <- b[, .(nk, rcity, ein)]
setkey(nn, nk, rcity)
a[, rival := {
  r <- nn[.(nk, qcity), nomatch = 0L]
  if (!nrow(r)) NA_character_ else {
    o <- unique(r$ein[r$ein != ein])
    if (!length(o)) NA_character_ else o[1]
  }
}, by = seq_len(nrow(a))]

a[, risk := !chosen_ok & !is.na(rival)]
hr()
say("THE PLAYWORKS SIGNATURE IN THE AGREEMENT CELL")
hr()
say("  chosen EIN has a row in the filed city        : %s (%.0f%%)",
    format(sum(a$chosen_ok), big.mark = ","), 100 * mean(a$chosen_ok))
say("  chosen EIN does NOT, and no same-name rival   : %s",
    format(sum(!a$chosen_ok & is.na(a$rival)), big.mark = ","))
say("  chosen EIN does NOT, and a RIVAL does  [RISK] : %s (%.1f%% of the cell)",
    format(sum(a$risk), big.mark = ","), 100 * mean(a$risk))
hr()
r <- a[risk == TRUE]
if (nrow(r)) {
  setorder(r, recip_name)
  say("examples (filed -> chosen EIN, vs a same-name EIN in the filed city):")
  n <- min(20L, nrow(r))
  for (i in seq_len(n))
    say("  %-9s %-32s %-16s chosen %s  rival %s", r$id[i],
        substr(r$recip_name[i], 1, 32), substr(r$recip_city[i], 1, 16),
        r$ein[i], r$rival[i])
}
fwrite(a[, .(id, recip_name, recip_city, recip_state, ein, chosen_ok, rival, risk)],
       file.path(PF, "data-dev", "AGREEMENT-RISK-SCAN.csv"))
hr()
say("wrote data-dev/AGREEMENT-RISK-SCAN.csv")
say("")
say("A hit is not a proven error -- the filed city can be a branch, a lockbox or")
say("a payment address. It is a case where name and place disagree and the")
say("pipeline followed the name, which is exactly what went wrong on PLAYWORKS.")
