# Drawing the labelling round.
#
# dev/ADJUDICATION-PREREQS.md §6b is the design this implements. Three of its
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
#
# A POPULATION IS NOT A PROVENANCE. The fingerprint says which grant file the
# ids mean something in. It says nothing about which normalizer produced the
# tiers and passes the draw stratifies on, and those move: rematching the same
# population under npnormalize 0.1.9 gave 23,340 MAYBE identities where 0.1.6
# gave 24,107 (dev/ADJ-ROUND-STAGE1-20261103.log). A draw recording only the
# population would therefore claim a reproducibility it does not have, so the
# signature the frame was matched under is recorded beside it.

# THE FRAME IS NOT ALWAYS A pf_match. Drawing §6b.3's frame against the runs on
# disk (dev/ADJ-ROUND-STAGE1-20261102.log) found that the current production run
# is serialized as `list(status, grants)` -- the identity-grain status frame and
# the grant-grain source, with no `$result` and no `pairs` attribute. It holds
# every case feature the design stratifies on, and it is the only run on disk
# that can be fingerprinted. Requiring a `pf_match` here would have sent the
# round to a frame whose labels cannot be re-attached, so a status frame is a
# first-class input.

# Where a frame says what matched it. pf_run_batches() stamps the status frame
# it returns, so a production run carries the signature inside the artifact.
# A frame written before that stamp existed says nothing, and NA is then the
# honest answer: reading the installed signature instead would assert that this
# draw's tiers came from it, which is precisely the claim nobody could check.
.pf_frame_normalizer <- function(x) {
  ok <- function(v) {
    v <- tryCatch(as.character(v), error = function(e) NULL)
    if (length(v) != 1L || is.na(v) || !nzchar(v)) NULL else v
  }
  hit <- ok(attr(x, "pf_stamp")$normalizer)
  if (is.null(hit) && is.list(x) && !is.data.frame(x)) {
    hit <- ok(attr(x$status, "pf_stamp")$normalizer)
    if (is.null(hit)) hit <- ok(attr(x$result, "pf_stamp")$normalizer)
    if (is.null(hit)) hit <- ok(x$normalizer)
  }
  if (is.null(hit)) NA_character_ else hit
}

