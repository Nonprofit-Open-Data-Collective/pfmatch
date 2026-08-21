#!/usr/bin/env Rscript
# ============================================================================
# Can a YES be flagged as "might have a sibling" without consulting the big
# reference?
#
# The tiered proposal only works if an early YES can be banked safely. Measured
# on 1,000 queries, 16 of 569 small-reference YES decisions (2.8%) get a
# DIFFERENT EIN from the big reference, and they are overwhelmingly arm/operating
# pairs: the small BMF lacks the sibling, so the cascade never sees the contest.
#
# A flag rescues the design if it catches those 16 while flagging few of the
# 553 that were fine. It must be computable from the SMALL run alone -- a flag
# that needs the big reference has already paid the cost it was meant to avoid.
#
# Four candidates, all cheap:
#
#   arm_name   pf_is_arm() on the winning candidate's name
#   sibling    the winning EIN appears in ANY substitutable dyad. This is the
#              direct test, and the dyad table is a hash lookup -- it does not
#              need the reference at all.
#   promo      the win sits exactly on the promotion floor (0.90), i.e. it was
#              carried by distinctive-name promotion rather than by evidence
#              rare       name_freq <= 3 in the small reference
#
# Output: data-dev/YES-CAUTION-FLAG.csv
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() cat(strrep("=", 78), "\n")
sb  <- function() cat(strrep("-", 78), "\n")

cmp <- fread(file.path(PF, "data-dev", "TIERED-REFERENCE.csv"),
             colClasses = list(character = c("e_s", "e_b")))
D   <- readRDS(file.path(PF, "data-dev", "PF-DYADS-UNIFIED.rds"))
S   <- D[dyad_class == "substitutable"]
sib_eins <- unique(c(S$ein_a, S$ein_b))

y <- cmp[t_s == "YES"]
y[, risky := !is.na(e_b) & !is.na(e_s) & e_b != e_s]
say("YES on the small reference: %d, of which risky: %d (%.1f%%)",
    nrow(y), sum(y$risky), 100*mean(y$risky))

## ------------------------------------------------------------------ flags
y[, arm_name := pf_is_arm(n_s)]
y[, sibling  := e_s %chin% sib_eins]
y[, promo    := !is.na(sc_s) & abs(sc_s - 0.90) < 1e-6]
y[, rare     := !is.na(nf_s) & nf_s <= 3]

ev <- function(flag, label) {
  f <- y[[flag]]; f[is.na(f)] <- FALSE
  tp <- sum(f & y$risky); fn <- sum(!f & y$risky)
  fp <- sum(f & !y$risky); tn <- sum(!f & !y$risky)
  say("%-34s caught %2d/%2d (%3.0f%%)  flagged %3d of %3d safe (%4.1f%%)  escalates %3d (%4.1f%%)",
      label, tp, tp + fn, 100*tp/max(tp+fn,1), fp, fp+tn, 100*fp/max(fp+tn,1),
      tp+fp, 100*(tp+fp)/nrow(y))
  invisible(c(tp = tp, fn = fn, fp = fp, tn = tn))
}

hr(); say("SINGLE FLAGS"); hr()
say("%-34s %-22s %-28s %s", "flag", "risky caught", "safe wrongly flagged", "total escalated")
sb()
ev("arm_name", "arm_name  (name has a suffix)")
ev("sibling",  "sibling   (EIN in a subst. dyad)")
ev("promo",    "promo     (score exactly 0.90)")
ev("rare",     "rare      (name_freq <= 3)")

hr(); say("COMBINATIONS"); hr()
y[, f_arm_sib  := arm_name | sibling]
y[, f_sib_pro  := sibling | promo]
y[, f_all3     := arm_name | sibling | promo]
ev("f_arm_sib", "arm_name OR sibling")
ev("f_sib_pro", "sibling OR promo")
ev("f_all3",    "arm_name OR sibling OR promo")

hr(); say("WHAT THE `sibling` FLAG MISSES"); hr()
miss <- y[risky == TRUE & sibling == FALSE]
say("risky YES with no substitutable dyad on the winning EIN: %d", nrow(miss))
if (nrow(miss)) print(miss[, .(.id, small = substr(n_s,1,34), big = substr(n_b,1,34),
                               arm_name, promo)], row.names = FALSE)

hr(); say("THE COST OF THE BEST FLAG"); hr()
best <- y$f_all3; best[is.na(best)] <- FALSE
say("escalating flagged YES adds %d of %d queries (%.1f%%) to the big-reference pass.",
    sum(best), nrow(y), 100*mean(best))
say("")
say("Runtime arithmetic, using the measured 128 vs 279 s per 1,000 identities:")
n_small <- nrow(cmp); n_esc <- nrow(cmp[t_s != "YES"]) + sum(best)
say("  single pass, big reference only : %6.0f s per 1,000", 279)
say("  tiered: all through small       : %6.0f s", 128)
say("          %d%% escalated to big     : %6.0f s", round(100*n_esc/n_small),
    279 * n_esc / n_small)
say("          total                   : %6.0f s per 1,000  (%.0f%% of single-pass)",
    128 + 279 * n_esc / n_small, 100*(128 + 279*n_esc/n_small)/279)

fwrite(y, file.path(PF, "data-dev", "YES-CAUTION-FLAG.csv"))
say(""); say("wrote data-dev/YES-CAUTION-FLAG.csv")
