#!/usr/bin/env Rscript
# ============================================================================
# run-triangulation-pilot.R -- measure the yield curve before committing to a
# multi-hour run.
#
# The question the grant file cannot answer: how many INFORMATIVE cases does a
# group produce? A case needs one rendering that cleared, another that did not,
# and disagreement between them, so it needs a match. The old sample yielded
# 0.66 cases per group, but on PARTIAL groups -- it only held renderings from
# the filers that happened to be sampled -- so that rate should not be assumed
# to transfer to complete corpus-wide groups.
#
# This matches a stratified pilot and reports cases per group AND cases per
# identity for each size bucket. Identities are what pf_run_batches() charges
# for, so cases-per-identity is the number that decides where to buy.
#
# Reference: REF-augmented.rds, the same one BASELINE-2026-10B's augmented arm
# uses, so group verdicts here are commensurable with the frozen baseline.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(library(digest)))
setDTthreads(0)
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("=", 86))
sq  <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; x }
e9  <- function(v) { v <- gsub("[^0-9]", "", as.character(v))
                     ifelse(nchar(v) == 9L, v, NA_character_) }

V2    <- "C:/Users/jlecy/Documents/grants/PF-GRANTS-PAID-V2-2009-2025.csv"
CHUNK <- 2000000L
hr(); say("run-triangulation-pilot  %s", format(Sys.time())); hr()

pilot <- as.data.table(readRDS(file.path(PF, "data-dev", "TRI-PILOT-GROUPS.rds")))
say("pilot groups %s | identities expected %s",
    format(nrow(pilot), big.mark = ","), format(sum(pilot$n_names), big.mark = ","))
want <- pilot$key

## ---- 1. pull the grants for those address keys -----------------------------
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

## ---- 2. prepare and match ---------------------------------------------------
kmap <- G[, .(grant_row = .I, key)]
prep <- pf_prepare(as.data.frame(G[, !"key"]), verbose = FALSE)
say("identities to match: %s", format(nrow(prep$recipients), big.mark = ","))

ref <- readRDS(file.path(PF, "data-dev", "REF-augmented.rds"))
say("reference: REF-augmented.rds, %s rows", format(nrow(ref$reference), big.mark = ","))
t0 <- proc.time()[["elapsed"]]
st <- pf_run_batches(prep$recipients, ref,
                     dir = file.path(PF, "data-dev", "ckpt-tri-pilot"),
                     passes = c(pf_staged_passes("lean", concat = TRUE),
                                pf_recovery_passes(state = TRUE)),
                     recover = TRUE, batch_size = 25000L, resume = FALSE,
                     verbose = TRUE)
el <- proc.time()[["elapsed"]] - t0
say("matched in %.1f min  (%.3f s/identity)", el / 60, el / nrow(prep$recipients))

gg <- as.data.table(pf_propagate_matches(prep$grants, st))
gg[, key := kmap$key[match(seq_len(nrow(gg)), kmap$grant_row)]]
saveRDS(list(status = st, grants = gg),
        file.path(PF, "data-dev", "TRI-PILOT-MATCH.rds"), compress = FALSE)

## ---- 3. the yield curve ------------------------------------------------------
# Same definition as dev/build-triangulation-sample.R, deliberately: a group is
# eligible when at least one rendering cleared, at least one did not, and the
# cleared ones agree on a single EIN; a non-YES row is informative when it did
# not already pick that anchor.
a <- gg[!is.na(key) & nzchar(key)]
a[, nm_key := gsub(" +", " ", trimws(toupper(gsub("[^A-Z0-9 ]", " ", sq(recip_name)))))]
a[, ein9 := e9(ein)]
a <- merge(a, pilot[, .(key, bucket, n_names_idx = n_names)], by = "key")

anch <- a[, {
  yes <- status == "YES" & !is.na(ein9)
  .(n_yes = sum(yes), n_other = sum(status != "YES"),
    yes_eins = uniqueN(ein9[yes]),
    anchor = if (sum(yes)) ein9[yes][1] else NA_character_)
}, by = .(key, bucket)]
elig <- anch[n_yes >= 1L & n_other >= 1L & yes_eins == 1L]
q <- merge(a[status != "YES"], elig[, .(key, anchor)], by = "key")
q <- q[is.na(ein9) | ein9 != anchor]

hr(); say("YIELD BY GROUP SIZE")
tot <- pilot[, .(groups = .N, identities = sum(n_names)), by = bucket]
el2 <- elig[, .(eligible = .N), by = bucket]
ca  <- q[, .(cases = .N), by = bucket]
z <- Reduce(function(x, y) merge(x, y, by = "bucket", all.x = TRUE),
            list(tot, el2, ca))
z[is.na(z)] <- 0L
z[, `:=`(elig_rate = eligible / groups,
         per_group = cases / groups,
         per_id    = cases / identities)]
setorder(z, bucket)
say("  %-7s %8s %9s %8s %10s %11s %11s", "size", "groups", "ident", "eligible",
    "elig rate", "cases/group", "cases/ident")
for (j in seq_len(nrow(z)))
  say("  %-7s %8s %9s %8s %9.1f%% %11.2f %11.3f", z$bucket[j],
      format(z$groups[j], big.mark = ","), format(z$identities[j], big.mark = ","),
      format(z$eligible[j], big.mark = ","), 100 * z$elig_rate[j],
      z$per_group[j], z$per_id[j])
say("  %-7s %8s %9s %8s %9.1f%% %11.2f %11.3f", "ALL",
    format(sum(z$groups), big.mark = ","), format(sum(z$identities), big.mark = ","),
    format(sum(z$eligible), big.mark = ","),
    100 * sum(z$eligible) / sum(z$groups),
    sum(z$cases) / sum(z$groups), sum(z$cases) / sum(z$identities))
say("")
say("  old sample, for comparison: 0.66 cases/group on PARTIAL groups")
fwrite(z, file.path(PF, "data-dev", "TRI-PILOT-YIELD.csv"))

## ---- 4. what 50,000 costs ----------------------------------------------------
SEC <- el / nrow(prep$recipients)
hr(); say("SIZING 50,000 CASES  (measured %.3f s/identity on this machine)", SEC)
idx <- as.data.table(readRDS(file.path(PF, "data-dev", "GROUP-INDEX.rds")))
idx <- idx[n_names > 1L]
idx[, street := sub("[|].*$", "", key)]
idx <- idx[!grepl("^P?O?BOX|^POST", street) & n_names < 25L]
br <- c(2, 3, 5, 10, 25, 100, Inf)
idx[, bucket := cut(n_grants, breaks = br, right = FALSE,
                    labels = c("2", "3-4", "5-9", "10-24", "25-99", "100+"))]
avail <- idx[, .(avail_groups = .N, avail_ids = sum(n_names)), by = bucket]
p <- merge(avail, z[, .(bucket, per_group, per_id)], by = "bucket")
setorder(p, -per_id)          # cheapest cases first
p[, cum_cases := cumsum(avail_groups * per_group)]
p[, cum_hours := cumsum(avail_ids) * SEC / 3600]
say("  buckets ordered by cases per identity (cheapest first):")
say("  %-7s %11s %11s %12s %12s", "size", "avail grp", "cases/ident", "cum cases", "cum hours")
for (j in seq_len(nrow(p)))
  say("  %-7s %11s %11.3f %12s %12.1f", p$bucket[j],
      format(p$avail_groups[j], big.mark = ","), p$per_id[j],
      format(round(p$cum_cases[j]), big.mark = ","), p$cum_hours[j])
hr(); say("done  %s", format(Sys.time()))
