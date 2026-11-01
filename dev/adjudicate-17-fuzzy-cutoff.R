#!/usr/bin/env Rscript
# ============================================================================
# adjudicate-17-fuzzy-cutoff.R -- the cutoff table, on npmatch's own name_key.
#
# The cutoff table in vignettes/outside-the-bmf.Rmd was first computed with an
# approximate normalizer written inline while the pass was being designed: a
# hand-rolled upcase / punctuation-strip / suffix-drop that stood in for
# npmatch::np_normalize() because the reference bundle was not loaded at the
# time. That is the wrong basis for a published default. np_normalize() drops a
# different suffix list, folds punctuation differently and emits name_key as
# the pass actually sees it, so a similarity computed off the approximation is
# not the similarity the cutoff is compared against. This recomputes all three
# columns against the real key.
#
# WHAT EACH COLUMN IS
#
#   recovered of the 33 the BMF holds -- of the 91 A-estimation NO cases, 33
#     had an EIN established by web search that was then confirmed present in
#     the reference. For each cutoff: in how many of those 33 does the fuzzy
#     pass OFFER that EIN as a candidate. Offering is the measure, not
#     clearing: the pass is a candidate generator and np_select / np_tier make
#     the decision, so an offer is what this function is responsible for.
#
#   false offers in the 57 it does not -- of the same 91, 57 were judged
#     NOT_LISTED: the recipient should not be in the BMF at all, so any
#     candidate the pass offers for them is a false offer by construction.
#
#   margin to the nearest personal name -- the cutoff minus the highest
#     similarity any individual's name reaches against the reference. This is
#     the number the default turns on, and it is measured with
#     skip_personal = FALSE on purpose: skip_personal is the mitigation, and
#     measuring the hazard through the mitigation would report zero.
#
# THE CAVEAT EVERY FIGURE INHERITS, stated because it is not small: ein_in_ref
# was established against the augmented BMF reference the 91 cases were
# adjudicated on (3.88M rows). This runs against the matchdb active-observed
# tier (6.67M rows), which is what the pipeline now uses by default. The two
# are different row sets, so an EIN counted as "in the reference" there may be
# absent here. The script checks each of the 33 against THIS reference and
# reports the overlap rather than assuming it.
#
# USAGE
#   Rscript dev/adjudicate-17-fuzzy-cutoff.R
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
DD <- file.path(PF, "data-dev")
suppressWarnings(suppressMessages(library(pfmatch)))
suppressWarnings(suppressMessages(library(stringdist)))

GRANTS  <- Sys.getenv("PF_FZ_GRANTS", "^efv2_1k_grants_.*\\.csv$")
CUTOFFS <- as.numeric(strsplit(Sys.getenv("PF_FZ_CUTOFFS", "0.95,0.90,0.85"), ",")[[1]])
REFBND  <- Sys.getenv("PF_FZ_REF", file.path(DD, "REF-FZ-BUNDLE.rds"))
OUT     <- file.path(DD, "ADJ-FUZZY-CUTOFF.rds")

say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() cat(strrep("=", 78), "\n")
nf  <- function(x) format(x, big.mark = ",")

hr(); say("FUZZY CUTOFF table on npmatch's own name_key"); hr()

## ---- 1. the 91 cases ------------------------------------------------------
v <- as.data.table(readRDS(file.path(DD, "ADJ-NO-SCORED.rds")))
a <- v[stratum == "A-estimation"]
stopifnot(nrow(a) == 91L)
hold  <- a[ein_in_ref %in% TRUE, .(grant_id, ein = pfmatch:::.pf_ein(ein))]
notin <- a[bmf_expectation %in% "NOT_LISTED", .(grant_id)]
say("%d cases; %d with an EIN the old reference held; %d judged NOT_LISTED",
    nrow(a), nrow(hold), nrow(notin))

## ---- 2. the query, through the real normalizer ----------------------------
# Built exactly as pf_fuzzy_recover() builds it -- np_query() then
# np_normalize() then the recovery keys -- so name_key here is byte-identical
# to the key the pass compares. Anything else and this script measures itself.
grants <- pf_recover_name_from_street(pf_read_grants(file.path(PF, "inputs"), pattern = GRANTS))
q_in <- grants[grants$in_scope, , drop = FALSE]
trunc <- if (!is.null(q_in$name_truncated)) q_in$name_truncated else NULL
# pf_add_recovery_keys() is documented but not exported, so it is qualified.
q <- pfmatch:::pf_add_recovery_keys(
  npmatch::np_normalize(npmatch::np_query(q_in, pf_map_grants())),
  only_truncated = trunc)
