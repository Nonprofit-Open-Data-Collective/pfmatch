#!/usr/bin/env Rscript
# ============================================================================
# Build an EIN-to-EIN affiliation link table from three independent sources,
# then find the MAYBE cases whose candidate list contains an operating arm and
# a fundraising arm of the same body, and measure how often each source can
# actually link that pair.
#
#   Schedule A Part I line 12  (SA-P01-T01)  supporting org -> supported org
#   Schedule R Part II         (SR-P02-T01)  filer <-> related exempt org
#   BMF group exemption        affiliation_code / group_exemption_number
#
# Sources are directional and differ in what they cover. Schedule A only exists
# if the filer *is* a 509(a)(3) supporting organization. Schedule R only exists
# if the filer answered "yes" to Part IV line 34. The BMF group fields describe
# group *rulings* (federated chapters), which is a different relation entirely.
#
# Output: data-dev/ARM-LINKS.rds, data-dev/MAYBE-ARM-PAIRS.csv
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
BMF <- file.path(PF, "..", "npmatch", "data-raw", "bmf_2026_01_processed.csv")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 78), "\n")
e9  <- function(x) { x <- gsub("[^0-9]", "", as.character(x))
                     ifelse(nchar(x) == 9L, x, NA_character_) }

## ---------------------------------------------------------------- link table
say("building link table ...")

sa <- fread(file.path(PF, "inputs", "SA-P01-T01-PUBLIC-CHARITY-STATUS-2022.CSV"),
            colClasses = "character", showProgress = FALSE,
            select = c("ORG_EIN", "SA_01_PCSTAT_ORG_EIN", "SA_01_PCSTAT_ORG_NAME_L1",
                       "SA_01_PCSTAT_ORG_TYPE"))
sa[, `:=`(a = e9(ORG_EIN), b = e9(SA_01_PCSTAT_ORG_EIN))]
sa_l <- unique(sa[!is.na(a) & !is.na(b) & a != b,
                  .(a, b, src = "SCHED_A", rel = "a_supports_b")])

sr <- fread(file.path(PF, "inputs", "SR-P02-T01-ID-RLTD-TAX-EXEMPED-ORGS-2022.CSV"),
            colClasses = "character", showProgress = FALSE,
            select = c("ORG_EIN", "SR_02_RLTD_ORG_EIN", "SR_02_RLTD_ORG_NAME_L1",
                       "SR_02_RLTD_ORG_CTRL_NA"))
sr[, `:=`(a = e9(ORG_EIN), b = e9(SR_02_RLTD_ORG_EIN))]
sr_l <- unique(sr[!is.na(a) & !is.na(b) & a != b,
                  .(a, b, src = "SCHED_R", rel = "a_related_b")])

bm <- fread(BMF, colClasses = "character", showProgress = FALSE,
            select = c("ein", "org_name_join", "affiliation_code",
                       "group_exemption_number", "subsection_code",
                       "ntee_code_clean"))
bm[, ein := e9(ein)]
bm <- bm[!is.na(ein)]
setkey(bm, ein)

links <- rbind(sa_l, sr_l)
# undirected lookup key as well, since either party may be the filer
und <- unique(rbind(links[, .(x = a, y = b, src, rel)],
                    links[, .(x = b, y = a, src,
                              rel = fifelse(rel == "a_supports_b", "b_supports_a",
                                            "a_related_b"))]))
setkey(und, x, y)
saveRDS(list(directed = links, undirected = und, bmf = bm),
        file.path(PF, "data-dev", "ARM-LINKS.rds"), compress = FALSE)

hr(); say("LINK TABLE"); hr()
say("Schedule A  (supporting org -> supported org) : %s pairs, %s distinct filers",
    format(nrow(sa_l), big.mark = ","), format(uniqueN(sa_l$a), big.mark = ","))
say("  rows dropped for a blank supported-org EIN  : %s of %s (%.0f%%)",
    format(sum(is.na(sa$b)), big.mark = ","), format(nrow(sa), big.mark = ","),
    100 * mean(is.na(sa$b)))
say("Schedule R Part II (filer <-> related exempt) : %s pairs, %s distinct filers",
    format(nrow(sr_l), big.mark = ","), format(uniqueN(sr_l$a), big.mark = ","))
say("  rows dropped for a blank related-org EIN    : %s of %s (%.0f%%)",
    format(sum(is.na(sr$b)), big.mark = ","), format(nrow(sr), big.mark = ","),
    100 * mean(is.na(sr$b)))
