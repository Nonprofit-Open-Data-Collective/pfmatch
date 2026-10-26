#!/usr/bin/env Rscript
# ============================================================================
# build-group-index.R -- the corpus-wide address-group index.
#
# WHY A SEPARATE INDEX. Triangulation groups renderings of one organisation by
# ADDRESS, which is independent of the name comparator under test. Grouping is
# purely structural -- it reads address and name off the grant file and never
# matches anything -- so it can run over the WHOLE corpus first, and only the
# grants inside a known multi-rendering group need to be matched afterwards.
#
# That inverts the original design (sample filers -> match -> group), where
# most matched grants landed in no group at all: 112,806 grants matched yielded
# 2,853 informative cases, about 40 grants per case. It also removes a
# selection property worth naming -- the old set is conditioned on which filers
# were drawn, so an organisation funded only by unsampled foundations is
# invisible however many variant renderings it has.
#
# A CHUNKED-AGGREGATION TRAP, which this script exists partly to avoid. An
# earlier pass accumulated per-chunk `uniqueN(name)` and `uniqueN(year)` and
# took the max across chunks. That is wrong, and wrong in a direction that
# hides the answer: the corpus is written year by year, so one address
# appearing in 2010 and again in 2023 sits in different chunks and scores
# n_years = 1. Distinct counts do not decompose over chunks. The fix is to
# accumulate distinct (key, name) and (key, year) PAIRS and count at the end.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("=", 80))

PF    <- Sys.getenv("PFMATCH_DIR", ".")
source(file.path(PF, "dev", "grants-path.R"))
V2    <- pf_grants_v2()
OUT   <- file.path(PF, "data-dev", "GROUP-INDEX.rds")
CHUNK <- 2000000L

hr(); say("build-group-index  %s", format(Sys.time())); hr()
hdr <- names(fread(V2, nrows = 0L))
KEEP <- c("OBJECTID", "TABLE_ID", "TAX_YEAR",
          "PF_15_G_PAID_RECIP_NAME_ORG_L1", "PF_15_G_PAID_RECIP_ADDR_L1",
          "PF_15_G_PAID_RECIP_ADDR_ZIP")
sel <- sort(match(KEEP, hdr)); stopifnot(!anyNA(sel))

pairs_nm <- list(); pairs_yr <- list(); counts <- list()
i <- 0L; seen <- 0L
repeat {
  ch <- fread(V2, colClasses = "character", na.strings = NULL,
              skip = 1L + i * CHUNK, nrows = CHUNK, header = FALSE,
              select = sel, col.names = hdr[sel], showProgress = FALSE)
  nn <- nrow(ch); if (!nn) break
  seen <- seen + nn; i <- i + 1L

  # the group key: normalized street + ZIP5. Address only -- never the name,
  # which is the thing under test.
  ch[, st := gsub("[^A-Z0-9]", "", toupper(PF_15_G_PAID_RECIP_ADDR_L1))]
  ch[, z5 := substr(gsub("[^0-9]", "", PF_15_G_PAID_RECIP_ADDR_ZIP), 1, 5)]
  ch[, nm := gsub("[^A-Z0-9 ]", "", toupper(PF_15_G_PAID_RECIP_NAME_ORG_L1))]
  ch <- ch[nzchar(st) & nchar(z5) == 5L & nzchar(nm)]
  if (!nrow(ch)) { rm(ch); if (nn < CHUNK) break else next }
  ch[, key := paste(st, z5, sep = "|")]

  counts[[i]]  <- ch[, .(n = .N), by = key]
  pairs_nm[[i]] <- unique(ch[, .(key, nm)])
  pairs_yr[[i]] <- unique(ch[, .(key, TAX_YEAR)])
  say("  chunk %2d  %11s rows scanned", i, format(seen, big.mark = ","))
  rm(ch); invisible(gc())
  if (nn < CHUNK) break
}

say("folding ...")
cnt <- rbindlist(counts)[, .(n_grants = sum(n)), by = key]; rm(counts)
pn  <- unique(rbindlist(pairs_nm))[, .(n_names = .N), by = key]; rm(pairs_nm)
py  <- unique(rbindlist(pairs_yr))[, .(n_years = .N), by = key]; rm(pairs_yr)
invisible(gc())
idx <- merge(merge(cnt, pn, by = "key"), py, by = "key")
rm(cnt, pn, py); invisible(gc())

hr(); say("CORPUS-WIDE ADDRESS GROUPS   (%s rows scanned)", format(seen, big.mark = ","))
say("  distinct address keys            %s", format(nrow(idx), big.mark = ","))
say("  keys with >1 grant               %s", format(sum(idx$n_grants > 1L), big.mark = ","))
say("  keys with >1 NAME rendering      %s", format(sum(idx$n_names > 1L), big.mark = ","))
say("  keys with >1 name AND >1 year    %s", format(sum(idx$n_names > 1L & idx$n_years > 1L), big.mark = ","))

m <- idx[n_names > 1L]
say("")
say("THE MATCH BILL for the multi-rendering universe")
say("  groups                           %s", format(nrow(m), big.mark = ","))
say("  grants inside them               %s  (%.1f%% of the corpus)",
    format(sum(m$n_grants), big.mark = ","), 100 * sum(m$n_grants) / seen)
say("  median grants per group          %d   mean %.1f   max %s",
    median(m$n_grants), mean(m$n_grants), format(max(m$n_grants), big.mark = ","))
say("  median names per group           %d   max %s",
    median(m$n_names), format(max(m$n_names), big.mark = ","))
say("  median years per group           %d   max %d", median(m$n_years), max(m$n_years))

hr(); say("GROUP SIZE DISTRIBUTION (multi-rendering groups)")
# 7 breaks make 6 intervals; an earlier version passed 7 labels, which shifted
# every bucket by one and reported groups of 2 grants as "3-4".
br  <- c(2, 3, 5, 10, 25, 100, Inf)
lab <- c("2", "3-4", "5-9", "10-24", "25-99", "100+")
stopifnot(length(lab) == length(br) - 1L)
m[, bucket := cut(n_grants, breaks = br, right = FALSE, labels = lab)]
# identities, not grant rows, are what the matcher costs: a group contributes
# roughly its distinct renderings.
d <- m[, .(groups = .N, grants = sum(n_grants), identities = sum(n_names),
           med_names = median(n_names)), by = bucket][order(bucket)]
say("  %-7s %9s %12s %12s %9s", "size", "groups", "grants", "identities", "med names")
for (j in seq_len(nrow(d)))
  say("  %-7s %9s %12s %12s %9d", d$bucket[j],
      format(d$groups[j], big.mark = ","), format(d$grants[j], big.mark = ","),
      format(d$identities[j], big.mark = ","), d$med_names[j])
say("  %-7s %9s %12s %12s", "TOTAL", format(sum(d$groups), big.mark = ","),
    format(sum(d$grants), big.mark = ","), format(sum(d$identities), big.mark = ","))

saveRDS(idx, OUT, compress = "xz")
hr(); say("wrote %s (%.1f MB)", OUT, file.size(OUT) / 1e6)
say("done  %s", format(Sys.time()))
