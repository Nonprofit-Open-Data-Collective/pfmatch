#!/usr/bin/env Rscript
# ============================================================================
# make-pf-variants.R -- build the bundled name/address variant corpus.
#
# Run from the package root, with data-dev/TRI-V2-MATCH.rds in place:
#   Rscript data-raw/make-pf-variants.R
#
# WHAT THIS IS. Every row is a PAIR of recipient renderings filed at the same
# street and ZIP, one of which the cascade resolved (YES) and one of which it
# did not (MAYBE). The pairs come from the 50,000-case triangulation run
# (dev/TRI-V2-BUILD.log, population cb3c78ff0f1a9546): 6,600 MAYBE identities,
# each paired with the best-scoring YES rendering at its address.
#
# WHY IT IS USEFUL. The pairs are, by construction, exactly the differences
# that SURVIVE normalization. pf_prepare_grants() collapses renderings that
# share a normalized name key and address into one identity, and np_normalize()
# has already absorbed leading THE, & -> AND, FDN -> FOUNDATION and the USPS
# street suffixes before any pass runs. So no pair here differs only in a way
# the normalizer already handles -- every pair is a live case that reached the
# comparator and split. That makes this a regression corpus for normalizer and
# pass changes: tighten the normalizer and specific documented pairs should
# move, and the ones recorded as already-closed should stay closed.
#
# WHAT IT IS NOT. It is NOT labelled ground truth. The triangulation verdicts
# are silver, confidence = low, and unadjudicated -- assigning the anchor's EIN
# to every other rendering at the address is the assumption under test, not a
# fact. `expected_same_org` is therefore TRUE only where the two names are the
# same string under a documented cosmetic transformation at an identical
# address, and NA -- not FALSE -- everywhere else. A pair whose names share no
# tokens may still be one organization (US OLYMPIC AND PARALYMPIC FOUNDATION /
# USOC) and a pair sharing a distinctive token may still be two (MARINE CORPS
# UNIVERSITY FOUNDATION / MARINE CORP SCHOLARSHIP FUND). Only adjudication
# settles those, and `label_basis` says which rows are waiting for it.
#
# PRIVACY. Pairs where either side is a person rather than an organization are
# dropped: a blank organization-name line, or .pf_looks_personal() firing. The
# filings are public, but a package should not ship individuals' names and home
# addresses as test data.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(library(digest)))
setDTthreads(0)
suppressWarnings(suppressMessages(devtools::load_all(".", quiet = TRUE)))
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("=", 78))
nf  <- function(x) format(x, big.mark = ",")
sq  <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; x }
nrm <- function(x) trimws(gsub(" +", " ", gsub("[^A-Z0-9 ]", " ", toupper(sq(x)))))
e9  <- function(v) { v <- gsub("[^0-9]", "", as.character(v))
                     ifelse(nchar(v) == 9L, v, NA_character_) }
num <- function(x) suppressWarnings(as.numeric(x))
# max(na.rm = TRUE) on an all-NA score warns and returns -Inf for every identity
# the cascade never scored; 417 of them in a 50k slice. Return NA instead.
smax <- function(x) { x <- num(x); x <- x[is.finite(x)]; if (length(x)) max(x) else NA_real_ }

SRC <- "data-dev/TRI-V2-MATCH.rds"
if (!file.exists(SRC))
  stop("need ", SRC, " -- produced by dev/build-triangulation-v2.R", call. = FALSE)
hr(); say("make-pf-variants  %s", format(Sys.time())); hr()
gg <- as.data.table(readRDS(SRC)$grants)

## ---- 1. eligible groups, same definition as the build ----------------------
a <- gg[!is.na(key) & nzchar(key) & !is.na(status)]
a[, nm_key := nrm(recip_name)]
a[, ein9 := e9(ein)]
grp <- a[, .(n_names = uniqueN(nm_key)), by = key][n_names >= 2L]
a <- merge(a, grp, by = "key")
a[, group_id := paste0("TG2-", substr(vapply(key, function(s)
    digest::digest(s, algo = "xxhash64"), character(1)), 1, 12))]
