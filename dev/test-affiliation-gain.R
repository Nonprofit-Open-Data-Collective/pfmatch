#!/usr/bin/env Rscript
# ============================================================================
# Two questions the joint-ID table did not answer.
#
# (1) Does Schedule A Part I *checkbox* status help where line 12 cannot?
#     Line 5 (COLLEGE_BEN_X) is "operated for the benefit of a college or
#     university owned or operated by a governmental unit" -- exactly the state
#     university foundation, whose parent is a government agency and therefore
#     can never appear on Schedule A line 12 or Schedule R Part II.
#     Line 4 (MEDICAL_RSRCH_X) names the affiliated hospital in plain text.
#
# (2) What does the affiliation data buy OVER name+geography clustering?
#     Confirming a cluster the name already found is worth little. Finding a
#     cluster the name CANNOT find -- two candidates with unrelated names --
#     is the actionable increment. This measures that.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 78), "\n")
e9  <- function(x) { x <- gsub("[^0-9]", "", as.character(x))
                     ifelse(nchar(x) == 9L, x, NA_character_) }

L  <- readRDS(file.path(PF, "data-dev", "AFFIL-LINKS.rds"))
sa <- L[src == "SCHED_A"]; sr <- L[src == "SCHED_R"]
linked <- unique(c(paste(sa$a, sa$b), paste(sa$b, sa$a),
                   paste(sr$a, sr$b), paste(sr$b, sr$a)))

## =====================================================================  (1)
cb <- fread(file.path(PF, "inputs", "SA-P01-T00-PUBLIC-CHARITY-STATUS-2022.CSV"),
            colClasses = "character", showProgress = FALSE,
            select = c("ORG_EIN", "SA_01_PCSTAT_COLLEGE_BEN_X",
                       "SA_01_PCSTAT_MEDICAL_RSRCH_X", "SA_01_PCSTAT_HOSPITAL_NAME_L1",
                       "SA_01_PCSTAT_HOSPITAL_ADDR_CITY", "SA_01_PCSTAT_HOSPITAL_ADDR_STATE",
                       "SA_01_PCSTAT_SUPPORT_ORG_X", "SA_01_PCSTAT_GOVT_X"))
setnames(cb, c("ein", "college_ben", "med_rsrch", "hosp_name", "hosp_city",
               "hosp_state", "support_org", "govt"))
cb[, ein := e9(ein)]
tx <- function(x) !is.na(x) & toupper(trimws(x)) %in% c("X", "1", "TRUE", "Y")
cb[, `:=`(college_ben = tx(college_ben), med_rsrch = tx(med_rsrch),
          support_org = tx(support_org), govt = tx(govt))]
cb <- unique(cb[!is.na(ein)], by = "ein")
setkey(cb, ein)

hr(); say("(1) SCHEDULE A PART I CHECKBOXES AS AN AFFILIATION SIGNAL"); hr()
say("Schedule A filers in 2022                       : %s", format(nrow(cb), big.mark = ","))
say("  line 5  operated for the benefit of a GOVERNMENT college : %s",
    format(sum(cb$college_ben), big.mark = ","))
say("  line 4  medical research org, hospital named            : %s",
    format(sum(cb$med_rsrch), big.mark = ","))
say("    ...of those with a hospital NAME populated            : %s",
    format(sum(cb$med_rsrch & nzchar(.pf_txt <- ifelse(is.na(cb$hosp_name), "", cb$hosp_name))), big.mark = ","))
say("  line 12 supporting organization                         : %s",
    format(sum(cb$support_org), big.mark = ","))

p <- fread(file.path(PF, "data-dev", "MAYBE-ARM-PAIRS.csv"), colClasses = "character")
for (j in c("sa_fwd", "sa_rev", "sr_any", "any_src")) p[, (j) := get(j) == "TRUE"]
u <- unique(p[, .(arm_ein, op_ein, any_src)])
i <- match(u$arm_ein, cb$ein)
u[, `:=`(arm_college_ben = !is.na(i) & cb$college_ben[i],
         arm_med_rsrch   = !is.na(i) & cb$med_rsrch[i],
         arm_files_sa    = !is.na(i))]
say("")
say("On the %d arm pairs from the MAYBE tier:", nrow(u))
say("  arm files Schedule A at all                   : %d (%.0f%%)",
    sum(u$arm_files_sa), 100 * mean(u$arm_files_sa))
say("  arm checks line 5 (government college parent) : %d", sum(u$arm_college_ben))
say("  arm checks line 4 (hospital affiliate)        : %d", sum(u$arm_med_rsrch))
say("")
say("The test that matters: among pairs NO source could link, how many are")
say("explained by the parent being a government body?")
miss <- u[any_src == FALSE]
say("  unlinked pairs                                : %d", nrow(miss))
say("  ...where the arm files Sched A and checks line 5 : %d", sum(miss$arm_college_ben))
say("  ...where the arm files Sched A and checks line 4 : %d", sum(miss$arm_med_rsrch))
say("  ...where the arm files Sched A but checks neither: %d",
    sum(miss$arm_files_sa & !miss$arm_college_ben & !miss$arm_med_rsrch))
