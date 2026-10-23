#!/usr/bin/env Rscript
# ============================================================================
# Is persistence actually an untapped lever, or does dedup already have it?
#
# The claim I made from the 47.6% repeat rate was that a grantee the funder
# named in an earlier year "has an identity the cascade may already have
# resolved, so the match can be propagated instead of re-scored."
#
# The second half of that is true and already true. Repeats were measured ON
# the dedup identity -- a repeat IS the same recipient_uid in a later year --
# and identities are global, matched once, with the answer applied to every
# row. So a propagation stage keyed on (filer, identity, year) would recompute
# something pf_dedup() and pf_propagate_matches() already do.
#
# This checks that before anything gets built, and then measures where the
# residual actually is: the SAME grantee written DIFFERENTLY by the same
# funder in different years, which becomes two identities and which global
# exact dedup cannot see.
#
# The targeted fix for that is filer-blocked FUZZY dedup. Blocking on the
# filer is cheap -- a funder's grantee list is hundreds of names, not 3.4M --
# and .pf_identity_key() already carries the guard that matters: corporate
# suffixes are stripped but AFFILIATE suffixes are retained, so "X" and
# "X FOUNDATION" are held apart by construction. That is exactly the trap that
# made within-filer propagation ~50% precise.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("-", 78))

M  <- readRDS(file.path(PF, "data-dev", "FILER-SAMPLE-MATCH.rds"))
gg <- as.data.table(M$grants)[in_scope == TRUE]

## ---- 1. is the repeat rate already absorbed by dedup? ----------------------
hr(); say("1. IS THE 47.6%% REPEAT RATE ALREADY HANDLED?")
fy <- unique(gg[, .(FILEREIN, recipient_uid, TAXYEAR, status)])
fy[, first_yr := min(TAXYEAR), by = .(FILEREIN, recipient_uid)]
fy[, is_repeat := TAXYEAR > first_yr]
say("filer-grantee-year rows : %s", format(nrow(fy), big.mark = ","))
say("  repeats               : %s (%.1f%%)",
    format(sum(fy$is_repeat), big.mark = ","), 100 * mean(fy$is_repeat))
# a repeat shares recipient_uid with an earlier year by construction, so the
# identity -- and therefore the match -- is already shared
chk <- fy[is_repeat == TRUE]
same <- chk[, .(n_status = uniqueN(status)), by = .(FILEREIN, recipient_uid)]
say("")
say("repeat pairs whose status DIFFERS across years: %d of %s",
    sum(same$n_status > 1), format(nrow(same), big.mark = ","))
say("  -> if this is 0, every repeat already carries the same answer and a")
say("     propagation stage keyed on it recovers exactly nothing.")

## ---- 2. where the residual is: different spellings, same funder ------------
hr(); say("2. THE RESIDUAL: ONE FUNDER, ONE GRANTEE, TWO SPELLINGS")
fi <- unique(gg[, .(FILEREIN, recipient_uid, recip_name, recip_street,
                    recip_city, recip_state, recip_zip5, status, ein)])
fi <- fi[!duplicated(paste(FILEREIN, recipient_uid))]
say("filer-identity pairs: %s across %s filers",
    format(nrow(fi), big.mark = ","), format(uniqueN(fi$FILEREIN), big.mark = ","))

# what pf_dedup's identity key does to these names, including the affiliate guard
q <- npmatch::np_normalize(npmatch::np_query(
  data.frame(.id = seq_len(nrow(fi)), name = fi$recip_name,
             street = fi$recip_street, city = fi$recip_city,
             state = fi$recip_state, zip5 = fi$recip_zip5,
             stringsAsFactors = FALSE),
  c(.id = ".id", name = "name", street = "street", city = "city",
    state = "state", zip5 = "zip5")))
fi[, ikey := pfmatch:::.pf_identity_key(q$name_full)]
fi[, aff  := pfmatch:::.pf_affiliate_tokens(q$name_full)]

# pairs within a filer that fuzzy dedup WOULD merge: same affiliate class,
# different identity key, high similarity
cand <- fi[nzchar(ikey)][, {
  if (.N < 2L) NULL else {
    dm <- stringdist::stringdistmatrix(ikey, ikey, method = "jw", p = 0.1)
    hit <- which(dm <= 0.08 & upper.tri(dm), arr.ind = TRUE)
    if (!nrow(hit)) NULL else
      list(a = .I[hit[, 1]], b = .I[hit[, 2]],
           sim = 1 - dm[hit], same_aff = aff[hit[, 1]] == aff[hit[, 2]],
           st_a = status[hit[, 1]], st_b = status[hit[, 2]],
           nm_a = recip_name[hit[, 1]], nm_b = recip_name[hit[, 2]])
  }
}, by = FILEREIN]
say("within-filer near-duplicate pairs at JW >= 0.92: %s", format(nrow(cand), big.mark = ","))
say("  with the SAME affiliate class (dedup would merge)  : %s",
    format(sum(cand$same_aff), big.mark = ","))
say("  with DIFFERENT affiliate class (the guard blocks)  : %s",
    format(sum(!cand$same_aff), big.mark = ","))

mergeable <- cand[same_aff == TRUE]
mixed <- mergeable[(st_a == "YES") != (st_b == "YES")]
say("")
say("of the mergeable pairs, those where exactly ONE side is YES: %s",
    format(nrow(mixed), big.mark = ","))
say("  -> these are the identities that would gain an answer")
say("")
say("what the affiliate guard is blocking (should be arm/operating pairs):")
blocked <- cand[same_aff == FALSE][order(-sim)]
if (nrow(blocked)) {
  s <- head(blocked, 10)
  for (i in seq_len(nrow(s)))
    message(sprintf("  %.3f  %-38s | %s", s$sim[i], substr(s$nm_a[i], 1, 38),
                    substr(s$nm_b[i], 1, 38)))
}
say("")
say("what it would merge (should be spelling variants of one body):")
if (nrow(mixed)) {
  set.seed(5)
  s <- mixed[sample(.N, min(12L, .N))]
  for (i in seq_len(nrow(s)))
    message(sprintf("  %.3f  [%-5s] %-34s | [%-5s] %s", s$sim[i], s$st_a[i],
                    substr(s$nm_a[i], 1, 34), s$st_b[i], substr(s$nm_b[i], 1, 34)))
}
fwrite(cand, file.path(PF, "data-dev", "FILER-FUZZY-CANDIDATES.csv"))
say("")
say("wrote data-dev/FILER-FUZZY-CANDIDATES.csv")
