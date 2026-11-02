# The dollar-sorted review queue.
#
# Grant dollars are heavily skewed, so reviewing large-to-small buys most of the
# recoverable dollars for a small fraction of the effort
# (dev/ADJUDICATION-PLAN.md section 4). This builds that ordering and the
# coverage curve over it.
#
# THE UNIT TRAP THIS FUNCTION EXISTS TO AVOID. pf_recipients() collapses grants
# to identities and keeps ONE representative row per identity -- the most
# complete one -- carrying no grant count and no dollar total. So the amount on
# a matched identity is that one grant's amount, not the identity's. At the 3.72x
# collapse measured in dev/FULL-01-PREPARE.log, a queue summed from a pf_match
# alone would be sorted by an arbitrary member of each cluster: sorted, plausible
# and by the wrong quantity. That is why `grants` is required whenever the match
# was built from deduped identities, and why supplying it is checked rather than
# assumed.

#' The dollar-sorted review queue
#'
#' One row per identity to review, ordered by the grant dollars behind it, with
#' the cumulative share of reviewable dollars at each depth. Cut it wherever the
#' budget falls: the curve is the point, not any single row count.
#'
#' @section What counts as reviewable, and what is excluded:
#' Two populations are removed before the queue is built, following
#' `dev/ADJUDICATION-PLAN.md` section 4, and both are **reported rather than
#' dropped** — their dollars are in the returned counts, because a queue that
#' silently excludes a population looks identical to one with nothing to exclude:
#' * **non-itemizing returns** — a recipient name that is a pointer
#'   (`SEE ATTACHED` and its variants, [pf_placeholder_pattern()]). No review can
#'   resolve a pointer; these need the attachment, see [pf_attached_report()].
#' * **foreign recipients** — no BMF row exists to find, so review cannot
#'   succeed. Detected from `oos_reason`.
#'
#' @section Why `grants` is usually required:
#' [pf_recipients()] keeps one representative row per identity and carries no
#' dollar total, so the amount on a matched identity is one member's amount
#' rather than the cluster's. Pass the every-row frame from [pf_prepare()]
#' (`p$grants`, which carries `recipient_uid`) and the dollars are summed per
#' identity. Where the match was *not* built from deduped identities, each row is
#' its own identity and the match alone is sufficient — that case is detected,
#' not guessed.
#'
#' @param x A `pf_match` from [pf_match_grants()].
#' @param grants The every-row grants frame from [pf_prepare()]. Required when
#'   `x` was built from deduped identities.
#' @param tiers Which outcomes to queue. Default `"MAYBE"`; `c("MAYBE", "NO")`
#'   queues the unresolved tier as well.
#' @param amount_col The grant amount column.
#' @param verbose Print the coverage curve.
#' @return A data frame ordered by `dollars` descending: `grant_id`, `tier`,
#'   `n_grants`, `dollars`, `share`, `cum_share`, `rank`. `attr(, "counts")`
#'   carries the reviewable total, the two exclusions with their dollars, and the
#'   identities with no usable amount. `attr(, "coverage")` gives the review
#'   effort needed for 50/70/80/90% of reviewable dollars.
#' @seealso [pf_adjudicate()] for the sheet, [pf_apply_verdicts()] for the
#'   answers coming back.
#' @examples
#' \dontrun{
#' p <- pf_prepare("inputs")
#' m <- pf_match_grants(p$recipients, ref)
#' q <- pf_review_queue(m, grants = p$grants)
#' attr(q, "coverage")
#' head(q[q$cum_share <= 0.70, ])
#' }
#' @export
pf_review_queue <- function(x, grants = NULL, tiers = "MAYBE",
                            amount_col = "PF_15_G_PAID_AMT", verbose = TRUE) {
  stopifnot(inherits(x, "pf_match"))
  bad <- setdiff(tiers, pf_status_levels())
  if (length(bad))
    stop(sprintf("`tiers` must be among %s; got %s",
                 paste(pf_status_levels(), collapse = ", "),
                 paste(bad, collapse = ", ")), call. = FALSE)

  st <- pf_status(x)
  st <- st[as.character(st$status) %in% tiers, , drop = FALSE]
  if (!nrow(st))
    stop(sprintf("no identities in %s, so there is nothing to queue.",
                 paste(tiers, collapse = "/")), call. = FALSE)

  # Was this match built from deduped identities? pf_recipients() keys the
  # cascade on "R<recipient_uid>" and keeps one row per identity, so a match
  # whose own grants frame carries recipient_uid cannot price an identity from
  # its own rows. Detected, so the caller is told rather than quietly misled.
  deduped <- !is.null(x$grants$recipient_uid)
  if (deduped && is.null(grants))
    stop(paste0(
      "this match was built from deduped identities, so the amount on each row ",
      "is one member grant's and not the identity's.\n",
      "  Pass `grants =` the every-row frame from pf_prepare() ($grants) and the ",
      "dollars are summed per identity.\n",
      "  Queueing on the representative row would be sorted by an arbitrary ",
      "member of each cluster -- at the measured 3.72x collapse that is the wrong ",
      "quantity, ordered convincingly."), call. = FALSE)

  if (is.null(grants)) {
    g <- x$grants
    key <- as.character(g$grant_id)
  } else {
    g <- as.data.frame(grants, stringsAsFactors = FALSE)
    if (is.null(g$recipient_uid) && is.null(g$grant_id))
      stop("`grants` needs recipient_uid (from pf_prepare()) or grant_id.",
           call. = FALSE)
    key <- if (!is.null(g$recipient_uid)) paste0("R", g$recipient_uid)
           else as.character(g$grant_id)
  }
  if (is.null(g[[amount_col]]))
    stop(sprintf(paste0(
      "`%s` is not a column of the grants frame, so no amount can be read.\n",
      "  Reading an absent column returns NULL and every dollar figure below ",
      "would be empty rather than wrong-looking."), amount_col), call. = FALSE)

  amt <- suppressWarnings(as.numeric(gsub("[^0-9.-]", "", as.character(g[[amount_col]]))))
  keep <- key %in% as.character(st$grant_id)
  g <- g[keep, , drop = FALSE]; key <- key[keep]; amt <- amt[keep]

  # the two exclusions, measured before they are applied
  ph <- pf_is_placeholder(g)
  if (is.null(ph) || !length(ph)) ph <- rep(FALSE, nrow(g))
  ph[is.na(ph)] <- FALSE
  oos <- st$oos_reason[match(key, as.character(st$grant_id))]
  fgn <- !is.na(oos) & grepl("foreign", oos, ignore.case = TRUE)
  excl <- ph | fgn

  cnt <- list(
    identities_in_tier = length(unique(key)),
    placeholder_rows   = sum(ph),
    placeholder_dollars = sum(amt[ph], na.rm = TRUE),
    foreign_rows       = sum(fgn),
    foreign_dollars    = sum(amt[fgn], na.rm = TRUE),
    rows_without_amount = sum(is.na(amt[!excl])))

  key <- key[!excl]; amt <- amt[!excl]
  if (!length(key))
    stop("every identity in the requested tiers was excluded as a placeholder or foreign.",
         call. = FALSE)

  # NA amounts contribute nothing to the sum but the identity is kept and its
  # missing rows are counted: dropping it would quietly shrink the denominator,
  # and treating NA as 0 would claim a figure the file does not carry.
  d <- data.frame(grant_id = key, amount = amt, stringsAsFactors = FALSE)
  agg <- stats::aggregate(amount ~ grant_id, data = d, FUN = sum,
                          na.rm = TRUE, na.action = stats::na.pass)
  n_g <- stats::aggregate(amount ~ grant_id, data = d,
                          FUN = function(z) length(z), na.action = stats::na.pass)
  out <- data.frame(
    grant_id = agg$grant_id,
    tier     = as.character(st$status[match(agg$grant_id, as.character(st$grant_id))]),
    n_grants = n_g$amount[match(agg$grant_id, n_g$grant_id)],
    dollars  = agg$amount,
    stringsAsFactors = FALSE)
  out <- out[order(-out$dollars, out$grant_id), , drop = FALSE]
  total <- sum(out$dollars, na.rm = TRUE)
  out$share     <- if (total > 0) out$dollars / total else NA_real_
  out$cum_share <- cumsum(ifelse(is.na(out$share), 0, out$share))
  out$rank      <- seq_len(nrow(out))
  rownames(out) <- NULL

  cnt$reviewable_identities <- nrow(out)
  cnt$reviewable_dollars    <- total
  cov <- vapply(c(0.50, 0.70, 0.80, 0.90),
                function(p) if (total > 0) sum(out$cum_share < p) + 1L else NA_integer_,
                numeric(1))
  names(cov) <- c("50%", "70%", "80%", "90%")
  attr(out, "counts") <- cnt
  attr(out, "coverage") <- cov

  if (verbose) {
    .pf_hr(verbose)
    .pf_say(verbose, "review queue over %s: %s identities, %s reviewable dollars",
            paste(tiers, collapse = "/"),
            format(nrow(out), big.mark = ","),
            paste0("$", format(round(total), big.mark = ",")))
    .pf_say(verbose, "  excluded: %s placeholder rows ($%s), %s foreign ($%s)",
            format(cnt$placeholder_rows, big.mark = ","),
            format(round(cnt$placeholder_dollars), big.mark = ","),
            format(cnt$foreign_rows, big.mark = ","),
            format(round(cnt$foreign_dollars), big.mark = ","))
    if (cnt$rows_without_amount)
      .pf_say(verbose, "  %s reviewable rows carry no readable amount and add nothing to the sum",
              format(cnt$rows_without_amount, big.mark = ","))
    .pf_say(verbose, "  reviews for 50/70/80/90%% of those dollars: %s",
            paste(cov, collapse = " / "))
    .pf_say(verbose, "  the curve is the result; any single row count is a budget, not a finding")
  }
  out
}