say("  ...where the arm files no Schedule A at all      : %d", sum(!miss$arm_files_sa))
say("")
say("line 5 as a standalone flag on the ARM, regardless of pairing:")
say("  precision is not the question -- it is a *status*, not a guess. An EIN")
say("  checking line 5 IS a government-college support arm by its own filing.")
lb5 <- cb[college_ben == TRUE]
say("  %s such EINs exist nationally.", format(nrow(lb5), big.mark = ","))

## =====================================================================  (2)
hr(); say("(2) WHAT DOES AFFILIATION DATA BUY OVER NAME CLUSTERING?"); hr()
say("Rebuilding every candidate pair in the MAYBE tier ...")
m  <- readRDS(file.path(PF, "data-dev", "PF-MATCH-RESULT-50k.rds"))
cfg <- npmatch::np_config()
pr0 <- npmatch::np_veto(npmatch::np_score(attr(m$result, "pairs"), cfg, method = "hier"), cfg)
res <- npmatch::np_tier(npmatch::np_select(pr0, cfg), cfg)
x <- m; x$result <- res; attr(x$result, "pairs") <- pr0; attr(x$result, "config") <- cfg
st <- as.data.table(pf_status(x))
maybe_ids <- st[status == "MAYBE", grant_id]

pr <- as.data.table(pr0)[veto == FALSE]
setorder(pr, .id, -score)
cd <- pr[.id %in% maybe_ids]
cd[, rank := seq_len(.N), by = .id]
cd <- cd[rank <= 5L]
cd[, `:=`(ein9 = e9(.ein), core = pf_arm_core(name_y), arm = pf_is_arm(name_y))]

# every unordered pair of candidates within a grant
cp <- cd[, {
  if (.N < 2L) NULL else {
    ii <- t(utils::combn(.N, 2L))
    list(e1 = ein9[ii[, 1]], e2 = ein9[ii[, 2]],
         n1 = name_y[ii[, 1]], n2 = name_y[ii[, 2]],
         c1 = core[ii[, 1]],  c2 = core[ii[, 2]],
         a1 = arm[ii[, 1]],   a2 = arm[ii[, 2]],
         s1 = state_y[ii[, 1]], s2 = state_y[ii[, 2]])
  }}, by = .id]
cp <- cp[!is.na(e1) & !is.na(e2)]
cp[, same_state := !is.na(s1) & !is.na(s2) & s1 == s2]
cp[, name_cluster := nchar(c1) >= 8L & c1 == c2 & (a1 != a2) & same_state]
cp[, disclosed := paste(e1, e2) %in% linked]

say("candidate pairs inside MAYBE grants   : %s", format(nrow(cp), big.mark = ","))
say("")
say("%-44s %9s %9s", "", "pairs", "grants")
f <- function(v, lbl) say("%-44s %9s %9s", lbl, format(sum(v), big.mark = ","),
                          format(uniqueN(cp$.id[v]), big.mark = ","))
f(cp$name_cluster,  "found by name+geo clustering")
f(cp$disclosed,     "disclosed by Schedule A or R")
f(cp$name_cluster & cp$disclosed, "both")
f(cp$disclosed & !cp$name_cluster, "DISCLOSED ONLY -- name clustering misses")
f(cp$name_cluster & !cp$disclosed, "name only -- no disclosure to confirm")
say("")
n_add <- uniqueN(cp$.id[cp$disclosed & !cp$name_cluster])
n_nm  <- uniqueN(cp$.id[cp$name_cluster])
say("MAYBE grants reached by name clustering alone      : %s (%.1f%%)",
    format(n_nm, big.mark = ","), 100 * n_nm / length(maybe_ids))
say("MAYBE grants reached ONLY via disclosure           : %s (%.1f%%)",
    format(n_add, big.mark = ","), 100 * n_add / length(maybe_ids))
say("combined                                           : %s (%.1f%%)",
    format(uniqueN(cp$.id[cp$name_cluster | cp$disclosed]), big.mark = ","),
    100 * uniqueN(cp$.id[cp$name_cluster | cp$disclosed]) / length(maybe_ids))

hr(); say("WHAT THE DISCLOSURE-ONLY PAIRS LOOK LIKE"); hr()
say("These are related organizations whose names share nothing. No amount of")
say("string clustering finds them.")
set.seed(5)
d <- unique(cp[disclosed == TRUE & name_cluster == FALSE & same_state == TRUE,
               .(n1, n2)])
s <- d[sample(.N, min(20L, .N))]
for (i in seq_len(nrow(s)))
  cat(sprintf("  %-42s <-> %s\n", substr(s$n1[i], 1, 42), substr(s$n2[i], 1, 42)))
fwrite(unique(cp[disclosed == TRUE & name_cluster == FALSE, .(.id, e1, e2, n1, n2)]),
       file.path(PF, "data-dev", "DISCLOSED-ONLY-PAIRS.csv"))
