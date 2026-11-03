#!/usr/bin/env Rscript
# ============================================================================
# score-shadow-labeler.R -- can a cheap model produce this round's truth?
#
# THE QUESTION, AND WHY IT IS NOT THE ROUND'S QUESTION. The round grades four
# ARMS against truth; claude-haiku-5-5 is already one of them (the light arm),
# so "how does a small model adjudicate" is answered there and not here. This
# asks something the round cannot: how far a cheap model agrees with the
# expensive one when both are doing the LABELER's job -- whole web, whole
# reference, no candidate packet. That matters because stage 2 is ~600 more
# cases and truth is the half of the round that does not scale.
#
# WHAT IT MEASURES, SAID ONCE AND PLAINLY. Agreement with fable, not accuracy.
# Both labelers are models; where they agree they can be wrong together, and
# nothing here can see that. TRUTH-LABELING-PROTOCOL.md section 6 step 4 -- a
# hand-labelled slice scored with pf_grade_verdicts() -- is still the only
# thing that converts either figure into an error rate. So a high number here
# licenses "haiku can stand in for fable", and specifically NOT "haiku is
# right".
#
# WHY pf_labeler_agreement() AND NOT NEW ARITHMETIC. Stacking the two files
# gives every case two labelers, which is the shape that function already
# takes, and it carries the strict/effective distinction (strict counts the
# NO_ORG reason, effective collapses the three of them) plus Wilson intervals
# and the per-labeler cut. Writing a second agreement statistic here would be
# a second definition of agreement in the same repository.
#
# The shard is read WITHOUT the key on purpose: a shadow labeler is not on the
# key's roster, and pf_read_truth() refuses an unrostered name -- correctly,
# since that check exists so a real shard cannot come back misattributed.
#
# USAGE  PF_LABEL_SHARD=1 Rscript dev/score-shadow-labeler.R
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
DD  <- file.path(PF, "data-dev")
DIR <- file.path(DD, "round-stage1-labelled")

SHARD  <- as.integer(Sys.getenv("PF_LABEL_SHARD", "1"))
REF    <- Sys.getenv("PF_LABEL_REF",    "claude-fable-5-1")
SHADOW <- Sys.getenv("PF_LABEL_SHADOW", "claude-haiku-5-5")

say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() cat(strrep("=", 78), "\n")

pick <- function(tag) {
  f <- list.files(DIR, pattern = sprintf("^shard-%02d-truth-%s.*\\.csv$",
                                         SHARD, gsub("\\.", "\\\\.", tag)),
                  full.names = TRUE)
  f <- f[!grepl("-limit[0-9]+\\.csv$", f)]   # smoke-test output is not a shard
  if (!length(f))
    stop(sprintf("no full labelled file for `%s` in %s.\n  Run dev/label-shard.R first.",
                 tag, DIR), call. = FALSE)
  if (length(f) > 1L)
    stop(sprintf("%d files match `%s`: %s", length(f), tag,
                 paste(basename(f), collapse = ", ")), call. = FALSE)
  f[1L]
}

fr <- pick(REF); fs <- pick(SHADOW)
hr(); say("SHADOW LABELER vs REFERENCE LABELER  shard %02d", SHARD); hr()
say("reference: %s", basename(fr))
say("shadow:    %s", basename(fs))

a <- utils::read.csv(fr, colClasses = "character")
b <- utils::read.csv(fs, colClasses = "character")
both <- rbind(a, b)

# Read without the key, for the reason in the header.
v <- pf_read_truth(both, population = unique(a$population)[1L], verbose = TRUE)

## ---- agreement -------------------------------------------------------------
say("")
ag <- pf_labeler_agreement(v)
print(ag)

## ---- where they differ, and how -------------------------------------------
m <- merge(as.data.table(a)[, .(grant_id, v_ref = verdict, e_ref = correct_ein,
                                b_ref = basis, c_ref = confidence,
                                u_ref = source_url, n_ref = note)],
           as.data.table(b)[, .(grant_id, v_sh = verdict, e_sh = correct_ein,
                                b_sh = basis, c_sh = confidence,
                                u_sh = source_url, n_sh = note)],
           by = "grant_id")
