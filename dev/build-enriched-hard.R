#!/usr/bin/env Rscript
# ============================================================================
# Build a TEXT-ENRICHED candidate view for the hard cases from the 200-case
# auto-accept validation set (37 WRONG + 19 AMBIGUOUS), plus a CORRECT control
# group, and measure what the added text actually offers.
#
# The question is not "does TF-IDF similarity help" -- dev/PURPOSE-MATCH-FINDINGS.md
# already measured that (it does not, much). The question is whether a *reader*
# given the NTEE definition, the 990 mission and the program descriptions can
# resolve cases that name+geography cannot. Those are different tasks: a
# foundation arm's mission statement frequently names its parent in plain
# English ("to support the work of X"), which no bag-of-words comparison against
# a grant purpose can exploit but a reader can.
#
# Output: data-dev/HARD-ENRICHED.csv (one row per candidate) and a coverage
# read-out on stdout.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
BMF <- file.path(PF, "..", "npmatch", "data-raw", "bmf_2026_01_processed.csv")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 78), "\n")

## ---- the labelled sample ---------------------------------------------------
d <- fread(file.path(PF, "data-dev", "AUTOACCEPT-SAMPLE-200.csv"), colClasses = "character")
v <- fread(file.path(PF, "dev", "autoaccept-verdicts.csv"))
drop <- intersect(c("verdict", "note"), names(d)); if (length(drop)) d[, (drop) := NULL]
d[, idx := .I]
d <- merge(d, v, by = "idx")
say("labelled cases: %d  (%s)", nrow(d),
    paste(sprintf("%s=%d", names(table(d$verdict)), table(d$verdict)), collapse = " "))

## ---- every candidate for those grants --------------------------------------
m  <- readRDS(file.path(PF, "data-dev", "PF-MATCH-RESULT-50k.rds"))
pr <- as.data.table(attr(m$result, "pairs"))
cfg <- npmatch::np_config()
pr <- npmatch::np_veto(npmatch::np_score(pr, cfg, method = "hier"), cfg)
pr <- as.data.table(pr)
setorder(pr, .id, -score)
cand <- pr[.id %in% d$grant_id & !veto]
cand[, rank := seq_len(.N), by = .id]
cand <- cand[rank <= 5L]   # the review packet is the top 5, as shipped
say("candidate rows for the labelled grants: %d over %d grants",
    nrow(cand), uniqueN(cand$.id))

## ---- text sources ----------------------------------------------------------
txt <- readRDS(file.path(PF, "data-dev", "ORG-TEXT-BUNDLE.rds"))   # 990 filers only
setkey(txt, ein)

# NTEE text for ALL candidate EINs, filers or not, straight from the BMF
eins <- unique(.pf_ein(cand$.ein))
b <- fread(BMF, colClasses = "character", showProgress = FALSE,
           select = c("ein", "subsection_code", "ntee_code_clean", "nteev2",
                      "ntee_code_definition", "ntee_common_code_definition",
                      "activity_code_definitions", "revenue_amount", "asset_amount"))
b[, ein := .pf_ein(ein)]
b <- b[ein %in% eins]
nt <- pf_ntee_text()
sq <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; x }
j1 <- match(sq(b$nteev2), nt$by_v2$key)
j2 <- match(sq(b$ntee_code_clean), nt$by_legacy$key)
b[, ntee_ref := fifelse(!is.na(j1), nt$by_v2$ref[j1],
                 fifelse(!is.na(j2), nt$by_legacy$ref[j2], ""))]
b[, ntee_all := trimws(paste(sq(ntee_code_clean), sq(ntee_code_definition),
                             sq(ntee_common_code_definition), sq(ntee_ref)))]
setkey(b, ein)

cand[, ein9 := .pf_ein(.ein)]
i <- match(cand$ein9, b$ein)
cand[, `:=`(ntee = sq(b$ntee_code_clean[i]), ntee_text = sq(b$ntee_all[i]),
            activity = sq(b$activity_code_definitions[i]),
            subsection = sq(b$subsection_code[i]),
            revenue = sq(b$revenue_amount[i]))]
k <- match(cand$ein9, txt$ein)
cand[, `:=`(return_type = sq(txt$return_type[k]), mission = sq(txt$mission[k]),
            prog = sq(txt$prog_all[k]),
            n_prog = fifelse(is.na(txt$n_programs[k]), 0L, txt$n_programs[k]))]

## ---- does the text state a supporting relationship? ------------------------
# The single most common error shape is entity vs its own foundation. A support
# organization very often says so in its own words.
REL <- paste0("(?i)\\b(for the benefit of|to benefit|to support|supports? the|",
              "supporting organization|sole member|affiliated with|auxiliary|",
              "friends of|fundraising arm|raise funds for|in support of|",
              "solely for the benefit)\\b")
