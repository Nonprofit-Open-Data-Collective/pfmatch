#' Downgrade a YES that landed on a sibling entity
#'
#' The cluster review in `dev/MISSED-GRANTS-NOTE.md` (section 2) found one
#' error shape again and again: the winning BMF name is the grantee's name
#' **plus** words that mark a different, affiliated entity. ADL went to the ADL
#' Professional Staff Association (2,493 rows), the Philadelphia Museum of Art
#' to its Women's Committee, Columbia Business School to an alumni club,
#' McLean Hospital to its employee medical trust. The token passes find these
#' because the sibling's name contains every query token, and the exact passes
#' because name plus ZIP does not separate entities that share both.
#'
#' This turns such a `YES` into `MAYBE`: the winning name contains every token
#' of the query name, and the tokens it adds include a sibling marker from
#' [pf_sibling_words()]. It reads only the status frame, so it cannot check
#' whether a candidate named exactly like the query was also found; it
#' downgrades either way, and review decides.
#'
#' @param status An identity- or grant-level status frame ([pf_status()],
#'   [pf_run_batches()]), with `recip_name`, `bmf_name` and `status`.
#' @param words A regular expression of sibling markers.
#' @return `status` with the downgrades applied, `sibling_guard` (`TRUE` where
#'   a `YES` was downgraded) and, where it was, `status_before_sibling`.
#' @examples
#' st <- data.frame(recip_name = c("ADL", "ADL"), status = "YES",
#'                  bmf_name = c("ADL PROFESSIONAL STAFF ASSOCIATION",
#'                               "ANTI-DEFAMATION LEAGUE"))
#' pf_sibling_guard(st)$status
#' @export
pf_sibling_guard <- function(status, words = pf_sibling_words()) {
  q <- .pf_sib_tokens(status$recip_name)
  b <- .pf_sib_tokens(status$bmf_name)
  yes <- as.character(status$status) %in% "YES" & !is.na(status$bmf_name)
  hit <- logical(nrow(status))
  for (i in which(yes)) {
    qi <- q[[i]]; bi <- b[[i]]
    if (!length(qi) || !all(qi %in% bi)) next
    extra <- bi[!bi %in% qi]
    if (length(extra) && grepl(words, paste(extra, collapse = " "), perl = TRUE))
      hit[i] <- TRUE
  }
  status$sibling_guard <- hit
  if (any(hit)) {
    if (is.null(status$status_before_sibling))
      status$status_before_sibling <- NA_character_
    status$status_before_sibling[hit] <- as.character(status$status[hit])
    status$status[hit] <- "MAYBE"
  }
  status
}

#' Words that mark an affiliated entity rather than the grantee
#'
#' Used by [pf_sibling_guard()]. Taken from the cluster-precision review in
#' `dev/MISSED-GRANTS-NOTE.md`: staff associations, alumni clubs, women's
#' committees, auxiliaries, guilds, advocacy arms, employee trusts,
#' fraternities, and the booster / parent groups that pair with schools.
#' `FOUNDATION` is deliberately absent: a university and its foundation are
#' both plausible payees, and [pf_dedup()] already keeps them apart.
#'
#' @return One regular expression, matched against the tokens the winning BMF
#'   name adds to the query.
#' @export
pf_sibling_words <- function() {
  paste0("(^| )(",
    paste(c("STAFF ASSOCIATION", "STAFF ASSN", "PROFESSIONAL STAFF",
            "ALUMNI", "ALUMNAE", "WOMENS (COMMITTEE|BOARD|AUXILIARY|ASSOCIATION|GUILD|CLUB)",
            "AUXILIARY", "GUILD", "ADVOCATES", "ACTION FUND", "ACTION NETWORK",
            "VOTES", "PAC", "POLITICAL",
            "EMPLOYEES?( (BENEFIT|MEDICAL|HEALTH|WELFARE|RETIREMENT))? (TRUST|PLAN|ASSOCIATION|ASSN|UNION)",
            "RETIREES", "FRATERNITY", "SORORITY", "COLONY", "BOOSTERS?",
            "PARENTS? (ASSOCIATION|ASSN|COUNCIL|CLUB|ORGANIZATION)", "PTA", "PTSA", "PTO",
            "NURSES ALUMNAE", "MOTHERS CLUB", "FATHERS CLUB"), collapse = "|"),
    ")( |$)")
}

# Name tokens for the superset test: case and punctuation folded, apostrophes
# dropped (WOMEN'S -> WOMENS), and the words that never distinguish an entity
# removed.
.pf_sib_tokens <- function(x) {
  x <- toupper(ifelse(is.na(x), "", as.character(x)))
  x <- gsub("'", "", x, fixed = TRUE)
  x <- gsub("&", " AND ", x, fixed = TRUE)
  x <- gsub(" +", " ", trimws(gsub("[^A-Z0-9]+", " ", x)))
  drop <- c("THE", "OF", "AND", "INC", "INCORPORATED", "CORP", "CORPORATION",
            "CO", "LLC", "LTD")
  lapply(strsplit(x, " ", fixed = TRUE), function(t) unique(t[nzchar(t) & !t %in% drop]))
}
