#!/usr/bin/env Rscript
# ============================================================================
# Rebuild the dyad table against the unified BMF and diff it against the
# monthly-BMF build.
#
# This is not a cosmetic re-run. The BMF supplies the names, geography and
# subsection codes that the classifier uses, and the unified file carries
# 3,687,435 EINs against the monthly file's 1,924,822 - it adds the `legacy`
# rows for organisations that have since lapsed. Both ends of a dyad have to
# resolve for the name-core path and the subsection veto to fire at all, so
# coverage of the dyad EINs is the number that moves.
#
# Output: data-dev/PF-DYADS-UNIFIED.rds / .csv
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("=", 78), "\n")
sb  <- function() cat(strrep("-", 78), "\n")

UNIFIED <- file.path(PF, "..", "npmatch", "data-raw",
                     "bmf_unified_geocoded-nteev2fix.csv")
SRC <- pf_dyad_sources("C:/Users/jdlec/Documents/grants/linkid/out/full")

hr(); say("BUILD AGAINST THE UNIFIED BMF"); hr()
u <- pf_build_dyads(SRC$supported, SRC$related, bmf = UNIFIED,
                    cache = file.path(PF, "data-dev", "PF-DYADS-UNIFIED.rds"))
pf_dyad_summary(u)

o <- readRDS(file.path(PF, "data-dev", "PF-DYADS.rds"))   # the monthly-BMF build

hr(); say("WHAT CHANGED"); hr()
say("%-34s %12s %12s %10s", "", "monthly BMF", "unified BMF", "delta")
f <- function(lbl, a, b) say("%-34s %12s %12s %+10s", lbl,
    format(a, big.mark=","), format(b, big.mark=","), format(b - a, big.mark=","))
f("pairs in the table", nrow(o), nrow(u))
f("both EINs resolve in the BMF", sum(o$in_bmf, na.rm=TRUE), sum(u$in_bmf, na.rm=TRUE))
f("same state known and TRUE", sum(o$same_state, na.rm=TRUE), sum(u$same_state, na.rm=TRUE))
f("same city known and TRUE", sum(o$same_city, na.rm=TRUE), sum(u$same_city, na.rm=TRUE))
f("substitutable", sum(o$dyad_class=="substitutable"), sum(u$dyad_class=="substitutable"))
say("")
say("BMF coverage of dyad EINs: %.1f%% -> %.1f%%",
    100*mean(o$in_bmf, na.rm=TRUE), 100*mean(u$in_bmf, na.rm=TRUE))

sb(); say("SUBSTITUTABLE BY REASON"); sb()
cmp <- merge(o[, .(dyad_id_o = dyad_id, ein_a, ein_b, cls_o = dyad_class,
                   rsn_o = dyad_reason)],
             u[, .(ein_a, ein_b, cls_u = dyad_class, rsn_u = dyad_reason)],
             by = c("ein_a", "ein_b"), all = TRUE)
say("pairs present in both builds: %s", format(sum(!is.na(cmp$cls_o) & !is.na(cmp$cls_u)), big.mark=","))
print(u[, .(pairs = .N), by = .(reason = dyad_reason, dyad_class)][
        dyad_class == "substitutable"][order(-pairs)], row.names = FALSE)

sb(); say("CLASS TRANSITIONS"); sb()
tr <- cmp[!is.na(cls_o) & !is.na(cls_u), .N, by = .(cls_o, cls_u)][order(-N)]
print(tr, row.names = FALSE)
say("")
prom <- cmp[cls_o == "related" & cls_u == "substitutable"]
say("promoted to substitutable by the unified BMF: %s", format(nrow(prom), big.mark=","))
if (nrow(prom)) {
  print(prom[, .(pairs = .N), by = .(was = rsn_o, now = rsn_u)][order(-pairs)][1:6],
        row.names = FALSE)
  nm <- rbind(u[, .(ein = ein_a, n = name_a)], u[, .(ein = ein_b, n = name_b)])
  nm <- unique(nm, by = "ein")
  prom[, `:=`(na = nm$n[match(ein_a, nm$ein)], nb = nm$n[match(ein_b, nm$ein)])]
  say("")
  print(head(prom[, .(a = substr(na,1,36), b = substr(nb,1,36))], 12), row.names = FALSE)
}
dem <- cmp[cls_o == "substitutable" & cls_u == "related"]
say("")
say("demoted to related by the unified BMF: %s", format(nrow(dem), big.mark=","))
if (nrow(dem)) print(dem[, .(pairs = .N), by = .(now = rsn_u)][order(-pairs)][1:6],
                     row.names = FALSE)

sb(); say("DEGREE - the safety number, recomputed"); sb()
s <- u[dyad_class == "substitutable"]
dg <- rbind(s[, .(ein = ein_a)], s[, .(ein = ein_b)])[, .N, by = ein]
say("substitutable EINs %s   max degree %d   mean %.2f   deg>10 %d",
    format(nrow(dg), big.mark=","), max(dg$N), mean(dg$N), sum(dg$N > 10))

fwrite(u, file.path(PF, "data-dev", "PF-DYADS-UNIFIED.csv"))
say(""); say("wrote data-dev/PF-DYADS-UNIFIED.rds and .csv")
