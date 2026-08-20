#!/usr/bin/env Rscript
# Score the enriched re-read of the 56 hard cases, and test whether the two
# structural signals visible in that read are mechanically extractable:
#   (a) the NTEE "support organization" codes -- ?11 (single-org support) and
#       ?12 (fund raising / fund distribution)
#   (b) the "SUPPORTING/FOUNDATION top pick with an operating runner-up" shape
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 78), "\n")
ci  <- function(k, n) if (n == 0) "-" else
  sprintf("%.0f-%.0f%%", 100 * binom.test(k, n)$conf.int[1], 100 * binom.test(k, n)$conf.int[2])

e <- fread(file.path(PF, "dev", "enrichment-verdicts.csv"))
d <- fread(file.path(PF, "data-dev", "HARD-ENRICHED.csv"), colClasses = "character")
d[, `:=`(idx = as.integer(idx), rank = as.integer(rank))]

hr(); say("WHAT THE ADDED TEXT DID, ON 56 CASES NAME+GEOGRAPHY COULD NOT CLOSE"); hr()
lv <- c("RESOLVED_ALT", "RESOLVED_PICK", "RESOLVED_NONE", "HELPS", "SILENT")
tb <- table(factor(e$outcome, lv))
for (k in lv) say("  %-15s %3d  (%.0f%%)", k, tb[[k]], 100 * tb[[k]] / nrow(e))
say("")
res <- sum(tb[c("RESOLVED_ALT", "RESOLVED_PICK", "RESOLVED_NONE")])
say("resolved to a definite answer : %d of %d  (%.0f%%, 95%% CI %s)",
    res, nrow(e), 100 * res / nrow(e), ci(res, nrow(e)))
say("  ...yielding a usable EIN    : %d  (ALT %d + PICK %d)",
    tb[["RESOLVED_ALT"]] + tb[["RESOLVED_PICK"]], tb[["RESOLVED_ALT"]], tb[["RESOLVED_PICK"]])
say("  ...yielding a confident NO  : %d", tb[["RESOLVED_NONE"]])
say("")
say("How the resolution was reached:")
q <- table(factor(e$evidence, c("QUOTE", "NTEE", "INFER", "NONE")))
say("  QUOTE  %2d  a verbatim string in the candidate's own 990 decides it", q[["QUOTE"]])
say("  NTEE   %2d  the classification code alone decides it", q[["NTEE"]])
say("  INFER  %2d  no single string; the reader reasons over the whole packet", q[["INFER"]])
say("  NONE   %2d  nothing to read", q[["NONE"]])
say("")
say("QUOTE cases are auditable -- a reviewer can point at the sentence. That is")
say("%.0f%% of resolutions. INFER cases are judgement and need the confidence flag.",
    100 * q[["QUOTE"]] / res)

hr(); say("BY ORIGINAL LABEL"); hr()
lab <- unique(d[, .(idx, verdict)])
m <- merge(e, lab, by = "idx")
print(dcast(m, verdict ~ factor(outcome, lv), fun.aggregate = length, drop = FALSE),
      row.names = FALSE)
say("")
say("Of %d cases originally labelled WRONG, %d are recovered to a different EIN",
    sum(m$verdict == "WRONG"), sum(m$verdict == "WRONG" & m$outcome == "RESOLVED_ALT"))
say("and %d become a confident NO rather than an unresolved MAYBE.",
    sum(m$verdict == "WRONG" & m$outcome == "RESOLVED_NONE"))

hr(); say("SIGNAL (a): IS THE SUPPORT-ORG NTEE CODE MECHANICALLY USABLE?"); hr()
# ?11 = Single Organization Support, ?12 = Fund Raising and Fund Distribution
d[, sup_code := grepl("^[A-Z](11|12)$", toupper(ntee))]
d[, is_pick := is_pick == "TRUE"]
tp <- d[rank == 1]
say("%-12s %6s %10s %12s", "verdict", "n", "sup NTEE", "share")
for (v in c("CORRECT", "AMBIGUOUS", "WRONG")) {
  s <- tp[verdict == v]
  say("%-12s %6d %10d %11.0f%%", v, nrow(s), sum(s$sup_code), 100 * mean(s$sup_code))
}
say("")
say("The pattern that matters: top pick carries a support code AND a runner-up")
say("exists that does not. That is the entity-vs-its-arm shape, stated in data")
say("rather than prose.")
r2 <- d[rank <= 2][, .(n = .N, pick_sup = sup_code[1],
                       ru_sup = if (.N > 1) sup_code[2] else NA,
                       verdict = verdict[1]), by = idx][n == 2]
r2[, fires := pick_sup & !ru_sup]
say("")
say("%-12s %8s %8s %10s", "verdict", "grants", "fires", "rate")
for (v in c("CORRECT", "AMBIGUOUS", "WRONG")) {
  s <- r2[verdict == v]
  say("%-12s %8d %8d %9.0f%%", v, nrow(s), sum(s$fires), 100 * mean(s$fires))
}
f <- r2[fires == TRUE]
say("")
say("When it fires: %d cases, %d WRONG + %d AMBIGUOUS, %d CORRECT.",
    nrow(f), sum(f$verdict == "WRONG"), sum(f$verdict == "AMBIGUOUS"),
    sum(f$verdict == "CORRECT"))
bad <- sum(f$verdict != "CORRECT")
say("precision as a DEMOTE flag: %d/%d = %.0f%%  95%% CI %s",
    bad, nrow(f), 100 * bad / nrow(f), ci(bad, nrow(f)))
say("")
say("Coverage is the limit: a usable NTEE is present on only %.0f%% of top picks,",
    100 * mean(nzchar(tp$ntee) & !toupper(tp$ntee) %in% c("INVALID", "UNDEFINED", "Z99")))
say("and INVALID/UNDEFINED is *more* common on the large orgs that cause the")
say("ambiguity in the first place (dev/PURPOSE-MATCH-FINDINGS.md section 3).")

hr(); say("SIGNAL (b): NAME-SHAPE -- 'X FOUNDATION' PICK WITH AN 'X' RUNNER-UP"); hr()
clean <- function(x) gsub("[^A-Z ]", "", toupper(x))
r2b <- d[rank <= 2][, .(n = .N, p = clean(cand_name)[1],
                        r = if (.N > 1) clean(cand_name)[2] else NA_character_,
                        verdict = verdict[1]), by = idx][n == 2]
SUF <- " (FOUNDATION|FOUND|ENDOWMENT|TRUST|FUND)$"
r2b[, fires := grepl(SUF, p) & !is.na(r) &
      trimws(sub(SUF, "", p)) == trimws(r)]
say("fires on %d of %d two-candidate grants", sum(r2b$fires), nrow(r2b))
fb <- r2b[fires == TRUE]
if (nrow(fb)) {
  print(fb[, .N, by = verdict], row.names = FALSE)
  say("precision as a DEMOTE flag: %d/%d = %.0f%%  95%% CI %s",
      sum(fb$verdict != "CORRECT"), nrow(fb),
      100 * mean(fb$verdict != "CORRECT"), ci(sum(fb$verdict != "CORRECT"), nrow(fb)))
}
say("")
say("This is the rule already noted in dev/ADJUDICATION-PLAN.md section 1, now")
say("measured as a string pattern rather than counted from hand notes.")
