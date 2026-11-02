#!/usr/bin/env Rscript
# ============================================================================
# measure-addr-key-spellings.R -- settle dev/PLACES-SYNC.md §4 step 4.
#
#   Rscript dev/measure-addr-key-spellings.R
#
# WHY. tests/testthat/test-addr-key.R showed that adopting
# npnormalize::np_addr_key() as the triangulation group key SPLITS 92 of the
# 5,410 shipped pairs: 11 because a box or mail-only street is blanked (right),
# 22 because a suite fused to the street word survives in street_key
# (npnormalize#7 §5, intended upstream), and 59 because the hand-rolled key
# deleted every separator and street_key keeps a space where a hyphen was.
# That last 59 is a loss, and step 4 cannot ship until it is answered.
#
# A third spelling would answer it -- gsub(" ", "", street_key), normalized and
# suffix-contracted and suite-stripped like street_key, but separator-blind the
# way the hand-rolled key accidentally was. The question this script measures
# is whether that spelling over-merges: whether being blind to spaces glues
# together addresses that are genuinely different, which is the failure the
# hand-rolled key would have had all along and nobody checked.
#
# THE THREE SPELLINGS, over a whole BMF reference rather than 5,410 pairs:
#
#   K1  hand   gsub("[^A-Z0-9]", "", toupper(street)) + "|" + zip5,
#              NA for a street matching ^P?O?BOX|^POST
#   K2  np     np_addr_key(street_key, zip5) -- street_key + " " + zip5, blank
#              for a box or mail-only street
#   K3  tight  np_addr_key(gsub(" ", "", street_key), zip5)
#
# Row counts and every figure below are read off this machine. Nothing here is
# quoted from an earlier pass -- see dev/PLACES-SYNC.md on quoting signatures
# and figures forward.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
PF <- "C:/Users/jdlec/Dropbox (Personal)/00 - URBAN/00-GITHUB/pfmatch"
suppressWarnings(suppressMessages(pkgload::load_all(PF, quiet = TRUE)))
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("=", 78))
nf  <- function(x) format(x, big.mark = ",")
pc  <- function(a, b) sprintf("%.2f%%", 100 * a / b)
sq  <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; x }

SRC <- file.path(PF, "data-dev", "REF-augmented.rds")
if (!file.exists(SRC)) stop("need ", SRC, call. = FALSE)

hr(); say("measure-addr-key-spellings  %s", format(Sys.time())); hr()
say("installed normalizer: %s  (npnormalize %s)",
    npmatch::np_normalize_signature(), as.character(packageVersion("npnormalize")))

t0 <- proc.time()[["elapsed"]]
r <- readRDS(SRC)
if (!is.null(r$reference)) r <- r$reference
setDT(r)
say("loaded %s rows x %s cols in %.0fs", nf(nrow(r)), ncol(r),
    proc.time()[["elapsed"]] - t0)

# ---- is the recorded street_key current, or does it predate the normalizer? --
# Recompute on a sample rather than trusting the column. This bundle IS stamped
# -- v1-3e7b9f9d59bbb19e, which is why pf_check_reference() can stop a match
# run against it -- and the stamp predates the installed normalizer, so its
# recorded keys are stale. (An earlier version of this comment called the file
# unstamped, repeating §3a's old heading; see §3a.)
set.seed(20261102L)
i <- sample.int(nrow(r), min(50000L, nrow(r)))
s <- r[i]
fresh <- as.data.table(npmatch::np_normalize(data.frame(
  name = sq(s$name), dba = sq(s$dba), street = sq(s$street), unit = sq(s$unit),
  city = sq(s$city), state = sq(s$state), zip5 = sq(s$zip5),
  zip_plus4 = sq(s$zip_plus4), stringsAsFactors = FALSE)))
same <- identical(sq(fresh$street_key), sq(s$street_key))
say("recorded street_key matches a fresh normalize on %s sampled rows: %s",
    nf(length(i)), same)
if (!same) {
  d <- which(sq(fresh$street_key) != sq(s$street_key))
  say("  %s of %s differ; first few:", nf(length(d)), nf(length(i)))
  print(head(data.frame(street = s$street[d], recorded = s$street_key[d],
                        fresh = fresh$street_key[d], stringsAsFactors = FALSE), 5))
  # The recompute is ~11 minutes over 3.9M rows, so cache it against the
  # signature that produced it; a rerun of this script is then seconds.
  CACHE <- file.path(PF, "data-dev", sprintf("ADDR-KEY-STREETKEY-%s.rds",
                                             npmatch::np_normalize_signature()))
  if (file.exists(CACHE)) {
    sk <- readRDS(CACHE)
    if (length(sk) == nrow(r)) {
      r[, street_key := sk]
      say("  reused %s", basename(CACHE))
    } else sk <- NULL
  } else sk <- NULL
  if (is.null(sk)) {
    say("  recomputing street_key over the whole file")
    t1 <- proc.time()[["elapsed"]]
    nn <- as.data.table(npmatch::np_normalize(data.frame(
      name = sq(r$name), dba = sq(r$dba), street = sq(r$street), unit = sq(r$unit),
      city = sq(r$city), state = sq(r$state), zip5 = sq(r$zip5),
      zip_plus4 = sq(r$zip_plus4), stringsAsFactors = FALSE)))
    r[, street_key := nn$street_key]
    saveRDS(nn$street_key, CACHE, compress = FALSE)
    rm(nn); invisible(gc())
    say("  recomputed in %.0fs, cached as %s",
        proc.time()[["elapsed"]] - t1, basename(CACHE))
  }
}

