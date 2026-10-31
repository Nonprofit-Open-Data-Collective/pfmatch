#!/usr/bin/env Rscript
# ============================================================================
# experiment-head-reference.R -- match against ONLY the organisations the
# benchmark already resolved, and see what that does.
#
# The reference is the BMF rows for the EINs that BASELINE-2026-10C's augmented
# arm cleared YES: 2,979 identities over 2,813 distinct EINs, 9,253 reference
# rows, 0.24% of the 3,880,431-row production reference.
#
# WHAT THIS CAN AND CANNOT SHOW, because it decides how to read the output.
#
# The mini reference is a strict SUBSET of the production one. Every row in it
# is also in the full reference. So it cannot surface a genuinely new correct
# match: any EIN it can reach, the full reference could also reach, and any
# query whose true answer is outside the 2,813 EINs cannot be answered at all.
# A subset reference produces a YES the full reference did not for exactly one
# reason -- the competitors are gone, so the margin and tie gates see an
# uncontested top candidate. That is either
#
#   (a) a real finding: the full reference's MAYBE tier is partly caused by
#       reference-side competition, which is already suspected -- 15.9% of the
#       MAYBE tie band is two BMF rows carrying one name for one body
#       (dev/CLUSTER-FINDINGS.md 8) -- or
#   (b) a false positive: a mediocre match looks decisive because nothing
#       better is present.
#
# Only a comparison against the full reference separates those, so both arms
# below report the full-reference answer beside the mini one.
#
# TWO ARMS, answering two different questions.
#
#   ARM C (coverage).  N grants drawn from the corpus, excluding the benchmark's
#     own, matched against the mini reference. Answers "how much grant volume
#     goes to this head of 2,813 organisations". New YES here is expected and
#     uninformative about precision: the Salvation Army appears 28,096 times in
#     the corpus, so a reference holding it will clear a lot of grants. Read the
#     RATE, not the count.
#
#   ARM R (rerun).  The benchmark's own 4,748 identities, matched against the
#     mini reference, cross-tabulated against their full-reference tier. This
#     is the arm with a hypothesis. The cells that matter are MAYBE->YES and
#     NO->YES: same query, same candidate present in both references, decision
#     changed only because competition was removed. For those, agreement with
#     the full reference's own best candidate says whether (a) or (b).
#
# THE STATISTICS CONFOUND, controlled by PF_EXP_STATS.
#
# name_freq and token_idf are computed FROM the reference. Over 9,253 rows every
# token looks rare, so the IDF gate (min_pair_idf) and the frequency cap
# (max_ref_freq) behave completely differently from production -- a change that
# has nothing to do with the question being asked. Default "full" carries the
# production tables into the mini bundle, isolating "fewer candidates" from
# "different statistics". Run it both ways; the difference is itself a result.
#
# USAGE
#   PF_EXP_ARM=R                       Rscript dev/experiment-head-reference.R
#   PF_EXP_ARM=C PF_EXP_N=50000        Rscript dev/experiment-head-reference.R
#   PF_EXP_ARM=C PF_EXP_N=1000000      Rscript dev/experiment-head-reference.R
#   PF_EXP_STATS=mini PF_EXP_ARM=R     Rscript dev/experiment-head-reference.R
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(library(npmatch)))
setDTthreads(0)
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
source(file.path(PF, "dev", "grants-path.R"))
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("=", 84))
nf  <- function(x) format(x, big.mark = ",")
pc  <- function(a, b) sprintf("%s (%.2f%%)", nf(a), 100 * a / b)
e9  <- function(v) { v <- gsub("[^0-9]", "", as.character(v))
                     ifelse(nchar(v) == 9L, v, NA_character_) }

