#!/usr/bin/env Rscript
# ============================================================================
# eval-purpose-sim.R -- can text similarity between the grant purpose and the
# candidate organization's own text surface the correct EIN?
#
# Metrics, per (purpose, field) pair:
#   cov_*  IDF-weighted containment   sum idf(q & d) / sum idf(q)
#   cos_*  TF-IDF cosine              (binary query, sublinear tf on the document)
#   ng4_*  character 4-gram cosine    (morphology backstop)
#   nb_*   semantic bridge: multinomial naive Bayes purpose -> NTEE, trained on
#          Form 990 mission statements labeled with the filer's own BMF code,
#          scored as LIFT  log P(code | purpose) - log P(code)
#
# Fields: NTEE reference text, IRS activity text, 990 mission, 990 programs,
#         ALL of them concatenated, and the candidate NAME (as a control).
#
# Sets:  gold   = 63 adjudicated MAYBE grants          (data-dev/PURPOSE-TESTSET.csv)
#        silver = 794 YES grants with >1 candidate     (…-YES.csv)
#
# Out: data-dev/PURPOSE-TESTSET-SCORED.csv, …-YES-SCORED.csv, read-out on stdout
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
PF  <- Sys.getenv("PFMATCH_DIR", ".")
NPM <- Sys.getenv("NPMATCH_DIR", "../npmatch")
BMF <- file.path(NPM, "data-raw", "bmf_2026_01_processed.csv")
source(file.path(PF, "dev", "purpose-enrich.R"))
say <- pt_say; sq <- pt_sq
set.seed(2026)

## ---------------------------------------------------------------- corpus ----
say("building the reference corpus ...")
corp <- copy(pt_text_by_ein())
say("  %d organizations", nrow(corp))

ct <- pt_utok(corp$mission)
N  <- length(ct)
df <- table(unlist(ct))
IDF <- log((N + 1) / (as.numeric(df) + 1)); names(IDF) <- names(df)
idf_of <- function(v) { i <- IDF[v]; i[is.na(i)] <- log(N + 1); as.numeric(i) }
say("  IDF over %d distinct tokens / %d documents", length(IDF), N)

## ------------------------------------------------- naive Bayes -> NTEE ------
b <- fread(BMF, select = c("ein", "ntee_code_clean", "nteev2_subsector"),
           colClasses = "character", na.strings = NULL, showProgress = FALSE)
b[, ein9 := pt_ein9(ein)]
bi <- match(corp$ein9, b$ein9)
corp[, code   := sq(b$ntee_code_clean[bi])]
corp[, sector := sq(b$nteev2_subsector[bi])]
corp[, major  := substr(code, 1, 1)]
corp[code %in% c("", "UNDEFINED", "INVALID", "Z99") | !grepl("^[A-Y]", code), major := ""]
corp[sector %in% c("", "UNU", "UNI"), sector := ""]

fit_nb <- function(lab, txt) {
  keep <- nzchar(lab) & nzchar(txt)
  lab <- lab[keep]; tt <- pt_tok(txt[keep])
  dt  <- data.table(lab = rep(lab, lengths(tt)), tk = unlist(tt))
  cnt <- dt[, .N, by = .(lab, tk)]
  tot <- cnt[, .(tot = sum(N)), by = lab]
  V   <- uniqueN(cnt$tk)
  cnt[, lp := log(N + 1) - log(tot$tot[match(lab, tot$lab)] + V)]
  pri <- data.table(lab = names(table(lab)), n = as.numeric(table(lab)))
  pri[, lpri := log(n / sum(n))]
  setkey(cnt, tk)
  list(cnt = cnt, tot = tot, V = V, pri = pri, docs = sum(keep))
}
nb_post <- function(m, toks) {
  labs <- m$pri$lab; lp <- m$pri$lpri
  if (length(toks)) {
    base <- -log(m$tot$tot[match(labs, m$tot$lab)] + m$V)
    for (t in toks) {
      add <- base
      hh <- m$cnt[.(t), nomatch = 0L]
      if (nrow(hh)) { k <- match(hh$lab, labs); add[k] <- hh$lp }
      lp <- lp + add
    }
  }
  p <- exp(lp - max(lp)); setNames(p / sum(p), labs)
}
say("training purpose -> NTEE naive Bayes ...")
nb_maj <- fit_nb(corp$major,  corp$mission)
nb_sec <- fit_nb(corp$sector, corp$mission)
say("  major-group model: %d docs, %d labels", nb_maj$docs, nrow(nb_maj$pri))
say("  subsector  model: %d docs, %d labels", nb_sec$docs, nrow(nb_sec$pri))

