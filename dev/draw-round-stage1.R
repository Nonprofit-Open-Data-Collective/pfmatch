# Draw stage 1 of the adjudication labelling round.
#
# dev/ADJUDICATION-PREREQS.md 6b.3 is the design; dev/ADJ-ROUND-STAGE1-20261102.log
# records what running it against the runs on disk changed about it.
#
# The frame is the production run, which is serialized as list(status, grants):
# the identity-grain status frame (one row per deduped recipient identity,
# carrying the tier, the pass that produced the pick, the margin and n_close)
# beside the grant-grain source (which carries OBJECTID, the dollar amount and
# the stated purpose). The two are keyed differently -- R<k> against
# recipient_uid == k -- which this script joins and verifies before drawing.
#
# Rscript dev/draw-round-stage1.R

suppressMessages(devtools::load_all(".", quiet = TRUE))
suppressMessages(library(data.table))

RUN   <- "data-dev/TRI-V2-MATCH.rds"
OUT   <- "data-dev/ADJ-ROUND-STAGE1.rds"
OUTC  <- "data-dev/ADJ-ROUND-STAGE1.csv"
N     <- 400L
SEED  <- 20261102L

say <- function(...) cat(sprintf(...), "\n", sep = "")

m <- readRDS(RUN)
s <- as.data.table(m$status)
g <- as.data.table(m$grants)
say("run %s: %s identities, %s grants", RUN,
    format(nrow(s), big.mark = ","), format(nrow(g), big.mark = ","))

# What matched the frame, and what is installed now. These are two different
# facts and the draw records the first: a frame matched under one normalizer and
# drawn under another is still a valid draw of that frame, but a reader months
# from now needs to know which produced the tiers being stratified on.
FSIG <- attr(s, "pf_stamp")$normalizer
if (is.null(FSIG)) FSIG <- m$normalizer
LIVE <- tryCatch(npmatch::np_normalize_signature(), error = function(e) NA_character_)
say("frame matched under %s (built %s)",
    if (is.null(FSIG)) "UNSTAMPED" else FSIG,
    if (is.null(m$built)) "unrecorded" else m$built)
say("installed now    %s%s", LIVE,
    if (!is.null(FSIG) && identical(FSIG, LIVE)) "" else "   <- DIFFERS from the frame")

# --- the identity-to-grant join, verified before it is used -------------------
s[, uid := suppressWarnings(as.integer(sub("^R", "", grant_id)))]
g[, uid := suppressWarnings(as.integer(recipient_uid))]
stopifnot(!anyNA(s$uid), !anyNA(g$uid))
nmz <- function(x) toupper(trimws(gsub(" +", " ", gsub("[^A-Za-z0-9 ]", " ", as.character(x)))))
set.seed(1L)
k <- sample(s$uid, min(500L, nrow(s)))
chk <- merge(s[uid %in% k, .(uid, sname = nmz(recip_name), stier = as.character(status))],
             g[uid %in% k, .(names = list(unique(nmz(recip_name))),
                             gtier = unique(status)[1L]), by = uid], by = "uid")
chk[, name_hit := mapply(function(a, b) a %in% b, sname, names)]
say("join check on %d sampled identities: name %d/%d, tier %d/%d",
    nrow(chk), sum(chk$name_hit), nrow(chk),
    sum(chk$stier == chk$gtier, na.rm = TRUE), nrow(chk))
stopifnot(all(chk$name_hit), all(chk$stier == chk$gtier, na.rm = TRUE))

# --- case features, at identity grain ----------------------------------------
g[, amt := suppressWarnings(as.numeric(.pf_col(g, "PF_15_G_PAID_AMT")))]
g[, purp := .pf_col(g, "PF_15_G_PAID_PURPOSE")]
g[, purp_ok := pf_purpose_is_contentful(purp)]
feat <- g[, .(dollars = sum(amt, na.rm = TRUE),
              n_grants = .N,
              # an identity is "purpose" if ANY of its grants states one: the
              # reviewer sees every grant of the identity, so one stated
              # purpose is evidence available to them
              purpose_contentful = any(purp_ok %in% TRUE)), by = uid]
qs <- quantile(feat$dollars[feat$uid %in% s[status == "MAYBE"]$uid],
               probs = c(.25, .5, .75), na.rm = TRUE)
say("MAYBE dollar quartiles: %s", paste(format(round(qs), big.mark = ","), collapse = " / "))
feat[, dollar_band := cut(dollars, breaks = c(-Inf, qs, Inf),
                          labels = c("q1", "q2", "q3", "q4"))]
feat[, purpose_band := ifelse(purpose_contentful, "purpose", "bare")]
extra <- feat[, .(grant_id = paste0("R", uid), purpose_band, dollar_band,
                  dollars, n_grants)]

# --- how fine a cross the frame can carry ------------------------------------
fr <- merge(s[status == "MAYBE", .(grant_id, pass = match_pass, margin, n_close)],
            extra, by = "grant_id")
fr[, margin_band := cut(margin, breaks = c(-Inf, 0.01, 0.20, Inf),
                        labels = c("tie", "narrow", "clear"))]
say("\nMAYBE frame: %s identities", format(nrow(fr), big.mark = ","))
designs <- list(
  "tier.pass"                = c("pass"),
  "tier.pass.purpose"        = c("pass", "purpose_band"),
  "tier.pass.purpose.margin" = c("pass", "purpose_band", "margin_band"),
  "6b.3 full (plus dollar)"  = c("pass", "purpose_band", "margin_band", "dollar_band"))
say("%-28s %7s %7s %9s %9s", "design", "cells", "n<20", "share<1", "share<2")
for (nm in names(designs)) {
  tb <- as.numeric(table(do.call(paste, c(fr[, designs[[nm]], with = FALSE], sep = "|"))))
  sh <- tb / sum(tb) * N
  say("%-28s %7d %7d %9d %9d", nm, length(tb), sum(tb < 20), sum(sh < 1), sum(sh < 2))
}

# --- the draw ----------------------------------------------------------------
d <- pf_round_sample(m, n = N, tiers = "MAYBE",
                     by = c("tier", "pass", "purpose_band"),
                     extra = as.data.frame(extra), stage = "stage1",
                     seed = SEED)
say("\npopulation %s  frame_id %s  normalizer %s", attr(d, "population"),
    attr(d, "frame_id"), attr(d, "normalizer"))
say("frame %s identities  drawn %d",
    format(attr(d, "frame_size"), big.mark = ","), nrow(d))
print(attr(d, "allocation"))
say("\nmargin band (recorded, not stratified):")
print(table(cut(d$margin, breaks = c(-Inf, 0.01, 0.20, Inf),
                labels = c("tie", "narrow", "clear")), useNA = "ifany"))
say("dollar band (recorded, not stratified):")
print(table(d$dollar_band, useNA = "ifany"))
say("dollars drawn: %s (median identity %s)",
    format(round(sum(d$dollars, na.rm = TRUE)), big.mark = ","),
    format(round(median(d$dollars, na.rm = TRUE)), big.mark = ","))

saveRDS(d, OUT)
utils::write.csv(as.data.frame(d), OUTC, row.names = FALSE, na = "")
say("\nwrote %s and %s", OUT, OUTC)
say("reproduce with: seed %d, n %d, run %s", SEED, N, RUN)
say("  normalizer %s | frame_id %s", attr(d, "normalizer"), attr(d, "frame_id"))
say("  the frame_id is the one to check: grant_id is a POSITION in this run's")
say("  identity numbering, and the population cannot see that numbering move.")
