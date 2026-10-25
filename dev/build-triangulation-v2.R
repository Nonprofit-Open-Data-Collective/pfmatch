#!/usr/bin/env Rscript
# ============================================================================
# build-triangulation-v2.R -- the 50,000-case address-triangulation set, built
# corpus-first from the deduplicated v2 population.
#
# WHAT THE PILOT SETTLED (dev/TRI-PILOT-YIELD.csv, 3,600 groups stratified
# across six size buckets). Cases per IDENTITY -- identities being what the
# matcher charges for -- rises monotonically with group size:
#
#     size      elig rate   cases/group   cases/identity
#     2             28.0%          0.24            0.118
#     3-4           29.0%          0.36            0.159
#     5-9           35.2%          0.74            0.274
#     10-24         35.7%          1.54            0.398
#     25-99         42.5%          4.66            0.669
#     100+          46.0%         15.90            1.283
#
# A group of 100+ grants is ELEVEN TIMES cheaper per case than a group of two.
# That is the opposite of the intuition this was sized on -- small groups look
# cheap per group and are the worst buy per case, because a two-rendering group
# only pays out if exactly one of the two cleared.
#
# WHY NOT JUST TAKE THE BIG ONES. Buying only from 100+ would deliver 50,000
# cases in under two hours, but the set would be conditioned on the most
# heavily funded recipients and could not be read as evidence about the
# comparator's real failure rate -- and pf_consistency() built on it would be
# measuring a biased slice. A proportional draw across the whole universe costs
# a few more hours and stays representative, so that is what this does.
#
# Expected, from the pilot's per-bucket rates weighted by the universe:
#     1.51 cases per group, 3.48 index-names per group
# and the index overstates identities by ~1.43x, because pf_prepare() collapses
# renderings more aggressively than the index's uppercase-alphanumeric key.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(library(digest)))
setDTthreads(0)
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("=", 88))
sq  <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; x }
e9  <- function(v) { v <- gsub("[^0-9]", "", as.character(v))
                     ifelse(nchar(v) == 9L, v, NA_character_) }

source(file.path(PF, "dev", "grants-path.R"))
V2     <- pf_grants_v2()
CHUNK  <- 2000000L
TARGET <- as.integer(Sys.getenv("PF_TRI_TARGET", "50000"))
SEED   <- 20261024L
hr(); say("build-triangulation-v2   target %s cases   %s",
          format(TARGET, big.mark = ","), format(Sys.time())); hr()

## ---- 1. the eligible universe, same filters as the plan --------------------
idx <- as.data.table(readRDS(file.path(PF, "data-dev", "GROUP-INDEX.rds")))
idx <- idx[n_names > 1L]
idx[, street := sub("[|].*$", "", key)]
idx <- idx[!grepl("^P?O?BOX|^POST", street)]   # a shared box is not a shared org
idx <- idx[n_names < 25L]                      # fiscal sponsors, DAF custodians
br  <- c(2, 3, 5, 10, 25, 100, Inf)
lab <- c("2", "3-4", "5-9", "10-24", "25-99", "100+")
idx[, bucket := cut(n_grants, breaks = br, right = FALSE, labels = lab)]
say("eligible universe: %s groups, %s grant rows",
    format(nrow(idx), big.mark = ","), format(sum(idx$n_grants), big.mark = ","))

## ---- 2. size a proportional draw -------------------------------------------
y <- fread(file.path(PF, "data-dev", "TRI-PILOT-YIELD.csv"))
rate <- merge(idx[, .(groups = .N), by = bucket], y[, .(bucket, per_group)],
              by = "bucket")
exp_per_group <- sum(rate$groups * rate$per_group) / sum(rate$groups)
# draw 10% over target: the per-bucket rates carry sampling error and the
# large-group bucket is heavy-tailed, so undershooting costs a second run.
n_draw <- ceiling(TARGET * 1.10 / exp_per_group)
say("expected %.2f cases/group over the universe -> drawing %s groups",
    exp_per_group, format(n_draw, big.mark = ","))
