#!/usr/bin/env Rscript
# ============================================================================
# experiment-dictionary-curve.R -- does the dictionary pass get better with
# scale, and how fast?
#
# THE CLAIM BEING TESTED. At full scale the dictionary would be built from
# millions of cleared grants rather than the 369,260 of one triangulation run,
# so recovery should be far larger. The mechanism is right, but the gain cannot
# scale with raw volume: a case is recovered when an unresolved rendering
# matches a CLEARED rendering OF THE SAME ORGANISATION, so what matters is
# distinct renderings per organisation, not rows. Volume buys renderings with
# diminishing returns -- the tenth foundation to write "USO" adds nothing -- so
# the curve should bend. This measures where.
#
# DESIGN. One fixed query set, dictionaries of increasing size, everything else
# held constant.
#
#   queries     the benchmark rows BASELINE-2026-10C left unresolved against
#               the full BMF reference: 1,044 MAYBE + 725 NO.
#   dictionary  a random share of the 369,260 cleared rows of the triangulation
#               run, at 2%, 5%, 10%, 25%, 50% and 100%. Same seed, nested
#               samples, so each size is a superset of the one below and the
#               curve is not a sampling artifact.
#   reported    dictionary YES on the unresolved set, and how many of those
#               agree with the BMF's own top candidate -- the only ones
#               pf_recover_from_dictionary(accept = "agree") would adopt.
#
# Each point is a dictionary build plus 1,769 queries against a small
# reference: about a minute. The whole curve is cheaper than one BMF arm.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(library(npmatch)))
setDTthreads(0)
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) message(sprintf(...)); hr <- function() message(strrep("=", 84))
nf  <- function(x) format(x, big.mark = ",")
sq  <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; x }
e9  <- function(v) { v <- gsub("[^0-9]", "", as.character(v))
                     ifelse(nchar(v) == 9L, v, NA_character_) }
SEED  <- as.integer(Sys.getenv("PF_CURVE_SEED", "20261031"))
SHARE <- as.numeric(strsplit(Sys.getenv("PF_CURVE_SHARES",
                                        "0.02,0.05,0.10,0.25,0.50,1.00"), ",")[[1]])

hr(); say("experiment-dictionary-curve   %s", format(Sys.time())); hr()

## ---- the fixed query set ---------------------------------------------------
b <- as.data.table(readRDS(file.path(PF, "dev", "BASELINE-2026-10C",
                                     "benchmark-1k-augmented.rds")))
b[, bmf_ein := e9(overall_ein)]
unresolved <- b[tier != "YES", .(.id, bmf_tier = tier, bmf_ein)]
say("queries: %s unresolved benchmark rows (%s MAYBE, %s NO)",
    nf(nrow(unresolved)), nf(sum(unresolved$bmf_tier == "MAYBE")),
    nf(sum(unresolved$bmf_tier == "NO")))

grants <- pf_read_grants(file.path(PF, "inputs"),
                         pattern = "^efv2_1k_grants_.*[.]csv$")
grants <- pf_recover_name_from_street(grants)
bkey <- unique(paste(sq(grants$OBJECTID), sq(grants$TABLE_ID), sep = "|"))

## ---- the pool the dictionary is drawn from ---------------------------------
g <- as.data.table(readRDS(file.path(PF, "data-dev", "TRI-V2-MATCH.rds"))$grants)
g[, gkey := paste(sq(OBJECTID), sq(TABLE_ID), sep = "|")]
pool <- g[status == "YES" & !is.na(ein) & nzchar(sq(ein)) & !(gkey %chin% bkey)]
say("pool: %s cleared rows over %s EINs", nf(nrow(pool)), nf(uniqueN(e9(pool$ein))))

# Nested samples: order once, then take prefixes. Each size contains the one
# below it, so a difference between points is scale and not a different draw.
set.seed(SEED)
ord <- sample.int(nrow(pool))
PASSES <- c(pf_staged_passes("lean", concat = TRUE),
            pf_recovery_passes(state = TRUE))

rows <- list()
for (sh in SHARE) {
  n <- max(1L, as.integer(round(sh * nrow(pool))))
  sub <- pool[ord[seq_len(n)]]
  hr(); say("share %.0f%%  -- %s cleared rows", 100 * sh, nf(n))
  d <- tryCatch(pf_grant_dictionary(sub, verbose = FALSE),
                error = function(e) e)
  if (inherits(d, "error")) { say("  dictionary failed: %s", conditionMessage(d)); next }
  t0 <- proc.time()[["elapsed"]]
  m <- pf_match_grants(grants, d, passes = PASSES, recover = TRUE,
                       verbose = FALSE, check_reference = "ignore")
  el <- proc.time()[["elapsed"]] - t0
  s <- as.data.table(as.data.frame(m$result))
  s <- s[, .(.id, dict_tier = tier, dict_ein = e9(overall_ein))]
  j <- merge(unresolved, s, by = ".id", all.x = TRUE)
  yes <- j[!is.na(dict_tier) & dict_tier == "YES"]
  agree <- yes[!is.na(bmf_ein) & dict_ein == bmf_ein]
  rows[[length(rows) + 1L]] <- data.table(
    share = sh, rows = n,
    renderings = attr(d, "n_renderings"), eins = attr(d, "n_eins"),
    ambiguous_dropped = attr(d, "ambiguous_dropped"),
    dict_yes = nrow(yes), agreeing = nrow(agree),
    pts_agree = round(100 * nrow(agree) / nrow(b), 3),
    pts_all = round(100 * nrow(yes) / nrow(b), 3),
    secs = round(el, 1))
  say("  renderings %s  EINs %s  ->  dict YES %s, agreeing %s  (%.1f s)",
      nf(attr(d, "n_renderings")), nf(attr(d, "n_eins")), nf(nrow(yes)),
      nf(nrow(agree)), el)
  rm(d, m, s, j); invisible(gc())
}

r <- rbindlist(rows)
hr(); say("THE CURVE  (clear-rate points are over the benchmark's %s rows)", nf(nrow(b)))
print(r, row.names = FALSE)

## ---- does it bend? ---------------------------------------------------------
if (nrow(r) >= 3) {
  hr(); say("MARGINAL RETURN")
  r[, d_rows := rows - shift(rows)]
  r[, d_agree := agreeing - shift(agreeing)]
  r[, per_100k := round(1e5 * d_agree / d_rows, 2)]
  print(r[-1, .(share, rows, agreeing, d_rows, d_agree,
                agreeing_per_100k_new_rows = per_100k)], row.names = FALSE)
  say("")
  say("A flat `agreeing_per_100k_new_rows` means linear scaling; a falling one")
  say("means saturation, and the shape is what decides whether a full-scale")
  say("dictionary is worth building for recall rather than for coverage.")
  # renderings per EIN is the quantity the mechanism actually depends on
  r[, rend_per_ein := round(renderings / eins, 3)]
  say("")
  say("renderings per EIN by size -- the quantity recovery depends on:")
  print(r[, .(share, rows, eins, renderings, rend_per_ein)], row.names = FALSE)
}
out <- file.path(PF, "data-dev", "EXP-DICT-CURVE.rds")
saveRDS(r, out, compress = FALSE)
say(""); say("wrote %s", out)
hr(); say("done  %s", format(Sys.time()))