#' Draw a stratified labelling round
#'
#' Builds the case frame for `ADJUDICATION-PREREQS.md` T1 and draws a
#' reproducible stratified sample from it.
#'
#' @section What it refuses, and why each is a stop:
#' * **No `seed`.** A round that cannot be redrawn cannot be audited, and the
#'   labels outlive the session that drew them.
#' * **A frame that cannot be fingerprinted**, unless `require_population =
#'   FALSE`. See below.
#' * **A `by` column that is not in the frame**, or that is present but
#'   entirely `NA`. Reading an absent column gives `NULL`, and either way every
#'   case lands in one cell: an unstratified draw that reports strata.
#' * **`n` larger than the population**, or an `oversample` floor larger than
#'   the population it names. Silently returning fewer cases turns a power
#'   calculation into a wish — §6b.2 sizes the round from the cell that has to
#'   separate, so a short cell is the one thing that must not pass unnoticed.
#'
#' @section Why the fingerprint is required rather than recorded:
#' `grant_id` is positional. The same id denotes a different grant in another
#' grant vintage, and names agree on **0%** of ids joined across the two known
#' vintages ([pf_population_id()]). Labels are the expensive part and they
#' outlive the frame, so an unfingerprintable frame is a stop: its labels could
#' never be re-attached to a grant. `require_population = FALSE` is for a dry
#' run whose labels will be thrown away — the archived GT extracts have no
#' `OBJECTID` and are the case it exists for.
#'
#' @section Why a population is not enough on its own:
#' The population fingerprints the grant *file*, and a label also has to name
#' an organisation within it. Identity ids used to be `R<k>` — positions among
#' the deduplicated recipients — so they were local to the run: rebuilding one
#' population after a normalizer change merged 682 duplicates and renumbered
#' everything downstream, leaving the population identical
#' (`cb3c78ff0f1a9546` both times) while `R10000` moved from `Childrens
#' Guardian` to `CONGREGATION ATERES YESHAYA`. A label from the first run
#' passed the population check against the second and attached to the wrong
#' organisation.
#'
#' [pf_identity_id()] replaced that: an id is now a hash of the identity's own
#' dedup key, so an id that matches names the same organisation by construction
#' and one whose identity changed is **absent** rather than wrong. A frame still
#' carries [pf_frame_id()] as `attr(, "frame_id")`, which fingerprints the whole
#' id-to-name pairing — a cheap check that two artifacts are the same run, and
#' the thing that catches a frame built before the ids were content-derived.
#'
#' @section Why the normalizer is recorded but not required:
#' The population says which grant file these ids mean something in. It does
#' not say which normalizer produced the `tier` and `pass` the draw stratifies
#' on, and those move with it: rematching one population under npnormalize
#' 0.1.9 gave 23,340 `MAYBE` identities where 0.1.6 gave 24,107, which is a
#' different frame and so a different draw. The signature is therefore recorded
#' as `attr(, "normalizer")`, taken from the run stamp [pf_run_batches()]
#' leaves on the status frame.
#'
#' It is recorded rather than required because the two failures are not the
#' same size. An unfingerprinted population makes the labels unattachable to
#' any grant, so they are worthless -- hence a stop. An unstamped normalizer
#' leaves the labels perfectly attachable; what it costs is the ability to show
#' that this draw's strata could be redrawn, which is a weaker claim and a
#' recoverable one. `NA` is reported where the frame predates stamping, and is
#' never filled in from the installed signature: that would assert the frame
#' was matched under whatever happens to be installed at draw time, which is
#' the one thing it cannot be known to have been.
#'
#' @param x A `pf_match`, or a [pf_status()]-shaped data frame, or a list with
#'   a `status` component holding one (how the production runs on disk are
#'   serialized). From a status frame the case features are read off its own
#'   `match_pass`, `margin` and `n_close` columns; note that [pf_status()]
#'   rounds `margin` to three decimals, so a `pf_match` gives the unrounded
#'   value and a status frame the rounded one.
#' @param n Target size. §6b.2: 250–300 per arm is what a "high-confidence
#'   precision ≥ 95%, lower bound ≥ 90%" claim costs, so 1,000 over four arms.
#' @param tiers Which tiers to draw from. Default `"MAYBE"`.
#' @param by Case-feature columns to stratify on. Must exist in the frame.
#'   Measured on the real frame (§6b.5), `tier · pass · purpose` is as fine as
#'   a 400-case stage 1 can carry; §6b.3's full five-way cross leaves 54 of 141
#'   cells with less than one case.
#' @param oversample Named list of `column = floor`: logical columns whose
#'   `TRUE` population is drawn up to at least `floor` cases. For the T8 flags
#'   and T7 shapes, which do not arrive by chance. Both flags compare the pick
#'   to the runner-up, so they can only be supplied from a pair-complete run.
#' @param extra Optional frame keyed by `grant_id` with further case features
#'   (the flags, a purpose band, a dollar band) to join before drawing.
#' @param stage Label recorded on every row, for the staged design.
#' @param seed Required. Recorded on the result.
#' @param grants Grant frame to fingerprint, when `x` does not carry one.
#' @param require_population Stop when the frame cannot be fingerprinted.
#' @param verbose Print the allocation.
#' @return A data frame of one row per drawn case: `grant_id`, `stratum`,
#'   `stage`, plus the `by` columns and anything from `extra`. Carries
#'   `attr(, "population")`, `attr(, "frame_id")`, `attr(, "normalizer")`,
#'   `attr(, "seed")`, `attr(, "allocation")`, `attr(, "frame_size")` and
#'   `attr(, "oversample")` — the last a frame of `column`, `floor` and
#'   `realized`, which differ whenever one floor's draw already satisfied
#'   another's.
#' @seealso [pf_grade_verdicts()] for scoring the round once it comes back.
#' @examples
#' \dontrun{
#' r <- pf_round_sample(m, n = 400, by = c("tier", "pass", "purpose_band"),
#'                      extra = features, stage = "stage1", seed = 20261102)
#' attr(r, "allocation")
#' }
#' @export
pf_round_sample <- function(x, n = 1000L, tiers = "MAYBE",
                            by = c("tier", "pass"), oversample = NULL,
                            extra = NULL, stage = "stage1", seed = NULL,
                            grants = NULL, require_population = TRUE,
                            verbose = TRUE) {
  if (is.null(seed))
    stop(paste0(
      "`seed` is required: a round that cannot be redrawn cannot be audited,\n",
      "  and these labels will outlive the session that drew them."),
      call. = FALSE)

  # --- where the frame comes from --------------------------------------------
  res <- NULL
  if (inherits(x, "pf_match")) {
    st  <- pf_status(x)
    gr  <- if (!is.null(grants)) grants else x$grants
    res <- as.data.frame(x$result, stringsAsFactors = FALSE)
  } else if (is.data.frame(x)) {
    st <- as.data.frame(x, stringsAsFactors = FALSE)
    gr <- grants
  } else if (is.list(x) && !is.null(x$status) && is.data.frame(x$status)) {
    st <- as.data.frame(x$status, stringsAsFactors = FALSE)
    gr <- if (!is.null(grants)) grants else x$grants
  } else {
    stop(paste0(
      "`x` must be a pf_match, a pf_status() frame, or a list with a `status`\n",
      "  component holding one. Got: ", paste(class(x), collapse = "/")),
      call. = FALSE)
  }
  if (is.null(st$grant_id) || is.null(st$status))
    stop("the status frame needs `grant_id` and `status` columns.", call. = FALSE)

  # Read off `x` before any subsetting: `[`, `as.data.frame()` and the tier
  # filter below all drop attributes they do not know about, so the stamp has
  # to be taken from the object as it arrived.
  nrm <- .pf_frame_normalizer(x)

  # The identity numbering, which the population fingerprint does not cover:
  # `R<k>` is positional among the deduplicated recipients, so a rebuild that
  # merges duplicates renumbers everything after the first merge while the
  # population stays identical. See pf_frame_id() for the measurement.
  frm <- tryCatch(pf_frame_id(st), error = function(e) NA_character_)

  # --- the fingerprint, before anything is drawn -----------------------------
  pop <- if (is.null(gr)) NA_character_
         else tryCatch(pf_population_id(gr), error = function(e) NA_character_)
  if (is.na(pop) && require_population)
    stop(paste0(
      "this frame cannot be fingerprinted, so its labels could never be\n",
      "  re-attached to a grant: `grant_id` is positional and names agree on 0%\n",
      "  of ids joined across the two known grant vintages. Pass `grants =` a\n",
      "  frame carrying OBJECTID, or `require_population = FALSE` for a dry run\n",
      "  whose labels will be thrown away."), call. = FALSE)

  st <- st[as.character(st$status) %in% tiers, , drop = FALSE]
  if (!nrow(st))
    stop(sprintf("no identities in %s, so there is nothing to draw.",
                 paste(tiers, collapse = "/")), call. = FALSE)

  # The case features. pf_status() already carries all three -- which pass
  # produced the pick, how close the runner-up was, how many were close -- and
  # they agree with the pair-level values on all 5,000 rows of the 1k run,
  # every tier (dev/ADJ-ROUND-STAGE1-20261102.log §2). Absent for an identity
  # no pass produced a pair for, which is why these are NA rather than dropped.
  col <- function(nm, cast)
    if (is.null(st[[nm]])) cast(rep(NA, nrow(st)))
    else suppressWarnings(cast(st[[nm]]))
  fr <- data.frame(
    grant_id = as.character(st$grant_id),
    tier     = as.character(st$status),
    pass     = col("match_pass", as.character),
    margin   = col("margin", as.numeric),
    n_close  = col("n_close", as.integer),
    stringsAsFactors = FALSE)
  if (!is.null(res) && !is.null(res$overall_margin) && !is.null(res$.id)) {
    i <- match(fr$grant_id, as.character(res$.id))
    fr$margin <- suppressWarnings(as.numeric(res$overall_margin[i]))
  }
  # pf_status() reads the pass off the result frame, which is where a run that
  # has one keeps it. Where it does not, the pairs still do, and taking NA
  # instead would collapse every pass stratum into one -- a silent
  # de-stratification, which is the failure this function exists to refuse.
  if (!is.null(res) && all(is.na(fr$pass)) && !is.null(res$.id) &&
      !is.null(res$overall_ein)) {
    pr <- attr(x$result, "pairs")
    if (!is.null(pr)) {
      pr <- as.data.frame(pr, stringsAsFactors = FALSE)
      if (!is.null(pr$pass)) {
        i <- match(fr$grant_id, as.character(res$.id))
        k <- match(paste(fr$grant_id, res$overall_ein[i]),
                   paste(as.character(pr$.id), as.character(pr$.ein)))
        fr$pass <- as.character(pr$pass)[k]
      }
    }
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

  # A column that is present but entirely NA stratifies no better than an
  # absent one: every case lands in the same cell and the draw reports strata
  # it did not have. The pass is the one that does this in practice, when a run
  # records it in neither the result frame nor the pairs.
  dead <- by[vapply(by, function(nm) all(is.na(fr[[nm]])), logical(1L))]
  if (length(dead))
    stop(sprintf(paste0(
      "these stratifying columns are entirely NA in the frame: %s\n",
      "  Every case would land in one cell, so this is an unstratified draw",
      " that reports strata.\n  Drop them from `by`, or draw from a run that",
      " records them."),
      paste(dead, collapse = ", ")), call. = FALSE)

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
  floors <- list()
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
      floors[[nm]] <- floor_n
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

  # Realized, not just asked for: one floor's draw can already satisfy another's
  # where the two populations overlap, and reporting only the floor understates
  # what the round actually holds.
  os <- data.frame(column = character(0), floor = integer(0),
                   realized = integer(0), stringsAsFactors = FALSE)
  if (length(floors))
    os <- data.frame(
      column   = names(floors),
      floor    = as.integer(unlist(floors)),
      realized = vapply(names(floors),
                        function(nm) sum(out[[nm]] %in% TRUE), integer(1L)),
      row.names = NULL, stringsAsFactors = FALSE)

  attr(out, "population") <- pop
  attr(out, "frame_id")   <- frm
  attr(out, "normalizer") <- nrm
  attr(out, "seed")       <- seed
  attr(out, "frame_size") <- nrow(fr)
  attr(out, "allocation") <- table(out$stratum)
  attr(out, "oversample") <- os

  if (verbose) {
    .pf_hr(verbose)
    .pf_say(verbose, "drew %s of %s %s identities into %d strata (seed %s)",
            format(nrow(out), big.mark = ","), format(nrow(fr), big.mark = ","),
            paste(tiers, collapse = "/"), length(attr(out, "allocation")), seed)
    if (nrow(os))
      .pf_say(verbose, "  oversampled: %s",
              paste(sprintf("%s floor %d, realized %d", os$column, os$floor,
                            os$realized), collapse = " | "))
    if (is.na(pop))
      .pf_say(verbose, "  population UNFINGERPRINTED: a dry run, these labels cannot be re-attached")
    else
      .pf_say(verbose, "  population %s -- pf_grade_verdicts() will enforce it", pop)
    if (is.na(nrm))
      .pf_say(verbose, "  normalizer UNSTAMPED: the frame does not record what matched it, so")
    if (is.na(nrm))
      .pf_say(verbose, "    these strata cannot be shown to be redrawable")
    else
      .pf_say(verbose, "  normalizer %s -- the signature the frame was matched under", nrm)
    if (!is.na(frm))
      .pf_say(verbose, "  frame %s -- fingerprints this run's id-to-name pairing", frm)
    .pf_say(verbose, "  confidence and evidence class are NOT stratifiable: the reviewer")
    .pf_say(verbose, "  assigns them, so stage this round (PREREQS 6b.1c)")
  }
  out
}