## how good is the bridge in principle, and what does brevity cost it?
ho <- corp[nzchar(major) & nzchar(mission)][sample(.N, 1500)]
acc <- function(m, txts, truth, ntok = Inf) {
  tk <- pt_tok(txts)
  if (is.finite(ntok)) tk <- lapply(tk, function(v) head(v, ntok))
  pr <- vapply(tk, function(t) { p <- nb_post(m, t); names(p)[which.max(p)] }, "")
  mean(pr == truth)
}
say("  in-corpus top-1 accuracy on 1,500 missions (26 major groups):")
say("    full mission      %4.1f%%", 100 * acc(nb_maj, ho$mission, ho$major))
say("    first 3 tokens    %4.1f%%", 100 * acc(nb_maj, ho$mission, ho$major, 3))
say("    first 2 tokens    %4.1f%%", 100 * acc(nb_maj, ho$mission, ho$major, 2))
say("    majority-class    %4.1f%%", 100 * max(table(ho$major)) / nrow(ho))

## ------------------------------------------------------------- scoring ------
FIELDS <- c(ntee = "cand_ntee_ref_text", act = "CAND_activity_code_definitions",
            mis  = "cand_mission",       prog = "cand_prog_all",
            all  = "all_text",           name = "cand_name")

score_set <- function(d) {
  d <- as.data.table(d)
  for (cl in c("rank", "purpose_ctoks", "correct_rank"))
    if (cl %in% names(d)) d[, (cl) := as.integer(get(cl))]
  for (cl in c("score", "name_sim"))
    if (cl %in% names(d)) d[, (cl) := as.numeric(get(cl))]
  for (cl in c("is_correct", "has_truth", "purpose_contentful"))
    if (cl %in% names(d) && !is.logical(d[[cl]])) d[, (cl) := get(cl) %in% c("TRUE", "true")]
  d[, all_text := trimws(paste(sq(cand_ntee_ref_text), sq(CAND_activity_code_definitions),
                               sq(cand_mission), sq(cand_prog_all)))]
  qt <- pt_utok(d$grant_purpose); qg <- pt_ng4(d$grant_purpose)
  qw <- lapply(qt, idf_of)
  for (nm in names(FIELDS)) {
    fv <- sq(d[[FIELDS[[nm]]]])
    dt <- pt_utok(fv); dg <- pt_ng4(fv); dtf <- pt_tok(fv)
    cov <- cos <- ngc <- rep(NA_real_, nrow(d))
    for (i in seq_len(nrow(d))) {
      if (!length(qt[[i]]) || !nzchar(fv[i])) next
      hit <- qt[[i]] %in% dt[[i]]
      cov[i] <- sum(qw[[i]][hit]) / sum(qw[[i]])
      tf <- table(dtf[[i]])
      if (!length(tf)) next
      dv <- (1 + log(as.numeric(tf))) * idf_of(names(tf))
      k  <- match(qt[[i]], names(tf)); ok <- !is.na(k)
      cos[i] <- sum(qw[[i]][ok] * dv[k[ok]]) / (sqrt(sum(qw[[i]]^2)) * sqrt(sum(dv^2)))
      if (length(qg[[i]]) && length(dg[[i]]))
        ngc[i] <- sum(qg[[i]] %in% dg[[i]]) / sqrt(length(qg[[i]]) * length(dg[[i]]))
    }
    d[, (paste0("cov_",  nm)) := cov]
    d[, (paste0("cos_",  nm)) := cos]
    d[, (paste0("ng4_",  nm)) := ngc]
  }
  # naive-Bayes lift on the candidate's own code
  uq <- unique(d[, .(grant_id, grant_purpose)]); uq[, i := .I]
  tk <- pt_utok(uq$grant_purpose)
  pm <- lapply(tk, function(t) nb_post(nb_maj, t))
  ps <- lapply(tk, function(t) nb_post(nb_sec, t))
  gi <- match(d$grant_id, uq$grant_id)
  d[, cand_major  := substr(sq(CAND_ntee_code_clean), 1, 1)]
  d[cand_major %in% c("", "Z", "I", "U") , cand_major := ""]
  d[!grepl("^[A-Y]$", cand_major), cand_major := ""]
  d[, cand_sector := sub("-.*$", "", sq(CAND_nteev2))]
  d[cand_sector %in% c("", "UNU", "UNI"), cand_sector := ""]
  lift <- function(plist, k, lab, pri) {
    if (!nzchar(lab)) return(NA_real_)
    p <- plist[[k]]; if (is.na(p[lab])) return(NA_real_)
    log(unname(p[lab])) - pri$lpri[match(lab, pri$lab)]
  }
  d[, nb_major  := mapply(function(k, l) lift(pm, k, l, nb_maj$pri), gi, cand_major)]
  d[, nb_sector := mapply(function(k, l) lift(ps, k, l, nb_sec$pri), gi, cand_sector)]
  d[]
}

