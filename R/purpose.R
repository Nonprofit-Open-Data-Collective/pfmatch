#' Grant purpose as a tiebreak signal
#'
#' Part XIV column (d), `SIGOCPYPOGOC`, asks the filer what the grant was for.
#' This module turns that free text into a comparison against the recipient's own
#' self-description and uses it to break ties the name cascade could not.
#'
#' @section Why a tiebreak and not a score:
#' Measured on 63 adjudicated MAYBE grants and 794 YES grants
#' (`dev/PURPOSE-MATCH-FINDINGS.md`):
#' \itemize{
#'   \item The purpose is contentless 58.9% of the time (median 2 words), and
#'     when it has content the comparison still separates candidates on only half
#'     of grants. It is silent far more often than it is wrong.
#'   \item Added to the linkage score across all pairs it is a net loss on grants
#'     that were already right (−14 of 794 at w = 0.4), and it would shift the
#'     score distribution the YES/MAYBE/NO thresholds are tuned against.
#'   \item Confined to the tie band it gains without losing, and the weight
#'     stops mattering — which is the signature of a tiebreak rather than a
#'     score term. So it is implemented as one, and the weight disappears.
#' }
#' The measured gain is small and rests on few cases: +1 grant of 61 at
#' npmatch's own gates, +3 if the `tie_high` gate is dropped. It is therefore
#' **off by default**; see [pf_purpose_tiebreak()].
#'
#' @name pf_purpose
NULL
#' Funding boilerplate
#'
#' Words that say a grant was *made* rather than what it was *for*. Removing
#' them is what distinguishes a purpose that carries information from one that
#' does not — and it is why a character-length gate does not work: 55 purposes
#' of 12 characters or fewer are contentful (`SCHOLARSHIP`, `EDUCATION`,
#' `Culture`), while 23 purposes over 30 characters are not (`TO SUPPORT THE
#' MISSION OF THE ORGANIZATION`).
#'
#' @return A character vector of stopwords.
#' @keywords internal
#' @export
pf_purpose_stopwords <- function() c(
  "THE","AND","FOR","TO","OF","IN","A","AN","ON","AT","BY","WITH","OR","THIS",
  "THAT","IS","ARE","AS","FROM","ITS","BE","WILL","WAS","WERE","HAS","HAVE","HAD",
  "OUR","WE","THEIR","THEY","IT","ALL","ANY","EACH","MORE","MOST","SUCH","WHICH",
  "WHO","WHOM","WHOSE","THAN","THEN","THERE","THESE","THOSE","INTO","OVER","UNDER",
  # the grant-making vocabulary
  "SUPPORT","GENERAL","FUND","FUNDS","FUNDING","PURPOSE","PURPOSES","OPERATING",
  "OPERATIONS","UNRESTRICTED","DONATION","DONATIONS","CONTRIBUTION","CONTRIBUTIONS",
  "GRANT","GRANTS","ANNUAL","USE","GIFT","GIFTS","ORGANIZATION","ORGANIZATIONS",
  "NONE","OTHER","VARIOUS","GOS","NEEDED","CHARITABLE","CHARITY","EXEMPT","DONEE",
  "FURTHER","FURTHERANCE","PROVIDE","PROVIDES","PROVIDING","SUPPORTED","PAYOUT",
  "BUDGET","DISCRETIONARY","UNDESIGNATED","REQUESTED","NEEDS","OPERATIONAL",
  # words naming the vehicle rather than the domain
  "ACTIVITY","ACTIVITIES","CAMPAIGN","PROJECT","PROJECTS","PROGRAM","PROGRAMS",
  "MISSION","SERVICE","SERVICES","GENERALS","SPONSORSHIP","MEMBERSHIP","PLEDGE",
  "EXPENSES","EXPENSE","MATCHING","PAYMENT","PAYMENTS","GIVING","GENEROUS")
