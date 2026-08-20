#!/usr/bin/env Rscript
# ============================================================================
# The two features on the wish-list that have never been tested:
#
#   (a) GRANTEE-NESS -- how many distinct foundations elsewhere in the file give
#       to this EIN? A body that receives grants from many unrelated funders is
#       an active grantee; a same-named distractor is often a dormant shell.
#   (b) FUNDER REPEAT -- does *this* foundation give to this EIN in another
#       grant or year? Foundations fund the same grantees repeatedly, and the
#       other rows may carry a fuller or cleaner name.
#
# Both priors are built ONLY from unambiguous YES matches (exact name, ZIP
# agreement, score >= 0.95) so that the training signal comes from easy cases
# and is applied to hard ones. Leave-one-out: a grant never contributes to its
# own prior, and neither does any other grant from the same filer when scoring
# feature (a).
#
# Evaluated as pair AUC on the adjudicated sets: P(correct candidate scores
# above a distractor from the same grant).
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")
hr  <- function() cat(strrep("-", 78), "\n")
e9  <- function(x) { x <- gsub("[^0-9]", "", as.character(x))
                     ifelse(nchar(x) == 9L, x, NA_character_) }

## ---- rebuild the 50k run --------------------------------------------------
m   <- readRDS(file.path(PF, "data-dev", "PF-MATCH-RESULT-50k.rds"))
cfg <- npmatch::np_config()
pr0 <- npmatch::np_veto(npmatch::np_score(attr(m$result, "pairs"), cfg, method = "hier"), cfg)
res <- npmatch::np_tier(npmatch::np_select(pr0, cfg), cfg)
x <- m; x$result <- res; attr(x$result, "pairs") <- pr0; attr(x$result, "config") <- cfg
st <- as.data.table(pf_status(x))
pr <- as.data.table(pr0)[veto == FALSE]

## ---- the prior, from unambiguous YES only ---------------------------------
top <- pr[, .SD[which.max(score)], by = .id]
easy <- merge(top[, .(grant_id = .id, ein = e9(.ein), score, geo_zip5,
                      nv = name_ver_y, nmt = name_match_type)],
              st[, .(grant_id, status, filer_ein = e9(filer_ein))], by = "grant_id")
easy <- easy[status == "YES" & score >= 0.95 & geo_zip5 %in% 1 &
             toupper(nv) %in% c("MAIN", NA) & !is.na(ein) & !is.na(filer_ein)]
say("unambiguous YES rows used to build the prior : %s", format(nrow(easy), big.mark = ","))
say("distinct recipient EINs                      : %s", format(uniqueN(easy$ein), big.mark = ","))
say("distinct filing foundations                  : %s", format(uniqueN(easy$filer_ein), big.mark = ","))

# (a) distinct funders per EIN
fund <- unique(easy[, .(ein, filer_ein)])
n_funders <- fund[, .(n_funders = .N), by = ein]
setkey(n_funders, ein)
say("")
say("distribution of distinct funders per recipient EIN:")
print(n_funders[, .N, by = .(bucket = cut(n_funders, c(0, 1, 2, 5, 20, Inf),
      labels = c("1", "2", "3-5", "6-20", "20+")))][order(bucket)], row.names = FALSE)

# (b) filer -> ein pairs
fk <- unique(easy[, .(k = paste(filer_ein, ein))])$k

## ---- evaluate on the adjudicated sets -------------------------------------
ev <- list()

a1 <- fread(file.path(PF, "data-dev", "AUDIT-MAYBE-100.csv"), colClasses = "character")
v1 <- fread(file.path(PF, "dev", "maybe-verdicts.csv"), colClasses = "character")
ev$audit <- merge(a1[, .(gid = grant_id, rank = as.integer(rank), ein = e9(ein),
                         filer_ein = e9(fdn_ein), nm = cand_name)],
                  v1[, .(gid = grant_id, cr = as.integer(correct_rank))], by = "gid")

a2 <- fread(file.path(PF, "data-dev", "HARD-ENRICHED.csv"), colClasses = "character")
v2 <- fread(file.path(PF, "dev", "enrichment-verdicts.csv"), colClasses = "character")
v2 <- v2[outcome %in% c("RESOLVED_ALT", "RESOLVED_PICK")]
s2 <- a2[, .(gid = paste0("E", idx), rank = as.integer(rank), ein = e9(cand_ein),
             nm = cand_name, idx = as.integer(idx), grant_id)]