personal <- if (!is.null(q_in$looks_personal)) q_in$looks_personal else rep(FALSE, nrow(q_in))
keep <- as.character(q$.id) %in% a$grant_id
q91  <- q[keep, , drop = FALSE]
p91  <- personal[keep]
say("  %d of the 91 are in scope and normalized (%d flagged personal)",
    nrow(q91), sum(p91 %in% TRUE))

## ---- 3. the reference -----------------------------------------------------
say("loading %s ...", basename(REFBND))
ref <- readRDS(REFBND)
pf_check_reference(ref, "stop")
r <- ref$reference
say("  %s rows, normalizer %s", nf(nrow(r)), ref$normalizer)

# The caveat, measured rather than assumed.
in_here <- hold$ein %in% pfmatch:::.pf_ein(r$.ein)
say("\nof the %d EINs the OLD reference held, %d are also in THIS one",
    nrow(hold), sum(in_here))
if (any(!in_here))
  say("  absent here: %s", paste(hold$grant_id[!in_here], collapse = ", "))

## ---- 4. the three columns, at each cutoff ---------------------------------
rows <- list()
for (cut in CUTOFFS) {
  hr(); say("CUTOFF %.2f", cut); hr()
  blk <- pf_fuzzy_candidates(q91, r, cutoff = cut, personal = p91,
                             skip_personal = TRUE, verbose = TRUE)
  off <- data.table(grant_id = as.character(q91$.id[blk$.x]),
                    ein = pfmatch:::.pf_ein(r$.ein[blk$.y]),
                    sim = attr(blk, "sim"))
  j <- merge(hold[in_here], off, by = c("grant_id", "ein"))
  rec <- uniqueN(j$grant_id)
  fo  <- off[grant_id %in% notin$grant_id]
  say("\n  recovered: %d of %d", rec, sum(in_here))
  if (nrow(j)) print(j[order(-sim)], row.names = FALSE)
  say("\n  false offers: %d pair(s) over %d of the %d NOT_LISTED cases",
      nrow(fo), uniqueN(fo$grant_id), nrow(notin))
  if (nrow(fo)) {
    fo2 <- copy(fo)
    fo2[, `:=`(filed = q91$name_key[match(grant_id, as.character(q91$.id))],
               bmf   = r$name_key[match(ein, pfmatch:::.pf_ein(r$.ein))])]
    print(fo2[order(-sim)][1:min(10L, .N)], row.names = FALSE)
  }
  rows[[sprintf("%.2f", cut)]] <- data.table(
    cutoff = cut, recovered = rec, of = sum(in_here),
    false_offers = nrow(fo), false_cases = uniqueN(fo$grant_id),
    pairs = nrow(off))
}

## ---- 5. the personal-name hazard ------------------------------------------
# skip_personal = FALSE on purpose: see the header. The scan runs at a cutoff
# well below any candidate default so the top of the distribution is visible
# rather than clipped by the number being justified.
hr(); say("PERSONAL NAMES, scanned with skip_personal = FALSE"); hr()
if (!any(p91 %in% TRUE)) {
  say("no personal rows among the 91; no margin to report")
  top <- NA_real_
} else {
  qp <- q91[p91 %in% TRUE, , drop = FALSE]
  pb <- pf_fuzzy_candidates(qp, r, cutoff = 0.70, top_k = 3L,
                            skip_personal = FALSE, verbose = TRUE)
  if (!nrow(pb)) { say("nothing reaches 0.70"); top <- NA_real_ } else {
    pt <- data.table(filed = qp$name_key[pb$.x], bmf = r$name_key[pb$.y],
                     ein = pfmatch:::.pf_ein(r$.ein[pb$.y]), sim = attr(pb, "sim"))
    setorder(pt, -sim)
    print(pt[1:min(12L, .N)], row.names = FALSE)
    top <- pt$sim[1]
    say("\nhighest similarity any individual's name reaches: %.3f (%s -> %s)",
        top, pt$filed[1], pt$bmf[1])
  }
}

hr(); say("SUMMARY"); hr()
sm <- rbindlist(rows)
sm[, margin := round(cutoff - top, 3)]
print(sm, row.names = FALSE)
say("")
say("`margin` is the cutoff minus %.3f, the top personal-name similarity.", top)
say("A cutoff whose margin approaches zero is not separating organizations")
say("from individuals; it is separating them by luck.")
saveRDS(list(summary = sm, top_personal = top, in_here = sum(in_here)), OUT)
say("\nwrote %s", OUT)
hr()
