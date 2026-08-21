#!/usr/bin/env Rscript
# ============================================================================
# Phase 2 - is the pooled graph safe to take connected components of?
#
# The proposal is a cluster id that lets a grant match either member of a
# related pair. That is only sound if the clusters are small and local. A
# transitive closure over Schedule R will merge whole hospital systems and
# dioceses, at which point "either member is correct" stops meaning anything.
#
# This measures the component size distribution under progressively tighter
# rules and picks the one that keeps clusters interpretable.
#
# Output: data-dev/CLUSTER-COMPONENTS.rds, data-dev/CLUSTER-GIANTS.csv
# ============================================================================
suppressWarnings(suppressMessages({library(data.table); library(igraph)}))
PF  <- Sys.getenv("PFMATCH_DIR", ".")
BMF <- file.path(PF, "..", "npmatch", "data-raw", "bmf_2026_01_processed.csv")
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 78), "\n")

L     <- readRDS(file.path(PF, "data-dev", "CLUSTER-PAIRS.rds"))
pairs <- L$pairs

bm <- fread(BMF, colClasses = "character", showProgress = FALSE,
            select = c("ein", "org_name_join", "org_addr_city",
                       "org_addr_state", "org_addr_zip5"))
setnames(bm, c("ein","name","city","state","zip5"))
bm[, ein := gsub("[^0-9]", "", ein)]
bm <- unique(bm, by = "ein"); setkey(bm, ein)

geo <- function(e, f) bm[[f]][match(e, bm$ein)]
pairs[, `:=`(x_st = geo(x, "state"), y_st = geo(y, "state"),
             x_ct = geo(x, "city"),  y_ct = geo(y, "city"),
             x_nm = geo(x, "name"),  y_nm = geo(y, "name"))]
pairs[, `:=`(same_state = !is.na(x_st) & x_st == y_st,
             same_city  = !is.na(x_ct) & !is.na(x_st) & x_ct == y_ct & x_st == y_st)]

hr(); say("HOW MUCH OF THE PAIR TABLE IS EVEN IN THE BMF?"); hr()
say("pairs where both EINs are in the BMF : %s (%.0f%%)",
    format(sum(!is.na(pairs$x_nm) & !is.na(pairs$y_nm)), big.mark=","),
    100*mean(!is.na(pairs$x_nm) & !is.na(pairs$y_nm)))
say("  ...same state                      : %.0f%%", 100*mean(pairs$same_state))
say("  ...same city                       : %.0f%%", 100*mean(pairs$same_city))

## ------------------------------------------------------- component sweep
rules <- list(
  `all pairs`                        = pairs[, .(x, y)],
  `same state`                       = pairs[same_state == TRUE, .(x, y)],
  `same city`                        = pairs[same_city  == TRUE, .(x, y)],
  `same city + 2+ years`             = pairs[same_city  == TRUE & n_years >= 2L, .(x, y)],
  `same city + Sch A directed`       = pairs[same_city  == TRUE & sched_a == 1L, .(x, y)]
)

comp_of <- function(e) {
  if (!nrow(e)) return(NULL)
  g  <- graph_from_data_frame(e, directed = FALSE)
  cl <- components(g)
  data.table(ein = names(cl$membership), cid = as.integer(cl$membership))
}

hr(); say("COMPONENT SIZE UNDER EACH RULE"); hr()
res <- list()
for (nm in names(rules)) {
  cm <- comp_of(rules[[nm]])
  sz <- cm[, .N, by = cid]$N
  res[[nm]] <- cm
  say("%-28s edges %8s  eins %7s  comps %7s  max %6d  mean %5.2f  >10 %5d  >100 %4d  %%eins in comps>10: %4.1f%%",
      nm, format(nrow(rules[[nm]]), big.mark=","),
      format(nrow(cm), big.mark=","), format(length(sz), big.mark=","),
      max(sz), mean(sz), sum(sz > 10), sum(sz > 100),
      100 * sum(sz[sz > 10]) / sum(sz))
}

hr(); say("SIZE DISTRIBUTION, all pairs vs same city"); hr()
for (nm in c("all pairs", "same city")) {
  sz <- res[[nm]][, .N, by = cid]$N
  b  <- cut(sz, c(1, 2, 3, 5, 10, 25, 100, 1000, Inf), right = FALSE,
            labels = c("2","3","4-5","6-10","11-25","26-100","101-1000",">1000"))
  say("%s:", nm); print(table(b))
}

## ------------------------------------------------------------ the giants
hr(); say("THE LARGEST COMPONENTS UNDER 'all pairs'"); hr()
cm <- res[["all pairs"]]
sz <- cm[, .N, by = cid][order(-N)]
top <- head(sz, 12)
gi  <- list()
for (i in seq_len(nrow(top))) {
  e  <- cm[cid == top$cid[i]]$ein
  nmv <- bm$name[match(e, bm$ein)]
  stv <- bm$state[match(e, bm$ein)]
  say("component %d - %d EINs, %d states: %s ...", i, top$N[i],
      uniqueN(stv[!is.na(stv)]),
      paste(head(nmv[!is.na(nmv)], 4), collapse = " | "))
  gi[[i]] <- data.table(rank = i, size = top$N[i], ein = e,
                        name = nmv, state = stv)
}
fwrite(rbindlist(gi), file.path(PF, "data-dev", "CLUSTER-GIANTS.csv"))

hr(); say("SAME-CITY GIANTS (the rule most likely to be shipped)"); hr()
cm2 <- res[["same city"]]
sz2 <- cm2[, .N, by = cid][order(-N)]
for (i in 1:10) {
  e <- cm2[cid == sz2$cid[i]]$ein
  nmv <- bm$name[match(e, bm$ein)]
  say("  %2d. %3d EINs (%s): %s ...", i, sz2$N[i],
      bm$city[match(e[1], bm$ein)],
      paste(head(nmv[!is.na(nmv)], 3), collapse = " | "))
}

saveRDS(list(components = res, pairs = pairs),
        file.path(PF, "data-dev", "CLUSTER-COMPONENTS.rds"), compress = FALSE)
say("wrote data-dev/CLUSTER-COMPONENTS.rds")