say("")
say("overlap: %s pairs appear in BOTH (undirected)",
    format(length(intersect(unique(paste(pmin(sa_l$a, sa_l$b), pmax(sa_l$a, sa_l$b))),
                            unique(paste(pmin(sr_l$a, sr_l$b), pmax(sr_l$a, sr_l$b))))), big.mark = ","))

## ------------------------------------------------- arm detection on the names
# Markers that mean "this row is the fundraising / support arm of something".
ARM_TAIL <- paste0("(FOUNDATION|FOUNDATION INC|FOUND|ENDOWMENT|ENDOWMENT FUND|",
                   "FUND|TRUST|SUPPORTING ORGANIZATION|SUPPORT CORPORATION|",
                   "AUXILIARY|GUILD|BOOSTER CLUB|BOOSTERS|ALUMNI ASSOCIATION|",
                   "ASSOCIATES|PARTNERS|SOCIETY)")
ARM_HEAD <- "(FRIENDS OF( THE)?|SUPPORTERS OF|ASSOCIATES OF)"
LEGAL <- "( INC| INCORPORATED| CORP| CORPORATION| CO| LTD| LLC| THE)"

norm <- function(x) {
  x <- toupper(as.character(x)); x[is.na(x)] <- ""
  x <- gsub("[^A-Z0-9 ]", " ", x)
  x <- gsub("\\bTHE\\b", " ", x)
  trimws(gsub(" +", " ", x))
}
strip_legal <- function(x) trimws(gsub(paste0(LEGAL, "+$"), "", x))
is_arm <- function(x) grepl(paste0(" ", ARM_TAIL, "$"), x) | grepl(paste0("^", ARM_HEAD, " "), x)
core_of <- function(x) {
  x <- strip_legal(x)
  x <- sub(paste0("^", ARM_HEAD, " "), "", x)
  x <- sub(paste0(" ", ARM_TAIL, "$"), "", x)
  trimws(gsub(" +", " ", x))
}

## ------------------------------------------------------ the MAYBE candidates
say("")
say("loading the 50k match result ...")
m  <- readRDS(file.path(PF, "data-dev", "PF-MATCH-RESULT-50k.rds"))
cfg <- npmatch::np_config()
pr <- npmatch::np_veto(npmatch::np_score(attr(m$result, "pairs"), cfg, method = "hier"), cfg)
res <- npmatch::np_tier(npmatch::np_select(pr, cfg), cfg)
x <- m; x$result <- res; attr(x$result, "pairs") <- pr; attr(x$result, "config") <- cfg
st <- as.data.table(pf_status(x))
maybe_ids <- st[status == "MAYBE", grant_id]

pr <- as.data.table(pr)[veto == FALSE]
setorder(pr, .id, -score)
cd <- pr[.id %in% maybe_ids]
cd[, rank := seq_len(.N), by = .id]
cd <- cd[rank <= 5L]
cd[, `:=`(ein9 = e9(.ein), nm = norm(name_y))]
cd[, `:=`(arm = is_arm(nm), core = core_of(nm))]
# a core must be substantive: >= 2 tokens and >= 8 characters
cd[, core_ok := nchar(core) >= 8L & lengths(strsplit(core, " ")) >= 2L]

grp <- cd[core_ok == TRUE, .(n = .N, n_arm = sum(arm), n_op = sum(!arm),
                             arm_ein = ein9[arm][1], op_ein = ein9[!arm][1],
                             arm_nm = name_y[arm][1], op_nm = name_y[!arm][1],
                             arm_rank = rank[arm][1], op_rank = rank[!arm][1]),
          by = .(grant_id = .id, core)]
pairs <- grp[n >= 2L & n_arm >= 1L & n_op >= 1L &
             !is.na(arm_ein) & !is.na(op_ein)]

hr(); say("ARM PAIRS INSIDE THE MAYBE TIER"); hr()
say("MAYBE grants                                    : %s", format(length(maybe_ids), big.mark = ","))
say("grants whose candidate list contains an arm pair: %s (%.1f%%)",
    format(uniqueN(pairs$grant_id), big.mark = ","),
    100 * uniqueN(pairs$grant_id) / length(maybe_ids))
say("distinct EIN pairs                              : %s",
    format(uniqueN(pairs[, paste(pmin(arm_ein, op_ein), pmax(arm_ein, op_ein))]), big.mark = ","))
say("")
say("which one does the cascade currently rank first?")
print(pairs[, .N, by = .(first = fifelse(arm_rank < op_rank, "the ARM", "the OPERATING org"))],
      row.names = FALSE)

