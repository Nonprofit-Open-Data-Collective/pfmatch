#!/usr/bin/env Rscript
# ============================================================================
# make-nteev2.R -- build the bundled NTEE lookup from the two NCCS source files.
#
# Run from the package root after dropping a newer vintage into inputs/:
#   Rscript data-raw/make-nteev2.R
#
# Produces data/nteev2.rda, a 1,086-row table keyed twice -- by the NTEEv2
# three-part code (ART-A00-AA) and by the legacy three-character code (A23) --
# because the BMF populates the two unevenly. On the audit sample the NTEEv2 key
# resolves 38% of candidates and the legacy key a further 51%, 89% combined.
#
# The source CSVs carry stray Latin-1 bytes, which is why everything is passed
# through iconv on the way in.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))

IN <- Sys.getenv("PFMATCH_INPUTS", "inputs")

u8 <- function(dt) {
  for (j in names(dt))
    set(dt, j = j, value = iconv(dt[[j]], "UTF-8", "UTF-8", sub = " "))
  dt
}
rd <- function(p) u8(fread(file.path(IN, p), colClasses = "character",
                           na.strings = NULL, showProgress = FALSE))
sq <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; x }

tidy <- rd("nteev2-descriptions-tidy-format.csv")
desc <- rd("nteev2-descriptions.csv")
setnames(desc, c("Level 1", "Levels 2-4", "Level 5",
                 "Category Name", "Category Description"),
               c("l1", "l24", "l5", "cat_name", "cat_desc"))
desc[, NTEE2 := paste(l1, l24, l5, sep = "-")]

tidy[, ref := trimws(gsub("  *", " ", paste(
  sq(level3.label), sq(level4.label), sq(level5.label),
  ifelse(keywords == "NA", "", sq(keywords)))))]

v2 <- merge(tidy[, .(NTEE2, ntee = NTEE, level1, level4, ref)],
            desc[, .(NTEE2, cat_name, cat_desc)], by = "NTEE2", all.x = TRUE)
v2[, ref := trimws(gsub("  *", " ", paste(ref, sq(cat_name), sq(cat_desc))))]
v2[, .rlen := nchar(ref)]

# Several legacy codes collapse onto one NTEEv2 code (B80, B8040, B8043 all
# map to EDU-B80-RG), and only some carry keywords. Keep one row per key,
# preferring the richest description, so the lookup is a function of the key
# rather than of incidental row order.
setorder(v2, NTEE2, -.rlen)
v2u <- v2[!duplicated(NTEE2)]

nteev2 <- list(
  by_v2     = v2u[, .(key = NTEE2, ref)],
  by_legacy = unique(v2[nzchar(level4), .(key = level4, ref)], by = "key"),
  codes     = v2[, .(NTEE2, ntee, level1, level4, cat_name)])

stopifnot(nrow(nteev2$by_v2) > 1000, nrow(nteev2$by_legacy) > 400,
          !anyDuplicated(nteev2$by_v2$key), !anyDuplicated(nteev2$by_legacy$key),
          all(nzchar(nteev2$by_v2$key)))

dir.create("data", showWarnings = FALSE)
save(nteev2, file = "data/nteev2.rda", compress = "xz")
cat(sprintf("data/nteev2.rda: %d NTEEv2 keys, %d legacy keys, %.0f KB\n",
            nrow(nteev2$by_v2), nrow(nteev2$by_legacy),
            file.size("data/nteev2.rda") / 1024))
