#!/usr/bin/env Rscript
# Prepare the publishable artifacts for s3://nccs-efile/dev/pfmatch/grants/.
# Builds locally and verifies; uploads only when PF_UPLOAD=1.
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("-", 78))

HOME <- "C:/Users/jlecy/Documents/grants"
CSV  <- file.path(HOME, "PF-GRANTS-PAID-2009-2025.csv")
GZ   <- paste0(CSV, ".gz")
STAGE <- file.path(HOME, "publish"); dir.create(STAGE, showWarnings = FALSE)
S3   <- "s3://nccs-efile/dev/pfmatch/grants"

## ---- compress --------------------------------------------------------------
if (!file.exists(GZ)) {
  hr(); say("compressing %.2f GB ...", file.size(CSV) / 2^30)
  t0 <- proc.time()[["elapsed"]]
  system2("gzip", c("-6", "-k", shQuote(CSV)))
  say("  -> %.2f GB in %.1f min", file.size(GZ) / 2^30,
      (proc.time()[["elapsed"]] - t0) / 60)
}

md5 <- function(p) unname(tools::md5sum(p))

## ---- manifest --------------------------------------------------------------
hr(); say("manifest")
log <- fread(file.path(HOME, "efilepf-build-log.csv"), colClasses = "character")
log[, rows := as.integer(rows)]

src <- data.table(
  year = as.character(2009:2025),
  source_file = sprintf("PF-P15-T01-SUPPLEMENTARY-INFO-GRANT-PAID-%d.CSV", 2009:2025))
src[, source_md5 := vapply(file.path(HOME, "efilepf", source_file), md5, "")]
src[, source_bytes := as.numeric(file.size(file.path(HOME, "efilepf", source_file)))]

man <- merge(log, src, by = "year", all = TRUE)
setcolorder(man, c("year", "rows", "missing_cols", "source_file",
                   "source_md5", "source_bytes"))
fwrite(man, file.path(STAGE, "MANIFEST-BY-YEAR.csv"))
say("  MANIFEST-BY-YEAR.csv  (%d years, %s rows)",
    nrow(man), format(sum(man$rows), big.mark = ","))

out <- data.table(
  artifact = c("PF-GRANTS-PAID-2009-2025.csv.gz", "MANIFEST-BY-YEAR.csv", "README.md"),
  role = c("rebuilt 990-PF Part XV grants-paid, GTDC-compatible schema",
           "per-year rows, md5 and bytes of each source extract",
           "provenance, column mapping, known gaps, rebuild instructions"))
out[, bytes := NA_real_][, md5 := NA_character_]
out[1, `:=`(bytes = as.numeric(file.size(GZ)), md5 = md5(GZ))]
out[2, `:=`(bytes = as.numeric(file.size(file.path(STAGE, "MANIFEST-BY-YEAR.csv"))),
            md5 = md5(file.path(STAGE, "MANIFEST-BY-YEAR.csv")))]
rd <- file.path(STAGE, "README.md")
if (file.exists(rd)) out[3, `:=`(bytes = as.numeric(file.size(rd)), md5 = md5(rd))]
fwrite(out, file.path(STAGE, "MANIFEST.csv"))
say("  MANIFEST.csv")
print(out[, .(artifact, bytes = round(bytes / 2^20, 1), md5)], row.names = FALSE)

## ---- upload ----------------------------------------------------------------
if (Sys.getenv("PF_UPLOAD") != "1") {
  hr(); say("PF_UPLOAD not set -- built locally, nothing uploaded.")
  say("staged in %s", STAGE)
  quit(save = "no")
}
hr(); say("uploading to %s", S3)
for (f in c(GZ, file.path(STAGE, c("MANIFEST-BY-YEAR.csv", "MANIFEST.csv", "README.md")))) {
  if (!file.exists(f)) { say("  MISSING %s", basename(f)); next }
  say("  %s (%.1f MB) ...", basename(f), file.size(f) / 2^20)
  st <- system2("aws", c("s3", "cp", shQuote(f), sprintf("%s/%s", S3, basename(f)),
                         "--only-show-errors"))
  say("    %s", if (st == 0) "ok" else sprintf("FAILED (exit %d)", st))
}
say("")
system2("aws", c("s3", "ls", paste0(S3, "/"), "--human-readable"))
