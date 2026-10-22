# SUPERSEDED -- kept only as a record of what not to do.
#
# This printed through cat() to stdout. R buffers stdout when it is
# redirected, so the run died without flushing and every result was lost.
# Use message() for progress in anything long-running.
#
# It is also the wrong instrument: dev/score-no-residual.R answers the same
# question by exact EIN lookup, which is both cheaper and not dependent on
# a name-normalisation choice. See dev/NO-RESIDUAL-AUDIT.md.

#!/usr/bin/env Rscript
# ============================================================================
# Local probe of the NO-residual organisation stratum.
#
# Before spending a web search on each case, ask the cheaper question: does the
# reference already CONTAIN a plausible row for this payee? The pipeline scored
# these as NO, but a NO can mean two very different things --
#
#   the organisation is absent from the reference   -> a data gap
#   the organisation is present and was not found   -> a matching failure
#
# and only the second is fixable in pfmatch. The August audit found 13 of 15
# web-confirmed NOs were already in the BMF, i.e. almost all matching failure.
# This probe tests that claim at scale and for free, by searching the reference
# for the payee's rarest token pair rather than by its blocking key -- so it
# sees rows the blocker never offered the scorer.
#
# This is deliberately recall-oriented and makes no accept/reject decision. It
# prints candidates for a human (or a web search) to judge.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
PF <- Sys.getenv("PFMATCH_DIR", ".")
say <- function(...) message(sprintf(...))
sq  <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; x }

d <- fread(file.path(PF, "data-dev", "AUDIT-NO-RESIDUAL-100.csv"),
           colClasses = "character")
d <- d[stratum == "organisation"]
setorder(d, id)

b <- fread(file.path(PF, "data-dev", "BMF-AUGMENTED-unified-fixed.csv"),
           colClasses = "character", showProgress = FALSE,
           select = c("ein", "org_name_join", "org_addr_city", "org_addr_state"))
say("reference rows: %s", format(nrow(b), big.mark = ","))

norm <- function(x) {
  x <- toupper(sq(x))
  x <- gsub("&", " AND ", x, fixed = TRUE)
  x <- gsub("[^A-Z0-9 ]", " ", x)
  gsub(" +", " ", trimws(x))
}
b[, nn := norm(org_name_join)]
B_ST <- toupper(sq(b$org_addr_state))

# Stop words carry no discriminating power, so a token pair drawn from them
# would return thousands of rows and nothing useful.
STOP <- c("THE", "OF", "AND", "FOR", "INC", "INCORPORATED", "A", "AN", "AT",
          "IN", "TO", "ON", "CO", "CORP", "LLC", "USA", "US", "FUND",
          "FOUNDATION", "TRUST", "ASSOCIATION", "SOCIETY", "CENTER", "CENTRE",
          "INTERNATIONAL", "NATIONAL", "AMERICAN", "AMERICA", "CHARITABLE",
          "SERVICES", "SERVICE", "PROGRAM", "PROJECT", "COMMUNITY", "CHURCH")

probe <- function(nm, state) {
  tk <- setdiff(strsplit(norm(nm), " ")[[1]], STOP)
  tk <- tk[nchar(tk) >= 3L]
  if (!length(tk)) return(NULL)
  # Rank tokens by rarity in the reference, then require the two rarest.
  frq <- vapply(tk, function(t) sum(grepl(paste0("\\b", t, "\\b"), b$nn)), 0L)
  tk  <- names(sort(frq))
  hit <- grepl(paste0("\\b", tk[1], "\\b"), b$nn)
  if (length(tk) >= 2L) {
    h2 <- hit & grepl(paste0("\\b", tk[2], "\\b"), b$nn)
    if (any(h2)) hit <- h2
  }
  # Prefer the filed state; fall back to the nation when the state has nothing.
  i <- which(hit & B_ST == toupper(sq(state)))
  if (!length(i)) i <- which(hit)
  if (!length(i)) return(NULL)
  if (length(i) > 4L) i <- i[1:4]
  b[i, .(ein, org_name_join, org_addr_city, org_addr_state)]
}

tr <- function(x, n) substr(gsub("[[:space:]]+", " ", sq(x)), 1, n)
for (k in seq_len(nrow(d))) {
  x <- d[k]
  cat(sprintf("\n%2d %s  %s | %s %s\n", k, x$id, tr(x$recip_name, 44),
              tr(x$recip_city, 18), x$recip_state))
  r <- probe(x$recip_name, x$recip_state)
  if (is.null(r)) { cat("      -- no reference row shares its rare tokens\n"); next }
  for (i in seq_len(nrow(r)))
    cat(sprintf("      %s  %-46s %s %s\n", r$ein[i], tr(r$org_name_join[i], 46),
                tr(r$org_addr_city[i], 16), r$org_addr_state[i]))
}