s2[, filer_ein := st$filer_ein[match(grant_id, st$grant_id)]][, filer_ein := e9(filer_ein)]
ev$enriched <- merge(s2, v2[, .(idx = as.integer(idx), cr = as.integer(pick_ein_rank))],
                     by = "idx")[, .(gid, rank, ein, filer_ein, nm, cr)]

d <- rbindlist(ev, use.names = TRUE, idcol = "set")
d <- d[!is.na(ein) & !is.na(cr)]
d[, correct := rank == cr]
d <- d[, if (any(correct) && .N > 1L) .SD, by = gid]     # need a correct + a distractor
say("")
say("adjudicated grants usable for AUC : %d  (%s candidate rows)",
    uniqueN(d$gid), format(nrow(d), big.mark = ","))

# leave-one-out: drop this filer's own contribution to the funder count
d[, nf_raw := n_funders$n_funders[match(ein, n_funders$ein)]]
d[is.na(nf_raw), nf_raw := 0L]
own <- paste(d$filer_ein, d$ein) %in% unique(paste(fund$filer_ein, fund$ein))
d[, grantee_prior := nf_raw - as.integer(own)]
d[, funder_repeat := as.integer(own)]

auc <- function(dt, col) {
  v <- dt[, {
    s <- get(col)
    if (!any(correct) || all(correct)) NULL else {
      pos <- s[correct]; neg <- s[!correct]
      list(a = mean(outer(pos, neg, ">") + 0.5 * outer(pos, neg, "==")), n = length(neg))
    }}, by = gid]
  list(auc = weighted.mean(v$a, v$n), grants = nrow(v))
}
# baseline: the cascade's own rank (higher is better -> negate)
d[, rank_score := -rank]

hr(); say("PAIR AUC ON THE ADJUDICATED SETS"); hr()
say("%-34s %8s %9s", "feature", "grants", "pair AUC")
for (f in c("rank_score", "grantee_prior", "funder_repeat")) {
  r <- auc(d, f)
  say("%-34s %8d %9.3f",
      switch(f, rank_score = "cascade rank (baseline)",
                grantee_prior = "(a) distinct other funders",
                funder_repeat = "(b) same funder, another grant"), r$grants, r$auc)
}
say("")
say("0.5 is chance. Above 0.5 the feature ranks the correct candidate higher.")

hr(); say("HOW OFTEN DOES EACH FEATURE FIRE AT ALL?"); hr()
fire <- d[, .(gp = length(unique(grantee_prior)) > 1L,
              fr = length(unique(funder_repeat)) > 1L), by = gid]
say("grants where (a) separates the candidates : %d of %d (%.0f%%)",
    sum(fire$gp), nrow(fire), 100 * mean(fire$gp))
say("grants where (b) separates the candidates : %d of %d (%.0f%%)",
    sum(fire$fr), nrow(fire), 100 * mean(fire$fr))
say("")
say("Conditional on firing:")
for (f in c("grantee_prior", "funder_repeat")) {
  sub <- d[gid %in% fire$gid[if (f == "grantee_prior") fire$gp else fire$fr]]
  if (nrow(sub)) {
    r <- auc(sub, f)
    top1 <- sub[, .(hit = correct[which.max(get(f))]), by = gid]
    say("  %-30s AUC %.3f   top-1 %.0f%% on %d grants",
        f, r$auc, 100 * mean(top1$hit), nrow(top1))
  }
}

hr(); say("THE ARM PROBLEM, RESTATED AS A FEATURE"); hr()
d[, is_arm := pf_is_arm(nm)]
say("correct candidates that are an arm     : %d of %d (%.0f%%)",
    d[correct == TRUE, sum(is_arm)], d[, sum(correct)],
    100 * d[correct == TRUE, mean(is_arm)])
say("distractors that are an arm            : %d of %d (%.0f%%)",
    d[correct == FALSE, sum(is_arm)], d[, sum(!correct)],
    100 * d[correct == FALSE, mean(is_arm)])
r <- auc(d[, .(gid, correct, s = -as.integer(is_arm))][, `:=`(s = s)], "s")
say("pair AUC of 'is not an arm'            : %.3f", r$auc)
fwrite(d, file.path(PF, "data-dev", "FEATURE-EVAL.csv"))
say("")
say("wrote data-dev/FEATURE-EVAL.csv")