ARM   <- toupper(Sys.getenv("PF_EXP_ARM", "R"))
N     <- as.integer(Sys.getenv("PF_EXP_N", "50000"))
STATS <- tolower(Sys.getenv("PF_EXP_STATS", "full"))
SEED  <- as.integer(Sys.getenv("PF_EXP_SEED", "20261031"))
BENCH <- file.path(PF, "dev", "BASELINE-2026-10C", "benchmark-1k-augmented.rds")
OUT   <- file.path(PF, "data-dev", sprintf("EXP-HEAD-%s-%s.rds", ARM, STATS))
stopifnot(ARM %in% c("C", "R"), STATS %in% c("full", "mini"))

hr(); say("experiment-head-reference   arm %s   stats %s   %s", ARM, STATS,
          format(Sys.time())); hr()

## ---- 1. the head: EINs the benchmark cleared YES ----------------------------
b  <- as.data.table(readRDS(BENCH))
yes_ein <- unique(e9(b[tier == "YES"]$overall_ein))
yes_ein <- yes_ein[!is.na(yes_ein)]
say("benchmark: %s identities, %s YES, %s distinct YES EINs",
    nf(nrow(b)), nf(nrow(b[tier == "YES"])), nf(length(yes_ein)))

## ---- 2. the mini reference, carved out of the production bundle -------------
# Carved rather than rebuilt from the BMF: the keys must be byte-identical to
# the production ones or the comparison measures normalization, not competition.
full <- readRDS(file.path(PF, "data-dev", "REF-augmented.rds"))
pf_check_reference(full)
fr <- as.data.table(full$reference)
mini <- fr[e9(.ein) %chin% yes_ein]
# Re-attach the reference class. as.data.table() strips it, and without
# `np_reference` npmatch takes the frame for a RAW BMF extract and fails on the
# mapped column names it expects there ("missing mapped column(s): ein,
# org_name_join, ..."). pf_collapse_reference() does the same thing for the
# same reason.
data.table::setattr(mini, "class", class(full$reference))
say("mini reference: %s rows over %s EINs  (%.4f%% of %s)",
    nf(nrow(mini)), nf(uniqueN(e9(mini$.ein))),
    100 * nrow(mini) / nrow(fr), nf(nrow(fr)))

# ref_index is an index OVER the reference, so it has to be rebuilt for the
# subset; reusing the production index would point at rows that are not there.
mini_bundle <- list(
  reference = mini,
  name_freq = if (STATS == "full") full$name_freq else npmatch::np_name_freq(mini$name_key),
  token_idf = if (STATS == "full") full$token_idf else npmatch::np_token_idf(mini$name_key),
  ref_index = npmatch::np_ref_index(mini),
  normalizer = full$normalizer)
say("statistics: %s  (name_freq %s rows, token_idf %s rows)", STATS,
    nf(nrow(as.data.frame(mini_bundle$name_freq))),
    nf(nrow(as.data.frame(mini_bundle$token_idf))))

PASSES <- c(pf_staged_passes("lean", concat = TRUE),
            pf_recovery_passes(state = TRUE))

run <- function(recipients, bundle, dir, label) {
  say("matching %s identities against %s ...", nf(nrow(recipients)), label)
  t0 <- proc.time()[["elapsed"]]
  st <- pf_run_batches(recipients, bundle, dir = dir, passes = PASSES,
                       recover = TRUE, batch_size = 25000L, resume = FALSE,
                       verbose = TRUE)
  el <- proc.time()[["elapsed"]] - t0
  say("  %.1f min  (%.3f s/identity)", el / 60, el / max(1, nrow(recipients)))
  list(status = as.data.table(st), seconds = el)
}

