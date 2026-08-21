#!/usr/bin/env Rscript
# ============================================================================
# run-bmf-comparison.R -- attribute the Schedule I augmentation properly.
#
# Three runs over the SAME grants, changing only the reference:
#
#   1  active    bmf_2026_01_processed.csv          reproduce the baseline
#   2  unified   bmf_unified_geocoded-nteev2fix.csv isolate the vintage effect
#   3  augmented BMF-AUGMENTED-unified-fixed.csv    isolate the alias effect
#
# Measured together the two changes are unattributable, which is the whole point
# of running three rather than one.
#
# Four metrics, because tier counts alone mislead:
#   tier movement          the headline
#   YES-answer stability   how many previously-confident EINs CHANGE -- harm
#   NO -> resolved         the gain, split by row_source (bmf vs schedi)
#   adjudicated accuracy   the 63 hand-verified answers: better, or just moved?
#
# Sample: PF_SET=1k, the five 1,000-row files. Not for speed -- it is the only
# set with adjudicated ground truth, since the 100 audited MAYBE cases are
# grant_ids from this run. On 50k every number would be tier movement with no
# way to tell whether the movement was right.
#
#   PF_SET=1k|50k|100k      default 1k
#   PF_ONLY=active,unified  restrict to some configs
# ============================================================================
suppressWarnings(suppressMessages({
  library(data.table); library(npmatch) }))
suppressWarnings(suppressMessages(devtools::load_all(
  Sys.getenv("PFMATCH_DIR", "."), quiet = TRUE)))
setDTthreads(0)

PF  <- Sys.getenv("PFMATCH_DIR", ".")
NPM <- Sys.getenv("NPMATCH_DIR", "../npmatch")
SET <- Sys.getenv("PF_SET", "1k")
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("=", 74), "\n")

PATTERN <- switch(SET, "1k" = "^1k_grants_.*[.]csv$",
                       "50k" = "^50k_grants[.]csv$",
                       "100k" = "^100k_grants[.]csv$")

CONFIGS <- list(
  active    = list(csv = file.path(NPM, "data-raw", "bmf_2026_01_processed.csv"),
                   cache = file.path(PF, "data-dev", "REF-active.rds"), active_col = NULL),
  unified   = list(csv = file.path(NPM, "data-raw", "bmf_unified_geocoded-nteev2fix.csv"),
                   cache = file.path(PF, "data-dev", "REF-unified.rds"), active_col = "bmf_source"),
  augmented = list(csv = file.path(PF, "data-dev", "BMF-AUGMENTED-unified-fixed.csv"),
                   cache = file.path(PF, "data-dev", "REF-augmented.rds"), active_col = "bmf_source"))
only <- Sys.getenv("PF_ONLY", "")
if (nzchar(only)) CONFIGS <- CONFIGS[strsplit(only, ",")[[1]]]

## ---- grants, prepared once and reused ---------------------------------------
hr(); say("PREPARE  %s", SET); hr()
prep <- pf_prepare(file.path(PF, "inputs"), pattern = PATTERN, dedup = "fuzzy")
say("identities to match: %s", format(nrow(prep$recipients), big.mark = ","))

## ---- ground truth -----------------------------------------------------------
v <- fread(file.path(PF, "dev", "maybe-verdicts.csv"), colClasses = "character",
           na.strings = NULL, showProgress = FALSE)
a <- fread(file.path(PF, "data-dev", "AUDIT-MAYBE-100.csv"), colClasses = "character",
           na.strings = NULL, showProgress = FALSE)
a[, rank := as.integer(rank)]
v[, correct_rank := suppressWarnings(as.integer(correct_rank))]
truth <- merge(a[, .(grant_id, rank, ein)],
               v[!is.na(correct_rank), .(grant_id, correct_rank)], by = "grant_id")
truth <- truth[rank == correct_rank, .(grant_id, correct_ein = .pf_ein(ein))]
say("adjudicated answers available: %d", nrow(truth))

