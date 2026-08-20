#!/usr/bin/env Rscript
# Are the four generic-name errors still in the YES tier at all? If an earlier
# fix already removed them, the IDF gate is redundant rather than effective.
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")

m  <- readRDS(file.path(PF, "data-dev", "PF-MATCH-RESULT-1k.rds"))
st <- pf_status(m)
pr <- as.data.table(attr(m$result, "pairs"))

watch <- c("COMMUNITY CHURCH", "CHRIST CHURCH", "HOUSE OF HOPE", "1",
           "CONGREGATION AGUDATH ISRAEL", "THE CENTER FOR MICHIGAN",
           "YOUTH WITH A MISSION")
i <- match(watch, st$recip_name)
d <- data.table(name = watch,
                status = as.character(st$status[i]),
                bmf = substr(st$bmf_name[i], 1, 30),
                qcity = substr(st$recip_city[i], 1, 14),
                bcity = substr(st$bmf_city[i], 1, 14),
                score = st$score[i])
print(d, row.names = FALSE)

say("\nname_idf on the selected pair for each (as the SHIPPED code computes it,")
say("from the REFERENCE name -- my probe used the QUERY name):")
j <- match(paste(st$grant_id[i], st$ein[i]), paste(pr$.id, pr$.ein))
print(data.table(name = watch,
                 ref_name_key = substr(pr$name_key_y[j], 1, 28),
                 name_idf = round(as.numeric(pr$name_idf[j]), 1),
                 name_freq = pr$name_freq[j],
                 promoted_eligible = !is.na(pr$name_freq[j]) &
                   as.numeric(pr$name_freq[j]) <= 3), row.names = FALSE)
