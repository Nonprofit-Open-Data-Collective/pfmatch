#' Stage 5 — semantic re-ranking of tied candidates
#'
#' When several candidates score within a hair of each other, name and geography
#' have already said everything they can. What separates them is *what the
#' organization does* versus *what the grant was for*. Adjudicating 100 MAYBE
#' cases by hand found NTEE / activity text decisive in **9 of the 10 cases where
#' the algorithm ranked the correct EIN below first place**.
#'
#' @section This re-ranks; it never generates candidates:
#' Grant purpose is roughly a third contentless (`GENERAL`, `GOS`,
#' `UNRESTRICTED`, and in one case a check stub), so blocking on it would explode
#' the pair count for very little. It is applied only **inside the tie band**,
#' where the combined score has already failed to separate candidates, and only
#' to re-order them — never to admit a candidate the cascade did not surface, and
#' never to promote a case the cascade rejected outright.
#'
#' @section What counts as "mission":
#' The BMF carries no mission statement. The proxies, in the order this module
#' trusts them:
#' \enumerate{
#'   \item `ntee_code_definition` — the NTEE classification in words. Always
#'     present, though ~1 in 4 reads `UNDEFINED`.
#'   \item `activity_code_definitions` — legacy IRS activity codes as text
#'     ("Hospital", "Church, synagogue, etc."). Only ~44% populated but the most
#'     mission-like field available, and it carried several of the decisive
#'     audit cases.
#'   \item `nteev2_subsector` — coarse sector, useful when the detailed code is
#'     undefined.
#' }
#' Real mission text from a 990 e-file extract can be joined in via
#' [pf_attach_missions()] and passed as `extra_text`.
#'
#' @name pf_semantic
NULL

# Words that carry no discriminating signal in either a grant purpose or an NTEE
# definition. Deliberately includes the grant-specific filler ("general
# support", "unrestricted") that would otherwise match everything.
.pf_purpose_stopwords <- function() c(
  "THE", "AND", "FOR", "OF", "TO", "A", "AN", "IN", "ON", "AT", "BY", "WITH",
  "OR", "AS", "IS", "ARE", "BE", "THIS", "THAT", "ITS", "IT", "FROM",
  "GENERAL", "SUPPORT", "OPERATING", "OPERATIONS", "UNRESTRICTED", "RESTRICTED",
  "GRANT", "GRANTS", "GIFT", "CONTRIBUTION", "CONTRIBUTIONS", "DONATION",
  "CHARITABLE", "CHARITY", "PURPOSE", "PURPOSES", "EXEMPT", "PROGRAM",
  "PROGRAMS", "PROJECT", "FUND", "FUNDING", "ANNUAL", "CAMPAIGN", "NEEDED",
  "VARIOUS", "OTHER", "NEC", "UNDEFINED", "INVALID", "NA", "SEE", "ATTACHED",
  "ORGANIZATION", "ORGANIZATIONS", "ORG", "INC", "USE", "USED", "PROVIDE",
  "PROVIDING", "SERVICES", "SERVICE", "ACTIVITIES", "ACTIVITY", "DESCRIBED",
  "SECTION", "CODE", "GOS")

.pf_words <- function(x) {
  v <- toupper(ifelse(is.na(x), "", as.character(x)))
  v <- gsub("[^A-Z0-9 ]", " ", v)
  toks <- strsplit(trimws(gsub("\\s+", " ", v)), " ", fixed = TRUE)
  sw <- .pf_purpose_stopwords()
  lapply(toks, function(t) unique(t[nchar(t) >= 4L & !(t %in% sw)]))
}