anch <- a[, {
  y <- status == "YES" & !is.na(ein9)
  .(n_yes = sum(y), n_other = sum(status != "YES"), yes_eins = uniqueN(ein9[y]),
    anchor = if (sum(y)) ein9[y][1] else NA_character_)
}, by = group_id]
elig <- anch[n_yes >= 1L & n_other >= 1L & yes_eins == 1L]
a <- merge(a, elig[, .(group_id, anchor)], by = "group_id")
say("eligible groups: %s", nf(nrow(elig)))

## ---- 2. one row per identity ------------------------------------------------
id <- a[, .(name = recip_name[1], name_alt = recip_name_alt[1],
            org1 = PF_15_G_PAID_RECIP_NAME_ORG_L1[1],
            street = PF_15_G_PAID_RECIP_ADDR_L1[1],
            unit = PF_15_G_PAID_RECIP_ADDR_L2[1],
            city = PF_15_G_PAID_RECIP_ADDR_CITY[1],
            state = PF_15_G_PAID_RECIP_ADDR_STATE[1],
            zip = PF_15_G_PAID_RECIP_ADDR_ZIP[1],
            personal = isTRUE(looks_personal[1]),
            n_names = n_names[1], bmf = bmf_name[1], ein9 = ein9[1],
            score = smax(score), status = status[1],
            pass = match_pass[1], grants = .N),
        by = .(group_id, key, anchor, recipient_uid)]
id[!is.finite(score), score := NA_real_]
# organizations only -- see PRIVACY above
id[, is_org := nzchar(trimws(sq(org1))) & !personal]

yes <- id[status == "YES" & !is.na(ein9) & is_org][order(group_id, -score)]
yes <- yes[, .SD[1], by = group_id]
myb <- id[status == "MAYBE" & is_org & (is.na(ein9) | ein9 != anchor)]
say("anchors: %s   MAYBE identities: %s  (organizations only)",
    nf(nrow(yes)), nf(nrow(myb)))

p <- merge(myb, yes[, .(group_id, a_name = name, a_alt = name_alt,
                        a_street = street, a_unit = unit, a_city = city,
                        a_state = state, a_zip = zip, a_bmf = bmf,
                        a_ein = ein9, a_score = score, a_pass = pass,
                        a_grants = grants)],
           by = "group_id")
setnames(p, c("name", "name_alt", "street", "unit", "city", "state", "zip",
              "ein9", "score", "pass", "grants"),
            c("b_name", "b_alt", "b_street", "b_unit", "b_city", "b_state",
              "b_zip", "b_ein", "b_score", "b_pass", "b_grants"))
say("pairs: %s in %s groups", nf(nrow(p)), nf(uniqueN(p$group_id)))

## ---- 3. the real normalized keys, from npmatch ------------------------------
# Computed with np_normalize() rather than re-implemented here, so the fixture
# records what the production normalizer actually does. np_normalize_signature()
# is stored as an attribute: if the normalizer changes, the keys in this
# fixture are stale and the signature says so.
keys <- function(name, alt, street, unit, city, state, zip) {
  z <- gsub("[^0-9]", "", sq(zip))
  g <- data.frame(grant_id = seq_along(name), recip_name = sq(name),
                  recip_name_alt = alt, recip_street = sq(street),
                  recip_unit = unit, recip_city = sq(city),
                  recip_state = sq(state),
                  recip_zip5 = ifelse(nchar(z) >= 5L, substr(z, 1, 5), NA),
                  stringsAsFactors = FALSE)
  q <- as.data.frame(npmatch::np_normalize(npmatch::np_query(g, pf_map_grants())))
  q[, c("name_key", "dba_key", "street_key", "is_po_box", "state_abb", "zip5")]
}
ka <- keys(p$a_name, p$a_alt, p$a_street, p$a_unit, p$a_city, p$a_state, p$a_zip)
kb <- keys(p$b_name, p$b_alt, p$b_street, p$b_unit, p$b_city, p$b_state, p$b_zip)
p[, `:=`(a_name_key = ka$name_key, a_dba_key = ka$dba_key,
         a_street_key = ka$street_key, a_zip5 = ka$zip5, a_state_abb = ka$state_abb,
         b_name_key = kb$name_key, b_dba_key = kb$dba_key,
         b_street_key = kb$street_key, b_zip5 = kb$zip5, b_state_abb = kb$state_abb)]

