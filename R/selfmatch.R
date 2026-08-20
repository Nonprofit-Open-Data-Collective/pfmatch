#' Never match a grant to the foundation that made it
#'
#' A 990-PF grant row is a payment *from* the filing foundation, so the filer's
#' own EIN can never be the recipient. The MAYBE audit caught this happening:
#' `SIGMA GAMMA ASSOCATION` was matched to `SIGMA GAMMA FOUNDATION`, which is the
#' filer — a confident, well-scored, structurally impossible answer. The correct
#' recipient sat at rank 2.
#'
#' This is a hard constraint rather than a scoring adjustment: no amount of name
#' or address agreement makes a self-match valid.
#'
#' @param x A `pf_match` result from [pf_match_grants()].
#' @param verbose Report how many pairs were removed.
#' @return `x` with self-matched pairs dropped and selection/tiering recomputed,
#'   so a query whose winner was its own filer falls back to its next-best
#'   candidate instead of being lost.
pf_drop_self_matches <- function(x, verbose = TRUE) {
  stopifnot(inherits(x, "pf_match"))
  pairs <- attr(x$result, "pairs")
  g <- x$grants
  if (is.null(g$FILEREIN)) {
    if (verbose) message("no FILEREIN column; nothing to guard against")
    return(x)
  }
  digits <- function(v) {
    v <- gsub("[^0-9]", "", as.character(v))
    v[!nzchar(v)] <- NA_character_
    ok <- !is.na(v) & nchar(v) <= 9L
    v[ok] <- formatC(v[ok], width = 9, flag = "0")
    v
  }
  filer <- stats::setNames(digits(g$FILEREIN), g$grant_id)
  df <- as.data.frame(pairs)
  self <- !is.na(filer[df$.id]) & digits(df$.ein) == unname(filer[df$.id])
  self[is.na(self)] <- FALSE
  if (verbose)
    cat(sprintf("self-match guard: dropped %d of %s candidate pairs (%d queries affected)\n",
                sum(self), format(nrow(df), big.mark = ","),
                length(unique(df$.id[self]))))
  if (!any(self)) return(x)
  keep <- df[!self, , drop = FALSE]
  for (a in c("cmp_cols", "profile")) attr(keep, a) <- attr(pairs, a)
  class(keep) <- class(pairs)
  cfg <- x$config
  res <- npmatch::np_tier(npmatch::np_select(keep, cfg), cfg)
  ord <- match(paste(res$.id, res$overall_ein), paste(keep$.id, keep$.ein))
  if (!is.null(keep$pass)) res$pass <- keep$pass[ord]
  attr(res, "stages") <- attr(x$result, "stages")
  attr(res, "pairs")  <- keep
  attr(res, "config") <- cfg
  x$result <- res
  x
}
