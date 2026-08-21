#!/usr/bin/env Rscript
# ============================================================================
# Would a tiered reference work? Cheap DB first, escalate the residue.
#
# The proposal: run every query against the small active BMF, bank the easy
# YES/NO, and send only MAYBE (and NO) to the larger unified/augmented
# reference. The cascade already does exactly this over PASSES -- a query
# resolved to YES leaves the pending set -- so extending it over REFERENCES is
# the same mechanism one level up.
#
# Two things decide whether it is sound, and both are measurable:
#
#   1. PAYOFF. Of the queries the small reference cannot settle, how many does
#      the big one settle? That is the escalation yield.
#
#   2. RISK. Of the queries the small reference DOES settle as YES, how many
#      does the big reference answer DIFFERENTLY? Early acceptance is only safe
#      if that number is near zero -- a YES banked against the active BMF is
#      never revisited, so any case where the true recipient is a legacy or
#      alias row is silently locked to the wrong EIN.
#
# Also measured: the name_freq shift. The distinctive-name promotion fires on
# `name_freq <= 3` counted IN THE REFERENCE. Doubling the reference makes rare
# names less rare, so a promotion that fires on the small DB may not fire on the
# large one. That is the one scoring term that is genuinely reference-dependent
# -- the base score (0.6*name + 0.4*geo) is not.
#
# Output: data-dev/TIERED-REFERENCE.csv
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(devtools::load_all(
  Sys.getenv("NPMATCH_DIR", "../npmatch"), quiet = TRUE)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
setDTthreads(0L)
say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() cat(strrep("=", 78), "\n")
sb  <- function() cat(strrep("-", 78), "\n")
e9 <- function(z) { z <- gsub("[^0-9]", "", as.character(z))
                    fifelse(nchar(z) == 9L, z, NA_character_) }
N <- as.integer(Sys.getenv("PF_N", "1000"))

g <- rbindlist(lapply(sprintf(file.path(PF, "inputs", "1k_grants_0%d.csv"), 1:5),
                      function(p) fread(p, colClasses = "character", showProgress = FALSE)),
               use.names = TRUE, fill = TRUE)
g[, grant_id := sprintf("G%06d", .I)]
prep <- pf_prepare(g, dedup = "fuzzy", verbose = FALSE)
q <- as.data.frame(prep$recipients)[seq_len(min(N, nrow(prep$recipients))), , drop = FALSE]
say("queries: %d", nrow(q))

REFS <- list(
  small = list(csv = file.path(PF, "..", "npmatch", "data-raw", "bmf_2026_01_processed.csv"),
               cache = file.path(PF, "data-dev", "REF-active.rds")),
  big   = list(csv = file.path(PF, "data-dev", "BMF-AUGMENTED-bmf_unified_geocoded_2026-08-20.csv"),
               cache = file.path(PF, "data-dev", "BMF-REF-AUG-2026-08-20.rds")))

run <- function(nm) {
  b <- pf_reference(REFS[[nm]]$csv, cache = REFS[[nm]]$cache, verbose = FALSE)
  t0 <- proc.time()[["elapsed"]]
  m <- pf_match_grants(q, b, passes = c(pf_staged_passes("lean"),
                                        pf_recovery_passes(state = TRUE)),
                       recover = TRUE, verbose = FALSE)
  el <- proc.time()[["elapsed"]] - t0
  r <- as.data.table(as.data.frame(m$result))
  pr <- as.data.table(as.data.frame(attr(m$result, "pairs")))
  # name_freq of the winning pair, for the promotion-shift question
  pr[, k := paste(.id, .ein)]
  nf <- pr[match(paste(r$.id, r$overall_ein), k), name_freq]
  out <- r[, .(.id, tier, ein = e9(overall_ein), score = overall_score,
               nm_y = overall_name_y, margin = overall_margin)]
  out[, name_freq := nf]
  say("  %-6s %s rows | %.0f s | YES %d MAYBE %d NO %d", nm,
      format(nrow(b$reference), big.mark = ","), el,
      sum(out$tier == "YES"), sum(out$tier == "MAYBE"), sum(out$tier == "NO"))
  rm(b, m, pr); invisible(gc())
  out
}

hr(); say("RUNNING BOTH REFERENCES ON THE SAME QUERIES"); hr()
S <- run("small"); B <- run("big")
cmp <- merge(S[, .(.id, t_s = tier, e_s = ein, sc_s = score, nf_s = name_freq, n_s = nm_y)],
             B[, .(.id, t_b = tier, e_b = ein, sc_b = score, nf_b = name_freq, n_b = nm_y)],
             by = ".id")

hr(); say("PAYOFF -- what does escalation actually buy?"); hr()
esc <- cmp[t_s != "YES"]
say("queries the SMALL reference did not settle as YES : %d", nrow(esc))
print(esc[, .N, by = .(small = t_s, big = t_b)][order(small, -N)], row.names = FALSE)
say("")
say("of those, the BIG reference settles as YES        : %d (%.0f%%)",
    sum(esc$t_b == "YES"), 100*mean(esc$t_b == "YES"))

hr(); say("RISK -- is an early YES safe to bank?"); hr()
yes_s <- cmp[t_s == "YES"]
say("YES on the small reference                        : %d", nrow(yes_s))
say("  big reference agrees on the SAME EIN            : %d (%.1f%%)",
    sum(yes_s$e_b == yes_s$e_s, na.rm = TRUE),
    100*mean(yes_s$e_b == yes_s$e_s, na.rm = TRUE))
say("  big reference picks a DIFFERENT EIN             : %d (%.1f%%)  <- the risk",
    sum(yes_s$e_b != yes_s$e_s, na.rm = TRUE),
    100*mean(yes_s$e_b != yes_s$e_s, na.rm = TRUE))
say("  ...and rates it YES there                       : %d",
    nrow(yes_s[e_b != e_s & t_b == "YES"]))
say("")
diff <- yes_s[e_b != e_s]
if (nrow(diff)) print(head(diff[, .(.id, small = substr(n_s,1,32), big = substr(n_b,1,32),
                                    sc_s = round(sc_s,2), sc_b = round(sc_b,2), t_b)], 20),
                      row.names = FALSE)

hr(); say("THE REFERENCE-DEPENDENT SCORING TERM"); hr()
say("The base score is 0.60*name + 0.40*geo and does NOT depend on the")
say("reference. Only the distinctive-name promotion does: it fires on")
say("name_freq <= %d counted in the reference.", npmatch::np_config()$distinct_name_maxfreq)
say("")
both <- cmp[!is.na(nf_s) & !is.na(nf_b)]
say("winning pairs with a name_freq on both sides      : %d", nrow(both))
say("  rare (<=3) on SMALL                             : %d", sum(both$nf_s <= 3))
say("  ...still rare on BIG                            : %d", sum(both$nf_s <= 3 & both$nf_b <= 3))
say("  ...NO LONGER rare on BIG                        : %d  <- promotion would differ",
    sum(both$nf_s <= 3 & both$nf_b > 3))
say("")
say("median name_freq of the winning pair: small %.0f, big %.0f",
    median(both$nf_s), median(both$nf_b))

fwrite(cmp, file.path(PF, "data-dev", "TIERED-REFERENCE.csv"))
say(""); say("wrote data-dev/TIERED-REFERENCE.csv")
