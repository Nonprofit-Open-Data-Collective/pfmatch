#!/usr/bin/env Rscript
# Follow-up: (a) is the disclosure gain real, or would a LOOSER name rule find
# the same pairs? (b) national counts for the Schedule A Part I checkboxes, and
# what box hospital and university arms actually tick.
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 78), "\n")
e9  <- function(x) { x <- gsub("[^0-9]", "", as.character(x))
                     ifelse(nchar(x) == 9L, x, NA_character_) }

## ---- (a) would a looser name rule have found them? -------------------------
d <- fread(file.path(PF, "data-dev", "DISCLOSED-ONLY-PAIRS.csv"), colClasses = "character")
STOP <- c("THE","OF","AND","FOR","INC","INCORPORATED","CORP","CORPORATION","CO",
          "A","AN","IN","TO","ASSOCIATION","ASSOC","FOUNDATION","FUND","TRUST",
          "SOCIETY","CENTER","CENTRE","INSTITUTE","SERVICES","SERVICE")
tok <- function(x) {
  x <- toupper(as.character(x)); x[is.na(x)] <- ""
  lapply(strsplit(gsub("[^A-Z0-9 ]", " ", x), " +"),
         function(v) setdiff(v[nzchar(v)], STOP))
}
t1 <- tok(d$n1); t2 <- tok(d$n2)
inter <- mapply(function(a, b) length(intersect(a, b)), t1, t2)
mn    <- pmin(lengths(t1), lengths(t2))
d[, `:=`(shared = inter, containment = ifelse(mn > 0, inter / mn, 0))]

hr(); say("(a) COULD A LOOSER NAME RULE HAVE FOUND THE DISCLOSURE-ONLY PAIRS?"); hr()
say("disclosure-only candidate pairs: %s", format(nrow(d), big.mark = ","))
say("")
say("%-46s %8s %8s", "shared content tokens (stoplisted)", "pairs", "share")
for (k in list(c(0, 0), c(1, 1), c(2, 99))) {
  v <- d$shared >= k[1] & d$shared <= k[2]
  say("%-46s %8s %7.0f%%",
      if (k[1] == 0) "  none -- no name rule could ever link them"
      else if (k[1] == 1) "  exactly one -- a loose rule might, at a cost"
      else "  two or more -- a looser rule would find these",
      format(sum(v), big.mark = ","), 100 * mean(v))
}
say("")
say("full containment (every content token of the shorter name is in the longer):")
say("  %s pairs (%.0f%%) -- these are the ones a containment rule catches",
    format(sum(d$containment >= 0.999), big.mark = ","), 100 * mean(d$containment >= 0.999))
say("")
say("So the honest increment over a GENEROUS name rule is only the pairs")
say("sharing at most one content token: %s pairs across %s grants.",
    format(sum(d$shared <= 1), big.mark = ","),
    format(uniqueN(d$.id[d$shared <= 1]), big.mark = ","))
say("")
say("Examples with ZERO shared content tokens:")
z <- unique(d[shared == 0, .(n1, n2)])
set.seed(3)
if (nrow(z)) { s <- z[sample(.N, min(12L, .N))]
  for (i in seq_len(nrow(s))) cat(sprintf("  %-40s <-> %s\n", substr(s$n1[i],1,40), substr(s$n2[i],1,40))) }

## ---- (b) the Part I checkboxes, nationally ---------------------------------
cb <- fread(file.path(PF, "inputs", "SA-P01-T00-PUBLIC-CHARITY-STATUS-2022.CSV"),
            colClasses = "character", showProgress = FALSE,
            select = c("ORG_EIN", "SA_01_PCSTAT_HOSPITAL_X", "SA_01_PCSTAT_MEDICAL_RSRCH_X",
                       "SA_01_PCSTAT_COLLEGE_BEN_X", "SA_01_PCSTAT_SUPPORT_ORG_X",
                       "SA_01_PCSTAT_PUB_SUPPORT_X", "SA_01_PCSTAT_HOSPITAL_NAME_L1",
                       "SA_01_PCSTAT_SUPPORT_T1_X", "SA_01_PCSTAT_SUPPORT_T2_X",
                       "SA_01_PCSTAT_SUPPORT_T3_FUNC_X", "SA_01_PCSTAT_SUPPORT_T3_NOFUNC_X"))