## ---- ARM R: the benchmark's own identities, both references -----------------
if (ARM == "R") {
  # Replicate dev/build-baseline.R's path EXACTLY, or the two runs are not
  # comparable. It does not call pf_prepare(): it reads the grants, repairs the
  # name-from-street field swap, and hands the GRANT ROWS to pf_match_grants(),
  # whose unit is the in-scope grant row -- 4,903 grants less 155 out of scope
  # is the benchmark's 4,748. Collapsing to recipient identities first gives
  # 4,683 of a different unit with ids that cannot be joined.
  grants <- pf_read_grants(file.path(PF, "inputs"),
                           pattern = "^efv2_1k_grants_.*[.]csv$")
  grants <- pf_recover_name_from_street(grants)
  say("benchmark population: %s grant rows", nf(nrow(grants)))
  t0 <- proc.time()[["elapsed"]]
  m <- pf_match_grants(grants, mini_bundle, passes = PASSES, recover = TRUE,
                       verbose = FALSE)
  el <- proc.time()[["elapsed"]] - t0
  s <- as.data.table(as.data.frame(m$result))
  say("matched %s rows against the mini reference in %.1f s (%.4f s/row)",
      nf(nrow(s)), el, el / max(1, nrow(s)))
  s[, ein9 := e9(overall_ein)]
  b[, ein9_full := e9(overall_ein)]
  j <- merge(s[, .(.id, mini_tier = tier, mini_ein = ein9,
                   mini_score = suppressWarnings(as.numeric(overall_score)),
                   mini_name_y = overall_name_y)],
             b[, .(.id, name_x, full_tier = tier, full_ein = ein9_full,
                   full_score = overall_score, full_margin = overall_margin)],
             by = ".id", all = TRUE)
  say("joined: %s rows, mini_tier missing on %s", nf(nrow(j)),
      nf(sum(is.na(j$mini_tier))))
  hr(); say("ARM R  full-reference tier x mini-reference tier")
  print(dcast(j[!is.na(full_tier)], full_tier ~ mini_tier,
              value.var = ".id", fun.aggregate = length), row.names = FALSE)
  hr(); say("THE CELLS THAT MATTER")
  for (ft in c("MAYBE", "NO")) {
    k <- j[full_tier == ft & mini_tier == "YES"]
    say("  %s -> YES on the mini reference: %s", ft, nf(nrow(k)))
    if (!nrow(k)) next
    agree <- k[!is.na(full_ein) & mini_ein == full_ein]
    say("    mini EIN == the full reference top candidate: %s",
        pc(nrow(agree), nrow(k)))
    say("    -> those are competition-blocked, not new information")
    say("    mini EIN differs or full had none: %s", nf(nrow(k) - nrow(agree)))
    say("    -> read these by hand; a subset reference cannot know better")
  }
  say("")
  say("  YES -> not YES (lost by removing the rest of the reference): %s",
      nf(nrow(j[full_tier == "YES" & mini_tier != "YES"])))
  say("  YES -> YES but a DIFFERENT EIN: %s",
      nf(nrow(j[full_tier == "YES" & mini_tier == "YES" &
                !is.na(mini_ein) & !is.na(full_ein) & mini_ein != full_ein])))
  saveRDS(j, OUT, compress = FALSE)
  say("wrote %s", OUT)
}