## ---- 4. classify ------------------------------------------------------------
ABB <- c(ST="SAINT", STE="SAINT", MT="MOUNT", UNIV="UNIVERSITY", ASSN="ASSOCIATION",
  ASSOC="ASSOCIATION", SOC="SOCIETY", NATL="NATIONAL", INTL="INTERNATIONAL",
  DEPT="DEPARTMENT", CTR="CENTER", CTRS="CENTERS", HOSP="HOSPITAL", CH="CHURCH",
  FDN="FOUNDATION", FND="FOUNDATION", FOUND="FOUNDATION", AMER="AMERICAN",
  COMM="COMMUNITY", SCH="SCHOOL", ACAD="ACADEMY", SVCS="SERVICES", SVC="SERVICE",
  MINS="MINISTRIES", MIN="MINISTRY", EPIS="EPISCOPAL", PRESB="PRESBYTERIAN",
  CATH="CATHOLIC", LUTH="LUTHERAN", METH="METHODIST")
SUF <- c("INC","INCORPORATED","CORP","CORPORATION","COMPANY","LLC","LTD","PC",
         "PA","LP","USA","US")
GEN <- c("THE","OF","AND","FOR","A","AN","IN","AT","TO","ON","INC","INCORPORATED",
  "FOUNDATION","FDN","FUND","TRUST","CHARITABLE","CHARITIES","CHARITY","CENTER",
  "CENTRE","CENTERS","SOCIETY","ASSOCIATION","ASSOC","ASSN","COMMUNITY","AMERICAN",
  "AMERICA","NATIONAL","INTERNATIONAL","USA","US","UNITED","STATES","CHURCH",
  "SCHOOL","SCHOOLS","UNIVERSITY","COLLEGE","HOSPITAL","CORP","CORPORATION",
  "COMPANY","CO","LLC","LTD","SERVICES","SERVICE","MINISTRIES","MINISTRY",
  "INSTITUTE","COUNCIL","PROJECT","PROGRAM","PROGRAMS","GROUP","ORGANIZATION",
  "FRIENDS","NEW","GREATER","COUNTY","CITY","STATE","REGIONAL","AREA",
  "ALLIANCE","NETWORK","COALITION","PARTNERSHIP","CLUB","CLUBS")
tk <- function(x) strsplit(x, " ", fixed = TRUE)
mapt <- function(x, f) vapply(tk(x), function(v) { v <- v[nzchar(v)]; f(v) }, character(1))
expand   <- function(x) mapt(x, function(v) { i <- match(v, names(ABB))
                        v[!is.na(i)] <- ABB[i[!is.na(i)]]; paste(v, collapse = " ") })
drop_suf <- function(x) mapt(x, function(v) {
                        while (length(v) > 1L && v[length(v)] %in% SUF) v <- v[-length(v)]
                        paste(v, collapse = " ") })
inits    <- function(x) mapt(x, function(v) paste(substr(setdiff(v, GEN), 1, 1), collapse = ""))
sqz <- function(x) gsub(" ", "", x)
A <- nrm(p$a_name); B <- nrm(p$b_name)

p[, name_lev := mapply(function(x, y) as.integer(adist(x, y)), A, B, USE.NAMES = FALSE)]
p[, name_jaccard := round(mapply(function(x, y) {
    x <- unique(x[nzchar(x)]); y <- unique(y[nzchar(y)])
    if (!length(x) || !length(y)) 0 else length(intersect(x, y)) / length(union(x, y))
  }, tk(A), tk(B), USE.NAMES = FALSE), 3)]
p[, shared_distinctive := mapply(function(x, y) {
    x <- setdiff(unique(x[nzchar(x)]), GEN); y <- setdiff(unique(y[nzchar(y)]), GEN)
    length(intersect(x, y))
  }, tk(A), tk(B), USE.NAMES = FALSE)]
subset_ <- mapply(function(x, y) {
    x <- unique(x[nzchar(x)]); y <- unique(y[nzchar(y)]); all(x %in% y) || all(y %in% x)
  }, tk(A), tk(B), USE.NAMES = FALSE)
