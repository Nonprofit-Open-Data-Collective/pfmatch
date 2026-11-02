# Drawing the labelling round.
#
# dev/ADJUDICATION-PREREQS.md §6b is the design this implements. Two of its
# findings are constraints on the code rather than on the prose:
#
# ONE CASE SET, ALL ARMS. §3's failure mode is two packets producing two
# denominators. pf_grade_layers() refuses such a comparison after the fact;
# this draws one case set so the refusal never has to fire.
#
# STRATIFY ONLY ON CASE FEATURES. `confidence` and `evidence_class` are
# assigned by the reviewer during review, so no draw can control them. Trying
# to is how the NTEE rung ended up at n=1 in one arm of the round on disk. This
# function therefore refuses a `by` column it cannot see at draw time, and the
# design compensates by staging the round instead.

#' Draw a stratified labelling round
#'
#' Builds the case frame for `ADJUDICATION-PREREQS.md` T1 and draws a
#' reproducible stratified sample from it.
#'
#' @section What it refuses, and why each is a stop:
#' * **No `seed`.** A round that cannot be redrawn cannot be audited, and the
#'   labels outlive the session that drew them.
#' * **A `by` column that is not in the frame.** Reading an absent column gives
#'   `NULL`, and a stratified draw over `NULL` is an unstratified draw that
#'   reports strata.
#' * **`n` larger than the population**, or an `oversample` floor larger than
#'   the population it names. Silently returning fewer cases turns a power
#'   calculation into a wish — §6b.2 sizes the round from the cell that has to
#'   separate, so a short cell is the one thing that must not pass unnoticed.
#'
#' @section Why the fingerprint travels with the draw:
#' `grant_id` is positional. The same id denotes a different grant in another
#' grant vintage, and names agree on **0%** of ids joined across the two known
#' vintages ([pf_population_id()]). Labels are expensive and long-lived, so the
#' population is recorded on the draw itself and [pf_grade_verdicts()] enforces
#' it later.
#'
#' @param x A `pf_match`.
#' @param n Target size. §6b.2: 250–300 per arm is what a "high-confidence
#'   precision ≥ 95%, lower bound ≥ 90%" claim costs, so 1,000 over four arms.
#' @param tiers Which tiers to draw from. Default `"MAYBE"`.
#' @param by Case-feature columns to stratify on. Must exist in the frame.
#' @param oversample Named list of `column = floor`: logical columns whose
#'   `TRUE` population is drawn up to at least `floor` cases. For the T8 flags
#'   and T7 shapes, which do not arrive by chance.
#' @param extra Optional frame keyed by `grant_id` with further case features
#'   (the flags, a dollar band) to join before drawing.
#' @param stage Label recorded on every row, for the staged design.
#' @param seed Required. Recorded on the result.
#' @param verbose Print the allocation.
#' @return A data frame of one row per drawn case: `grant_id`, `stratum`,
#'   `stage`, plus the `by` columns and anything from `extra`. Carries
#'   `attr(, "population")`, `attr(, "seed")`, `attr(, "allocation")` and
#'   `attr(, "frame_size")`.
#' @seealso [pf_grade_verdicts()] for scoring the round once it comes back.
#' @examples
#' \dontrun{
#' r <- pf_round_sample(m, n = 400, by = c("tier", "pass"),
#'                      oversample = list(flag_arm_shape = 100),
#'                      extra = flags, stage = "stage1", seed = 20261102)
#' attr(r, "allocation")
#' }
#' @export
pf_round_sample <- function(x, n = 1000L, tiers = "MAYBE",
                            by = c("tier", "pass"), oversample = NULL,
                            extra = NULL, stage = "stage1", seed = NULL,
                            verbose = TRUE) {
  stopifnot(inherits(x, "pf_match"))
  if (is.null(seed))
    stop(paste0(
      "`seed` is required: a round that cannot be redrawn cannot be audited,\n",
      "  and these labels will outlive the session that drew them."),
      call. = FALSE)

  st <- pf_status(x)
  st <- st[as.character(st$status) %in% tiers, , drop = FALSE]
  if (!nrow(st))
    stop(sprintf("no identities in %s, so there is nothing to draw.",
                 paste(tiers, collapse = "/")), call. = FALSE)

  fr <- data.frame(grant_id = as.character(st$grant_id),
                   tier = as.character(st$status), stringsAsFactors = FALSE)

  # The pair-level case features: which pass produced the pick, and how close
  # the runner-up was. Absent for an identity no pass produced a pair for --
  # most of the NO tier -- which is why these are NA rather than dropped.
  res <- as.data.frame(x$result, stringsAsFactors = FALSE)
  if (!is.null(res$.id)) {
    i <- match(fr$grant_id, as.character(res$.id))
    pr <- attr(x$result, "pairs")
    pick_pass <- rep(NA_character_, nrow(fr))
    if (!is.null(pr)) {
      pr <- as.data.frame(pr, stringsAsFactors = FALSE)
      if (!is.null(pr$pass) && !is.null(res$overall_ein)) {
        k <- match(paste(fr$grant_id, res$overall_ein[i]),
                   paste(as.character(pr$.id), as.character(pr$.ein)))
        pick_pass <- as.character(pr$pass)[k]
      }
    }
    fr$pass <- pick_pass
    fr$margin <- suppressWarnings(as.numeric(res$overall_margin[i]))
    fr$n_close <- suppressWarnings(as.integer(res$n_close[i]))
  } else {
    fr$pass <- NA_character_; fr$margin <- NA_real_; fr$n_close <- NA_integer_
  }

  if (!is.null(extra)) {
    ex <- as.data.frame(extra, stringsAsFactors = FALSE)
    if (is.null(ex$grant_id))
      stop("`extra` needs a grant_id column to join on.", call. = FALSE)
    j <- match(fr$grant_id, as.character(ex$grant_id))
    for (nm in setdiff(names(ex), c("grant_id", names(fr)))) fr[[nm]] <- ex[[nm]][j]
  }

  miss <- by[!by %in% names(fr)]
  if (length(miss))
    stop(sprintf(paste0(
      "these stratifying columns are not in the frame: %s\n  present: %s\n",
      "  Reading an absent column gives NULL, and a stratified draw over NULL",
      " is an unstratified draw that reports strata."),
      paste(miss, collapse = ", "), paste(names(fr), collapse = ", ")),
      call. = FALSE)

  if (n > nrow(fr))
    stop(sprintf(paste0(
      "asked for %s cases but the frame holds %s.\n",
      "  Returning fewer would turn section 6b.2's power calculation into a",
      " wish, so this stops instead."),
      format(n, big.mark = ","), format(nrow(fr), big.mark = ",")),
      call. = FALSE)

  fr$stratum <- apply(fr[, by, drop = FALSE], 1L, function(r)
    paste(ifelse(is.na(r), "NA", as.character(r)), collapse = " | "))

  set.seed(seed)
  taken <- character(0)

  # Oversample floors first: these populations are small and would be rounded
  # away by proportional allocation (PREREQS T8's flags are the instance).
  os <- list()
  if (!is.null(oversample)) {
    if (is.null(names(oversample)) || any(!nzchar(names(oversample))))
      stop("`oversample` must be a NAMED list of column = floor.", call. = FALSE)
    for (nm in names(oversample)) {
      if (is.null(fr[[nm]]))
        stop(sprintf("`oversample` names `%s`, which is not in the frame.", nm),
             call. = FALSE)
      pool <- fr$grant_id[fr[[nm]] %in% TRUE]
      floor_n <- as.integer(oversample[[nm]])
      if (length(pool) < floor_n)
        stop(sprintf(paste0(
          "`%s` has %d cases in the frame but a floor of %d was asked for.\n",
          "  At %d the Wilson interval is about %.0f points wide, which is why",
          " the floor exists; a short cell cannot carry the finding."),
          nm, length(pool), floor_n, length(pool),
          100 * diff(pf_wilson(round(0.6 * max(1L, length(pool))),
                               max(1L, length(pool)))[1, ])), call. = FALSE)
      pick <- sample(setdiff(pool, taken), min(floor_n, length(setdiff(pool, taken))))
      taken <- c(taken, pick)
      os[[nm]] <- length(pick)
    }
  }

  # Proportional allocation over the remainder, largest-remainder rounding so
  # the parts sum to n exactly rather than to n plus or minus a few.
  rest <- fr[!fr$grant_id %in% taken, , drop = FALSE]
  want <- n - length(taken)
  if (want > 0) {
    tb <- table(rest$stratum)
    share <- as.numeric(tb) / sum(tb) * want
    alloc <- pmin(as.integer(floor(share)), as.integer(tb))
    left <- want - sum(alloc)
    if (left > 0) {
      ord <- order(share - floor(share), decreasing = TRUE)
      for (ii in ord) {
        if (left == 0) break
        if (alloc[ii] < tb[ii]) { alloc[ii] <- alloc[ii] + 1L; left <- left - 1L }
      }
    }
    names(alloc) <- names(tb)
    for (s in names(alloc)) {
      if (alloc[[s]] == 0L) next
      pool <- rest$grant_id[rest$stratum == s]
      taken <- c(taken, sample(pool, alloc[[s]]))
    }
  }

  out <- fr[match(taken, fr$grant_id), , drop = FALSE]
  out$stage <- stage
  rownames(out) <- NULL
  pop <- tryCatch(pf_population_id(x$grants), error = function(e) NA_character_)
  attr(out, "population") <- pop
  attr(out, "seed")       <- seed
  attr(out, "frame_size") <- nrow(fr)
  attr(out, "allocation") <- table(out$stratum)
  attr(out, "oversample") <- os

  if (verbose) {
    .pf_hr(verbose)
    .pf_say(verbose, "drew %s of %s %s identities into %d strata (seed %s)",
            format(nrow(out), big.mark = ","), format(nrow(fr), big.mark = ","),
            paste(tiers, collapse = "/"), length(attr(out, "allocation")), seed)
    if (length(os))
      .pf_say(verbose, "  oversampled: %s",
              paste(sprintf("%s %d", names(os), unlist(os)), collapse = " | "))
    if (is.na(pop))
      .pf_say(verbose, "  population UNFINGERPRINTED (no OBJECTID): these labels cannot be re-attached")
    else
      .pf_say(verbose, "  population %s -- pf_grade_verdicts() will enforce it", pop)
    .pf_say(verbose, "  confidence and evidence class are NOT stratifiable: the reviewer")
    .pf_say(verbose, "  assigns them, so stage this round (PREREQS 6b.1c)")
  }
  out
}