## ---- ARM C: N fresh grants from the corpus ----------------------------------
if (ARM == "C") {
  V2  <- pf_grants_v2()
  hdr <- names(fread(V2, nrows = 0L))
  # Exclude the benchmark's own grants so "new" means new. The benchmark key is
  # OBJECTID | TABLE_ID, the published row key.
  bg <- pf_read_grants(file.path(PF, "inputs"),
                       pattern = "^efv2_1k_grants_.*[.]csv$")
  bkey <- paste(bg$OBJECTID, bg$TABLE_ID, sep = "|")
  say("excluding %s benchmark grant rows", nf(length(unique(bkey))))
  # Deterministic draw: pick row positions up front, then keep them while
  # scanning. Reading all 30 columns for 17.25M rows at once is ~6 GB.
  total <- 17253199L
  set.seed(SEED)
  want <- sort(sample.int(total, min(N * 2L, total)))  # 2x, then trim post-filter
  CH <- 2000000L; i <- 0L; seen <- 0L; acc <- list()
  repeat {
    ch <- fread(V2, colClasses = "character", na.strings = NULL, header = FALSE,
                skip = 1L + i * CH, nrows = CH, col.names = hdr,
                showProgress = FALSE)
    n <- nrow(ch); if (!n) break
    idx <- want[want > seen & want <= seen + n] - seen
    if (length(idx)) acc[[length(acc) + 1L]] <- ch[idx]
    seen <- seen + n; i <- i + 1L
    say("  chunk %d  %s scanned, %s drawn", i, nf(seen),
        nf(sum(vapply(acc, nrow, 0L))))
    rm(ch); invisible(gc())
    if (n < CH) break
  }
  g <- rbindlist(acc); rm(acc); invisible(gc())
  g <- g[!(paste(OBJECTID, TABLE_ID, sep = "|") %chin% bkey)]
  if (nrow(g) > N) g <- g[1:N]
  say("drawn: %s grant rows (benchmark rows removed)", nf(nrow(g)))
  prep <- pf_prepare(as.data.frame(g), verbose = FALSE)
  say("-> %s identities", nf(nrow(prep$recipients)))
  m <- run(prep$recipients, mini_bundle,
           file.path(PF, "data-dev", sprintf("ckpt-exp-head-C-%s", STATS)),
           "the mini reference")
  s <- m$status
  hr(); say("ARM C  %s identities against the %s-EIN head", nf(nrow(s)),
            nf(length(yes_ein)))
  tt <- s[, .N, by = status][order(-N)]
  tt[, share := sprintf("%.2f%%", 100 * N / sum(tt$N))]
  print(tt, row.names = FALSE)
  say("")
  say("A YES here means the grant went to one of the %s organisations the",
      nf(length(yes_ein)))
  say("benchmark already resolved. That is coverage, not accuracy.")

  ## ---- the precision control, because the caveat alone is not enough -------
  # The mini arm's YES clears were decided with the competitors absent. Re-match
  # a sample of them against the FULL reference: if the full reference reaches
  # the same EIN, the clear survives contest; if it reaches a different one or
  # declines to clear, the mini YES was an artifact of the missing competition.
  VN <- as.integer(Sys.getenv("PF_EXP_VERIFY", "400"))
  yrows <- s[status == "YES"]
  if (nrow(yrows) && VN > 0) {
    set.seed(SEED)
    pick <- yrows[sample(.N, min(.N, VN))]$grant_id
    rec <- as.data.table(prep$recipients)
    idcol <- if (!is.null(rec$grant_id)) "grant_id" else names(rec)[1]
    sub <- rec[get(idcol) %chin% pick]
    hr(); say("PRECISION CONTROL: %s of the %s mini-YES identities, re-matched",
              nf(nrow(sub)), nf(nrow(yrows)))
    v <- run(sub, full, file.path(PF, "data-dev", "ckpt-exp-head-verify"),
             "the FULL reference")
    fv <- v$status
    cmp <- merge(yrows[, .(grant_id, mini_ein = e9(ein))],
                 fv[, .(grant_id, full_tier = status, full_ein = e9(ein))],
                 by = "grant_id")
    say("")
    say("  full-reference verdict on identities the mini arm cleared YES:")
    print(cmp[, .N, by = full_tier][order(-N)], row.names = FALSE)
    same <- cmp[full_tier == "YES" & !is.na(full_ein) & full_ein == mini_ein]
    say("")
    say("  SURVIVES CONTEST (full also YES, same EIN): %s", pc(nrow(same), nrow(cmp)))
    say("  full clears a DIFFERENT EIN                : %s",
        nf(nrow(cmp[full_tier == "YES" & !is.na(full_ein) & full_ein != mini_ein])))
    say("  full does not clear at all                 : %s",
        nf(nrow(cmp[full_tier != "YES"])))
    say("  -> the last two are the mini reference clearing what contest would not")
    saveRDS(list(status = s, verify = cmp, seconds = m$seconds,
                 n_identities = nrow(s)), OUT, compress = FALSE)
  } else {
    saveRDS(list(status = s, seconds = m$seconds, n_identities = nrow(s)),
            OUT, compress = FALSE)
  }
  say("wrote %s", OUT)
}
hr(); say("done  %s", format(Sys.time()))