setnames(cb, c("ein", "hospital", "med_rsrch", "college_ben", "support_org",
               "pub_support", "hosp_name", "t1", "t2", "t3f", "t3n"))
cb[, ein := e9(ein)]
tx <- function(x) !is.na(x) & toupper(trimws(x)) %in% c("X", "1", "TRUE", "Y")
for (j in c("hospital", "med_rsrch", "college_ben", "support_org", "pub_support",
            "t1", "t2", "t3f", "t3n")) cb[, (j) := tx(get(j))]
cb <- unique(cb[!is.na(ein)], by = "ein")

hr(); say("(b) SCHEDULE A PART I CHECKBOXES, 2022"); hr()
say("Schedule A filers                                   : %s", format(nrow(cb), big.mark = ","))
say("  line 3  hospital                                  : %s", format(sum(cb$hospital), big.mark = ","))
say("  line 4  medical research org (names the hospital)  : %s", format(sum(cb$med_rsrch), big.mark = ","))
say("  line 5  benefit of a GOVERNMENT college/university : %s", format(sum(cb$college_ben), big.mark = ","))
say("  line 7  publicly supported 170(b)(1)(A)(vi)        : %s", format(sum(cb$pub_support), big.mark = ","))
say("  line 12 supporting organization                    : %s", format(sum(cb$support_org), big.mark = ","))
say("")
say("Line 4 is a much narrower box than it looks: it is for medical *research*")
say("organizations operated in conjunction with a hospital, not for hospital")
say("foundations generally. Only %s filers tick it and only %s name a hospital.",
    format(sum(cb$med_rsrch), big.mark = ","),
    format(sum(cb$med_rsrch & !is.na(cb$hosp_name) & nzchar(cb$hosp_name)), big.mark = ","))

## what do arms actually tick?
p <- fread(file.path(PF, "data-dev", "MAYBE-ARM-PAIRS.csv"), colClasses = "character")
u <- unique(p[, .(arm_ein, op_ein, any_src = any_src == "TRUE", arm_nm)])
i <- match(u$arm_ein, cb$ein)
u[, `:=`(files = !is.na(i), l3 = !is.na(i) & cb$hospital[i], l4 = !is.na(i) & cb$med_rsrch[i],
         l5 = !is.na(i) & cb$college_ben[i], l7 = !is.na(i) & cb$pub_support[i],
         l12 = !is.na(i) & cb$support_org[i])]
say("")
say("What the %d MAYBE-tier arms tick (of the %d that file Schedule A):",
    nrow(u), sum(u$files))
for (j in c("l3", "l4", "l5", "l7", "l12"))
  say("  %-6s %4d (%.0f%% of filers)", j, sum(u[[j]]), 100 * sum(u[[j]]) / sum(u$files))
say("")
say("Line 12 and line 7 do the work. A university or hospital arm that is")
say("*publicly supported in its own right* ticks line 7 and discloses nothing.")

## the line-5 population, checked
say("")
hr(); say("LINE 5: THE GOVERNMENT-PARENT ARMS"); hr()
l5 <- u[l5 == TRUE]
say("MAYBE-tier arms ticking line 5                  : %d", nrow(l5))
say("  of which NO source could link to their parent : %d (%.0f%%)",
    sum(!l5$any_src), 100 * mean(!l5$any_src))
say("")
say("These are exactly the cases where the operating entity is a government")
say("agency, so there is no related nonprofit to disclose. Sample:")
set.seed(9)
s <- l5[sample(.N, min(12L, .N))]
for (i in seq_len(nrow(s))) cat(sprintf("  %s\n", substr(s$arm_nm[i], 1, 60)))
