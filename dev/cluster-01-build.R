#!/usr/bin/env Rscript
# ============================================================================
# Phase 1 - build a pooled, multi-year EIN-to-EIN link table from linkid's
# dyad extracts, and characterise it.
#
#   dyad_supported_orgs.csv        Sch A Part I line 12g  (supporting -> supported)
#   dyad_related_exempt_orgs.csv   Sch R Part II          (filer <-> related exempt)
#
# The 2022-only build in dev/build-arm-links.R linked 49% of name-detected arm
# pairs. These files cover 2009-2023, so the first question is simply how much
# pooling buys, and the second is whether the pooled graph is still safe to
# take connected components of.
#
# Output: data-dev/CLUSTER-PAIRS.rds
# ============================================================================
suppressWarnings(suppressMessages({library(data.table); library(duckdb); library(DBI)}))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
DIR <- "C:/Users/jdlec/Documents/grants/linkid/out/full"
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 78), "\n")

con <- dbConnect(duckdb::duckdb())
dbExecute(con, "PRAGMA threads=6; PRAGMA memory_limit='12GB'")
dbExecute(con, sprintf("PRAGMA temp_directory='%s'",
                       file.path(tempdir(), "duck")))

pull <- function(file, tag) {
  q <- sprintf("
    SELECT ego_ein, alter_ein, tax_year, alter_name, alter_state, alter_city,
           direction, ego_controls_alter, alter_controls_ego, rel_type,
           alter_ein_valid, is_self_loop
    FROM read_csv('%s', header=true, all_varchar=true,
                  sample_size=-1, ignore_errors=true)", file)
  d <- as.data.table(dbGetQuery(con, q))
  d[, src := tag][]
}

say("reading Schedule A supported orgs ...")
sa <- pull(file.path(DIR, "dyad_supported_orgs.csv"), "SCHED_A")
say("  rows: %s", format(nrow(sa), big.mark = ","))

say("reading Schedule R related exempt orgs ...")
sr <- pull(file.path(DIR, "dyad_related_exempt_orgs.csv"), "SCHED_R")
say("  rows: %s", format(nrow(sr), big.mark = ","))

d <- rbindlist(list(sa, sr), use.names = TRUE)
rm(sa, sr); gc()

e9 <- function(x) { x <- gsub("[^0-9]", "", as.character(x))
                    fifelse(nchar(x) == 9L & !grepl("^0{9}$", x), x, NA_character_) }

hr(); say("RAW ROW COUNTS AND EIN AVAILABILITY"); hr()
d[, `:=`(a = e9(ego_ein), b = e9(alter_ein), year = as.integer(tax_year))]
print(d[, .(rows = .N,
            ego_ein_ok  = sum(!is.na(a)),
            alter_ein_ok = sum(!is.na(b)),
            pct_alter_ein = round(100 * mean(!is.na(b)), 1),
            both_ok = sum(!is.na(a) & !is.na(b)),
            self_loop = sum(a == b, na.rm = TRUE)), by = src])

hr(); say("ROWS BY TAX YEAR"); hr()
print(dcast(d[!is.na(year), .N, by = .(src, year)], year ~ src, value.var = "N"))

## ------------------------------------------------------------ the pair table
p <- d[!is.na(a) & !is.na(b) & a != b]
p[, `:=`(x = pmin(a, b), y = pmax(a, b))]

pairs <- p[, .(n_rows   = .N,
               n_years  = uniqueN(year),
               yr_min   = min(year, na.rm = TRUE),
               yr_max   = max(year, na.rm = TRUE),
               sched_a  = as.integer(any(src == "SCHED_A")),
               sched_r  = as.integer(any(src == "SCHED_R")),
               ctrl     = as.integer(any(ego_controls_alter %in% c("true","TRUE") |
                                         alter_controls_ego %in% c("true","TRUE")))),
           by = .(x, y)]

hr(); say("POOLED PAIR TABLE"); hr()
say("distinct undirected EIN pairs        : %s", format(nrow(pairs), big.mark = ","))
say("  Schedule A only                    : %s", format(sum(pairs$sched_a == 1 & pairs$sched_r == 0), big.mark=","))
say("  Schedule R only                    : %s", format(sum(pairs$sched_r == 1 & pairs$sched_a == 0), big.mark=","))
say("  both                               : %s", format(sum(pairs$sched_a == 1 & pairs$sched_r == 1), big.mark=","))
say("distinct EINs appearing              : %s", format(uniqueN(c(pairs$x, pairs$y)), big.mark = ","))
say("")
say("pairs seen in exactly one tax year   : %s (%.0f%%)",
    format(sum(pairs$n_years == 1), big.mark=","), 100*mean(pairs$n_years == 1))
say("pairs seen in 5+ tax years           : %s (%.0f%%)",
    format(sum(pairs$n_years >= 5), big.mark=","), 100*mean(pairs$n_years >= 5))

hr(); say("HOW MUCH DOES POOLING BUY OVER A SINGLE YEAR?"); hr()
for (yy in c(2018, 2020, 2021, 2022)) {
  one <- unique(p[year == yy, .(x, y)])
  say("tax year %d alone: %s pairs (%.0f%% of pooled)", yy,
      format(nrow(one), big.mark=","), 100 * nrow(one) / nrow(pairs))
}
# cumulative growth
cum <- sapply(sort(unique(p$year)), function(yy)
  uniqueN(p[year <= yy, paste(x, y)]))
print(data.table(through_year = sort(unique(p$year)), cumulative_pairs = cum))

## ------------------------------------------------------- directed supporting
sup <- unique(p[src == "SCHED_A", .(supporter = a, supported = b)])
say("")
say("directed Schedule A supporter->supported pairs: %s", format(nrow(sup), big.mark=","))

saveRDS(list(pairs = pairs, sup = sup,
             alter_geo = unique(p[!is.na(b), .(ein = b, name = alter_name,
                                               state = alter_state, city = alter_city)],
                                by = "ein")),
        file.path(PF, "data-dev", "CLUSTER-PAIRS.rds"), compress = FALSE)
say("wrote data-dev/CLUSTER-PAIRS.rds")
dbDisconnect(con, shutdown = TRUE)