scored <- m[nzchar(v_ref) & nzchar(v_sh)]
say("\n%d of %d cases carry a verdict from both", nrow(scored), nrow(m))

say("\nverdict agreement, reference (rows) against shadow (columns):")
print(table(reference = scored$v_ref, shadow = scored$v_sh))

found <- scored[v_ref == "ORG_FOUND" & v_sh == "ORG_FOUND"]
if (nrow(found)) {
  same <- found[e_ref == e_sh]
  w <- pf_wilson(nrow(same), nrow(found))
  say("\nboth said ORG_FOUND on %d cases; same EIN on %d = %.1f%% [%.1f, %.1f]",
      nrow(found), nrow(same), 100 * nrow(same) / nrow(found),
      100 * w[1, "lo"], 100 * w[1, "hi"])
}

# The cheap labeler declining is a different failure from the cheap labeler
# being wrong, and it is the one that decides whether it can carry stage 2:
# an UNRESOLVED or UNFINDABLE row costs a re-label by the expensive model,
# which is a known price, while a confidently wrong row is not.
say("\nwhat each labeler did with the cases the other settled:")
say("  reference ORG_FOUND, shadow did not resolve: %d",
    nrow(scored[v_ref == "ORG_FOUND" & v_sh %in% c("UNRESOLVED", "NO_ORG_UNFINDABLE")]))
say("  shadow ORG_FOUND, reference did not resolve: %d",
    nrow(scored[v_sh == "ORG_FOUND" & v_ref %in% c("UNRESOLVED", "NO_ORG_UNFINDABLE")]))

say("\nsourcing: basis=web with a url -- reference %d/%d, shadow %d/%d",
    sum(scored$b_ref == "web" & nzchar(scored$u_ref)), nrow(scored),
    sum(scored$b_sh == "web" & nzchar(scored$u_sh)), nrow(scored))
say("confidence: reference %s | shadow %s",
    paste(sprintf("%s=%d", names(table(scored$c_ref)), table(scored$c_ref)),
          collapse = " "),
    paste(sprintf("%s=%d", names(table(scored$c_sh)), table(scored$c_sh)),
          collapse = " "))

# Does the cheap labeler know when it is off-reference? If its disagreements
# are concentrated in its own low-confidence rows, a confidence gate makes it
# usable at a known cost. If they are spread evenly, the gate buys nothing --
# which is T3's question asked of a labeler rather than an arm.
say("\nshadow's agreement with the reference, by the SHADOW's own confidence:")
scored[, agree := v_ref == v_sh & e_ref == e_sh]
for (cf in c("high", "medium", "low")) {
  z <- scored[c_sh == cf]
  if (!nrow(z)) next
  w <- pf_wilson(sum(z$agree), nrow(z))
  say("  %-6s %2d/%2d = %5.1f%% [%.1f, %.1f]%s", cf, sum(z$agree), nrow(z),
      100 * mean(z$agree), 100 * w[1, "lo"], 100 * w[1, "hi"],
      if (nrow(z) < 20L) "   (n < 20: not usable on its own)" else "")
}

dis <- scored[agree == FALSE]
if (nrow(dis)) {
  say("\n%d disagreement%s, every one listed so they can be read:",
      nrow(dis), if (nrow(dis) == 1L) "" else "s")
  for (k in seq_len(nrow(dis))) {
    say("\n  %s", dis$grant_id[k])
    say("    reference: %s %s (%s/%s)", dis$v_ref[k], dis$e_ref[k],
        dis$b_ref[k], dis$c_ref[k])
    say("       %s", substr(dis$n_ref[k], 1, 150))
    say("    shadow:    %s %s (%s/%s)", dis$v_sh[k], dis$e_sh[k],
        dis$b_sh[k], dis$c_sh[k])
    say("       %s", substr(dis$n_sh[k], 1, 150))
  }
}

hr()
say("AGREEMENT IS NOT ACCURACY. Both labelers are models and can be wrong")
say("together; this cannot see that. A high figure says the cheap labeler can")
say("stand in for the expensive one, not that either is right. What converts")
say("it is the hand-labelled slice (TRUTH-LABELING-PROTOCOL.md section 6.4).")
hr()
