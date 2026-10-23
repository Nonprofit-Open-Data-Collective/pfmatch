#!/usr/bin/env Rscript
# ============================================================================
# Score the NO-residual audit.
#
# The question is not "how many are unmatchable" on its own -- it is how the
# residual DIVIDES. A NO that hides a real organisation already sitting in the
# reference is a matching failure and recoverable in pfmatch. A NO on a payee
# that has no EIN at all is the floor, and no amount of tuning moves it. Those
# two have opposite implications and the tier label conflates them.
#
# For every web-confirmed EIN the script also tests presence in BOTH references
# directly, which is exact where a name probe is only suggestive.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
PF <- Sys.getenv("PFMATCH_DIR", ".")
say <- function(...) message(sprintf(...))
hr  <- function() message(strrep("-", 74))
e9  <- function(v) { v <- gsub("[^0-9]", "", as.character(v))
                     ifelse(nchar(v) == 9L, v, NA_character_) }

v <- fread(file.path(PF, "dev", "no-residual-verdicts.csv"), colClasses = "character")
s <- fread(file.path(PF, "data-dev", "AUDIT-NO-RESIDUAL-100.csv"), colClasses = "character")

stopifnot(nrow(v) == sum(s$stratum == "organisation"))
stopifnot(!anyDuplicated(v$id))

## ---- does the reference actually hold the EIN the web gave us? -------------
b <- fread(file.path(PF, "data-dev", "BMF-AUGMENTED-unified-fixed.csv"),
           colClasses = "character", showProgress = FALSE, select = "ein")
m <- fread(file.path(PF, "data-dev", "REF-MATCHDB.csv"),
           colClasses = "character", showProgress = FALSE, select = "ein")
B <- unique(e9(b$ein)); M <- unique(e9(m$ein))
say("reference EINs: BMF %s, matchdb %s",
    format(length(B), big.mark = ","), format(length(M), big.mark = ","))

v[, ein := e9(web_ein)]
v[, in_bmf := ein %in% B]
v[, in_mdb := ein %in% M]
v[is.na(ein), c("in_bmf", "in_mdb") := NA]

hr()
say("THE RESIDUAL, AS FILED (100 sampled from the 592 NO under both references)")
hr()
print(s[, .N, by = stratum][order(-N)], row.names = FALSE)

hr()
say("THE 67 ORGANISATION-STRATUM CASES, ADJUDICATED")
hr()
print(v[, .N, by = verdict][order(-N)], row.names = FALSE)

## ---- the split that matters -------------------------------------------------
real <- v[verdict == "REAL-ORG"]
# The presence test is only evidence when the EIN came from OUTSIDE the
# reference. An EIN read off a near-miss row is in the reference by
# construction, so counting it here would be circular.
chk  <- real[basis == "web" & !is.na(ein)]
hr()
say("OF THE %d CONFIRMED REAL ORGANISATIONS", nrow(real))
hr()
say("  EIN established independently of the reference (web) : %d", nrow(chk))
say("    of those, the EIN IS in the BMF                    : %d", sum(chk$in_bmf))
say("    of those, the EIN IS in matchdb                    : %d", sum(chk$in_mdb))
say("    of those, in NEITHER reference                     : %d",
    sum(!chk$in_bmf & !chk$in_mdb))
if (any(!chk$in_bmf & !chk$in_mdb))
  for (i in which(!chk$in_bmf & !chk$in_mdb))
    say("      absent: %s  %s (%s)", chk$id[i], chk$web_name[i], chk$web_ein[i])
say("  EIN taken from a reference near-miss (circular, excluded) : %d",
    nrow(real[basis == "reference" & !is.na(ein)]))
say("  no EIN pinned down at all                                 : %d",
    nrow(real[is.na(ein)]))
say("")
say("  web-search basis overall: %d of %d cases", sum(v$basis == "web"), nrow(v))

## ---- roll the whole sample up to the 592 -----------------------------------
# Collapse to the only distinction that changes what we should do next.
v[, class := fcase(
  verdict == "REAL-ORG",                         "recoverable: a real org, missed",
  verdict == "UNCLEAR-GEO",                      "recoverable: name matched, place did not",
  verdict %in% c("NO-OWN-EIN", "NOT-A-CHARITY"), "floor: payee has no exemption",
  verdict == "UNFINDABLE",                       "floor: no such organisation",
  verdict == "INDIVIDUAL",                       "floor: payee is a person",
  default                                      = "unresolved")]
# The non-organisation strata are NOT interchangeable, and an earlier version of
# this rollup labelled all of them "payee is a person" -- folding the 4
# government bodies and 1 aggregate placeholder into the person count and
# reporting 42 persons where the true figure is 37. They are all floor, but the
# composition was wrong and the denominator estimate downstream depended on it.
s2 <- s[stratum != "organisation"]
s2[, class := fcase(
  stratum == "individual payee",      "floor: payee is a person",
  stratum == "government body",       "floor: payee has no exemption",
  default                           = "floor: no such organisation")]
cls <- rbind(v[, .(n = .N), by = class],
             s2[, .(n = .N), by = class])[, .(n = sum(n)), by = class]
cls[, pct := 100 * n / 100]
setorder(cls, -n)
hr()
say("THE FULL 100, ROLLED UP")
hr()
print(cls, row.names = FALSE)
rec <- sum(cls[grepl("^recoverable", class)]$n)
flr <- sum(cls[grepl("^floor", class)]$n)
unr <- sum(cls[class == "unresolved"]$n)
say("")
say("  recoverable in pfmatch : %2d%%   -> %3.0f of the 592", rec, 592 * rec / 100)
say("  genuine floor          : %2d%%   -> %3.0f of the 592", flr, 592 * flr / 100)
say("  unresolved             : %2d%%   -> %3.0f of the 592", unr, 592 * unr / 100)
say("")
say("  592 is %.1f%% of the 4,869 identities, so the recoverable part is %.1f points",
    100 * 592 / 4869, 100 * (592 * rec / 100) / 4869)

## ---- what the recoverable cases actually need ------------------------------
hr()
say("WHY THE RECOVERABLE ONES WERE MISSED")
hr()
fail <- c(
  "acronym or initialism"        = "G000145|G002951|G003018|G003086|G004078|G002150",
  "dba or trade name"            = "G001402|G002885|G003429|G002704|G001460",
  "legal name differs"           = "G000907|G002832|G004572|G003733|G002284|G002181",
  "truncated or abbreviated"     = "G001170|G002579|G002630",
  "event or programme as payee"  = "G001777|G002473|G004596",
  "typo in the filed name"       = "G002405|G004966|G001935",
  "filed state or city is wrong" = "G003722",
  "plain name, plain miss"       = "G000304|G000311|G000920|G001912|G002810")
for (k in names(fail)) {
  n <- sum(grepl(fail[[k]], real$id))
  say("  %-30s %2d", k, n)
}
say("")
say("  covered: %d of %d", sum(vapply(fail, function(p) sum(grepl(p, real$id)), 0L)),
    nrow(real))

fwrite(v, file.path(PF, "data-dev", "NO-RESIDUAL-SCORED.csv"))
hr()
say("wrote data-dev/NO-RESIDUAL-SCORED.csv")
