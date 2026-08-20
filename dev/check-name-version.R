#!/usr/bin/env Rscript
# The reference legal names behind the generic-name errors are NOT generic
# (FORT JONES COMMUNITY CHURCH, CHRIST CHURCH OF BEAVER SPRINGS). So the >= 0.95
# name similarity cannot have come from the legal name. Which version matched?
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 74), "\n")

m  <- readRDS(file.path(PF, "data-dev", "PF-MATCH-RESULT-1k.rds"))
st <- pf_status(m)
pr <- as.data.table(attr(m$result, "pairs"))

watch <- c("COMMUNITY CHURCH", "CHRIST CHURCH", "HOUSE OF HOPE", "1",
           "CONGREGATION AGUDATH ISRAEL")
i <- match(watch, st$recip_name)
j <- match(paste(st$grant_id[i], st$ein[i]), paste(pr$.id, pr$.ein))
hr(); say("WHICH NAME VERSION MATCHED?"); hr()
print(data.table(query = watch,
                 ver_x = pr$name_ver_x[j], ver_y = pr$name_ver_y[j],
                 matched_x = substr(pr$name_x[j], 1, 26),
                 matched_y = substr(pr$name_y[j], 1, 26),
                 legal_y = substr(pr$name_key_y[j], 1, 30),
                 name_sim = round(as.numeric(pr$name_key[j]), 3)), row.names = FALSE)

hr(); say("HOW OFTEN IS A PROMOTED MATCH MADE ON SOMETHING OTHER THAN THE LEGAL NAME?"); hr()
cfg0 <- npmatch::np_config(distinct_name_min_idf = 0)
p <- npmatch::np_score(pr, cfg0, method = "hier")
nf <- as.numeric(p$name_freq)
ns <- as.numeric(p$name_key); ns[is.na(ns)] <- 0
elig <- !is.na(nf) & ns >= 0.95 & nf <= cfg0$distinct_name_maxfreq
say("promotion-eligible pairs: %s", format(sum(elig), big.mark = ","))
vy <- p$name_ver_y[elig]; vy[is.na(vy)] <- "(none)"
print(sort(table(vy), decreasing = TRUE))
say("\nshare matched on something other than the primary name: %.1f%%",
    100 * mean(!(vy %in% c("main", "(none)"))))

hr(); say("AND AMONG THE PAIRS ACTUALLY SELECTED AS YES?"); hr()
sel <- match(paste(st$grant_id[st$status == "YES"], st$ein[st$status == "YES"]),
             paste(p$.id, p$.ein))
sel <- sel[!is.na(sel)]
se <- sel[elig[sel]]
vy2 <- p$name_ver_y[se]; vy2[is.na(vy2)] <- "(none)"
say("YES matches that relied on promotion: %d", length(se))
print(sort(table(vy2), decreasing = TRUE))
