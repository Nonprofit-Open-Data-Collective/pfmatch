#!/usr/bin/env Rscript
# ============================================================================
# Extract real cascade examples for the workflow vignette.
#
# The vignette must show, per pass, cases that CLEAR and cases that are carried
# forward. Inventing those would be worse than useless -- the whole point is
# that the hard cases are not what one would guess. So they are pulled from an
# actual run: data-dev/BENCH-EFILEPF-augmented.rds, which carries the `pass`
# column (where the winning candidate was generated) plus the per-stage report.
#
# ONE SUBTLETY the vignette has to state. `pass` records where the CHOSEN
# candidate was first generated, not where the case was decided. np_cascade()
# drops a query from `pending` only when it reaches YES; MAYBE and NO keep going,
# later passes add more candidates, and the final tier is recomputed over the
# UNION of everything. So "A1 / MAYBE" means the winning candidate came from the
# tightest pass and still did not clear.
#
# Writes data-dev/VIGNETTE-EXAMPLES.rds -- small, so the vignette needs no
# 3.9M-row reference and no cascade run at build time.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
PF  <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("-", 86))
sq  <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; x }

res <- readRDS(file.path(PF, "data-dev", "BENCH-EFILEPF-augmented.rds"))
stages <- as.data.table(attr(res, "stages"))
r <- as.data.table(res)
say("run: %s identities, %d passes reported", format(nrow(r), big.mark = ","), nrow(stages))

g <- as.data.table(pf_prepare_grants(pf_recover_name_from_street(
  pf_read_grants(file.path(PF, "inputs"), pattern = "^ef1k_grants_.*\\.csv$"))))
gk <- g[, .(.id = grant_id, recip_name, recip_city, recip_state, recip_zip5,
            purpose = SIGOCPYPOGOC, amount = SIGOCPYAMOUN, taxyear = TAXYEAR)]
r <- merge(r, gk, by = ".id", all.x = TRUE)

r[, score := suppressWarnings(as.numeric(overall_score))]
r[, runner := suppressWarnings(as.numeric(runner_up_score))]
r[, margin := fifelse(is.na(runner), score, score - runner)]
r[, name_sim := suppressWarnings(as.numeric(overall_name_sim))]

hr(); say("TIER BY PASS (pass = where the winning candidate was generated)"); hr()
print(dcast(r[, .N, by = .(pass, tier)], pass ~ tier, value.var = "N", fill = 0),
      row.names = FALSE)

## ---- pick examples ---------------------------------------------------------
# regular: a clear case -- high score AND a decisive margin
# hard:    cleared, but only just -- the smallest margin that still reached YES
# carried: the winning candidate came from this pass and the case still did not
#          clear, so later passes kept adding candidates
pick <- function(dt, n = 1L) {
  if (!nrow(dt)) return(dt[0])
  dt[1:min(n, nrow(dt))]
}
cols <- c(".id", "pass", "tier", "recip_name", "recip_city", "recip_state",
          "recip_zip5", "overall_ein", "overall_name_y", "score", "margin",
          "name_sim", "purpose", "amount")

out <- list()
for (p in unique(stats::na.omit(r$pass))) {
  z <- r[pass == p]
  yes <- z[tier == "YES"]
  reg <- pick(yes[order(-margin, -score)])           # most decisive
  hrd <- pick(yes[order(margin, score)])             # only just cleared
  car <- pick(z[tier != "YES"][order(-score)], 2L)   # carried forward
  if (nrow(reg)) out[[length(out) + 1L]] <-
    cbind(role = "clears (regular)", reg[, ..cols])
  if (nrow(hrd) && !identical(hrd$.id, reg$.id)) out[[length(out) + 1L]] <-
    cbind(role = "clears (hard)", hrd[, ..cols])
  if (nrow(car)) out[[length(out) + 1L]] <-
    cbind(role = "carried forward", car[, ..cols])
}
ex <- rbindlist(out, fill = TRUE)
setorder(ex, pass, role)

hr(); say("EXAMPLES SELECTED: %d", nrow(ex)); hr()
say("%-8s %-17s %-6s %-32s %-30s %6s %6s", "pass", "role", "tier",
    "filed name", "matched BMF name", "score", "margin")
for (i in seq_len(nrow(ex)))
  say("%-8s %-17s %-6s %-32s %-30s %6.3f %6.3f",
      substr(ex$pass[i], 1, 8), ex$role[i], ex$tier[i],
      substr(sq(ex$recip_name[i]), 1, 32), substr(sq(ex$overall_name_y[i]), 1, 30),
      ex$score[i], ex$margin[i])

saveRDS(list(stages = stages, examples = ex,
             tier_by_pass = dcast(r[, .N, by = .(pass, tier)], pass ~ tier,
                                  value.var = "N", fill = 0),
             totals = r[, .N, by = tier]),
        file.path(PF, "data-dev", "VIGNETTE-EXAMPLES.rds"))
hr()
say("wrote data-dev/VIGNETTE-EXAMPLES.rds")
