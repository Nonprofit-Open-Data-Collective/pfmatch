#!/usr/bin/env Rscript
# ============================================================================
# Build the shipping dyad table and characterise it.
#
#   data-dev/PF-DYADS.rds   the table, class pf_dyads
#   data-dev/PF-DYADS.csv   the same, for anything outside R
#
# Source: linkid's dyad_ extracts. The efile_ variants of the same two tables
# carry no filer EIN - only OBJECTID - and cannot be used here.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("=", 78), "\n")
sub <- function() cat(strrep("-", 78), "\n")

BMF <- file.path(PF, "..", "npmatch", "data-raw", "bmf_2026_01_processed.csv")
SRC <- pf_dyad_sources("C:/Users/jdlec/Documents/grants/linkid/out/full")

hr(); say("BUILD"); hr()
d <- pf_build_dyads(SRC$supported, SRC$related, bmf = BMF,
                    cache = file.path(PF, "data-dev", "PF-DYADS.rds"))
pf_dyad_summary(d)

hr(); say("COMPOSITION"); hr()
sub(); say("class by reason"); sub()
print(d[, .(pairs = .N, pct = round(100*.N/nrow(d), 1)),
        by = .(dyad_class, dyad_reason)][order(dyad_class, -pairs)], row.names = FALSE)

sub(); say("class by source"); sub()
print(d[, .(pairs = .N), by = .(dyad_class,
        source = fifelse(src_a & src_r, "both",
                 fifelse(src_a, "Schedule A only", "Schedule R only")))][
        order(dyad_class, -pairs)], row.names = FALSE)

sub(); say("geography and persistence"); sub()
say("both EINs in the BMF     : %s (%.0f%%)",
    format(sum(d$in_bmf, na.rm = TRUE), big.mark=","), 100*mean(d$in_bmf, na.rm=TRUE))
say("same state               : %s (%.0f%%)",
    format(sum(d$same_state, na.rm=TRUE), big.mark=","), 100*mean(d$same_state, na.rm=TRUE))
say("same city                : %s (%.0f%%)",
    format(sum(d$same_city, na.rm=TRUE), big.mark=","), 100*mean(d$same_city, na.rm=TRUE))
say("")
print(d[, .(pairs = .N), by = .(dyad_class, years = cut(n_years, c(0,1,2,5,10,Inf),
      labels = c("1","2","3-5","6-10","11+")))][order(dyad_class, years)], row.names = FALSE)

sub(); say("WHY PAIRS WERE KEPT OUT OF substitutable"); sub()
print(d[dyad_class == "related", .(pairs = .N),
        by = .(reason = base::sub("^.*demoted: ", "demoted: ", dyad_reason))][order(-pairs)],
      row.names = FALSE)
say("")
say("Schedule A edges rejected for fan-out (the supporter is a grantmaker,")
say("not an arm) - the biggest offenders:")
sa <- d[!is.na(sched_a_dir)]
sa[, sup := fifelse(sched_a_dir == "a_supports_b", ein_a, ein_b)]
sa[, sup_nm := fifelse(sched_a_dir == "a_supports_b", name_a, name_b)]
print(head(unique(sa[fan_out > 3L, .(sup, nm = substr(sup_nm,1,44), fan_out)],
                  by = "sup")[order(-fan_out)], 10), row.names = FALSE)

sub(); say("SUBSTITUTABLE EXAMPLES"); sub()
print(head(d[dyad_class == "substitutable" & same_city == TRUE,
             .(a = substr(name_a,1,36), b = substr(name_b,1,36), dyad_reason)], 15),
      row.names = FALSE)

sub(); say("RELATED-ONLY EXAMPLES - never collapse these"); sub()
print(head(d[dyad_class == "related" & same_city == TRUE,
             .(a = substr(name_a,1,36), b = substr(name_b,1,36))], 15),
      row.names = FALSE)

## ---------------------------------------------- degree, as a safety report
sub(); say("DEGREE - the hub check"); sub()
deg <- rbind(d[, .(ein = ein_a, dyad_class)], d[, .(ein = ein_b, dyad_class)])[
       , .(deg_all = .N, deg_sub = sum(dyad_class == "substitutable")), by = ein]
say("EINs in the table: %s", format(nrow(deg), big.mark=","))
print(table(all = cut(deg$deg_all, c(0,1,2,3,6,11,26,Inf), right = FALSE,
                      labels = c("1","2","3","4-5","6-10","11-25","26+"))))
print(table(substitutable_only = cut(deg$deg_sub, c(0,1,2,3,6,11,26,Inf), right = FALSE,
                      labels = c("0","1","2","3-5","6-10","11-25","26+"))))
say("")
say("max substitutable degree: %d - the worst case a collapse could reach",
    max(deg$deg_sub))
print(head(deg[order(-deg_sub)][, .(ein, deg_sub, deg_all)], 8), row.names = FALSE)

fwrite(d, file.path(PF, "data-dev", "PF-DYADS.csv"))
say(""); say("wrote data-dev/PF-DYADS.rds and .csv")