set.seed(SEED)
sel <- idx[sample(.N, min(.N, n_draw))]
say("drawn: %s groups, %s grant rows, %s index-names (~%s identities)",
    format(nrow(sel), big.mark = ","), format(sum(sel$n_grants), big.mark = ","),
    format(sum(sel$n_names), big.mark = ","),
    format(round(sum(sel$n_names) / 1.43), big.mark = ","))
saveRDS(sel, file.path(PF, "data-dev", "TRI-V2-GROUPS-SELECTED.rds"))
want <- sel$key

## ---- 3. extract -------------------------------------------------------------
hdr <- names(fread(V2, nrows = 0L))
hit <- list(); i <- 0L; seen <- 0L
repeat {
  ch <- fread(V2, colClasses = "character", na.strings = NULL,
              skip = 1L + i * CHUNK, nrows = CHUNK, header = FALSE,
              col.names = hdr, showProgress = FALSE)
  nn <- nrow(ch); if (!nn) break
  seen <- seen + nn; i <- i + 1L
  ch[, key := paste(gsub("[^A-Z0-9]", "", toupper(PF_15_G_PAID_RECIP_ADDR_L1)),
                    substr(gsub("[^0-9]", "", PF_15_G_PAID_RECIP_ADDR_ZIP), 1, 5),
                    sep = "|")]
  h <- ch[key %chin% want]
  if (nrow(h)) hit[[length(hit) + 1L]] <- h
  say("  chunk %d  %s scanned, %s kept", i, format(seen, big.mark = ","),
      format(sum(vapply(hit, nrow, 0L)), big.mark = ","))
  rm(ch); invisible(gc())
  if (nn < CHUNK) break
}
G <- rbindlist(hit); rm(hit); invisible(gc())
say("extracted %s grant rows for %s keys",
    format(nrow(G), big.mark = ","), format(uniqueN(G$key), big.mark = ","))
keyv <- G$key

## ---- 4. prepare and match ---------------------------------------------------
prep <- pf_prepare(as.data.frame(G[, !"key"]), verbose = FALSE)
say("identities to match: %s", format(nrow(prep$recipients), big.mark = ","))
ref <- readRDS(file.path(PF, "data-dev", "REF-augmented.rds"))
say("reference: REF-augmented.rds, %s rows", format(nrow(ref$reference), big.mark = ","))
t0 <- proc.time()[["elapsed"]]
st <- pf_run_batches(prep$recipients, ref,
                     dir = file.path(PF, "data-dev", "ckpt-tri-v2"),
                     passes = c(pf_staged_passes("lean", concat = TRUE),
                                pf_recovery_passes(state = TRUE)),
                     recover = TRUE, batch_size = 25000L, resume = TRUE,
                     verbose = TRUE)
el <- proc.time()[["elapsed"]] - t0
say("matched in %.1f min (%.3f s/identity)", el / 60, el / nrow(prep$recipients))

gg <- as.data.table(pf_propagate_matches(prep$grants, st))
gg[, key := keyv]
POP <- pf_population_id(gg)
say("population id: %s", POP)
saveRDS(list(status = st, grants = gg),
        file.path(PF, "data-dev", "TRI-V2-MATCH.rds"), compress = FALSE)

## ---- 5. the artifacts, same definitions as the original ---------------------
a <- gg[!is.na(key) & nzchar(key)]
a[, nm_key := gsub(" +", " ", trimws(toupper(gsub("[^A-Z0-9 ]", " ", sq(recip_name)))))]
a[, ein9 := e9(ein)]
# re-derive the group from what was actually matched: pf_prepare() may drop
# rows, so a key's rendering count here can differ from the index's
grp <- a[, .(n_rows = .N, n_names = uniqueN(nm_key)), by = key][n_names >= 2L]
a <- merge(a, grp[, .(key)], by = "key")
a[, group_id := paste0("TG2-", substr(vapply(key, function(s)
    digest::digest(s, algo = "xxhash64"), character(1)), 1, 12))]
say("groups with >=2 renderings after matching: %s",
    format(uniqueN(a$group_id), big.mark = ","))

fwrite(a[, .(grant_id, group_id, population = POP, recip_name, recip_city,
             recip_state, recip_zip5)],
       file.path(PF, "data-dev", "TRIANGULATION-V2-GROUPS.csv"))
say("wrote TRIANGULATION-V2-GROUPS.csv  (no labels: grouping only)")

