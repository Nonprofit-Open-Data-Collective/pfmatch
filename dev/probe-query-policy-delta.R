#!/usr/bin/env Rscript
# ============================================================================
# Exactly what changes when the default moves from "operating" to "query".
#
# The tier counts are identical (+629 either way), so the change is entirely in
# WHICH EIN is reported. This counts those grants and checks the direction: a
# switch is only justified where the grant record itself names the arm.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
suppressWarnings(suppressMessages(devtools::load_all(
  Sys.getenv("NPMATCH_DIR", "../npmatch"), quiet = TRUE)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
setDTthreads(0L)
say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() cat(strrep("=", 78), "\n")

D <- readRDS(file.path(PF, "data-dev", "PF-DYADS-UNIFIED.rds"))
m <- readRDS(file.path(PF, "data-dev", "PF-MATCH-RESULT-50k.rds"))
cfg <- npmatch::np_config()
say("scoring ...")
pr <- npmatch::np_veto(npmatch::np_score(attr(m$result, "pairs"), cfg, method = "hier"), cfg)
base <- m
base$result <- npmatch::np_tier(npmatch::np_select(pr, cfg), cfg)
attr(base$result, "pairs") <- pr
base$config <- cfg

runp <- function(policy) {
  o <- suppressMessages(pf_dyad_collapse(base, D, pf_dyad_config(policy = policy),
                                         np_config = cfg))
  a <- as.data.table(as.data.frame(o$result))
  a[, .(.id, tier, ein = overall_ein, nm = overall_name_y, coll = dyad_collapsed)]
}
Q <- runp("query"); O <- runp("operating")
g <- as.data.table(base$grants)
cmp <- merge(Q[, .(.id, t_q = tier, e_q = ein, n_q = nm, coll)],
             O[, .(.id, t_o = tier, e_o = ein, n_o = nm)], by = ".id")
cmp[, q_name := g$recip_name[match(.id, g$grant_id)]]
cmp[, q_is_arm := pf_is_arm(q_name)]

hr(); say("query VS operating"); hr()
say("collapsed grants                    : %d", sum(cmp$coll, na.rm = TRUE))
say("tier differs                        : %d", sum(cmp$t_q != cmp$t_o))
say("REPORTED EIN differs                : %d", sum(cmp$e_q != cmp$e_o, na.rm = TRUE))
ch <- cmp[!is.na(e_q) & !is.na(e_o) & e_q != e_o]
say("")
say("of the changed grants:")
say("  the grant record names an arm     : %d (%.0f%%)",
    sum(ch$q_is_arm, na.rm = TRUE), 100*mean(ch$q_is_arm, na.rm = TRUE))
say("  query policy now reports an arm   : %d (%.0f%%)",
    sum(pf_is_arm(ch$n_q)), 100*mean(pf_is_arm(ch$n_q)))
say("")
say("Every switch should be a grant whose own name says FOUNDATION and whose")
say("reported EIN now matches it. Anything else is the rule misfiring.")
say("")
print(head(ch[, .(.id, query = substr(q_name, 1, 34),
                  was = substr(n_o, 1, 28), now = substr(n_q, 1, 28))], 20),
      row.names = FALSE)
bad <- ch[q_is_arm %in% FALSE]
say("")
say("switches where the grant does NOT name an arm: %d", nrow(bad))
if (nrow(bad)) print(head(bad[, .(.id, query = substr(q_name,1,34),
                                  was = substr(n_o,1,26), now = substr(n_q,1,26))], 10),
                     row.names = FALSE)

fwrite(ch, file.path(PF, "data-dev", "QUERY-POLICY-DELTA.csv"))
say(""); say("wrote data-dev/QUERY-POLICY-DELTA.csv")