# ---- the three spellings ----------------------------------------------------
hr(); say("THE THREE KEY SPELLINGS"); hr()
st  <- toupper(gsub("[^A-Z0-9]", "", toupper(sq(r$street))))
box <- grepl("^P?O?BOX|^POST", st)
z   <- sq(r$zip5)
r[, k1 := ifelse(nzchar(st) & !box & nzchar(z), paste(st, z, sep = "|"), NA_character_)]
r[, k2 := npnormalize::np_addr_key(sq(street_key), z)]
r[, k3 := npnormalize::np_addr_key(gsub(" ", "", sq(street_key)), z)]
r[k2 == "", k2 := NA_character_]
r[k3 == "", k3 := NA_character_]

tab <- data.table(
  spelling = c("K1 hand", "K2 np (street_key)", "K3 tight (no spaces)"),
  keyed = c(sum(!is.na(r$k1)), sum(!is.na(r$k2)), sum(!is.na(r$k3))),
  groups = c(uniqueN(r$k1, na.rm = TRUE), uniqueN(r$k2, na.rm = TRUE),
             uniqueN(r$k3, na.rm = TRUE)))
tab[, dropped := nrow(r) - keyed]
tab[, rows_per_group := round(keyed / groups, 3)]
print(tab)
say("")
say("rows the box rule drops: K1 %s (%s), K2 %s (%s)",
    nf(tab$dropped[1]), pc(tab$dropped[1], nrow(r)),
    nf(tab$dropped[2]), pc(tab$dropped[2], nrow(r)))

# ---- K1 vs K2: what the switch costs ---------------------------------------
hr(); say("K1 -> K2: WHAT ADOPTING street_key DOES"); hr()
a <- r[!is.na(k1) & !is.na(k2), .(k1, k2, street, street_key, zip5, street_num = sq(street_num))]
spl <- a[, .(n_k2 = uniqueN(k2)), by = k1]
say("K1 groups that K2 splits:   %s of %s (%s)",
    nf(sum(spl$n_k2 > 1L)), nf(nrow(spl)), pc(sum(spl$n_k2 > 1L), nrow(spl)))
mrg <- a[, .(n_k1 = uniqueN(k1)), by = k2]
say("K2 groups that merge >1 K1: %s of %s (%s)",
    nf(sum(mrg$n_k1 > 1L)), nf(nrow(mrg)), pc(sum(mrg$n_k1 > 1L), nrow(mrg)))

# ---- K2 vs K3: does blindness to spaces buy anything, and at what risk? -----
hr(); say("K2 -> K3: WHAT SPACE-BLINDNESS BUYS, AND WHAT IT RISKS"); hr()
b <- r[!is.na(k2) & !is.na(k3), .(k2, k3, street, street_key, street_num = sq(street_num))]
m <- b[, .(n_k2 = uniqueN(k2), n_num = uniqueN(street_num[nzchar(street_num)])), by = k3]
say("K3 groups that merge >1 K2 group: %s of %s (%s)",
    nf(sum(m$n_k2 > 1L)), nf(nrow(m)), pc(sum(m$n_k2 > 1L), nrow(m)))
say("  of those, groups whose merged rows disagree on street_num: %s",
    nf(sum(m$n_k2 > 1L & m$n_num > 1L)))
say("  i.e. merges where the house number itself differs: %s of the merges",
    pc(sum(m$n_k2 > 1L & m$n_num > 1L), max(1L, sum(m$n_k2 > 1L))))
say("K3 never splits a K2 group by construction: %s",
    all(b[, .(n_k3 = uniqueN(k3)), by = k2]$n_k3 == 1L))

hr(); say("EXAMPLES: K2 groups that K3 glues together"); hr()
ex <- m[n_k2 > 1L][order(-n_k2)][seq_len(min(12L, .N))]
for (kk in ex$k3) {
  g <- unique(b[k3 == kk, .(street_key, street_num)])
  say("K3 %-34s  <- %s", kk, paste(unique(g$street_key), collapse = "  |  "))
}

hr(); say("EXAMPLES: the risky merges, where street_num disagrees"); hr()
rk <- m[n_k2 > 1L & n_num > 1L][order(-n_k2)][seq_len(min(12L, .N))]
if (!nrow(rk)) say("none") else for (kk in rk$k3) {
  g <- unique(b[k3 == kk, .(street_key, street_num)])
  say("K3 %-34s  <- %s", kk,
      paste(sprintf("%s (num %s)", g$street_key, g$street_num), collapse = "  |  "))
}

hr(); say("done  %s   (%.0fs total)", format(Sys.time()), proc.time()[["elapsed"]] - t0); hr()