#' Semantic agreement between a grant's own text and a candidate's mission proxies
#'
#' @section The query side is the NAME plus the purpose, not the purpose alone:
#' An earlier version compared only the grant purpose against the candidate's
#' mission text and scored ~0 for 55% of rows, because purpose text is dominated
#' by filler. Inspecting the cases where a human reviewer used NTEE to decide
#' showed the signal actually lives in the **recipient name**:
#' `BOCA RATON COMM HOSP` against a candidate whose activity text reads
#' `Hospital`; `SUMMIT COUNTY HISTORICAL SOCIETY` against `Historical Societies`.
#' The purpose contributed nothing in both (`CHARITABLE ACTIVITIES`, `GENERAL
#' OPERATING`).
#'
#' This is not double-counting the name score. That measures string similarity
#' between two names; this measures whether the *kind of organization* the name
#' describes matches the *kind* the BMF classified — independent evidence that is
#' exactly what separates five same-ZIP candidates from one another.
#'
#' @section Prefix matching:
#' Tokens match on a shared five-character prefix, or when one is a prefix of the
#' other. Without it `HOSP` misses `HOSPITAL`, `HISTORICAL` misses `HISTORY`, and
#' `EDUCATION` misses `EDUCATIONAL` — which is most of the signal.
#'
#' @param query_text Character vector of grant-side text (recipient name, ideally
#'   pasted with the grant purpose), one per candidate row.
#' @param ... One or more character vectors of candidate mission text (NTEE
#'   definition, activity text, subsector, optionally a real mission statement).
#' @return Numeric vector in `[0, 1]`: the IDF-weighted share of the query's
#'   content words accounted for by the candidate's mission text. `NA` where
#'   either side has no content words, so callers can tell "no agreement" from
#'   "nothing to compare".
#' @export
pf_semantic_score <- function(query_text, ...) {
  cand_text <- do.call(paste, c(list(...), sep = " "))
  pw <- .pf_words(query_text)
  cw <- .pf_words(cand_text)

  # IDF over the candidate corpus, keyed on the 5-char stem so that inflections
  # share a weight
  # 4 characters, not 5: HOSP must match HOSPITAL, and a 5-char stem gives
  # "HOSP" vs "HOSPI". Also catches HISTORICAL~HISTORY, EDUCATION~EDUCATIONAL.
  stem <- function(x) substr(x, 1, 4)
  all_c <- stem(unlist(cw, use.names = FALSE))
  n_doc <- max(1L, length(cw))
  df <- table(all_c)
  idf <- log(n_doc / pmax(1, as.numeric(df)))
  names(idf) <- names(df)

  vapply(seq_along(pw), function(i) {
    p <- pw[[i]]; cand <- cw[[i]]
    if (!length(p) || !length(cand)) return(NA_real_)
    ps <- stem(p); cs <- stem(cand)
    w <- idf[ps]; w[is.na(w)] <- log(n_doc)     # unseen stem = maximally rare
    hit <- ps %in% cs
    if (sum(w) <= 0) return(NA_real_)
    as.numeric(sum(w[hit]) / sum(w))
  }, numeric(1))
}

#' Re-rank tied candidates by purpose-to-mission agreement
#'
#' @param cand A candidate frame from [pf_candidate_frame()], one row per
#'   (grant, candidate), carrying `score`, `grant_purpose`, and the `CAND_*`
#'   context columns.
#' @param tie_band Candidates within this much of the grant's top score are
#'   considered tied and eligible for re-ranking. Outside the band nothing moves.
#' @param weight How much the semantic score may shift a candidate. Kept small
#'   deliberately: this is a tiebreak, not a scoring term, and it must not be
#'   able to overturn a clear name/geography win.
#' @param extra_text Optional additional mission text column name (e.g. a real
#'   990 mission statement joined by [pf_attach_missions()]).
#' @return `cand` with `semantic`, `score_reranked`, `rank_reranked`, and
#'   `reranked` (TRUE where the top pick changed) added.
#' @export
pf_semantic_rerank <- function(cand, tie_band = 0.05, weight = 0.06,
                               extra_text = NULL) {
  stopifnot(!is.null(cand$score), !is.null(cand$grant_id))
  gv <- function(nm) if (!is.null(cand[[nm]])) cand[[nm]] else rep("", nrow(cand))
  txt <- list(gv("CAND_ntee_code_definition"),
              gv("CAND_activity_code_definitions"),
              gv("CAND_nteev2_subsector"),
              gv("CAND_ntee_common_code_definition"))
  if (!is.null(extra_text)) txt <- c(txt, list(gv(extra_text)))

  # query side: the recipient name carries most of the signal, the purpose adds
  # to it when it has any content
  qtext <- trimws(paste(gv("recip_name"), gv("grant_purpose")))
  cand$semantic <- do.call(pf_semantic_score, c(list(qtext), txt))

  sc  <- as.numeric(cand$score)
  top <- stats::ave(sc, cand$grant_id, FUN = function(v) max(v, na.rm = TRUE))
  in_band <- !is.na(sc) & (top - sc) <= tie_band

  sem <- cand$semantic; sem[is.na(sem)] <- 0
  cand$score_reranked <- sc + ifelse(in_band, weight * sem, 0)

  # Preserve npmatch's OWN choice as the tiebreak, so that when the semantic term
  # contributes nothing the winner is unchanged. This must key on `is_top_pick`,
  # not on score rank: np_select() applies its own high-tie rule (`tiebreak =
  # "name"`), so its pick is frequently not the highest-scoring row. An earlier
  # version tiebroke on score rank alone and silently overrode that rule, which
  # showed up as five "broken" cases having nothing to do with semantics — e.g.
  # demoting SIERRA CLUB FOUNDATION back to SIERRA CLUB.
  chosen <- if (!is.null(cand$is_top_pick)) as.integer(cand$is_top_pick) else 0L
  chosen[is.na(chosen)] <- 0L
  incoming <- if (!is.null(cand$rank)) as.numeric(cand$rank) else seq_len(nrow(cand))
  ord <- order(cand$grant_id, -cand$score_reranked, -chosen, incoming)
  cand <- cand[ord, , drop = FALSE]
  cand$rank_reranked <- stats::ave(seq_len(nrow(cand)), cand$grant_id, FUN = seq_along)
  ch2 <- if (!is.null(cand$is_top_pick)) as.integer(cand$is_top_pick) else NA_integer_
  cand$reranked <- cand$rank_reranked == 1L & !is.na(ch2) & ch2 != 1L
  rownames(cand) <- NULL
  cand
}
