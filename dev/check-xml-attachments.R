#!/usr/bin/env Rscript
# Across every fetched "SEE ATTACHED" return: is there ANY route to the grant
# detail -- a binary attachment, a supplemental text block, or more than one
# itemized grant group?
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 78), "\n")
usd <- function(x) paste0("$", formatC(x, format = "f", digits = 0, big.mark = ","))

f <- list.files(file.path(PF, "data-dev", "xml-cache"), full.names = TRUE)
say("returns cached: %d\n", length(f))

out <- rbindlist(lapply(f, function(p) {
  x <- readLines(p, warn = FALSE); one <- paste(x, collapse = "\n")
  gc1 <- function(pat) {
    m <- regmatches(one, regexpr(pat, one, perl = TRUE))
    if (!length(m)) NA_character_ else sub(pat, "\\1", m, perl = TRUE)
  }
  cnt <- function(tag) {
    g <- gregexpr(tag, one, fixed = TRUE)[[1]]
    if (g[1] == -1) 0L else length(g)
  }
  data.table(
    file = basename(p), kb = round(file.size(p) / 1024),
    filer = gc1('<BusinessNameLine1Txt>([^<]*)</BusinessNameLine1Txt>'),
    ein = gc1('<Filer>\\s*<EIN>([0-9]+)</EIN>'),
    taxyear = gc1('<TaxYr>([0-9]{4})</TaxYr>'),
    binary_attachments = as.integer(gc1('binaryAttachmentCnt="([0-9]+)"')),
    n_grant_paid = cnt("<GrantOrContributionPdDurYrGrp>"),
    n_grant_future = cnt("<GrantOrContriApprvForFutGrp>"),
    total_paid = as.numeric(gc1("<TotalGrantOrContriPdDurYrAmt>([0-9]+)</TotalGrantOrContriPdDurYrAmt>")),
    max_line_chars = max(nchar(x)),
    n_ref_docs = cnt("referenceDocumentId"))
}), fill = TRUE)

hr(); say("IS THE DETAIL RECOVERABLE FROM THE XML?"); hr()
print(out[, .(file = substr(file, 1, 22), kb, taxyear,
              binary = binary_attachments, paid_grps = n_grant_paid,
              future_grps = n_grant_future, total = usd(total_paid),
              longest_line = max_line_chars)], row.names = FALSE)

hr(); say("VERDICT"); hr()
say("returns with a binary attachment      : %d of %d",
    sum(out$binary_attachments > 0, na.rm = TRUE), nrow(out))
say("returns with >1 itemized paid grant   : %d of %d", sum(out$n_grant_paid > 1), nrow(out))
say("returns with any line > 400 chars     : %d of %d", sum(out$max_line_chars > 400), nrow(out))
say("total dollars represented by these    : %s", usd(sum(out$total_paid, na.rm = TRUE)))
say("")
if (all(out$n_grant_paid <= 1) && all(out$binary_attachments == 0, na.rm = TRUE)) {
  say("The grant detail is NOT in the XML. Each return files exactly one Part XIV")
  say("row whose recipient name is the placeholder text, with the full amount")
  say("attached to it, and declares zero binary attachments. The itemization")
  say("exists only on paper, 'available upon request'.")
  say("")
  say("An XML-recovery script cannot work. What the XML DOES give, reliably, is")
  say("the filer EIN, tax year, and the authoritative Part XIV totals -- which is")
  say("exactly what the flagging report needs.")
}
fwrite(out, file.path(PF, "data-dev", "ATTACHED-XML-ATTACHMENTS.csv"))
