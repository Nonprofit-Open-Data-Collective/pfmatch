#!/usr/bin/env Rscript
# ============================================================================
# build-audit-samples.R -- three 100-case samples for manual audit
#
#   AUDIT-NO-100.csv     no candidate accepted: is the org real, and why did we
#                        surface nothing? Includes a direct BMF name probe.
#   AUDIT-OOS-100.csv    out-of-sample: is the scope flag right?
#   AUDIT-MAYBE-100.csv  candidate-level, enriched with NTEE / activity-code
#                        mission proxies for BOTH the recipient candidates and
#                        the filing foundation, plus the grant purpose.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
NPM <- Sys.getenv("NPMATCH_DIR", "../npmatch")
BMF_CSV <- file.path(NPM, "data-raw", "bmf_2026_01_processed.csv")
SEED <- 2026

say <- function(...) cat(sprintf(...), "\n")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))

m  <- readRDS(file.path(PF, "data-dev", "PF-MATCH-RESULT-1k.rds"))
st <- pf_status(m)
say("loaded match result: %d grants", nrow(st))

say("building BMF context table ...")
ctx <- pf_bmf_context(BMF_CSV)
say("  %d EINs with context", nrow(ctx))

set.seed(SEED)
pick <- function(s, n = 100) {
  ids <- st$grant_id[st$status == s]
  sort(sample(ids, min(n, length(ids))))
}
no_ids <- pick("NO"); oos_ids <- pick("OOS"); maybe_ids <- pick("MAYBE")

# ---------------------------------------------------------------- NO sample --
# The diagnostic question is "did the BMF contain a plausible row we failed to
# surface?", so probe the reference directly: normalized-name containment plus a
# same-state-and-city name similarity scan, neither of which the cascade uses.
say("probing the BMF for the %d NO cases ...", length(no_ids))
ref <- readRDS(file.path(PF, "data-dev", "BMF-REFERENCE-BUNDLE.rds"))$reference
rk  <- ref$name_key; rk[is.na(rk)] <- ""
ref_state <- ref$state; ref_city <- ref$city

g <- m$grants
gi <- match(no_ids, g$grant_id)
qn <- npmatch::np_normalize(npmatch::np_query(g[gi, , drop = FALSE], pf_map_grants()))

probe <- rbindlist(lapply(seq_along(no_ids), function(i) {
  key <- qn$name_key[i]
  if (is.na(key) || !nzchar(key)) return(data.table(grant_id = no_ids[i]))
  # (a) exact containment either direction, anywhere in the BMF
  hit <- which(rk == key)
  mode <- if (length(hit)) "exact" else NA_character_
  if (!length(hit)) {
    sub <- grepl(key, rk, fixed = TRUE) | (nchar(key) > 8 & startsWith(rk, key))
    hit <- which(sub); if (length(hit)) mode <- "containment"
  }
  # (b) closest name in the same city+state (catches word-order / abbreviation)
  if (!length(hit) && !is.na(qn$state[i]) && !is.na(qn$city[i])) {
    loc <- which(ref_state == qn$state[i] & ref_city == qn$city[i])
    if (length(loc)) {
      d <- stringdist::stringdist(key, rk[loc], method = "jw", p = 0.1)
      best <- loc[order(d)][1:min(3, length(loc))]
      if (min(d, na.rm = TRUE) < 0.25) { hit <- best; mode <- "same-city-fuzzy" }
    }
  }
  if (!length(hit)) return(data.table(grant_id = no_ids[i], probe_mode = "none"))
  hit <- hit[1:min(3, length(hit))]
  data.table(grant_id = no_ids[i], probe_mode = mode,
             probe_ein = paste(ref$.ein[hit], collapse = " | "),
             probe_name = paste(ref$name[hit], collapse = " | "),
             probe_city = paste(ref$city[hit], collapse = " | "),
             probe_state = paste(ref$state[hit], collapse = " | "))
}), fill = TRUE)

no_out <- as.data.table(st[match(no_ids, st$grant_id),
  c("grant_id", "filer_ein", "filer_name", "recip_name", "recip_name_alt",
    "recip_city", "recip_state", "recip_zip5", "status_raw", "recipient_type",
    "looks_personal", "ein", "bmf_name", "bmf_city", "bmf_state", "score",
    "name_sim", "match_pass")])
setnames(no_out, c("ein", "bmf_name", "bmf_city", "bmf_state", "score", "name_sim"),
         c("best_ein", "best_bmf_name", "best_bmf_city", "best_bmf_state",
           "best_score", "best_name_sim"))
no_out[, recip_street := g$recip_street[match(grant_id, g$grant_id)]]
no_out[, grant_purpose := g$SIGOCPYPOGOC[match(grant_id, g$grant_id)]]
no_out[, name_key := qn$name_key[match(grant_id, no_ids)]]
no_out <- merge(no_out, probe, by = "grant_id", all.x = TRUE)
no_out[, verdict := ""][, verdict_note := ""]
fwrite(no_out, file.path(PF, "data-dev", "AUDIT-NO-100.csv"), na = "")
say("  wrote AUDIT-NO-100.csv | probe modes: %s",
    paste(sprintf("%s=%d", names(table(no_out$probe_mode, useNA = "ifany")),
                  table(no_out$probe_mode, useNA = "ifany")), collapse = " "))

# --------------------------------------------------------------- OOS sample --
oos_out <- as.data.table(st[match(oos_ids, st$grant_id),
  c("grant_id", "filer_ein", "filer_name", "recip_name", "recip_city",
    "recip_state", "recip_zip5", "status_raw", "recipient_type",
    "recipient_type_detail", "looks_personal", "oos_reason")])
oos_out[, recip_street := g$recip_street[match(grant_id, g$grant_id)]]
oos_out[, recip_name_l2 := g$recip_name_l2[match(grant_id, g$grant_id)]]
oos_out[, grant_purpose := g$SIGOCPYPOGOC[match(grant_id, g$grant_id)]]
oos_out[, grant_amount := g$SIGOCPYAMOUN[match(grant_id, g$grant_id)]]
oos_out[, verdict := ""][, verdict_note := ""]
fwrite(oos_out, file.path(PF, "data-dev", "AUDIT-OOS-100.csv"), na = "")
say("  wrote AUDIT-OOS-100.csv | reasons: %s",
    paste(sprintf("%s=%d", names(table(oos_out$oos_reason)),
                  table(oos_out$oos_reason)), collapse = " "))

# ------------------------------------------------------------- MAYBE sample --
say("building enriched candidate frame for %d MAYBE cases ...", length(maybe_ids))
cand <- pf_candidate_frame(m, ids = maybe_ids, k = 5, bmf_context = ctx)
cand$verdict <- ""; cand$verdict_note <- ""
fwrite(cand, file.path(PF, "data-dev", "AUDIT-MAYBE-100.csv"), na = "")
say("  wrote AUDIT-MAYBE-100.csv | %d candidate rows over %d grants (%.1f per grant)",
    nrow(cand), length(unique(cand$grant_id)), nrow(cand) / length(unique(cand$grant_id)))