#' Tokenize purpose or organization text
#'
#' @param x Character vector.
#' @param unique_only Drop repeats within a document.
#' @param stopwords Vocabulary to remove; defaults to [pf_purpose_stopwords()].
#' @param min_nchar Shortest token to keep.
#' @return A list of character vectors.
pf_purpose_tokens <- function(x, unique_only = FALSE,
                              stopwords = pf_purpose_stopwords(), min_nchar = 3L) {
  x <- as.character(x); x[is.na(x)] <- ""
  n <- gsub("  *", " ", trimws(toupper(gsub("[^A-Za-z ]", " ", x))))
  out <- strsplit(n, " ", fixed = TRUE)
  lapply(out, function(v) {
    v <- v[nchar(v) >= min_nchar & !v %in% stopwords]
    if (unique_only) unique(v) else v
  })
}
#' Does the purpose say anything?
#'
#' `TRUE` when at least one token survives the boilerplate stoplist. Gate on
#' this, not on character length.
#'
#' @param x Character vector of grant purposes.
#' @return A logical vector.
#' @export
pf_purpose_is_contentful <- function(x) lengths(pf_purpose_tokens(x, TRUE)) > 0L
#' IDF-weighted containment of a purpose in a document
#'
#' The share of the purpose's information content that is present in the
#' organization's text:
#' \deqn{ \mathrm{cov}(q,d) = \sum_{t \in q \cap d} \mathrm{idf}(t) \;/\; \sum_{t \in q} \mathrm{idf}(t) }
#'
#' Asymmetric on purpose. The query is two words and the document can be five
#' thousand, so a symmetric measure (cosine, Jaccard) is near zero for every pair
#' and cannot rank them; containment asks only how much of the *query* is
#' accounted for, and is insensitive to document length. `NA` when the purpose
#' has no content tokens or the document is empty — never 0, because a zero is
#' evidence against and this is an absence of evidence.
#'
#' @param purpose,doc Character vectors, recycled to common length.
#' @param idf Named numeric of token IDF weights (see [pf_build_org_text()]).
#' @return A numeric vector in `[0, 1]`, with `NA` where undefined.
pf_purpose_coverage <- function(purpose, doc, idf) {
  n <- max(length(purpose), length(doc))
  purpose <- rep_len(purpose, n); doc <- rep_len(doc, n)
  qt <- pf_purpose_tokens(purpose, TRUE)
  dt <- pf_purpose_tokens(doc, TRUE)
  default <- if (length(idf)) max(idf) else 1
  w <- function(v) { z <- idf[v]; z[is.na(z)] <- default; as.numeric(z) }
  vapply(seq_len(n), function(i) {
    q <- qt[[i]]
    if (!length(q) || !length(dt[[i]])) return(NA_real_)
    wi <- w(q)
    s <- sum(wi)
    if (!is.finite(s) || s == 0) return(NA_real_)
    sum(wi[q %in% dt[[i]]]) / s
  }, numeric(1))
}
#' Tiebreak settings
#'
#' @param tie_band Candidates within this much of the top score are in
#'   contention. Matches npmatch's `np_config()$tie_band`.
#' @param tie_high Only tiebreak when the top score is at least this. npmatch
#'   defaults to 0.95; setting it to 0 widens the tiebreak to every near-tie,
#'   which on the audit sample raises the gain from +1 to +3 of 61 grants but is
#'   a change to selection behaviour that 61 grants cannot justify.
#' @param keys Ordered tiebreak keys, applied in sequence until one separates the
#'   contenders. `cov_all` is the purpose comparison; `has_mission` is whether
#'   the candidate files a Form 990 with a mission statement at all.
#' @return A list.
#' @keywords internal
#' @export
pf_tiebreak_config <- function(tie_band = 0.05, tie_high = 0.95,
                               keys = c("cov_all", "has_mission"))
  list(tie_band = tie_band, tie_high = tie_high, keys = keys)
