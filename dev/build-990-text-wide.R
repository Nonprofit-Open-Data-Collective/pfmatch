#!/usr/bin/env Rscript
# Build a one-row-per-OBJECTID table of Form 990 Part III narrative text.
#
#   mission                 <- F9-P03-T00-MISSION-2022        (Part III line 1)
#   program_01              <- F9-P03-T00-PROGRAM-ONE-2022    (Part III line 4a)
#   program_02              <- F9-P03-T00-PROGRAM-TWO-2022    (line 4b)
#   program_03              <- F9-P03-T00-PROGRAM-THREE-2022  (line 4c)
#   program_04 .. program_N <- F9-P03-T01-PROGRAMS-OTHER-2022 (line 4d, repeating)
#
# Slots are the 990 line, NOT a compacted sequence: an org that filled only
# line 4b leaves program_01 empty.  That keeps the wide table joinable back to
# the source rows.
#
# Outputs (data-dev/):
#   F9-P03-TEXT-LONG-2022.csv  tidy, one row per OID x program  (canonical)
#   F9-P03-TEXT-WIDE-2022.csv  one row per OID, PROG_SLOTS slots + overflow
#   F9-P03-TEXT-WIDE-2022.rds  same, as an R object

suppressPackageStartupMessages(library(data.table))
setDTthreads(0)

ROOT   <- Sys.getenv("PFMATCH_DIR", ".")
DATA   <- file.path(ROOT, "inputs")
OUT    <- file.path(ROOT, "data-dev")
YEAR   <- "2022"

PROG_SLOTS <- 10L   # 99.3% of returns fit; the rest roll into prog_overflow_desc

KEYS <- c("OBJECTID", "EIN2", "ORG_EIN", "ORG_NAME_L1", "ORG_NAME_L2",
          "RETURN_TYPE", "TAX_YEAR", "TAX_PERIOD_END_DATE", "URL")
PFLD <- c("F9_03_PROG_DESC", "F9_03_PROG_EXP", "F9_03_PROG_GRANT", "F9_03_PROG_REV")

rd <- function(f, cols)
  fread(file.path(DATA, f), select = cols, colClasses = "character",
        showProgress = FALSE, na.strings = NULL)

msg <- function(...) cat(sprintf(...), "\n", sep = "")

## ---- 1. mission -----------------------------------------------------------
msg("reading mission ...")
mis <- rd(sprintf("F9-P03-T00-MISSION-%s.csv", YEAR),
          c(KEYS, "F9_03_ORG_MISSION_PURPOSE"))
setnames(mis, "F9_03_ORG_MISSION_PURPOSE", "mission")
dup <- sum(duplicated(mis$OBJECTID))
if (dup) { msg("  dropping %d duplicate OBJECTID rows", dup)
           mis <- mis[!duplicated(OBJECTID)] }
msg("  %d returns, %d distinct EINs", nrow(mis), uniqueN(mis$ORG_EIN))

## ---- 2. programs -> long --------------------------------------------------
one_of <- function(file, slot) {
  x <- rd(file, c("OBJECTID", PFLD))
  x[, prog_slot := slot]
  x
}
msg("reading programs ...")
long <- rbindlist(list(
  one_of(sprintf("F9-P03-T00-PROGRAM-ONE-%s.csv",   YEAR), 1L),
  one_of(sprintf("F9-P03-T00-PROGRAM-TWO-%s.csv",   YEAR), 2L),
  one_of(sprintf("F9-P03-T00-PROGRAM-THREE-%s.csv", YEAR), 3L)))

oth <- rd(sprintf("F9-P03-T01-PROGRAMS-OTHER-%s.csv", YEAR),
          c("OBJECTID", "TABLE_ID", PFLD))
setorder(oth, OBJECTID, TABLE_ID)
oth[, prog_slot := 3L + seq_len(.N), by = OBJECTID]   # line 4d -> slots 4, 5, ...
oth[, TABLE_ID := NULL]