p[, is_initialism := (nchar(sqz(B)) >= 2L & sqz(B) == inits(A)) |
                     (nchar(sqz(A)) >= 2L & sqz(A) == inits(B))]

cls <- rep("different name", nrow(p))
cls[p$name_jaccard >= 0.5 & !subset_]                 <- "partial token overlap"
cls[p$name_lev <= 2L & p$name_lev > 0L]               <- "typo"
cls[subset_]                                          <- "token added or dropped"
cls[(startsWith(A, B) | startsWith(B, A)) & pmin(nchar(A), nchar(B)) >= 10L] <- "truncation"
cls[sqz(expand(A)) == sqz(expand(B))]                 <- "abbreviation"
# Test the ampersand on the RAW names, not on A/B: nrm() has already turned &
# into a space, so comparing normalized strings can never detect it and the
# class was unreachable -- those pairs fell into "token added or dropped",
# which is true of the token stream but hides the actual cause.
amp_raw <- function(x) sqz(nrm(gsub("&", " AND ", toupper(sq(x)))))
cls[amp_raw(p$a_name) == amp_raw(p$b_name)]           <- "and vs ampersand"
cls[sqz(drop_suf(A)) == sqz(drop_suf(B))]             <- "corporate suffix"
cls[sqz(sub("^THE ", "", A)) == sqz(sub("^THE ", "", B))] <- "leading THE"
cls[sqz(A) == sqz(B)]                                 <- "spacing or punctuation"
cls[A == B]                                           <- "identical normalized"
p[, name_class := cls]

z4 <- function(x) { d <- gsub("[^0-9]", "", sq(x)); ifelse(nchar(d) >= 9L, substr(d, 6, 9), "") }
p[, `:=`(street_differs = nrm(a_street) != nrm(b_street),
         unit_differs   = nrm(a_unit)   != nrm(b_unit),
         city_differs   = nrm(a_city)   != nrm(b_city),
         state_differs  = sq(a_state_abb) != sq(b_state_abb),
         zip4_differs   = z4(a_zip)     != z4(b_zip))]
p[, addr_class := fifelse(unit_differs, "unit differs",
                  fifelse(city_differs, "city differs",
                  fifelse(street_differs, "street spelling",
                  fifelse(zip4_differs, "zip4 differs",
                  fifelse(state_differs, "state differs", "identical")))))]
# what the cascade can actually see: it blocks on name_key/dba_key x zip5/state
# and never reads street, unit or city (R/match.R, pf_staged_passes()).
p[, name_key_equal   := sq(a_name_key) == sq(b_name_key) & nzchar(sq(a_name_key))]
p[, street_key_equal := sq(a_street_key) == sq(b_street_key)]
p[, zip5_equal       := sq(a_zip5) == sq(b_zip5)]
p[, blocking_intact  := zip5_equal & !state_differs]
# Where name_key agrees the two renderings still reached the comparator
# separately, because pf_dedup() keys identity on name_full (R/dedup.R:114) --
# deliberately, so that an organization and its affiliate are not merged by a
# name_key that has already dropped the affiliate suffix. The consequence is a
# seam: the cascade blocks stage A1 on name_key + zip5, so two identities that
# share both can still be tiered differently.
#
# `b_outscores_a` is the flag that matters for reading the silver labels.
# Triangulation writes the anchor's EIN onto the candidate as correct_ein. When
# the candidate's own match is BETTER than the anchor's -- a higher score, or an
# exact name+ZIP5 hit against a token-blocked one -- that assignment is running
# against the system's own evidence, and the pair should be read before it is
# trusted. BETHEL COLLEGE (0.960, A3-name-dba) against BETHEL UNIVERSITY
# (0.980, A1-name-zip5) is the shape: a renamed organization, where the
# candidate found the better row.
STRENGTH <- c(`A1-name-zip5` = 6L, `A2-name-state` = 5L, `A3-name-dba` = 4L,
              `A4-dba-name` = 4L, `A5-dba-dba` = 4L, `C1-name-any` = 3L,
              `C2-dba-any` = 3L, `B1-token-state` = 2L, `B2-token-concat` = 2L,
              `C3-token-any` = 1L)
