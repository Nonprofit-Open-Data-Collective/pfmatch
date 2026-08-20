#!/usr/bin/env Rscript
# What IS in a "SEE ATTACHED" return, if not the itemized grants?
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 78), "\n")
CACHE <- file.path(PF, "data-dev", "xml-cache")
f <- list.files(CACHE, full.names = TRUE)
stopifnot(length(f) > 0)
target <- f[which.max(file.size(f))]
say("inspecting %s (%.0f KB)", basename(target), file.size(target) / 1024)

x <- readLines(target, warn = FALSE)
one <- paste(x, collapse = "\n")

hr(); say("MOST FREQUENT ELEMENTS"); hr()
tags <- regmatches(one, gregexpr("<[A-Za-z][A-Za-z0-9]*", one))[[1]]
tb <- sort(table(sub("^<", "", tags)), decreasing = TRUE)
print(head(tb, 25))

hr(); say("THE Part XV / GRANT SECTION AS FILED"); hr()
i <- grep("GrantOrContributionPdDurYrGrp", x)
if (length(i)) {
  rng <- max(1, i[1] - 2):min(length(x), i[length(i)] + 24)
  cat(paste(trimws(x[rng]), collapse = "\n"), "\n")
}

hr(); say("ANY FREE-TEXT BLOCK LONG ENOUGH TO HOLD A GRANT LIST?"); hr()
long <- x[nchar(x) > 400]
say("lines longer than 400 chars: %d", length(long))
if (length(long)) {
  for (k in head(seq_along(long), 3)) {
    tag <- sub("^\\s*<([A-Za-z0-9]+).*", "\\1", long[k])
    say("  <%s> %d chars:", tag, nchar(long[k]))
    say("    %s ...", substr(trimws(long[k]), 1, 260))
  }
}

hr(); say("DOES ANY TEXT MENTION AN ATTACHMENT OR STATEMENT?"); hr()
hits <- grep("attach|statement|schedule|see part", x, ignore.case = TRUE, value = TRUE)
say("lines mentioning attach/statement/schedule: %d", length(hits))
for (h in head(unique(trimws(hits)), 8)) say("  %s", substr(h, 1, 150))