#' Break near-ties on grant purpose and filing presence
#'
#' Recomputes the overall pick for grants where the top candidates are within
#' `tie_band` of each other, ordering the contenders by the configured keys
#' instead of by score. **Scores are not modified**, so the YES / MAYBE / NO
#' thresholds keep their meaning and the benchmark stays comparable; only the
#' choice among tied candidates changes.
#'
#' Features are computed lazily, for contending candidates only — a few thousand
#' pairs rather than the millions the cascade scored.
#'
#' @section What the keys are worth:
#' On the 61 contested adjudicated grants, ordering by `cov_all` then
#' `has_mission` inside the band gains 3 and loses 0 (0.770 -> 0.820) with
#' `tie_high = 0`, or gains 1 and loses 0 at `tie_high = 0.95`. On the 794 YES
#' grants it changes nothing, because none of them are inside the band. Note
#' that npmatch's own `tiebreak = "name"` key is net 0 to −2 on this data: it
#' assumes the entity whose full name matches the query is the right one, and in
#' 990-PF grants the correct recipient is the `FOUNDATION` arm 52.8% of the time,
#' so the assumption is a coin flip here.
#'
#' @param x A `pf_match` from [pf_match_grants()].
#' @param org_text Output of [pf_build_org_text()].
#' @param config Output of [pf_tiebreak_config()].
#' @return `x` with `result$overall_*` rewritten where the tiebreak fired, plus
#'   `tiebreak_fired`, `tiebreak_key`, and `tiebreak_from_ein` columns recording
#'   every change.
#' @export
pf_purpose_tiebreak <- function(x, org_text, config = pf_tiebreak_config()) {
  stopifnot(inherits(x, "pf_match"))
  res <- as.data.frame(x$result)
  pr  <- data.table::as.data.table(attr(x$result, "pairs"))
  if (!is.null(pr$veto)) pr <- pr[!(pr$veto %in% TRUE)]
  g <- x$grants
  idf <- attr(org_text, "token_idf")
  res$tiebreak_fired    <- FALSE
  res$tiebreak_key      <- NA_character_
  res$tiebreak_from_ein <- NA_character_
  # 1. which grants are in contention at all?
  data.table::setorder(pr, .id, -score)
  tops <- pr[, .(top = score[1L],
                 n_close = sum(score >= score[1L] - config$tie_band)), by = .id]
  live <- tops[n_close >= 2L & top >= config$tie_high]$.id
  if (!length(live)) return(structure(
    .pf_setresult(x, .pf_reclass(res, x$result)), class = "pf_match"))
  cand <- pr[.id %in% live]
  cand[, top := max(score), by = .id]
  cand <- cand[score >= top - config$tie_band]
  # 2. features, for contenders only
  gi <- match(cand$.id, g$grant_id)
  cand[, purpose := as.character(g$SIGOCPYPOGOC)[gi]]
  cand[, ein := .pf_ein(.ein)]
  ti <- match(cand$ein, org_text$ein)
  cand[, all_text   := .pf_txt_sq(org_text$all_text[ti])]
  cand[, has_mission := as.numeric(!is.na(ti) & org_text$has_mission[ti])]
  cand[, contentful := pf_purpose_is_contentful(purpose)]
  cand[, cov_all := NA_real_]
  ok <- which(cand$contentful & nzchar(cand$all_text))
  if (length(ok))
    cand[ok, cov_all := pf_purpose_coverage(purpose, all_text, idf)]
  # 3. order the contenders by the keys, in sequence
  cand <- data.table::copy(cand)
  for (k in config$keys) {
    v <- suppressWarnings(as.numeric(cand[[k]]))
    v[is.na(v)] <- -Inf
    data.table::set(cand, j = paste0(".key_", k), value = v)
  }
  keycols <- paste0(".key_", config$keys)
  data.table::set(cand, j = ".seq", value = seq_len(nrow(cand)))
  data.table::setorderv(cand, c(".id", keycols, ".seq"),
                        c(1L, rep(-1L, length(keycols)), 1L))
  win <- cand[!duplicated(.id)]
  # a key only counts as having decided anything if it actually separated them
  decided <- cand[, {
    d <- NA_character_
    for (k in keycols) if (data.table::uniqueN(get(k)) > 1L) { d <- sub("^\\.key_", "", k); break }
    .(key = d)
  }, by = .id]
  # 4. write back only where the pick changed
  ri <- match(win$.id, res$.id)
  changed <- !is.na(ri) & res$overall_ein[ri] != win$ein &
             !is.na(decided$key[match(win$.id, decided$.id)])
  ci <- ri[changed]
  if (length(ci)) {
    res$tiebreak_from_ein[ci] <- res$overall_ein[ci]
    res$tiebreak_fired[ci]    <- TRUE
    res$tiebreak_key[ci]      <- decided$key[match(win$.id[changed], decided$.id)]
    res$overall_ein[ci]       <- win$ein[changed]
    res$overall_name_y[ci]    <- win$name_y[changed]
    res$overall_score[ci]     <- win$score[changed]
    if (!is.null(win$name_key)) res$overall_name_sim[ci] <- win$name_key[changed]
  }
  message(sprintf(
    "pf_purpose_tiebreak: %d grants in contention, %d picks changed (%s)",
    length(live), sum(res$tiebreak_fired),
    paste(sprintf("%s=%d", names(table(res$tiebreak_key)),
                  table(res$tiebreak_key)), collapse = " ")))
  structure(.pf_setresult(x, .pf_reclass(res, x$result)),
            class = "pf_match")
}
# Replace x$result, keeping every attribute the caller put on the new result.
#
# This existed as `utils::modifyList(x, list(result = new))`, which is wrong
# here and silently so. modifyList recurses whenever both the old and new values
# are lists -- and a data.frame IS a list -- so instead of replacing the result
# it merged the new one COLUMN BY COLUMN into the old object. The columns came
# through, which is why nothing looked broken, but the returned frame was the
# old one wearing new columns, and every attribute set on the new frame was
# discarded. pf_dyad_collapse() attaches the reduced pair set as an attribute,
# so the collapse's whole output was being thrown away while its tier counts --
# computed before the assignment -- still looked correct.
.pf_setresult <- function(x, new) { x$result <- new; x }

# preserve np_tiered class and the pairs attribute across the rewrite
.pf_reclass <- function(new, old) {
  for (a in setdiff(names(attributes(old)), c("names", "row.names", "class")))
    attr(new, a) <- attr(old, a)
  class(new) <- class(old)
  new
}