anch <- a[, {
  yes <- status == "YES" & !is.na(ein9)
  .(n_yes = sum(yes), n_other = sum(status != "YES"),
    yes_eins = uniqueN(ein9[yes]),
    anchor = if (sum(yes)) ein9[yes][1] else NA_character_,
    anchor_name = if (sum(yes)) sq(bmf_name[yes])[1] else "",
    anchor_score = if (sum(yes)) suppressWarnings(max(as.numeric(score[yes]), na.rm = TRUE)) else NA_real_)
}, by = group_id]
elig <- anch[n_yes >= 1L & n_other >= 1L & yes_eins == 1L]
q <- merge(a[status != "YES"], elig, by = "group_id")
q <- q[is.na(ein9) | ein9 != anchor]
q <- merge(q, a[, .(n_names_at_addr = uniqueN(nm_key)), by = group_id], by = "group_id")
q[, flag_person := grepl("EDUCATIONAL GRANT|SCHOLARSHIP", toupper(sq(recip_name))) |
                   (!is.na(looks_personal) & looks_personal %in% TRUE)]
q[, flag_shared := n_names_at_addr >= 4L]
q[, flag_weak_anchor := is.na(anchor_score) | anchor_score < 0.90]
q[, flag_single_anchor := n_yes < 2L]
q[, n_flags := flag_person + flag_shared + flag_weak_anchor + flag_single_anchor]

hr(); say("INFORMATIVE CASES: %s", format(nrow(q), big.mark = ","))
say("  against a target of %s  (%.0f%%)", format(TARGET, big.mark = ","),
    100 * nrow(q) / TARGET)
say("  eligible groups      %s of %s  (%.1f%%)", format(nrow(elig), big.mark = ","),
    format(uniqueN(a$group_id), big.mark = ","),
    100 * nrow(elig) / uniqueN(a$group_id))
print(q[, .(cases = .N), by = n_flags][order(n_flags)], row.names = FALSE)
say("  0 flags is the cleanest slice; review that first.")
say("")
say("  by group size:")
qb <- merge(q[, .(cases = .N), by = group_id],
            unique(a[, .(group_id, key)]), by = "group_id")
qb <- merge(qb, idx[, .(key, bucket)], by = "key")
print(qb[, .(groups = .N, cases = sum(cases)), by = bucket][order(bucket)], row.names = FALSE)

qcols <- c("group_id", "grant_id", "recip_name", "recip_street", "recip_city",
           "n_names_at_addr", "recip_state", "recip_zip5", "status", "ein9",
           "score", "anchor", "anchor_name", "anchor_score", "n_yes", "n_other",
           "flag_person", "flag_shared", "flag_weak_anchor",
           "flag_single_anchor", "n_flags")
qout <- q[, intersect(qcols, names(q)), with = FALSE]
qout[, c("verdict", "note") := ""]
setorder(qout, n_flags, group_id)
fwrite(qout, file.path(PF, "data-dev", "TRIANGULATION-V2-SAMPLE.csv"))
say("wrote TRIANGULATION-V2-SAMPLE.csv  (adjudication QUEUE, %s cases)",
    format(nrow(qout), big.mark = ","))

tri <- data.table(
  truth_id = paste0("TRI2-", substr(vapply(paste(q$group_id, q$grant_id),
                     function(s) digest::digest(s, algo = "xxhash64"),
                     character(1)), 1, 12)),
  grant_id = q$grant_id, population = POP, object_id = NA_character_,
  recip_name = q$recip_name, verdict = "ORG_FOUND",
  correct_ein = q$anchor, wrong_ein = NA_character_,
  basis = "triangulated", confidence = "low",
  source = "TRIANGULATION-V2-SAMPLE.csv",
  note = sprintf("anchor %s (%s) from %d YES rendering(s) at the same street+zip; %d flag(s)",
                 q$anchor, substr(sq(q$anchor_name), 1, 40), q$n_yes, q$n_flags))
fwrite(tri, file.path(PF, "data-dev", "PF-TRUTH-V2-TRIANGULATED.csv"))
say("wrote PF-TRUTH-V2-TRIANGULATED.csv  (silver, confidence = low)")
hr(); say("done  %s", format(Sys.time()))
