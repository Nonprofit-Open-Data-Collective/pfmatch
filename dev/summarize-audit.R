#!/usr/bin/env Rscript
# Summarize the three 100-case audits into the tables used in AUDIT-FINDINGS.md.
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
DD <- file.path(PF, "data-dev")
hr <- function() cat(strrep("-", 74), "\n")

# ------------------------------------------------------------------ MAYBE ---
v <- fread(file.path(PF, "dev", "maybe-verdicts.csv"), colClasses = "character")
cat("\n### MAYBE: 100 adjudicated cases\n"); hr()
print(v[, .N, by = verdict][order(-N)], row.names = FALSE)
cat(sprintf("\ncorrect EIN present in top 5 : %d\n", sum(v$verdict %in% c("CORRECT_TOP", "CORRECT_DEEPER"))))
cat(sprintf("  of which the top pick is right: %d\n", sum(v$verdict == "CORRECT_TOP")))
cat(sprintf("  correct but mis-ranked        : %d\n", sum(v$verdict == "CORRECT_DEEPER")))

cat("\nfailure / ambiguity mode (non-correct-top cases):\n")
print(v[nzchar(failure_mode), .N, by = failure_mode][order(-N)], row.names = FALSE)

cat("\nNTEE or activity code decisive:\n")
print(v[, .N, by = .(ntee_decisive, verdict)][order(-N)], row.names = FALSE)
cat(sprintf("\nNTEE decisive among the %d mis-ranked cases: %d (%.0f%%)\n",
            sum(v$verdict == "CORRECT_DEEPER"),
            sum(v$verdict == "CORRECT_DEEPER" & v$ntee_decisive == "yes"),
            100 * mean(v$ntee_decisive[v$verdict == "CORRECT_DEEPER"] == "yes")))

# projected effect on the headline rate
m  <- readRDS(file.path(DD, "PF-MATCH-RESULT-1k.rds"))
src <- file.path(PF, "R"); for (f in list.files(src, pattern = "\\.R$", full.names = TRUE)) source(f)
suppressWarnings(suppressMessages(devtools::load_all(
  Sys.getenv("NPMATCH_DIR", "../npmatch"), quiet = TRUE)))
st <- pf_status(m)
n_maybe <- sum(st$status == "MAYBE"); n_att <- sum(st$status != "OOS")
n_yes <- sum(st$status == "YES")
rate_top <- mean(v$verdict == "CORRECT_TOP")
rate_any <- mean(v$verdict %in% c("CORRECT_TOP", "CORRECT_DEEPER"))
cat(sprintf("\nprojection over the full MAYBE tier (%d cases, %d attempted grants):\n", n_maybe, n_att))
cat(sprintf("  accepting the top pick as-is  : +%.0f matches -> %.1f%% (from %.1f%%)\n",
            n_maybe * rate_top, 100 * (n_yes + n_maybe * rate_top) / n_att, 100 * n_yes / n_att))
cat(sprintf("  adjudicating the top 5        : +%.0f matches -> %.1f%%\n",
            n_maybe * rate_any, 100 * (n_yes + n_maybe * rate_any) / n_att))

# -------------------------------------------------------------------- OOS ---
cat("\n\n### OOS: 100 inspected cases\n"); hr()
o <- fread(file.path(DD, "AUDIT-OOS-100.csv"), colClasses = "character")
print(o[, .N, by = oos_reason][order(-N)], row.names = FALSE)
# organizations confirmed present in the BMF by the targeted probe
mis <- c("IOWA CENTRAL COMMUNITY COLLEGE", "BEMIDJI STATE UNIVERSITY", "STETSON UNIVERSITY",
         "HOFSTRA UNIV", "UW-STOUT", "University of West Georgia", "COLLEGE OF CHARLESTON",
         "UNIVERSITY OF MARY", "LUTHER COLLEGE", "Mississippi State University",
         "EMMAUS BIBLE COLLEGE", "SHEILA CHIPPS CO EASTERN UNIVERSITY",
         "ZACH MUCKLEROY TCU SCHOLARSHIP", "CHRISTIAN PANDO - WESTERN NEW MEXIC",
         "University of Missouri fbo Annamari", "NICOLE GOMEZ UCONN SCHOOL OF MEDI",
         "UNIVERSITY OF GEORGIA", "WENATCHEE VALLEY COLLEGE", "SAM HOUSTON STATE UNIVERSITY",
         "KENAN-FLAGLER BUSINSESS SCHOOL FOUNDATION", "COUNCIL OF SENIOR CENTERS DBA LIVEON NY",
         "FAIRBURY MUSIC PROGRAM", "CANYON RIDGE HIGH SCHOOL", "WESLEY CHAPEL ELEMENTARY")
o[, misclassified := recip_name %in% mis]
cat(sprintf("\nmisclassified (a BMF organization exists): %d of %d\n", sum(o$misclassified), nrow(o)))
print(o[, .(n = .N, misclassified = sum(misclassified),
            pct = round(100 * mean(misclassified))), by = oos_reason][order(-n)], row.names = FALSE)
cat("\nof the misclassified, how many are scholarship/tuition grants routed through a school:\n")
cat(sprintf("  purpose mentions scholarship/tuition/education: %d\n",
            sum(o$misclassified & grepl("SCHOLAR|TUITION|EDUCAT|ACADEMIC", toupper(o$grant_purpose)))))

# --------------------------------------------------------------------- NO ---
cat("\n\n### NO: 100 probed cases\n"); hr()
p <- fread(file.path(DD, "AUDIT-NO-100-PROBE.csv"), colClasses = "character")
print(p[, .N, by = mode][order(-N)], row.names = FALSE)
cat("\ntop-similarity distribution of the oracle probe's best BMF candidate:\n")
print(round(quantile(as.numeric(p$top_sim), c(0, .25, .5, .75, 1), na.rm = TRUE), 3))
