#!/usr/bin/env Rscript
# ============================================================================
# Stratify the NO-residual sample before any web searching.
#
# "Confirm they cannot be matched" is only a meaningful question for payees that
# are organisations. A scholarship cheque written to a named student has no EIN
# to find, and no amount of searching changes that -- counting those as
# unmatchable successes would inflate the residual's apparent floor. So the
# sample is split first on what the filed record alone settles, and the searching
# is spent on the stratum where a search can change the answer.
#
# The strata are deliberately conservative: a case goes to "individual" only on
# a person-shaped name AND an individual-shaped signal (the filer's own status
# code, the package's looks_personal flag, or a scholarship/stipend purpose).
# A borderline case stays in the organisation stratum and gets searched, so the
# error runs against the convenient answer rather than toward it.
#
# NOTE: do not rewrite this file through a bash heredoc. The regexes below need
# their doubled backslashes and a heredoc strips one level, which silently
# turned "\\b" into a backspace character on the first pass and voided the
# aggregate stratum entirely.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
say <- function(...) message(sprintf(...))
sq  <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; x }

p <- file.path(PF, "data-dev", "AUDIT-NO-RESIDUAL-100.csv")
d <- fread(p, colClasses = "character")

nm <- toupper(sq(d$recip_name))
pu <- toupper(sq(d$purpose))
st <- toupper(sq(d$status_norm))

## ---- placeholders standing in for a payee rather than naming one -----------
AGG <- paste0("^(VARIOUS|MULTIPLE|ANONYMOUS|CONFIDENTIAL|SEE ATTACH|SEE STAT",
              "|SEE SCHED|NONE|N/?A|MISCELLANEOUS|OTHER|UNKNOWN|NOT APPLICABLE",
              ")\\b")

## ---- organisation vocabulary: one of these and it is not a person ----------
ORGW <- paste0("\\b(FOUNDATION|FUND|TRUST|INC|INCORPORATED|CORP|CORPORATION|LLC",
               "|ASSOCIATION|ASSN|SOCIETY|COUNCIL|CLUB|CHURCH|TEMPLE|SYNAGOGUE",
               "|MOSQUE|MINISTR(Y|IES)|MISSION(S)?|PARISH|DIOCESE|CONGREGATION",
               "|SCHOOL|ACADEMY|COLLEGE|UNIVERSITY|INSTITUTE|SEMINARY|YESHIVA",
               "|HOSPITAL|CLINIC|HOSPICE|CENTER|CENTRE|HOME|SHELTER|HOUSE",
               "|LIBRARY|MUSEUM|THEATRE|THEATER|ORCHESTRA|CHORUS|BALLET|GALLERY",
               "|UNITED|AMERICAN|NATIONAL|INTERNATIONAL|AMERICA|USA",
               "|CHARIT(Y|IES|ABLE)|RELIEF|AID|SERVICES|SERVICE|PROGRAM|PROJECT",
               "|ALLIANCE|COALITION|NETWORK|PARTNERSHIP|COMMITTEE|BOARD|LEAGUE",
               "|DEPARTMENT|DISTRICT|COUNTY|CITY OF|TOWN OF|STATE OF|BUREAU",
               "|CHAPTER|AUXILIARY|LODGE|POST|TROOP|CHAPTER|CORPS|GUILD",
               "|HABITAT|SALVATION|GOODWILL|YMCA|YWCA|JDRF|ASPCA|SPCA|PTA|PTO",
               ")\\b")

## ---- name shapes a person takes and an organisation does not ---------------
# Two or three capitalised tokens with no organisation word, optionally with a
# middle initial, a hyphenated surname, or a trailing generational suffix.
PERS <- paste0("^([A-Z][A-Za-z'`-]+)",            # given name
               "( [A-Z][A-Za-z'`-]+)?",           # optional middle name
               "( [A-Z]\\.?)?",                   # optional middle initial
               "( [A-Z][A-Za-z'`-]+)",            # surname
               "( (JR|SR|II|III|IV))?\\.?$")
# "SURNAME, GIVEN" and "SURNAME GIVEN" both occur in the filed data.
PERS2 <- "^[A-Z][A-Za-z'`-]+, ?[A-Z][A-Za-z'`-]+( [A-Z]\\.?)?$"
TITLE <- "^(MR|MRS|MS|MISS|DR|REV|FR|SR|PROF)\\.? "

## ---- purposes that describe a payment to a person --------------------------
INDPU <- paste0("\\b(SCHOLARSHIP|SCHOLARSHIPS|STIPEND|STIPENDS|FELLOWSHIP",
                "|TUITION|BURSARY|GRANT TO INDIVIDUAL|TO AN INDIVIDUAL",
                "|INDIGENT|HARDSHIP|EMERGENCY ASSISTANCE|PRIZE|AWARD TO",
                ")\\b")

## ---- government bodies, which have no 501(c)(3) determination --------------
GOVT <- paste0("\\b(PUBLIC SCHOOL|ELEMENTARY SCHOOL|MIDDLE SCHOOL|HIGH SCHOOL",
               "|SCHOOL DISTRICT|UNIFIED SCHOOL|INDEPENDENT SCHOOL DISTRICT",
               "|ISD|USD|BOARD OF EDUCATION|DEPARTMENT OF|CITY OF|TOWN OF",
               "|COUNTY OF|STATE OF|TOWNSHIP|BOROUGH OF|VILLAGE OF",
               "|POLICE|SHERIFF|FIRE DEPARTMENT|PUBLIC LIBRARY)\\b")

has_org  <- grepl(ORGW, nm)
pers_nm  <- (grepl(PERS, d$recip_name) | grepl(PERS2, nm) | grepl(TITLE, nm)) &
            !has_org
ind_sig  <- d$recipient_type == "individual" | st %in% c("I", "INDIVIDUAL") |
            grepl(INDPU, pu)

d[, stratum := fcase(
  !nzchar(nm),                      "no payee name",
  grepl(AGG, nm),                   "aggregate placeholder",
  pers_nm & ind_sig,                "individual payee",
  grepl(GOVT, nm) & !grepl("\\b(FOUNDATION|FUND|PTA|PTO|ASSOCIATION)\\b", nm),
                                    "government body",
  default                         = "organisation")]

say("")
print(d[, .N, by = stratum][order(-N)], row.names = FALSE)
say("")
say("searchable organisations: %d of %d", sum(d$stratum == "organisation"), nrow(d))

## ---- cases the shape rules disagree about, printed for eyeballing ----------
say("")
say("person-shaped name but no individual signal (kept as organisation):")
x <- d[pers_nm & !ind_sig]
if (nrow(x)) for (i in seq_len(nrow(x)))
  say("  %s  %-40s | %-18s | %s", x$id[i], substr(x$recip_name[i], 1, 40),
      substr(sq(x$purpose[i]), 1, 18), x$recipient_type[i])
say("")
say("individual signal but not person-shaped (kept as organisation):")
x <- d[!pers_nm & ind_sig & stratum == "organisation"]
if (nrow(x)) for (i in seq_len(nrow(x)))
  say("  %s  %-40s | %-18s | %s", x$id[i], substr(x$recip_name[i], 1, 40),
      substr(sq(x$purpose[i]), 1, 18), x$recipient_type[i])

fwrite(d, p)
say("")
say("stratum written back to data-dev/AUDIT-NO-RESIDUAL-100.csv")
