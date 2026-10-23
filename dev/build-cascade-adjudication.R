#!/usr/bin/env Rscript
# ============================================================================
# Build the adjudication packet for the cells that decide the cascade.
#
# Not the whole MAYBE tier. Adjudicating 1,058 undifferentiated cases would
# produce a large artifact of uncertain quality -- when 200 were labelled in
# August, independent verification of a stratified subsample found roughly 45%
# of the labels survived unchanged. The three cells below are what actually
# parameterise the BMF-vs-matchdb trade-off, and they total 654 rather than
# 1,058.
#
#   cleared    244  MAYBE under BMF, YES under matchdb -- are tier 2's gains real?
#   changed     46  YES under both, different EIN      -- is tier 1 locking in errors?
#   demoted    364  YES under BMF, MAYBE under matchdb -- is matchdb right to doubt?
#
# Each case carries BOTH references' answers side by side plus the candidate
# text that was measured to resolve 45 of 56 hard cases
# (dev/ENRICHMENT-FINDINGS.md): NTEE definition, 990 mission, program
# descriptions.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("-", 78))
e9  <- function(v) { v <- gsub("[^0-9]", "", as.character(v))
                     ifelse(nchar(v) == 9L, v, NA_character_) }
sq  <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; x }

j <- fread(file.path(PF, "data-dev", "TWO-TIER-SIMULATION.csv"), colClasses = "character")
cells <- c("MAYBE->YES cleared", "YES->YES  EIN CHANGED", "YES->MAYBE  demoted")
d <- j[cell %in% cells]
say("disputed cases: %s", format(nrow(d), big.mark = ","))
print(d[, .N, by = cell], row.names = FALSE)

## ---- the grant as filed ----------------------------------------------------
g <- pf_read_grants(file.path(PF, "inputs"), pattern = "^ef1k_grants_")
g <- as.data.table(pf_prepare_grants(pf_recover_name_from_street(g)))
gk <- g[, .(id = grant_id, recip_name, recip_city, recip_state, recip_zip5,
            purpose = SIGOCPYPOGOC, amount = SIGOCPYAMOUN, taxyear = TAXYEAR,
            filer = FILERNAME1)]
d <- merge(d, gk, by = "id", all.x = TRUE)

## ---- BMF context for both candidate EINs -----------------------------------
# The monthly BMF is the WRONG context source here: tier 1 ran against the
# augmented UNIFIED reference, so an EIN present only in the unified file
# renders blank and the case looks like the BMF side found nothing. That
# biased the first 16 adjudications toward matchdb. Use the same file the run
# used, and fall back to matchdb names for EINs it alone carries.
BMF <- file.path(PF, "data-dev", "BMF-AUGMENTED-unified-fixed.csv")
b <- fread(BMF, colClasses = "character", showProgress = FALSE,
           select = c("ein", "org_name_join", "org_addr_city", "org_addr_state",
                      "org_addr_zip5", "subsection_code", "ntee_code_clean",
                      "ntee_code_definition"))
mdbn <- fread(file.path(PF, "data-dev", "REF-MATCHDB.csv"), colClasses="character",
              showProgress=FALSE, select=c("ein","org_name_join","org_addr_city",
                                           "org_addr_state","org_addr_zip5"))
mdbn[, ein := e9(ein)]
mdbn <- mdbn[!duplicated(ein)]
b[, ein := e9(ein)]
setkey(b, ein)
att <- function(dt, col, pre) {
  i <- match(dt[[col]], b$ein)
  m2 <- match(dt[[col]], mdbn$ein)
  fb <- function(v1, v2) ifelse(nzchar(sq(v1)), sq(v1), sq(v2))
  dt[, (paste0(pre, "_name"))  := fb(b$org_name_join[i], mdbn$org_name_join[m2])]
  dt[, (paste0(pre, "_city"))  := fb(b$org_addr_city[i], mdbn$org_addr_city[m2])]
  dt[, (paste0(pre, "_state")) := fb(b$org_addr_state[i], mdbn$org_addr_state[m2])]
  dt[, (paste0(pre, "_zip"))   := fb(b$org_addr_zip5[i], mdbn$org_addr_zip5[m2])]
  dt[, (paste0(pre, "_ntee"))  := trimws(paste(sq(b$ntee_code_clean[i]),
                                               sq(b$ntee_code_definition[i])))]
  dt
}
d <- att(d, "ein_a", "bmf")
d <- att(d, "ein_b", "mdb")

## ---- the 990 text that resolved 45 of 56 hard cases ------------------------
tx <- readRDS(file.path(PF, "data-dev", "ORG-TEXT-BUNDLE.rds"))
setkey(tx, ein)
for (p in c("a", "b")) {
  k <- match(d[[paste0("ein_", p)]], tx$ein)
  d[, (paste0(if (p == "a") "bmf" else "mdb", "_mission")) :=
      substr(sq(tx$mission[k]), 1, 300)]
  d[, (paste0(if (p == "a") "bmf" else "mdb", "_prog")) :=
      substr(sq(tx$prog_all[k]), 1, 300)]
}

keep <- c("id", "cell", "recip_name", "recip_city", "recip_state", "recip_zip5",
          "purpose", "amount", "taxyear", "filer",
          "ein_a", "bmf_name", "bmf_city", "bmf_state", "bmf_zip", "bmf_ntee",
          "bmf_mission", "bmf_prog", "score_a", "margin_a",
          "ein_b", "mdb_name", "mdb_city", "mdb_state", "mdb_zip", "mdb_ntee",
          "mdb_mission", "mdb_prog", "score_b", "margin_b")
keep <- intersect(keep, names(d))
out <- d[, ..keep]
out[, verdict := ""][, note := ""]
setorder(out, cell, id)
fwrite(out, file.path(PF, "data-dev", "CASCADE-ADJUDICATION.csv"))
hr()
say("wrote data-dev/CASCADE-ADJUDICATION.csv (%s cases, %d columns)",
    format(nrow(out), big.mark = ","), ncol(out))
say("")
say("text coverage, which is what decides these:")
say("  BMF-side candidate has 990 text    : %.0f%%", 100 * mean(nzchar(out$bmf_mission)))
say("  matchdb-side candidate has 990 text: %.0f%%", 100 * mean(nzchar(out$mdb_mission)))
say("  at least one side has text         : %.0f%%",
    100 * mean(nzchar(out$bmf_mission) | nzchar(out$mdb_mission)))