rank_of <- function(x) { r <- STRENGTH[as.character(x)]; as.integer(ifelse(is.na(r), 0L, r)) }
p[, `:=`(a_pass_rank = rank_of(a_pass), b_pass_rank = rank_of(b_pass))]
p[, b_outscores_a := !is.na(b_score) & !is.na(a_score) &
    (b_score > a_score | b_pass_rank > a_pass_rank)]

## ---- 5. label, conservatively ----------------------------------------------
COSMETIC <- c("identical normalized", "spacing or punctuation", "leading THE",
              "corporate suffix", "and vs ampersand", "abbreviation")
p[, expected_same_org := NA]
p[, label_basis := "unadjudicated"]
p[name_class %in% COSMETIC & addr_class == "identical",
  `:=`(expected_same_org = TRUE,
       label_basis = "cosmetic name variant at an identical address")]
p[, label_confidence := fifelse(is.na(expected_same_org), NA_character_, "high")]
say("labelled TRUE: %s   left NA for adjudication: %s",
    nf(sum(!is.na(p$expected_same_org))), nf(sum(is.na(p$expected_same_org))))

## ---- 6. a curated, balanced exemplar subset ---------------------------------
# Deterministic: within each name_class x addr_class cell, the pairs with the
# highest anchor score first, then alphabetical. No sampling, so the subset is
# stable across rebuilds and a diff is readable.
setorder(p, name_class, addr_class, -a_score, b_name)
p[, curated := seq_len(.N) <= 6L, by = .(name_class, addr_class)]
say("curated exemplars: %s across %s class combinations",
    nf(sum(p$curated)), nf(uniqueN(p[, paste(name_class, addr_class)])))

## ---- 7. assemble ------------------------------------------------------------
p[, pair_id := paste0("PV-", substr(vapply(paste(group_id, b_name),
    function(s) digest::digest(s, algo = "xxhash64"), character(1)), 1, 12))]
pf_variants <- as.data.frame(p[, .(
  pair_id, group_id, addr_key = key, curated,
  a_name, a_name_key, a_dba_key, a_street, a_street_key, a_unit, a_city,
  a_state = a_state_abb, a_zip, a_zip5, a_ein, a_bmf, a_score, a_pass, a_grants,
  b_name, b_name_key, b_dba_key, b_street, b_street_key, b_unit, b_city,
  b_state = b_state_abb, b_zip, b_zip5, b_ein, b_score, b_pass, b_grants,
  a_status = "YES", b_status = "MAYBE",
  name_class, addr_class, name_lev, name_jaccard, shared_distinctive,
  is_initialism,
  # raw-vs-normalized: `*_differs` is the filed text, `*_key_equal` is what the
  # normalizer made of it. A pair with street_differs & street_key_equal is one
  # the normalizer already reconciles; the two together are the address test.
  street_differs, unit_differs, city_differs, zip4_differs, state_differs,
  name_key_equal, street_key_equal, zip5_equal, blocking_intact,
  a_pass_rank, b_pass_rank, b_outscores_a, n_names_at_addr = n_names,
  expected_same_org, label_basis, label_confidence)][
    order(name_class, addr_class, pair_id)])

attr(pf_variants, "population")  <- "cb3c78ff0f1a9546"
attr(pf_variants, "source_run")  <- "dev/build-triangulation-v2.R, 2026-10-25"
attr(pf_variants, "normalizer")  <- tryCatch(npmatch::np_normalize_signature(),
                                             error = function(e) NA_character_)
attr(pf_variants, "built")       <- as.character(Sys.Date())

hr(); say("pf_variants: %s rows, %s columns", nf(nrow(pf_variants)), ncol(pf_variants))
print(as.data.table(pf_variants)[, .(pairs = .N), by = name_class][order(-pairs)],
      row.names = FALSE)
save(pf_variants, file = "data/pf_variants.rda", compress = "xz")
say("wrote data/pf_variants.rda  (%.1f KB)", file.size("data/pf_variants.rda") / 1024)
hr(); say("done  %s", format(Sys.time()))
