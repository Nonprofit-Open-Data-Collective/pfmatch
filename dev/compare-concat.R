#!/usr/bin/env Rscript
# Does the adjacent-token compound pass (B2) earn its 223k candidates?
# Also: where do its 48 YES matches go when it is switched off -- MAYBE or NO?
suppressWarnings(suppressMessages(library(data.table)))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
NPM <- Sys.getenv("NPMATCH_DIR", "../npmatch")
SET <- Sys.getenv("PF_SET", "1k")
PAT <- switch(SET, "1k" = "^1k_grants_.*\\.csv$", "50k" = "^50k_grants\\.csv$",
              "100k" = "^100k_grants\\.csv$", stop("bad PF_SET"))
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 74), "\n")

g   <- pf_read_grants(file.path(PF, "inputs"), pattern = PAT)
ref <- readRDS(file.path(PF, "data-dev", "BMF-REFERENCE-BUNDLE.rds"))

run <- function(nm, p) {
  m <- pf_match_grants(g, ref, passes = p, verbose = FALSE)
  st <- pf_status(m)
  t <- table(factor(st$status, pf_status_levels()))
  say("  %-26s %10s cand %7.1f s  YES %4d MAYBE %4d NO %4d",
      nm, format(sum(attr(m$result, "stages")$candidates), big.mark = ","),
      m$timing[["match"]], t[["YES"]], t[["MAYBE"]], t[["NO"]])
  list(nm = nm, st = st, secs = m$timing[["match"]], n = m$n[["in_scope"]],
       cand = sum(attr(m$result, "stages")$candidates), yes = t[["YES"]])
}

hr(); say("B2 (adjacent-token compound) ON vs OFF, sweep = lean"); hr()
on  <- run("lean, concat ON",  pf_staged_passes("lean", concat = TRUE))
off <- run("lean, concat OFF", pf_staged_passes("lean", concat = FALSE))

say("\ndropping B2: %.2fx faster, %.2fx fewer candidates, %+d YES",
    on$secs / off$secs, on$cand / off$cand, off$yes - on$yes)

hr(); say("WHERE DO THE LOST YES MATCHES LAND?"); hr()
k <- on$st$grant_id
a <- as.character(on$st$status)
b <- as.character(off$st$status[match(k, off$st$grant_id)])
lost <- which(a == "YES" & b != "YES")
say("baseline-of-this-test YES lost by dropping B2: %d", length(lost))
print(table(landed_in = b[lost]))
if (length(lost)) {
  say("\nexamples (these are the de-spacing recoveries B2 exists for):")
  d <- data.table(name = substr(on$st$recip_name[lost], 1, 36),
                  bmf = substr(on$st$bmf_name[lost], 1, 36),
                  score = on$st$score[lost], now = b[lost])
  print(head(d, 15), row.names = FALSE)
}
say("\nAll lost matches remain visible for adjudication if they land in MAYBE;")
say("only those landing in NO are true recall losses.")
