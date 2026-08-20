#!/usr/bin/env Rscript
# ============================================================================
# Do the "SEE ATTACHED" returns actually carry the grant detail in their XML?
#
# The GTDC extract gives one row per Part XIV Table 3a entry. When a filer
# writes "SEE ATTACHED SCHEDULE" there, the extract has nothing to work with.
# But the e-file XML may still contain the itemized grants -- either as repeated
# GrantOrContributionPdDurYrGrp elements that the extract failed to flatten, or
# in a supplemental-information / attachment section.
#
# This fetches a sample of those returns and looks.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
SET <- Sys.getenv("PF_SET", "50k")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 78), "\n")
usd <- function(x) paste0("$", formatC(x, format = "f", digits = 0, big.mark = ","))
CACHE <- file.path(PF, "data-dev", "xml-cache"); dir.create(CACHE, showWarnings = FALSE)

m  <- readRDS(file.path(PF, "data-dev", sprintf("PF-MATCH-RESULT-%s.rds", SET)))
g  <- as.data.table(m$grants)
st <- as.data.table(pf_status(m))
i  <- match(st$grant_id, g$grant_id)
st[, amount := suppressWarnings(as.numeric(g$SIGOCPYAMOUN[i]))]
st[, url := g$URL[i]][, taxyear := g$TAXYEAR[i]]

ph <- "SEE ATTACH|SEE SCHED|SEE PART|SEE STATEMENT|SEE LIST|ATTACHED LIST|^VARIOUS|^SEVERAL|^MISC|AVAILABLE UPON|SEE EXHIBIT|SCHEDULE ATTACHED|SEE ABOVE|SEE FOOTNOTE"
p <- st[grepl(ph, toupper(recip_name)) & !is.na(url) & nzchar(url)]
setorder(p, -amount)
say("placeholder rows with a URL: %d | total %s", nrow(p), usd(sum(p$amount, na.rm = TRUE)))

N <- as.integer(Sys.getenv("PF_N", "8"))
probe <- unique(p, by = "url")[seq_len(min(N, uniqueN(p$url)))]
say("fetching %d distinct returns ...\n", nrow(probe))

hr(); say("PER-RETURN FINDINGS"); hr()
out <- rbindlist(lapply(seq_len(nrow(probe)), function(k) {
  u <- probe$url[k]
  f <- file.path(CACHE, basename(u))
  if (!file.exists(f)) {
    ok <- tryCatch({ utils::download.file(u, f, quiet = TRUE, mode = "wb"); TRUE },
                   error = function(e) FALSE, warning = function(w) FALSE)
    if (!ok || !file.exists(f) || file.size(f) < 500) {
      say("  [%d] FETCH FAILED  %s", k, basename(u)); return(NULL)
    }
  }
  x <- paste(readLines(f, warn = FALSE), collapse = "\n")
  cnt <- function(pat) length(gregexpr(pat, x, fixed = TRUE)[[1]][gregexpr(pat, x, fixed = TRUE)[[1]] > 0])
  n_grp  <- cnt("<GrantOrContributionPdDurYrGrp>")
  n_appr <- cnt("<GrantOrContributionApprvFutGrp>")
  n_rcp  <- cnt("<RecipientBusinessName>")
  n_pers <- cnt("<RecipientPersonNm>")
  n_supp <- cnt("<SupplementalInformationDetail>")
  n_att  <- cnt("<AttachmentInformation")
  say("  [%d] %s  y%s  %s", k, substr(probe$filer_name[k], 1, 30), probe$taxyear[k],
      usd(probe$amount[k]))
  say("       size %6.0f KB | GrantPdDurYr %3d | ApprvFut %3d | RecipBizName %3d | RecipPerson %3d",
      file.size(f) / 1024, n_grp, n_appr, n_rcp, n_pers)
  say("       SupplementalInfo %d | AttachmentInformation %d", n_supp, n_att)
  data.table(url = u, filer = probe$filer_name[k], taxyear = probe$taxyear[k],
             reported_amount = probe$amount[k], kb = round(file.size(f) / 1024),
             n_grant_groups = n_grp, n_recip_biz = n_rcp, n_recip_person = n_pers,
             n_supplemental = n_supp)
}), fill = TRUE)

if (!nrow(out)) { say("\nno returns fetched; stopping"); quit(save = "no") }

hr(); say("SUMMARY"); hr()
say("returns fetched              : %d", nrow(out))
say("carrying itemized grant groups: %d (%.0f%%)",
    sum(out$n_grant_groups > 0), 100 * mean(out$n_grant_groups > 0))
say("median grant groups per return: %.0f", stats::median(out$n_grant_groups))
say("total itemized grants recoverable in this sample: %s",
    format(sum(out$n_grant_groups), big.mark = ","))
fwrite(out, file.path(PF, "data-dev", "ATTACHED-XML-PROBE.csv"))
say("\nwrote data-dev/ATTACHED-XML-PROBE.csv")