## ---------------------------------------------------------------- eval ------
METRICS <- NULL
auc <- function(m, s) {
  x <- s[[m]]; y <- s$is_correct; ok <- !is.na(x)
  p <- x[ok & y]; n <- x[ok & !y]
  if (!length(p) || !length(n)) return(c(NA, NA))
  r <- rank(c(p, n))
  c((sum(r[seq_along(p)]) - length(p) * (length(p) + 1) / 2) / (length(p) * length(n)),
    length(p))
}
rankit <- function(m, s) {
  z <- s[!is.na(get(m)), .(grant_id, v = get(m), is_correct)]
  z <- z[, if (.N >= 2 && sum(is_correct) == 1) .SD, by = grant_id]
  if (!nrow(z)) return(c(NA, NA, NA, NA))
  fired <- z[, .(fire = uniqueN(v) > 1), by = grant_id]
  z <- z[grant_id %in% fired[fire == TRUE]$grant_id]
  if (!nrow(z)) return(c(0, NA, NA, 0))
  r <- z[, .(hit = is_correct[which.max(v)],
             rr  = 1 / frank(-v, ties.method = "min")[is_correct]), by = grant_id]
  c(fires = nrow(fired[fire == TRUE]) / nrow(fired), top1 = mean(r$hit),
    mrr = mean(r$rr), n = nrow(r))
}
report <- function(s, title) {
  s <- s[has_truth == TRUE]
  say(""); say("== %s : %d grants, %d candidate rows ==", title,
               uniqueN(s$grant_id), nrow(s))
  tb <- rbindlist(lapply(METRICS, function(m) {
    a <- auc(m, s); r <- rankit(m, s)
    data.table(metric = m, pair_auc = round(a[1], 3), n_pos = a[2],
               fires = round(r[1], 2), n_fired = r[4],
               top1 = round(r[2], 3), mrr = round(r[3], 3))
  }))
  print(tb[order(-pair_auc)])
  bs <- rankit("score", s)
  say("  baseline, name/geo score alone: top1 = %.3f  mrr = %.3f  over %d grants",
      bs[2], bs[3], bs[4])
}

gold <- score_set(fread(file.path(PF, "data-dev", "PURPOSE-TESTSET.csv"),
                        colClasses = "character", na.strings = NULL, showProgress = FALSE))
METRICS <- c(grep("^(cov|cos|ng4)_", names(gold), value = TRUE), "nb_major", "nb_sector")
fwrite(gold, file.path(PF, "data-dev", "PURPOSE-TESTSET-SCORED.csv"), na = "")

silver <- score_set(fread(file.path(PF, "data-dev", "PURPOSE-TESTSET-YES.csv"),
                          colClasses = "character", na.strings = NULL, showProgress = FALSE))
silver[, hard := hard %in% c("TRUE", "true")]
fwrite(silver, file.path(PF, "data-dev", "PURPOSE-TESTSET-YES-SCORED.csv"), na = "")

report(silver[purpose_contentful == TRUE], "SILVER (YES tier, contentful purpose)")
report(gold, "GOLD (adjudicated MAYBE, all)")
report(gold[purpose_contentful == TRUE], "GOLD (adjudicated MAYBE, contentful purpose)")

## does adding the best metric to the name score change the top pick?
say(""); say("== combining with the name/geo score, GOLD contentful ==")
g <- gold[has_truth == TRUE & purpose_contentful == TRUE]
for (m in c("cov_all", "cos_all", "cov_ntee", "nb_major")) {
  for (w in c(0, 0.05, 0.1, 0.2, 0.4)) {
    z <- g[, .(grant_id, is_correct,
               v = score + w * fifelse(is.na(get(m)), 0, get(m)))]
    z <- z[, if (.N >= 2 && sum(is_correct) == 1) .SD, by = grant_id]
    r <- z[, .(hit = is_correct[which.max(v)]), by = grant_id]
    say("  %-9s w=%-5.2f top1 = %.3f  (%d/%d)", m, w, mean(r$hit), sum(r$hit), nrow(r))
  }
}

say(""); say("== the 8 hard GOLD cases (contentful purpose, correct NOT at rank 1) ==")
h <- gold[has_truth == TRUE & purpose_contentful == TRUE & correct_rank > 1]
for (id in unique(h$grant_id)) {
  x <- gold[grant_id == id][order(rank)]
  say("-- %s  purpose: %s", id, substr(x$grant_purpose[1], 1, 70))
  say("   filed: %s (%s %s)", substr(x$recip_name[1], 1, 46), x$recip_city[1], x$recip_state[1])
  for (i in seq_len(nrow(x)))
    say("    %s%d %-40s ntee=%-9s cov_all=%-5s cov_ntee=%-5s nb_maj=%-6s",
        ifelse(x$is_correct[i], "*", " "), x$rank[i], substr(x$cand_name[i], 1, 40),
        x$CAND_ntee_code_clean[i],
        formatC(x$cov_all[i], format = "f", digits = 2),
        formatC(x$cov_ntee[i], format = "f", digits = 2),
        formatC(x$nb_major[i], format = "f", digits = 2))
}
