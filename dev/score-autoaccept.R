#!/usr/bin/env Rscript
# Score the 200 hand-labelled auto-accept candidates and test whether any
# sub-rule recovers acceptable precision.
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 78), "\n")

d <- fread(file.path(PF, "data-dev", "AUTOACCEPT-SAMPLE-200.csv"), colClasses = "character")
v <- fread(file.path(PF, "dev", "autoaccept-verdicts.csv"))
# the sample sheet ships empty verdict/note columns for labelling; drop them so
# the merge with the filled-in verdicts does not produce verdict.x / verdict.y
drop <- intersect(c("verdict", "note"), names(d))
if (length(drop)) d[, (drop) := NULL]
d[, idx := .I]
d <- merge(d, v, by = "idx")
num <- function(x) suppressWarnings(as.numeric(x))
d[, `:=`(score = num(score), name_sim = num(name_sim), margin = num(margin),
         n_band = as.integer(n_band))]

ci <- function(k, n) {
  if (n == 0) return("-")
  b <- stats::binom.test(k, n)$conf.int
  sprintf("%.0f-%.0f%%", 100 * b[1], 100 * b[2])
}

hr(); say("THE RULE AS PROPOSED: ZIP5 agrees AND margin >= 0.05"); hr()
tb <- table(factor(d$verdict, c("CORRECT", "AMBIGUOUS", "WRONG")))
for (k in names(tb)) say("  %-10s %3d (%.1f%%)", k, tb[[k]], 100 * tb[[k]] / nrow(d))
say("")
say("strict precision  (CORRECT / all)          : %.1f%%  95%% CI %s",
    100 * tb[["CORRECT"]] / nrow(d), ci(tb[["CORRECT"]], nrow(d)))
n_dec <- tb[["CORRECT"]] + tb[["WRONG"]]
say("lenient precision (CORRECT / decided)      : %.1f%%  95%% CI %s",
    100 * tb[["CORRECT"]] / n_dec, ci(tb[["CORRECT"]], n_dec))
say("")
say("The original estimate was 18/18 = 100%% on the first 100-case sample.")
say("On 200 fresh cases it is %.0f%%. The 18/18 was a small-sample artifact:",
    100 * tb[["CORRECT"]] / nrow(d))
say("18 successes gives a 95%% CI of 82-100%%, and the truth is near the bottom.")

hr(); say("WHY: PRECISION BY WHICH NAME VERSION MATCHED"); hr()
say("%-16s %6s %9s %9s %7s %12s", "name_ver", "n", "correct", "ambiguous", "wrong", "precision")
for (nv in unique(d$name_ver)) {
  s <- d[name_ver == nv]
  k <- sum(s$verdict == "CORRECT")
  say("%-16s %6d %9d %9d %7d %11.0f%%", nv, nrow(s), k,
      sum(s$verdict == "AMBIGUOUS"), sum(s$verdict == "WRONG"), 100 * k / nrow(s))
}
say("")
say("npmatch caps TOKEN_OVERLAP matches below YES on purpose -- containment")
say("cannot separate a parent from a chapter or an auxiliary. The rule was")
say("auto-accepting precisely the cases npmatch had already flagged as unsafe.")

hr(); say("CAN A TIGHTER RULE RECOVER PRECISION?"); hr()
say("%-46s %5s %8s %10s %12s", "rule", "fires", "correct", "precision", "95% CI")
rules <- list(
  "as proposed (ZIP5 & margin>=.05)"        = quote(rep(TRUE, .N)),
  "+ name_ver == MAIN"                      = quote(name_ver == "MAIN"),
  "+ MAIN & name_sim == 1"                  = quote(name_ver == "MAIN" & name_sim >= 0.999),
  "+ MAIN & margin >= 0.20"                 = quote(name_ver == "MAIN" & margin >= 0.20),
  "+ MAIN & name_sim==1 & margin>=0.20"     = quote(name_ver == "MAIN" & name_sim >= 0.999 & margin >= 0.20),
  "+ MAIN & no runner-up in band"           = quote(name_ver == "MAIN" & n_band == 1),
  "+ score >= 0.95"                         = quote(score >= 0.95),
  "+ score >= 0.95 & margin >= 0.20"        = quote(score >= 0.95 & margin >= 0.20)
)
for (nm in names(rules)) {
  f <- d[, eval(rules[[nm]])]; f[is.na(f)] <- FALSE
  n <- sum(f); k <- sum(f & d$verdict == "CORRECT")
  say("%-46s %5d %8d %9s %12s", nm, n, k,
      if (n) sprintf("%.0f%%", 100 * k / n) else "-", ci(k, n))
}

hr(); say("THE FOUNDATION-ARM TRAP"); hr()
arm <- d[grepl("foundation|its foundation", note, ignore.case = TRUE)]
say("cases turning on an entity-vs-its-foundation choice: %d", nrow(arm))
print(arm[, .N, by = verdict], row.names = FALSE)
say("")
say("Of these, the ones marked WRONG all share a signature: the plain entity is")
say("sitting in the candidate list as the runner-up, and the rule took the")
say("foundation anyway.")
rr <- d[grepl("runner-up", note, fixed = TRUE)]
say("cases where the note cites an exact-name runner-up: %d (%d wrong, %d ambiguous)",
    nrow(rr), sum(rr$verdict == "WRONG"), sum(rr$verdict == "AMBIGUOUS"))
fwrite(d[, .(idx, recip_name, bmf_name, name_ver, score, name_sim, margin,
             verdict, note)], file.path(PF, "data-dev", "AUTOACCEPT-LABELLED-200.csv"))