long <- rbindlist(list(long, oth), use.names = TRUE)
setnames(long, PFLD, c("prog_desc", "prog_exp", "prog_grant", "prog_rev"))
setorder(long, OBJECTID, prog_slot)
dupp <- sum(duplicated(long, by = c("OBJECTID", "prog_slot")))
if (dupp) { msg("  dropping %d duplicate OBJECTID/slot rows", dupp)
            long <- unique(long, by = c("OBJECTID", "prog_slot")) }
msg("  %d program rows over %d returns", nrow(long), uniqueN(long$OBJECTID))

fwrite(long, file.path(OUT, sprintf("F9-P03-TEXT-LONG-%s.csv", YEAR)))

## ---- 3. long -> wide ------------------------------------------------------
msg("pivoting to %d slots ...", PROG_SLOTS)
num <- function(v) { v <- suppressWarnings(as.numeric(v)); v[is.na(v)] <- 0; v }

tail_ <- long[prog_slot > PROG_SLOTS]
head_ <- long[prog_slot <= PROG_SLOTS]

wide <- dcast(head_, OBJECTID ~ prog_slot,
              value.var = c("prog_desc", "prog_exp", "prog_grant", "prog_rev"),
              fill = NA_character_)
# prog_desc_1 -> program_01_desc
for (nm in setdiff(names(wide), "OBJECTID")) {
  p <- regmatches(nm, regexpr("[0-9]+$", nm))
  f <- sub("^prog_", "", sub("_[0-9]+$", "", nm))
  setnames(wide, nm, sprintf("program_%02d_%s", as.integer(p), f))
}
setcolorder(wide, c("OBJECTID",
  unlist(lapply(seq_len(PROG_SLOTS),
    function(i) sprintf("program_%02d_%s", i, c("desc","exp","grant","rev"))))))

ovf <- tail_[, .(prog_overflow_n     = .N,
                 prog_overflow_desc  = paste(prog_desc, collapse = " "),
                 prog_overflow_exp   = sum(num(prog_exp)),
                 prog_overflow_grant = sum(num(prog_grant)),
                 prog_overflow_rev   = sum(num(prog_rev))), by = OBJECTID]

cnt <- long[, .(n_programs = .N,
                n_programs_with_text = sum(nzchar(trimws(prog_desc)))), by = OBJECTID]

out <- Reduce(function(a, b) merge(a, b, by = "OBJECTID", all.x = TRUE),
              list(mis, cnt, wide, ovf))
out[is.na(n_programs),           `:=`(n_programs = 0L, n_programs_with_text = 0L)]
out[is.na(prog_overflow_n),      prog_overflow_n := 0L]
out[, has_mission := nzchar(trimws(mission))]

fwrite(out, file.path(OUT, sprintf("F9-P03-TEXT-WIDE-%s.csv", YEAR)))
saveRDS(out, file.path(OUT, sprintf("F9-P03-TEXT-WIDE-%s.rds", YEAR)), compress = FALSE)

## ---- 4. read-out ----------------------------------------------------------
msg("")
msg("wide: %d rows x %d cols", nrow(out), ncol(out))
msg("  with mission text        %6d (%4.1f%%)", sum(out$has_mission), 100*mean(out$has_mission))
msg("  with >=1 program text    %6d (%4.1f%%)", sum(out$n_programs_with_text > 0),
    100*mean(out$n_programs_with_text > 0))
msg("  with neither             %6d (%4.1f%%)",
    sum(!out$has_mission & out$n_programs_with_text == 0),
    100*mean(!out$has_mission & out$n_programs_with_text == 0))
msg("  overflow (>%d programs)  %6d", PROG_SLOTS, sum(out$prog_overflow_n > 0))
msg("")
msg("returns per RETURN_TYPE:"); print(out[, .N, by = RETURN_TYPE][order(-N)])
msg("programs per return:");     print(quantile(out$n_programs, c(.5,.9,.99,.999,1)))
nch <- out[, nchar(mission)]
msg("mission nchar quantiles:"); print(quantile(nch, c(.1,.5,.9,.99,1)))