## ------------------------------------------------- can the sources link them?
up <- unique(pairs[, .(arm_ein, op_ein)])
up[, k1 := paste(arm_ein, op_ein)]
up[, k2 := paste(op_ein, arm_ein)]
lk <- function(keys, tbl) keys %in% paste(tbl$a, tbl$b)
up[, `:=`(
  sa_fwd = lk(k1, sa_l),          # the arm files Schedule A naming the operating org
  sa_rev = lk(k2, sa_l),
  sr_any = lk(k1, sr_l) | lk(k2, sr_l))]
i1 <- match(up$arm_ein, bm$ein); i2 <- match(up$op_ein, bm$ein)
g1 <- bm$group_exemption_number[i1]; g2 <- bm$group_exemption_number[i2]
up[, grp_same := !is.na(g1) & !is.na(g2) & nzchar(g1) & nzchar(g2) &
                 !grepl("^0+$", g1) & g1 == g2]   # 0000 = no group ruling
up[, in_bmf := !is.na(i1) & !is.na(i2)]
up[, any_src := sa_fwd | sa_rev | sr_any | grp_same]

hr(); say("HOW OFTEN IS THE PAIR ACTUALLY DISCLOSED?"); hr()
n <- nrow(up)
f <- function(v, lbl) say("  %-46s %5d  %5.1f%%", lbl, sum(v), 100 * mean(v))
say("distinct arm/operating EIN pairs: %d", n)
f(up$sa_fwd,  "Schedule A: the arm names the operating org")
f(up$sa_rev,  "Schedule A: reverse direction")
f(up$sr_any,  "Schedule R Part II: either direction")
f(up$grp_same,"BMF: same group exemption number")
say("")
f(up$any_src, "ANY of the above")
f(up$sa_fwd | up$sa_rev, "Schedule A, either direction")
say("")
say("Schedule R alone catches %d pairs Schedule A misses; Schedule A alone catches %d.",
    sum(up$sr_any & !(up$sa_fwd | up$sa_rev)), sum((up$sa_fwd | up$sa_rev) & !up$sr_any))

fwrite(merge(pairs, up[, .(arm_ein, op_ein, sa_fwd, sa_rev, sr_any, grp_same, any_src)],
             by = c("arm_ein", "op_ein")),
       file.path(PF, "data-dev", "MAYBE-ARM-PAIRS.csv"))
say("")
say("wrote data-dev/MAYBE-ARM-PAIRS.csv")

## ------------------------------------------- why are the rest not disclosed?
hr(); say("WHY THE UNDISCLOSED PAIRS ARE UNDISCLOSED"); hr()
files_sa <- unique(sa_l$a); files_sr <- unique(sr_l$a)
up[, `:=`(arm_files_sa = arm_ein %in% files_sa, arm_files_sr = arm_ein %in% files_sr,
          op_files_sa  = op_ein  %in% files_sa, op_files_sr  = op_ein  %in% files_sr)]
miss <- up[any_src == FALSE]
say("pairs with no link from any source: %d of %d", nrow(miss), nrow(up))
say("  neither party files Schedule A or R at all : %d (%.0f%%)",
    sum(!miss$arm_files_sa & !miss$arm_files_sr & !miss$op_files_sa & !miss$op_files_sr),
    100 * mean(!miss$arm_files_sa & !miss$arm_files_sr & !miss$op_files_sa & !miss$op_files_sr))
say("  the arm files a schedule but not naming this EIN : %d",
    sum((miss$arm_files_sa | miss$arm_files_sr)))
say("")
say("A supporting organization that files 990-EZ or 990-N never produces a")
say("Schedule A Part I line 12 table, and a filer only completes Schedule R if it")
say("answered yes to Part IV line 34. Non-disclosure is mostly non-filing.")

hr(); say("SAMPLE OF DETECTED PAIRS"); hr()
ex <- unique(pairs[, .(core, arm_nm, op_nm, arm_ein, op_ein, arm_rank, op_rank)])
ex <- merge(ex, up[, .(arm_ein, op_ein, sa_fwd, sr_any, grp_same, any_src)],
            by = c("arm_ein", "op_ein"))
set.seed(11)
s <- ex[sample(.N, min(25L, .N))]
for (i in seq_len(nrow(s))) {
  cat(sprintf("  %-40s | %-40s | %s%s%s r=%s/%s
",
      substr(s$arm_nm[i], 1, 40), substr(s$op_nm[i], 1, 40),
      ifelse(s$sa_fwd[i], "SchA ", "     "),
      ifelse(s$sr_any[i], "SchR ", "     "),
      ifelse(s$grp_same[i], "GRP", "   "), s$arm_rank[i], s$op_rank[i]))
}
fwrite(ex, file.path(PF, "data-dev", "ARM-PAIR-EXAMPLES.csv"))
