#!/usr/bin/env Rscript
# ============================================================================
# Why does a pair with a matching city not get city credit?
#
# Arithmetic on the recorded scores says these cases were scored with STATE
# credit only (0.20) when the reference plainly holds a row in the filed city,
# which should earn 0.50. Salvation Army scored 0.6017 = 0.6(0.8695) + 0.4(0.20)
# exactly. That is a discrepancy between the evidence available and the evidence
# used, and guessing at it has already cost two wrong hypotheses this session
# (missing payee addresses -- refuted, 99.8% city coverage; the JW 0.85 floor --
# refuted, these names score 0.86-0.91).
#
# So instrument it: take the ACTUAL candidate pairs for the adjudicated EINs,
# run the real np_compare() and print every geo input to .np_hier_score()
# alongside the reconstructed score. No inference, just the columns.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(devtools::load_all(
  Sys.getenv("NPMATCH_DIR", "../npmatch"), quiet = TRUE)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
setDTthreads(4L)
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("-", 96))
sq  <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; x }
e9  <- function(z) { z <- gsub("[^0-9]", "", as.character(z))
                     fifelse(nchar(z) == 9L, z, NA_character_) }

R <- readRDS(file.path(PF, "data-dev", "NO-RESIDUAL-REPLAY-CANDS.rds"))
cs <- as.data.table(R$cs); tgt_rows <- R$tgt_rows

FOCUS <- c("G002181", "G001170", "G000907", "G002810", "G004596", "G001935")
cs <- cs[id %in% FOCUS]
say("tracing %d cases", nrow(cs))

q <- data.frame(name = cs$recip_name, dba = "", division = "",
                street = cs$recip_street, city = cs$recip_city,
                state = cs$recip_state, zip5 = cs$recip_zip5, zip_plus4 = "",
                stringsAsFactors = FALSE)
q <- np_normalize(q); q$.id <- cs$id

prof <- np_detect_geo(q)
say("detected geo profile: %s  [fields: %s]", as.character(prof),
    paste(attr(prof, "fields"), collapse = ", "))
say("query coverage: %s", paste(sprintf("%s=%.2f", names(attr(prof, "coverage")),
    attr(prof, "coverage")), collapse = "  "))

ref <- pf_reference(file.path(PF, "data-dev",
        "BMF-AUGMENTED-bmf_unified_geocoded_2026-08-20.csv"),
        cache = file.path(PF, "data-dev", "BMF-REF-AUG-2026-08-20.rds"),
        verbose = FALSE)$reference

# every reference row for each focus EIN -- the full candidate set the scorer
# could have chosen from, not just the one it picked
rows <- sort(unique(unlist(tgt_rows[cs$id])))
say("reference rows for these EINs: %d", length(rows))
sub <- ref[rows, , drop = FALSE]

cand <- data.frame(
  .x = rep(seq_len(nrow(q)), each = nrow(sub)),
  .y = rep(seq_len(nrow(sub)), times = nrow(q)))
keep <- vapply(seq_len(nrow(cand)), function(i)
  rows[cand$.y[i]] %in% tgt_rows[[cs$id[cand$.x[i]]]], NA)
cand <- cand[keep, , drop = FALSE]
say("pairs to score: %d", nrow(cand))

cmp <- np_compare(q, sub, candidates = cand, profile = as.character(prof))
cfg <- np_config()
cmp <- np_score(cmp, cfg, method = "hier")   # returns the frame, not a vector

gw <- cfg$geo_weights
d <- as.data.table(cmp)
d[, qid := q$.id[.x]]
z <- function(v) { v <- as.numeric(v); v[is.na(v)] <- 0; v }
d[, city_sim_raw := z(city)]
d[, nm := z(name_key)]

hr()
say("EVERY GEO INPUT, PER PAIR")
hr()
for (cid in FOCUS) {
  x <- d[qid == cid]
  if (!nrow(x)) next
  say("")
  say("== %s  filed: %s | %s %s %s", cid,
      substr(cs[id == cid]$recip_name, 1, 30), cs[id == cid]$recip_city,
      cs[id == cid]$recip_state, cs[id == cid]$recip_zip5)
  setorder(x, -score)
  n <- min(5L, nrow(x))
  say("   %-32s %-14s %-3s %5s %5s %4s %4s %4s %4s %6s",
      "reference name", "ref city", "st", "name", "city", "z5", "z3", "stn", "stt", "score")
  for (i in seq_len(n))
    say("   %-32s %-14s %-3s %5.2f %5.2f %4d %4d %4d %4d %6.3f",
        substr(sq(x$name_y[i]), 1, 32), substr(sq(x$city_y[i]), 1, 14),
        sq(x$state_y[i]), x$nm[i], x$city_sim_raw[i],
        as.integer(x$geo_zip5[i]), as.integer(x$geo_zip3[i]),
        as.integer(x$geo_stnum[i]), as.integer(x$geo_state[i]), x$score[i])
}
hr()
say("city column is JW, FLOORED AT %.2f inside .np_hier_score(); a city_sim", cfg$jw_threshold)
say("printed above as 0.00 contributed nothing even if the names look alike.")
fwrite(d[, .(qid, name_y, city_x, city_y, state_x, state_y, nm,
             city_sim_raw, geo_zip5, geo_zip3, geo_stnum, geo_state, score)],
       file.path(PF, "data-dev", "GEO-CREDIT-TRACE.csv"))
say("wrote data-dev/GEO-CREDIT-TRACE.csv")