cand[, rel_phrase := grepl(REL, paste(mission, prog), perl = TRUE)]
cand[, has_text := nzchar(mission) | nzchar(prog)]
cand[, usable_ntee := nzchar(ntee) & !(toupper(ntee) %in% c("INVALID", "UNDEFINED", "Z99"))]

## ---- attach the label and emit ---------------------------------------------
lab <- d[, .(grant_id, idx, verdict, note, recip_name, recip_city, recip_state,
             recip_zip5, purpose, amount, picked_ein = ein)]
out <- merge(cand[, .(grant_id = .id, rank, cand_ein = ein9, cand_name = name_y,
                      cand_city = city_y, cand_state = state_y, cand_zip = zip5_y,
                      name_ver = name_ver_y, score, ntee, subsection,
                      revenue, return_type, n_prog, usable_ntee, has_text,
                      rel_phrase, ntee_text, mission, prog)],
             lab, by = "grant_id")
out[, is_pick := cand_ein == .pf_ein(picked_ein)]
setorder(out, idx, rank)
fwrite(out, file.path(PF, "data-dev", "HARD-ENRICHED.csv"))
say("wrote data-dev/HARD-ENRICHED.csv (%d candidate rows)", nrow(out))

## ---- coverage read-out -----------------------------------------------------
hard <- out[verdict %in% c("WRONG", "AMBIGUOUS")]
ctrl <- out[verdict == "CORRECT"]
hr(); say("TEXT COVERAGE ON THE CANDIDATES"); hr()
say("%-34s %10s %10s", "", "hard", "correct")
f <- function(a, b, lbl) say("%-34s %9.1f%% %9.1f%%", lbl, 100 * a, 100 * b)
f(mean(hard$has_text), mean(ctrl$has_text), "candidate has 990 Part III text")
f(mean(hard$usable_ntee), mean(ctrl$usable_ntee), "candidate has a usable NTEE")
f(mean(nzchar(hard$prog)), mean(nzchar(ctrl$prog)), "candidate has program descriptions")
say("")
gh <- hard[, .(all_text = all(has_text), any_text = any(has_text),
               n = .N), by = .(idx)]
gc <- ctrl[, .(all_text = all(has_text), any_text = any(has_text),
               n = .N), by = .(idx)]
say("grants where EVERY candidate has text : hard %.0f%%  correct %.0f%%",
    100 * mean(gh$all_text), 100 * mean(gc$all_text))
say("grants where NO candidate has text    : hard %.0f%%  correct %.0f%%",
    100 * mean(!gh$any_text), 100 * mean(!gc$any_text))

hr(); say("THE SUPPORTING-RELATIONSHIP PHRASE"); hr()
say("candidates whose own 990 text names a support relationship:")
say("  hard cases   : %d of %d with text (%.0f%%)",
    sum(hard$rel_phrase), sum(hard$has_text), 100 * sum(hard$rel_phrase) / sum(hard$has_text))
say("  correct cases: %d of %d with text (%.0f%%)",
    sum(ctrl$rel_phrase), sum(ctrl$has_text), 100 * sum(ctrl$rel_phrase) / sum(ctrl$has_text))
say("")
say("on the TOP PICK specifically (the candidate the rule would accept):")
tp <- out[rank == 1]
print(tp[, .(n = .N, has_text = sum(has_text), rel = sum(rel_phrase),
             rel_pct = round(100 * sum(rel_phrase) / .N)), by = verdict],
      row.names = FALSE)
say("")
say("A support phrase on the top pick is a WRONG-flag if it fires more often on")
say("hard cases than correct ones.")

hr(); say("FOUNDATION-ARM CASES SPECIFICALLY"); hr()
arm <- unique(out[grepl("foundation", note, ignore.case = TRUE), .(idx, verdict)])
say("cases whose note turns on an entity-vs-foundation choice: %d", nrow(arm))
a <- out[idx %in% arm$idx]
ap <- a[rank == 1]
say("  top pick has 990 text        : %d of %d", sum(ap$has_text), nrow(ap))
say("  top pick's text names support: %d of %d", sum(ap$rel_phrase), nrow(ap))
say("")
say("Is the DISTINCTION visible? For each such grant, do the top pick and the")
say("runner-up differ in whether their text names a support relationship?")
pairwise <- a[rank <= 2, .(n = .N, differs = length(unique(rel_phrase)) > 1L,
                           both_text = all(has_text)), by = idx][n == 2]
say("  grants with a runner-up          : %d", nrow(pairwise))
say("  both have text                   : %d", sum(pairwise$both_text))
say("  support phrase separates the two : %d (%.0f%% of those with both)",
    sum(pairwise$differs & pairwise$both_text),
    100 * sum(pairwise$differs & pairwise$both_text) / max(1, sum(pairwise$both_text)))
