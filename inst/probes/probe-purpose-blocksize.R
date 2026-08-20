#!/usr/bin/env Rscript
# ============================================================================
# probe-purpose-blocksize.R -- if a purpose-similarity floor were used to SURFACE
# candidates rather than to rank them, how big is the surviving set?
#
# probe-threshold-recall.R shows a floor cannot be set safely inside a 5-candidate
# set. This asks the generation-side version: for the most common contentful
# grant purposes, how many of the 545k organizations with 990 text would clear
# the floor? A recall device is only useful if what it returns is smaller than
# what you started with.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
PF <- Sys.getenv("PFMATCH_DIR", ".")
source(file.path(PF, "dev", "purpose-enrich.R"))
say <- pt_say

corp <- copy(pt_text_by_ein())
corp[, all_text := trimws(paste(pt_sq(mission), pt_sq(prog_all)))]
N <- nrow(corp)
say("corpus: %d organizations with Form 990 Part III text", N)

toks <- pt_utok(corp$all_text)
idx  <- data.table(ein9 = rep(corp$ein9, lengths(toks)), tk = unlist(toks))
cnt  <- idx[, .N, by = tk][order(-N)]

g <- fread(file.path(PF, "inputs", "50k_grants.csv"), select = "SIGOCPYPOGOC",
           colClasses = "character", na.strings = NULL, showProgress = FALSE)
gt <- pt_utok(g$SIGOCPYPOGOC)
top <- sort(table(unlist(gt)), decreasing = TRUE)
top <- head(top, 20)

say("")
say("For the 20 most common CONTENTFUL purpose tokens: how many organizations")
say("would clear a containment floor on that token alone?")
out <- data.table(token = names(top), grants_using = as.integer(top))
out[, orgs_matching := cnt$N[match(token, cnt$tk)]]
out[is.na(orgs_matching), orgs_matching := 0L]
out[, pct_of_corpus := round(100 * orgs_matching / N, 1)]
print(out[order(-grants_using)])

say("")
say("A single-token purpose is %4.1f%% of contentful purposes.",
    100 * mean(lengths(gt)[lengths(gt) > 0] == 1))
say("Median block size over the 20 tokens above: %s organizations",
    format(median(out$orgs_matching), big.mark = ","))
say("For comparison, the whole BMF is 1,924,822 records and the cascade returns")
say("a handful of candidates per grant.")
