#!/usr/bin/env Rscript
# Compare the monthly processed BMF now in use against the NCCS unified BMF
# (one row per EIN, 1989-present). The unified file is longitudinal, so the
# question that matters is whether it carries the organisations the monthly
# snapshot has dropped -- in particular the 22,604 EINs that filed a 2022 Form
# 990 but are absent from the monthly file.
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(6L)
DR <- "C:/Users/jlecy/Dropbox/00 - URBAN/00-GITHUB/npmatch/data-raw"
EF <- "C:/Users/jlecy/Documents/grants/efile"
say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() { cat(strrep("-", 78), "\n"); flush.console() }
e9  <- function(x) { x <- gsub("[^0-9]", "", as.character(x))
                     ifelse(nchar(x) == 9L, x, NA_character_) }

files <- c(monthly = file.path(DR, "bmf_2026_01_processed.csv"),
           unified = file.path(DR, "bmf_unified_geocoded_2026-08-20.csv"))
if (!file.exists(files[["unified"]]))
  files[["unified"]] <- file.path(DR, "bmf_unified_geocoded.csv")

hr(); say("VINTAGE COMPARISON"); hr()
d <- list()
for (nm in names(files)) {
  p <- files[[nm]]
  x <- fread(p, colClasses = "character", showProgress = FALSE,
             select = c("ein", "org_name_join", "org_addr_state",
                        "status_code", "ruling_date"))
  x[, ein := e9(ein)]
  x <- x[!is.na(ein)]
  d[[nm]] <- x
  say("%-8s %-46s", nm, basename(p))
  say("         rows %s   distinct EINs %s   %.2f GB",
      format(nrow(x), big.mark = ","), format(uniqueN(x$ein), big.mark = ","),
      file.size(p) / 2^30)
}
mo <- unique(d$monthly$ein); un <- unique(d$unified$ein)
say("")
say("EINs in unified but NOT monthly : %s", format(length(setdiff(un, mo)), big.mark = ","))
say("EINs in monthly but NOT unified : %s", format(length(setdiff(mo, un)), big.mark = ","))
say("shared                          : %s", format(length(intersect(un, mo)), big.mark = ","))

hr(); say("DOES THE UNIFIED FILE CLOSE THE MISSING-FILER GAP?"); hr()
h <- fread(file.path(EF, "F9-P00-T00-HEADER-2022.CSV"), colClasses = "character",
           showProgress = FALSE, select = "ORG_EIN")
setnames(h, "ein"); h[, ein := e9(ein)]
filers <- unique(h$ein[!is.na(h$ein)])
say("distinct 2022 Form 990 filers        : %s", format(length(filers), big.mark = ","))
miss_mo <- setdiff(filers, mo); miss_un <- setdiff(filers, un)
say("  absent from the MONTHLY BMF        : %s (%.1f%%)",
    format(length(miss_mo), big.mark = ","), 100 * length(miss_mo) / length(filers))
say("  absent from the UNIFIED BMF        : %s (%.1f%%)",
    format(length(miss_un), big.mark = ","), 100 * length(miss_un) / length(filers))
say("  recovered by switching             : %s (%.1f%% of the gap)",
    format(length(miss_mo) - length(miss_un), big.mark = ","),
    100 * (length(miss_mo) - length(miss_un)) / max(1, length(miss_mo)))

hr(); say("AND THE SCHEDULE I RECIPIENT EINs?"); hr()
si <- fread(file.path(EF, "SI-P02-T01-GRANTS-US-ORGS-GOVTS-2022.CSV"),
            colClasses = "character", showProgress = FALSE,
            select = c("ORG_EIN", "SI_02_GRANT_US_ORG_EIN"))
setnames(si, c("filer", "ein")); si[, ein := e9(ein)]
si <- si[!is.na(ein)]
nf <- si[, .(n_filers = uniqueN(filer)), by = ein]
say("distinct Schedule I recipient EINs   : %s", format(nrow(nf), big.mark = ","))
for (b in list(list("monthly", mo), list("unified", un))) {
  m <- !(nf$ein %in% b[[2]])
  say("  absent from the %-8s BMF      : %s (%.1f%%)", b[[1]],
      format(sum(m), big.mark = ","), 100 * mean(m))
}
say("")
say("restricted to EINs corroborated by >= 2 distinct filers (the gate):")
g <- nf[n_filers >= 2]
for (b in list(list("monthly", mo), list("unified", un))) {
  m <- !(g$ein %in% b[[2]])
  say("  absent from the %-8s BMF      : %s of %s (%.1f%%)", b[[1]],
      format(sum(m), big.mark = ","), format(nrow(g), big.mark = ","), 100 * mean(m))
}

hr(); say("STATUS CODE MIX -- WHAT THE UNIFIED FILE ADDS"); hr()
add <- d$unified[ein %in% setdiff(un, mo)]
say("EINs unique to the unified file: %s", format(uniqueN(add$ein), big.mark = ","))
print(head(add[, .N, by = status_code][order(-N)], 8), row.names = FALSE)
say("")
say("A revoked or lapsed organisation still received the grant that a 990-PF")
say("reports. Carrying it in the reference is what lets the match succeed; the")
say("status code is then available downstream as a caveat.")
