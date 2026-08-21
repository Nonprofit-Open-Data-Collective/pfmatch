#!/usr/bin/env Rscript
# ============================================================================
# 30.8% of substitutable pairs share no content token. Is that a defect?
#
# The table-level rate and the rate that actually fires are different numbers.
# A candidate list is name-blocked: two candidates for the same query almost
# always share tokens, so an edge between two differently-named bodies rarely
# gets the chance to merge anything. Measured on top-two pairs in the 50k run
# the no-shared-token rate was 1.1%, not 31%.
#
# This separates the two, looks at what the risky edges actually are, and prices
# an optional extra gate.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("=", 78), "\n")
sb  <- function() cat(strrep("-", 78), "\n")

D <- readRDS(file.path(PF, "data-dev", "PF-DYADS.rds"))
S <- D[dyad_class == "substitutable"]

norm <- function(z) { z <- toupper(as.character(z)); z[is.na(z)] <- ""
  gsub(" +", " ", trimws(gsub("[^A-Z0-9 ]", " ", z))) }
STOP <- c("THE","OF","AND","INC","INCORPORATED","FOUNDATION","FUND","TRUST","CORP",
          "CORPORATION","CO","LTD","LLC","ASSOCIATION","SOCIETY","CENTER","CENTRE",
          "FOR","A","IN","INSTITUTE","SERVICES","SERVICE")
tk <- function(z) lapply(strsplit(norm(z), " "), function(w) setdiff(w, STOP))
shared_of <- function(x, y) {
  a <- tk(x); b <- tk(y)
  mapply(function(p, q) length(intersect(p, q)), a, b)
}
S[, shared := shared_of(name_a, name_b)]

hr(); say("THE TABLE-LEVEL RATE VS THE RATE THAT FIRES"); hr()
say("substitutable pairs               : %s", format(nrow(S), big.mark=","))
say("  sharing no content token        : %s (%.1f%%)",
    format(sum(S$shared == 0), big.mark=","), 100*mean(S$shared == 0))
say("")
print(S[, .(pairs = .N, pct = round(100*.N/nrow(S),1)),
        by = .(reason = dyad_reason, no_shared_token = shared == 0)][order(reason)],
      row.names = FALSE)
say("")
say("As expected the risk sits entirely in exclusive_support: the name-core")
say("paths cannot produce a zero by construction.")

## ------------------------------------------------ what fires on real lists
t2 <- fread(file.path(PF, "data-dev", "CLUSTER-TOP2.csv"),
            colClasses = list(character = c("e1","e2")))
t2[, cls := pf_dyad_lookup(D, e1, e2)]
fired <- t2[cls == "substitutable"]
fired[, shared := shared_of(n1, n2)]
sb(); say("EDGES THAT ACTUALLY FIRE ON A CANDIDATE LIST (50k top-two pairs)"); sb()
say("top-two pairs classed substitutable: %s", format(nrow(fired), big.mark=","))
say("  sharing no content token         : %s (%.1f%%)",
    format(sum(fired$shared == 0), big.mark=","), 100*mean(fired$shared == 0))
say("")
say("Table-level %.1f%% versus fired %.1f%%. The blocking does the filtering:",
    100*mean(S$shared == 0), 100*mean(fired$shared == 0))
say("two candidates for one query are already name-similar, so an edge between")
say("two differently-named bodies seldom gets the chance to merge anything.")
say("")
if (any(fired$shared == 0))
  print(fired[shared == 0, .(top = substr(n1,1,36), runner = substr(n2,1,36), status)],
        row.names = FALSE)

sb(); say("THE RISKY EDGES THEMSELVES - exclusive_support, no shared token"); sb()
set.seed(2)
r <- S[shared == 0 & dyad_reason == "exclusive_support"]
say("pairs: %s   same city: %.0f%%   5+ years disclosed: %.0f%%",
    format(nrow(r), big.mark=","), 100*mean(r$same_city, na.rm=TRUE),
    100*mean(r$n_years >= 5, na.rm=TRUE))
print(r[sample(.N, 20L), .(a = substr(name_a,1,36), b = substr(name_b,1,36),
                           same_city, n_years)], row.names = FALSE)
say("")
say("These are mostly real: a hospital and its named-differently housing arm,")
say("a school and its endowment trust. But some are a supporting organisation")
say("and its single grantee, which is a relation and not a substitution.")

## --------------------------------------------------------- an optional gate
sb(); say("PRICING AN EXTRA GATE ON THE EXCLUSIVE-SUPPORT PATH"); sb()
gates <- list(
  `as shipped`                       = rep(TRUE, nrow(S)),
  `+ require a shared token`         = S$shared >= 1,
  `+ require same city`              = S$same_city %in% TRUE,
  `+ shared token OR same city`      = S$shared >= 1 | S$same_city %in% TRUE,
  `+ shared token AND same city`     = S$shared >= 1 & S$same_city %in% TRUE)
say("%-32s %9s %8s %9s", "gate", "pairs", "%kept", "top-2 hit")
for (g in names(gates)) {
  v <- gates[[g]]
  keep <- S[v]
  k <- paste(keep$ein_a, keep$ein_b)
  hit <- paste(pmin(t2$e1, t2$e2), pmax(t2$e1, t2$e2)) %chin% k
  say("%-32s %9s %7.0f%% %9d", g, format(sum(v), big.mark=","),
      100*mean(v), sum(hit))
}
say("")
say("The `as shipped` row is the one to beat. A gate that removes a third of")
say("the table but only a handful of firing edges is buying nothing measurable")
say("on this evidence - and it would remove the acronym and rebrand cases that")
say("are the only reason disclosure beats a name rule at all.")