## ---- run each configuration --------------------------------------------------
res <- list()
for (nm in names(CONFIGS)) {
  cfg <- CONFIGS[[nm]]
  hr(); say("RUN  %s", toupper(nm)); hr()
  if (!file.exists(cfg$csv)) { say("  MISSING %s -- skipped", cfg$csv); next }

  t0 <- proc.time()[["elapsed"]]
  ref <- pf_reference(cfg$csv, cache = cfg$cache, active_col = cfg$active_col)
  say("  reference: %s rows | %.0f s",
      format(nrow(ref$reference), big.mark = ","), proc.time()[["elapsed"]] - t0)

  t1 <- proc.time()[["elapsed"]]
  lnk <- pf_link(prep, ref, dir = file.path(PF, "data-dev", paste0("batches-", nm)),
                 batch_size = 25000L)
  say("  cascade: %.0f s", proc.time()[["elapsed"]] - t1)

  st <- as.data.table(lnk$status)
  st[, ein9 := .pf_ein(ein)]
  # provenance of the winning reference row, when the reference carries it
  if (!is.null(ref$reference$row_source)) {
    i <- match(st$ein9, .pf_ein(ref$reference$.ein))
    st[, row_source := ref$reference$row_source[i]]
  } else st[, row_source := NA_character_]
  res[[nm]] <- st
  saveRDS(st, file.path(PF, "data-dev", sprintf("CMP-STATUS-%s-%s.rds", nm, SET)))
  rm(ref, lnk); invisible(gc())
}

## ---- compare -----------------------------------------------------------------
hr(); say("1. TIER MOVEMENT"); hr()
tiers <- rbindlist(lapply(names(res), function(nm) {
  s <- res[[nm]]
  data.table(config = nm, tier = factor(s$status, pf_status_levels()))[, .N, by = .(config, tier)]
}))
print(dcast(tiers, tier ~ config, value.var = "N", fill = 0L))

base <- names(res)[1]
for (nm in names(res)[-1]) {
  hr(); say("2. %s vs %s", toupper(nm), toupper(base)); hr()
  m <- merge(res[[base]][, .(grant_id, s0 = status, e0 = ein9)],
             res[[nm]][, .(grant_id, s1 = status, e1 = ein9, src = row_source)],
             by = "grant_id")
  say("  tier transitions (rows = before, cols = after):")
  print(table(before = m$s0, after = m$s1))
  say("")
  yes0 <- m[s0 == "YES" & !is.na(e0)]
  say("  YES-ANSWER STABILITY  (harm check)")
  say("    previously YES            : %s", format(nrow(yes0), big.mark = ","))
  say("    still YES, same EIN       : %s", format(yes0[s1 == "YES" & e1 == e0, .N], big.mark = ","))
  say("    still YES, DIFFERENT EIN  : %s   <-- inspect each",
      format(yes0[s1 == "YES" & e1 != e0, .N], big.mark = ","))
  say("    no longer YES             : %s", format(yes0[s1 != "YES", .N], big.mark = ","))
  say("")
  say("  NO -> RESOLVED  (the gain)")
  conv <- m[s0 == "NO" & s1 %in% c("YES", "MAYBE")]
  say("    previously NO             : %s", format(m[s0 == "NO", .N], big.mark = ","))
  say("    now YES                   : %s", format(conv[s1 == "YES", .N], big.mark = ","))
  say("    now MAYBE                 : %s", format(conv[s1 == "MAYBE", .N], big.mark = ","))
  if (any(!is.na(conv$src))) {
    say("    by reference row source:")
    print(conv[, .N, by = .(src, s1)][order(-N)])
  }
}

hr(); say("3. ACCURACY ON THE %d ADJUDICATED ANSWERS", nrow(truth)); hr()
acc <- rbindlist(lapply(names(res), function(nm) {
  z <- merge(res[[nm]][, .(grant_id, ein9, status)], truth, by = "grant_id")
  data.table(config = nm, n = nrow(z),
             correct = sum(z$ein9 == z$correct_ein, na.rm = TRUE),
             pct = round(100 * mean(z$ein9 == z$correct_ein, na.rm = TRUE), 1))
}))
print(acc)

hr(); say("DONE -- per-run status saved to data-dev/CMP-STATUS-*-%s.rds", SET); hr()
