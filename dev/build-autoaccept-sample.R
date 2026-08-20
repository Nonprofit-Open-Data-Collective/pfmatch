#!/usr/bin/env Rscript
# ============================================================================
# Build a fresh 200-case validation sample for the auto-accept rule
#   ZIP5 agrees AND margin >= 0.05
# measured at 18/18 on the original 100. That is a 95% CI of ~82-100%, so the
# rule needs confirming on cases it was not fitted to.
#
# Drawn from the 50k result (a larger MAYBE pool), rescored with the CURRENT
# config so the statuses reflect the shipped pipeline, and de-duplicated against
# the already-labelled 100 on (filer, recipient, amount) since grant_id is only
# unique within a file.
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
suppressWarnings(suppressMessages(library(npmatch)))
suppressWarnings(suppressMessages(devtools::load_all(PF, quiet = TRUE)))
say <- function(...) cat(sprintf(...), "\n")
set.seed(2026)

m <- readRDS(file.path(PF, "data-dev", "PF-MATCH-RESULT-50k.rds"))
pairs <- attr(m$result, "pairs")
cfg <- npmatch::np_config()                       # current shipped defaults
p   <- npmatch::np_veto(npmatch::np_score(pairs, cfg, method = "hier"), cfg)
res <- npmatch::np_tier(npmatch::np_select(p, cfg), cfg)
x <- m; x$result <- res
attr(x$result, "pairs") <- p; attr(x$result, "config") <- cfg
st <- as.data.table(pf_status(x))
say("rescored with current config: %s", paste(sprintf("%s=%d",
    names(table(st$status)), table(st$status)), collapse = "  "))

pr <- as.data.table(p)
setorder(pr, .id, -score)
runner <- pr[, .(top = score[1], second = if (.N > 1) score[2] else 0,
                 n_cand = .N, n_band = sum(score >= score[1] - 0.05)), by = .id]
# pf_status() already carries the runner-up margin from np_select(); no need to
# recompute it, and doing so collided on the column name.
runner[, my_margin := top - second]

mb <- st[status == "MAYBE"]
mb <- merge(mb, runner, by.x = "grant_id", by.y = ".id")
mb[, margin := as.numeric(margin)]
mb[, fires := geo_zip5 %in% 1 & margin >= 0.05]
say("MAYBE cases: %s | rule fires on %s (%.1f%%)",
    format(nrow(mb), big.mark = ","), format(sum(mb$fires), big.mark = ","),
    100 * mean(mb$fires))

# exclude anything already labelled (grant_id is not unique across files)
g <- as.data.table(m$grants)
mb[, amount := suppressWarnings(as.numeric(g$SIGOCPYAMOUN[match(grant_id, g$grant_id)]))]
old <- fread(file.path(PF, "data-dev", "AUDIT-MAYBE-100.csv"), colClasses = "character")
oldkey <- unique(paste(gsub("[^0-9]", "", old$fdn_ein), toupper(old$recip_name)))
mb[, k := paste(gsub("[^0-9]", "", filer_ein), toupper(recip_name))]
fresh <- mb[fires == TRUE & !(k %in% oldkey)]
say("fresh firing cases available: %s", format(nrow(fresh), big.mark = ","))

N <- as.integer(Sys.getenv("PF_N", "200"))
samp <- fresh[sample(.N, min(N, .N))]
setorder(samp, grant_id)

# attach the top pick's context plus the runner-up, for judging
j <- match(paste(samp$grant_id, samp$ein), paste(pr$.id, pr$.ein))
samp[, `:=`(
  cand_city = pr$city_y[j], cand_state = pr$state_y[j], cand_zip = pr$zip5_y[j],
  name_ver = pr$name_ver_y[j], legal_y = pr$name_key_y[j],
  matched_y = pr$name_y[j], pass = pr$pass[j])]
ru <- pr[, .SD[2], by = .id]
k2 <- match(samp$grant_id, ru$.id)
samp[, `:=`(ru_name = ru$name_y[k2], ru_score = ru$score[k2])]
samp[, purpose := g$SIGOCPYPOGOC[match(grant_id, g$grant_id)]]

out <- samp[, .(grant_id, recip_name, recip_city, recip_state, recip_zip5,
                purpose, amount, bmf_name, matched_y, legal_y, name_ver,
                cand_city, cand_state, cand_zip, ein, score, name_sim,
                margin, n_band, n_cand, ru_name, ru_score, pass,
                verdict = "", note = "")]
fwrite(out, file.path(PF, "data-dev", "AUTOACCEPT-SAMPLE-200.csv"))
say("wrote data-dev/AUTOACCEPT-SAMPLE-200.csv (%d cases)", nrow(out))
