#!/usr/bin/env Rscript
# ============================================================================
# Build the NO-residual audit packet.
#
# The population is NOT the tier-1 NO tier. It is the 592 identities that are
# NO under BOTH references -- the residual the cascade cannot reach, which is
# what "cannot be matched" has to mean once tier 2 exists. Tier-1 NO is 15% of
# the file but a quarter of it is recovered or surfaced by tier 2, so auditing
# it would measure a population the cascade does not leave behind.
#
# The August NO audit (dev/AUDIT-FINDINGS.md) found the tier was a
# name-resolution problem rather than absence: 13 of 15 web-confirmed EINs were
# already in the BMF. That was 15 confirmations against the active BMF. This
# packet is 100 against both the augmented unified BMF and matchdb, so a hit
# here is a genuine reference gap rather than a stale-file artifact.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) message(sprintf(...))
sq  <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; x }
e9  <- function(v) { v <- gsub("[^0-9]", "", as.character(v))
                     ifelse(nchar(v) == 9L, v, NA_character_) }

j <- fread(file.path(PF, "data-dev", "TWO-TIER-SIMULATION.csv"), colClasses = "character")
d <- j[cell == "NO->NO"]
say("NO under both references: %d", nrow(d))

g <- pf_read_grants(file.path(PF, "inputs"), pattern = "^ef1k_grants_")
g <- as.data.table(pf_prepare_grants(pf_recover_name_from_street(g)))
gk <- g[, .(id = grant_id, recip_name, recip_name_alt, recip_street,
            recip_city, recip_state, recip_zip5, recipient_type,
            status_norm, looks_personal, is_foreign, has_name,
            purpose = SIGOCPYPOGOC, amount = SIGOCPYAMOUN,
            taxyear = TAXYEAR, filer = FILERNAME1)]
d <- merge(d, gk, by = "id", all.x = TRUE)

# the near-miss each reference surfaced, so the audit can see what was rejected
b <- fread(file.path(PF, "data-dev", "BMF-AUGMENTED-unified-fixed.csv"),
           colClasses = "character", showProgress = FALSE,
           select = c("ein", "org_name_join", "org_addr_city", "org_addr_state"))
b[, ein := e9(ein)]
m <- fread(file.path(PF, "data-dev", "REF-MATCHDB.csv"), colClasses = "character",
           showProgress = FALSE,
           select = c("ein", "org_name_join", "org_addr_city", "org_addr_state"))
m[, ein := e9(ein)]
m <- m[!duplicated(ein)]
pick <- function(dt, col, ref, pre) {
  i <- match(dt[[col]], ref$ein)
  dt[, (paste0(pre, "_near")) := sq(ref$org_name_join[i])]
  dt[, (paste0(pre, "_loc"))  := trimws(paste(sq(ref$org_addr_city[i]),
                                              sq(ref$org_addr_state[i])))]
  dt
}
d <- pick(d, "ein_a", b, "bmf")
d <- pick(d, "ein_b", m, "mdb")

# Pre-stratify on what the record alone settles, so the searching goes where a
# search can change the answer. A payee with no name, or a name that is a
# person, is unmatchable by construction and needs no lookup. The flags come
# from pf_prepare_grants() rather than a fresh regex, so the strata mean the
# same thing here as they do in the pipeline.
AGG <- paste0("^(VARIOUS|MULTIPLE|ANONYMOUS|CONFIDENTIAL|SEE ATTACH|SEE STAT",
              "|NONE|N/A|NA|MISCELLANEOUS|OTHER|UNKNOWN)\b")

set.seed(2026)
s <- d[sample(.N, 100L)]
nm <- toupper(sq(s$recip_name))
s[, prior := fcase(
  !nzchar(nm) | has_name == FALSE, "no payee name",
  grepl(AGG, nm),                  "aggregate or withheld",
  looks_personal == TRUE,          "looks personal",
  is_foreign == TRUE,              "foreign payee",
  default                        = "searchable")]
say("")
print(s[, .N, by = prior][order(-N)], row.names = FALSE)

keep <- c("id", "recip_name", "recip_name_alt", "recip_street", "recip_city",
          "recip_state", "recip_zip5", "recipient_type", "status_norm",
          "purpose", "amount", "taxyear", "filer",
          "prior", "ein_a", "bmf_near", "bmf_loc", "score_a",
          "ein_b", "mdb_near", "mdb_loc", "score_b")
out <- s[, intersect(keep, names(s)), with = FALSE]
out[, c("web_ein", "web_name", "verdict", "note") := ""]
fwrite(out, file.path(PF, "data-dev", "AUDIT-NO-RESIDUAL-100.csv"))
say("")
say("wrote data-dev/AUDIT-NO-RESIDUAL-100.csv (%d cases)", nrow(out))
