#!/usr/bin/env Rscript
# ============================================================================
# What does the triangulation sample actually span, and what is the ceiling?
#
# The premise to test: grouping recipients ACROSS YEARS should multiply the
# informative cases, because an organisation written one way in 2019 and
# another in 2023 is exactly the comparator failure triangulation exists to
# find -- and the split outcome (one rendering cleared, the other did not) is
# what makes a case informative rather than merely duplicated.
#
# So: is the current sample single-year or already multi-year, how much of its
# signal comes from cross-year pairs, and how far does the full corpus go.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("-", 80))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))

M <- readRDS(file.path(PF, "data-dev", "FILER-SAMPLE-MATCH.rds"))
g <- as.data.table(M$grants)
say("FILER-SAMPLE-MATCH grants: %s", format(nrow(g), big.mark = ","))
yr <- if ("TAXYEAR" %in% names(g)) "TAXYEAR" else "TAX_YEAR"

hr(); say("TAX YEARS IN THE TRIANGULATION SOURCE")
ty <- g[, .N, by = c(yr)][order(get(yr))]
for (i in seq_len(nrow(ty)))
  say("  %-6s %8s  %5.1f%%", ty[[yr]][i], format(ty$N[i], big.mark = ","),
      100 * ty$N[i] / nrow(g))
say("  -> %d distinct tax years", nrow(ty))

## ---- how multi-year are the groups? ----------------------------------------
grp <- fread(file.path(PF, "data-dev", "TRIANGULATION-GROUPS.csv"),
             colClasses = "character")
gi <- g[, .(grant_id, tax_year = as.character(get(yr)))]
grp <- merge(grp, gi, by = "grant_id", all.x = TRUE)

hr(); say("GROUP SPAN  (a group is one address; members are renderings there)")
sp <- grp[, .(n_rows = .N, n_years = uniqueN(tax_year),
              n_names = uniqueN(recip_name)), by = group_id]
say("  groups                     %s", format(nrow(sp), big.mark = ","))
say("  single-year groups         %s  (%4.1f%%)",
    format(sum(sp$n_years == 1L), big.mark = ","), 100 * mean(sp$n_years == 1L))
say("  multi-year groups          %s  (%4.1f%%)",
    format(sum(sp$n_years > 1L), big.mark = ","), 100 * mean(sp$n_years > 1L))
say("  median years per group     %d   max %d", median(sp$n_years), max(sp$n_years))
say("  groups with >1 NAME        %s  (%4.1f%%)   <- the variant-spelling cases",
    format(sum(sp$n_names > 1L), big.mark = ","), 100 * mean(sp$n_names > 1L))

hr(); say("WHERE THE NAME VARIANTS COME FROM")
say("  of groups with >1 name, how many span >1 year:")
v <- sp[n_names > 1L]
say("    multi-year %s of %s  (%4.1f%%)",
    format(sum(v$n_years > 1L), big.mark = ","), format(nrow(v), big.mark = ","),
    100 * mean(v$n_years > 1L))
say("  So cross-year pairing is %s the source of variant renderings.",
    if (mean(v$n_years > 1L) > 0.5) "ALREADY the dominant" else "NOT yet the main")

## ---- the ceiling -------------------------------------------------------------
hr(); say("CEILING: the same grouping over the full deduplicated corpus")
V2 <- "C:/Users/jlecy/Documents/grants/PF-GRANTS-PAID-V2-2009-2025.csv"
if (file.exists(V2)) {
  hdr <- names(fread(V2, nrows = 0L))
  KEEP <- c("PF_15_G_PAID_RECIP_ADDR_L1", "PF_15_G_PAID_RECIP_ADDR_ZIP",
            "PF_15_G_PAID_RECIP_NAME_ORG_L1", "TAX_YEAR")
  sel <- sort(match(KEEP, hdr))
  acc <- list(); i <- 0L; seen <- 0L; CH <- 2000000L
  repeat {
    ch <- fread(V2, colClasses = "character", na.strings = NULL,
                skip = 1L + i * CH, nrows = CH, header = FALSE,
                select = sel, col.names = hdr[sel], showProgress = FALSE)
    nn <- nrow(ch); if (!nn) break
    seen <- seen + nn; i <- i + 1L
    ch[, k := paste(toupper(gsub("[^A-Z0-9]", "", toupper(PF_15_G_PAID_RECIP_ADDR_L1))),
                    substr(gsub("[^0-9]", "", PF_15_G_PAID_RECIP_ADDR_ZIP), 1, 5),
                    sep = "|")]
    ch <- ch[nzchar(gsub("[|]", "", k))]
    acc[[i]] <- ch[, .(n = .N, yrs = uniqueN(TAX_YEAR),
                       nm = uniqueN(PF_15_G_PAID_RECIP_NAME_ORG_L1)), by = k]
    rm(ch)
    if (nn < CH) break
  }
  z <- rbindlist(acc)[, .(n = sum(n), yrs = max(yrs), nm = max(nm)), by = k]
  rm(acc); invisible(gc())
  say("  scanned %s rows", format(seen, big.mark = ","))
  say("  distinct address keys         %s", format(nrow(z), big.mark = ","))
  say("  keys with >1 grant            %s", format(sum(z$n > 1L), big.mark = ","))
  say("  keys with >1 NAME rendering   %s   <- the triangulation universe",
      format(sum(z$nm > 1L), big.mark = ","))
  say("  keys with >1 name AND >1 year %s", format(sum(z$nm > 1L & z$yrs > 1L), big.mark = ","))
  say("")
  say("  against the current sample's %s groups with >1 name",
      format(sum(sp$n_names > 1L), big.mark = ","))
  say("  -> roughly %.0fx more available at full-corpus scale",
      sum(z$nm > 1L) / max(1L, sum(sp$n_names > 1L)))
  say("")
  say("  NOTE this counts the GROUPING universe, not informative cases. A case")
  say("  is informative only when the renderings got DIFFERENT verdicts, which")
  say("  needs a match run and cannot be counted from the grant file alone.")
} else {
  say("  v2 corpus absent; skipped")
}
hr()
