# ============================================================================
# Sharding the truth round across labelers, and reading it back.
#
# WHY THIS EXISTS. Stage 1 is 400 cases and needs 400 truth rows.
# `PF-TRUTH-V2` carries ~172, fingerprinted to `efv2_1k`; the stage-1 frame
# fingerprints to cb3c78ff0f1a9546, and pf_evaluate() and pf_grade_verdicts()
# both refuse that join outright rather than scoring across populations. So
# the round's truth is built fresh or not at all. It is per-case, independent,
# web-shaped work, 400 times over -- the one step in the round that fans out
# across labelers, where the draw and the arms do not.
#
# THE HAZARD IT IS BUILT AROUND. The arms being graded are themselves LLM
# adjudicators. If truth is also produced by models, grading measures
# AGREEMENT and reports it as accuracy, with a tight Wilson interval on it --
# the shape dev/METRIC-SHAPES.md exists to catch, and the reason PREREQS
# section 4 / T2 records candidate-only review surviving independent checking
# on ~5 of 12. Three things here exist only for that reason:
#
#   * `labeler` is required on every row, so one labeler can be scored on its
#     own, cut out, or dropped. pf_truth_schema() does not carry it and
#     PF-TRUTH-V2 does not have it, so it is required of NEW shard output
#     instead of being added to the old schema -- adding it there would make
#     every existing truth file unreadable by pf_evaluate() on the same day.
#   * `basis = "web"` requires a `source_url`. An asserted basis is an
#     inference wearing a web label, and `basis` is the knob that keeps model
#     truth away from the deep arm the way `min_confidence` keeps weak rows
#     out of a denominator.
#   * a blinded overlap. Cases dealt into two shards, marked as such in the
#     key and nowhere in what either labeler sees, are the only read on
#     whether this truth is worth anything -- and it is computable before the
#     rest of the round is spent.
#
# WHAT IT DOES NOT DO. It does not resolve a contested case in favour of the
# more confident labeler. pf_consolidate_truth() marks it `UNRESOLVED`, which
# pf_grade_verdicts() already excludes from the denominator, because the
# alternative is a truth row whose whole authority is that two models
# disagreed and one of them sounded surer. Nor does it turn agreement into
# accuracy: only a hand-labelled slice does that, and pf_labeler_agreement()
# says so in its own output rather than leaving the reader to remember.
# ============================================================================

# Spread n items over k shards as evenly as n allows, giving the remainder to
# shards drawn at random rather than to the first few: the overlap is dealt
# shard by shard, and handing the extra always to shards 1..r would make the
# low-numbered labelers systematically better measured than the others.
.pf_spread <- function(n, k) {
  out <- rep(n %/% k, k)
  rem <- n %% k
  if (rem > 0L) {
    # sample.int, so a length-one candidate set is not read as seq_len(x)
    i <- sample.int(k, rem)
    out[i] <- out[i] + 1L
  }
  as.integer(out)
}

#' The shard-file contract
#'
#' What a labeler's returned truth file has to carry: [pf_truth_schema()] plus
#' the four columns that make a fanned-out round auditable.
#'
#' @section Why this is a second schema and not an extension of the first:
#' `pf_truth_schema()` is the *minimum for grading*, and
#' `data-dev/PF-TRUTH-V2.csv` meets it exactly. Adding `labeler` there would
#' make that file, and every figure measured against it, unreadable by
#' [pf_evaluate()] the moment this merged. So the stricter contract is required
#' of new shard output only, and a merged shard set is a superset of the
#' grading schema -- which means [pf_evaluate()] and [pf_grade_verdicts()]
#' accept it untouched.
#'
#' @return A character vector of required column names.
#' @seealso [pf_truth_shards()] to deal the cases out, [pf_read_truth()] to
#'   read them back.
#' @examples
#' pf_shard_schema()
#' @export
pf_shard_schema <- function()
  c(pf_truth_schema(),
    "labeler",     # who produced the row: a model id and harness, or a person
    "shard",       # the shard it arrived in; checked against the key
    "source_url",  # the page that established it. REQUIRED when basis == "web"
    "note")        # one sentence of reasoning. Free text, never parsed

#' Deal a drawn round out to labelers, with a blinded overlap
#'
#' Takes the frame [pf_round_sample()] drew and assigns every case to a shard,
#' dealing round-robin *within* stratum so each shard carries the same stratum
#' mix. A fraction of cases is dealt to a second shard as well; those are the
#' overlap, and inter-labeler agreement on them ([pf_labeler_agreement()]) is
#' the cheapest available read on whether the round's truth is worth anything.
#'
#' @section Why round-robin within stratum, and not a split of the row order:
#' A contiguous split hands one labeler the strata that happen to sort first.
#' If that labeler is weaker -- a different model, a different day, a prompt
#' that drifted -- the weakness arrives as a *stratum* effect, and a stratum
#' effect is exactly what the round is being run to measure. Dealing within
#' stratum makes a bad labeler show up as a labeler, where
#' [pf_labeler_agreement()] can see it.
#'
#' @section The overlap is dealt on the same principle:
#' Each shard gives up its own share of the overlap cases and the second
#' copies travel on a rotation of lags, so every shard both gives and receives
#' the same number -- exactly when `k` divides the overlap, within one
#' otherwise. Sampling both halves uniformly, which is what this did first,
#' is balanced only in expectation: the 400-case stage-1 deal landed one
#' labeler 7 overlap cases and another 15 against an expectation of 10, and
#' [pf_labeler_agreement()] reads a per-labeler cell under `min_n` as unusable
#' -- leaving only the pooled rate, which is where a single bad labeler hides.
#'
#' @section What it refuses, and why each is a stop:
#' * **No `seed`.** The same refusal as [pf_round_sample()], for the same
#'   reason: an assignment that cannot be redealt cannot be audited, and these
#'   labels outlive the session that dealt them.
#' * **No population fingerprint.** `grant_id` is positional, and a CSV does
#'   not carry attributes -- so a draw read back from `ADJ-ROUND-STAGE1.csv`
#'   has lost its fingerprint and must be given one. Labels dealt without it
#'   cannot be re-attached to anything later.
#' * **An overlap with `k = 1`.** There is no second labeler to be the second
#'   opinion, so the request is not a small overlap; it is none.
#' * **A duplicated `grant_id`.** One case in two shards by accident is the
#'   overlap arriving unmarked, which is the one thing it must not be.
#'
#' @param draw The frame from [pf_round_sample()], a path to a CSV of it, or a
#'   character vector of `grant_id`s.
#' @param k Number of shards. Mostly this divides by labeler capacity --
#'   6-8 shards of 50-60 cases is a working size -- but it is not free of the
#'   statistics: `k` multiplies the overlap the per-labeler cut needs, because
#'   each labeler only sees `overlap * n / k` of it. Stage 1 went to five
#'   labelers rather than eight for that reason (`dev/ADJUDICATION-PREREQS.md`
#'   6b.6), trading 92 cases a labeler for an overlap that clears `min_n`.
#' @param overlap Fraction of cases dealt to a second shard as well. Default
#'   `0.1`. `0` turns the agreement read off, which is worth doing
#'   deliberately rather than by default. Size it against
#'   [pf_labeler_agreement()]'s `min_n` rather than by taste: the per-labeler
#'   cut needs `overlap * n / k >= min_n / 2` cases on every shard, so 400
#'   cases over 8 labelers need `0.2` and over 5 need `0.15`. The deal prints
#'   what each labeler got and says when it is short.
#' @param seed Required. Recorded on the result.
#' @param labelers Optional character vector of length `k` naming who gets
#'   each shard, and **required to be distinct** when there is an overlap: two
#'   shards under one name make the overlap between them unreadable, since
#'   [pf_labeler_agreement()] needs two different names on a case and
#'   [pf_read_truth()] refuses one labeler answering a case twice. When given,
#'   it is written onto the key and the templates, and [pf_read_truth()]
#'   refuses a shard that comes back under a name the key did not deal it to.
#'   When absent, a stamp is still required of the returned rows and what
#'   arrived is reported rather than checked. Naming them is a **re-stamp, not
#'   a redeal**: `labelers` decorates an assignment the seed already fixed, so
#'   a round dealt without one can be re-dealt with one and nothing moves.
#' @param population The fingerprint these ids are valid in. Taken from
#'   `attr(draw, "population")` when the draw still carries it.
#' @param require_population Set `FALSE` only for a dry run whose labels will
#'   be thrown away.
#' @param verbose Print the allocation.
#' @return A data frame of one row per (case, shard) -- so an overlap case has
#'   two -- carrying `grant_id`, `stratum`, `shard`, `labeler`, `overlap` and
#'   `primary`, classed `pf_shards`. Attributes: `population`, `frame_id` and
#'   `normalizer` (all carried from the draw, `NA` where it did not record
#'   one), `seed`, `k`, `overlap_n`, `sizes`.
#' @seealso [pf_write_shards()] to put it on disk blinded,
#'   [pf_labeler_agreement()] for what the overlap buys.
#' @examples
#' d <- data.frame(grant_id = sprintf("R%03d", 1:60),
#'                 stratum = rep(c("a", "b", "c"), 20))
#' s <- pf_truth_shards(d, k = 4, seed = 1, population = "deadbeefdeadbeef",
#'                      verbose = FALSE)
#' table(s$shard, s$stratum)
#' @export
pf_truth_shards <- function(draw, k = 8L, overlap = 0.1, seed = NULL,
                            labelers = NULL, population = NULL,
                            require_population = TRUE, verbose = TRUE) {
  if (is.null(seed))
    stop(paste0(
      "`seed` is required: an assignment that cannot be redealt cannot be\n",
      "  audited, and these labels will outlive the session that dealt them."),
      call. = FALSE)

  if (is.character(draw) && length(draw) == 1L && file.exists(draw))
    draw <- utils::read.csv(draw, colClasses = "character",
                            stringsAsFactors = FALSE)
  if (is.character(draw))
    draw <- data.frame(grant_id = draw, stringsAsFactors = FALSE)
  fr <- as.data.frame(draw, stringsAsFactors = FALSE)
  if (is.null(fr$grant_id))
    stop("`draw` has no grant_id column.", call. = FALSE)
  fr$grant_id <- as.character(fr$grant_id)

  if (anyDuplicated(fr$grant_id)) {
    d <- unique(fr$grant_id[duplicated(fr$grant_id)])
    stop(sprintf(paste0(
      "%d cases appear twice in the draw: %s\n",
      "  One case in two shards by accident is the overlap arriving",
      " unmarked, which is the one thing it must not be."),
      length(d), paste(utils::head(d, 5), collapse = ", ")), call. = FALSE)
  }

  if (is.null(fr$stratum)) {
    fr$stratum <- "ALL"
    .pf_say(verbose, "no stratum column: dealing over one stratum, so a weak")
    .pf_say(verbose, "  labeler and a hard stratum will not be separable")
  }
  fr$stratum <- as.character(fr$stratum)

  k <- as.integer(k)
  if (is.na(k) || k < 1L) stop("`k` must be at least 1.", call. = FALSE)
  if (k > nrow(fr))
    stop(sprintf("asked for %d shards over %d cases.", k, nrow(fr)),
         call. = FALSE)
  if (!is.numeric(overlap) || length(overlap) != 1L ||
      is.na(overlap) || overlap < 0 || overlap > 0.5)
    stop("`overlap` must be a single fraction in [0, 0.5].", call. = FALSE)
  if (overlap > 0 && k < 2L)
    stop(paste0(
      "an overlap needs at least two shards: with k = 1 there is no second\n",
      "  labeler to be the second opinion, so this is not a small overlap,",
      " it is none."), call. = FALSE)
  if (!is.null(labelers) && length(labelers) != k)
    stop(sprintf("`labelers` names %d labelers for %d shards.",
                 length(labelers), k), call. = FALSE)
  # A name on two shards is not extra capacity, it is a hole in the overlap.
  # pf_labeler_agreement() counts a case as having a second opinion only when
  # two DIFFERENT names carry it, and pf_read_truth() refuses one labeler
  # answering the same case twice outright -- so the overlap cases shared by
  # those two shards come back unusable, and they come back that way after the
  # labelling is paid for. Refused here, where it is still free.
  if (!is.null(labelers) && overlap > 0 && anyDuplicated(labelers)) {
    d <- unique(labelers[duplicated(labelers)])
    stop(sprintf(paste0(
      "`labelers` repeats %s. Two shards under one name make the overlap",
      " between\n  them unreadable: pf_labeler_agreement() needs two",
      " different names on a case,\n  and pf_read_truth() refuses one labeler",
      " answering a case twice."),
      paste(sprintf("`%s`", utils::head(d, 3)), collapse = ", ")),
      call. = FALSE)
  }

  pop <- if (!is.null(population)) as.character(population)
         else attr(draw, "population")
  if (is.null(pop) || is.na(pop) || !nzchar(pop)) {
    if (require_population)
      stop(paste0(
        "no population fingerprint. grant_id is positional, so a label dealt\n",
        "  without one cannot be re-attached to any grant file later -- and a\n",
        "  draw read back from CSV has lost the attribute pf_round_sample()\n",
        "  put on it, so pass `population =` explicitly.\n",
        "  Set require_population = FALSE only for a dry run."), call. = FALSE)
    pop <- NA_character_
  }

  set.seed(seed)

  # Deal continuously across strata, shuffling within each: the counter does
  # not reset, so a stratum of 3 does not always land in shards 1-3 and every
  # shard ends within one case of every other.
  strata <- sort(unique(fr$stratum))
  ids <- unlist(lapply(strata, function(s) sample(fr$grant_id[fr$stratum == s])),
                use.names = FALSE)
  shard <- ((seq_along(ids) - 1L) %% k) + 1L

  a <- data.frame(grant_id = ids, shard = shard, overlap = FALSE,
                  primary = TRUE, stringsAsFactors = FALSE)

  n_ov <- as.integer(round(overlap * nrow(fr)))
  if (n_ov > 0L) {
    # BOTH HALVES OF THE OVERLAP ARE DEALT, NOT SAMPLED. The first version of
    # this drew the overlap cases uniformly and then drew each second shard
    # uniformly from the others. Both are balanced in expectation and neither
    # is balanced, and the cost falls on the only cheap read the round has on
    # its own truth: pf_labeler_agreement() reports a per-labeler cell below
    # `min_n` as unusable, and the pooled rate it reports instead is exactly
    # where a single bad labeler hides. The 400-case stage-1 deal came out at
    # 7 overlap cases for one labeler and 15 for another against an
    # expectation of 10 (dev/ADJ-ROUND-STAGE1-DEAL-20261103.log), so three of
    # the eight sat under min_n by chance alone.
    #
    # So each shard gives up its own share of the overlap, and the second
    # copies go out on a rotation of LAGS rather than a coin flip: every shard
    # draws from the same multiset of lags, so every shard receives as many
    # second copies as it gives up -- exactly when k divides n_ov, within one
    # otherwise. The lag and not the partner, because a fixed offset pairs the
    # same two labelers every time and the agreement figure is then about one
    # pair rather than about the round.
    per  <- .pf_spread(n_ov, k)
    lags <- seq_len(k - 1L)
    base <- rep_len(lags[sample.int(k - 1L)], max(per))
    sec <- do.call(rbind, lapply(seq_len(k), function(p) {
      cand <- a$grant_id[a$shard == p]
      np <- min(per[p], length(cand))
      if (np < 1L) return(NULL)
      # sample.int and not sample(): sample(x) on a length-one x permutes
      # seq_len(x) instead of x, which recycled one case into three shards.
      off <- base[seq_len(np)][sample.int(np)]
      data.frame(grant_id = cand[sample.int(length(cand), np)],
                 shard = ((p - 1L + off) %% k) + 1L,
                 overlap = TRUE, primary = FALSE, stringsAsFactors = FALSE)
    }))
    a$overlap[match(sec$grant_id, a$grant_id)] <- TRUE
    a <- rbind(a, sec[, names(a), drop = FALSE])
    # what was dealt, not what was asked for: the clamp above can only bind on
    # a frame too small to give one shard its share, and the attribute is what
    # a later redeal is checked against.
    n_ov <- nrow(sec)
  }

  a$stratum <- fr$stratum[match(a$grant_id, fr$grant_id)]
  a$labeler <- if (is.null(labelers)) NA_character_
               else as.character(labelers)[a$shard]
  a <- a[order(a$shard, a$grant_id), c("grant_id", "stratum", "shard",
                                       "labeler", "overlap", "primary")]
  rownames(a) <- NULL

  attr(a, "population") <- pop
  # Carried, not re-derived: the signature belongs to the run that produced the
  # draw's tiers, and the deal happens later -- possibly under a different
  # installed stack. NA where the draw did not carry one, including every draw
  # read back from a CSV.
  carry <- function(nm) {
    v <- attr(draw, nm)
    if (is.null(v) || !length(v)) NA_character_ else as.character(v)[1L]
  }
  attr(a, "normalizer") <- carry("normalizer")
  # The identity numbering the dealt ids are positions in. Without it a shard
  # re-read against a rebuilt frame passes the population check and attaches to
  # different organisations; see pf_frame_id().
  attr(a, "frame_id")   <- carry("frame_id")
  attr(a, "seed")       <- seed
  attr(a, "k")          <- k
  attr(a, "overlap_n")  <- n_ov
  attr(a, "sizes")      <- table(shard = a$shard)
  class(a) <- c("pf_shards", "data.frame")

  if (verbose) {
    .pf_hr(verbose)
    .pf_say(verbose, "dealt %s cases into %d shards (%s rows, seed %s)",
            format(nrow(fr), big.mark = ","), k,
            format(nrow(a), big.mark = ","), seed)
    .pf_say(verbose, "  shard sizes: %s",
            paste(sprintf("%s:%d", names(attr(a, "sizes")),
                          as.integer(attr(a, "sizes"))), collapse = " "))
    .pf_say(verbose, "  %d cases (%.0f%%) dealt to a second shard as the blinded overlap",
            n_ov, 100 * n_ov / max(1L, nrow(fr)))
    # The number the deal used to leave the reader to compute off the key, and
    # the one that decides whether the per-labeler agreement cut exists at all:
    # pf_labeler_agreement()'s min_n is 20, and a cell under it comes back
    # usable = FALSE. Said here because this is the last moment it is free to
    # change -- after the shards go out it costs a relabel.
    if (n_ov > 0L) {
      ovs <- as.integer(table(factor(a$shard[a$overlap], levels = seq_len(k))))
      .pf_say(verbose, "  overlap per labeler: %s (min %d, max %d)",
              paste(ovs, collapse = " "), min(ovs), max(ovs))
      if (min(ovs) < 20L)
        .pf_say(verbose, paste0(
          "  under pf_labeler_agreement()'s min_n of 20, so the PER-LABELER\n",
          "  cut will read unusable and only the pooled rate will survive --\n",
          "  which is the rate a single bad labeler hides in. Raise `overlap`",
          "\n  or lower `k`."))
    }
    if (is.na(pop))
      .pf_say(verbose, "  population UNFINGERPRINTED: these labels cannot be re-attached")
    else
      .pf_say(verbose, "  population %s -- pf_read_truth() will enforce it", pop)
    if (n_ov == 0L)
      .pf_say(verbose, "  no overlap: agreement is unmeasurable for this round")
  }
  a
}

#' Write the shard files a labeler works from
#'
#' Puts one blinded case list and one pre-keyed truth template per shard on
#' disk, plus the key that records which cases are the overlap.
#'
#' @section What blinded means here, and what it does not:
#' The case file a labeler sees carries no `overlap` column and its rows are
#' shuffled, so the duplicated cases are not identifiable from the file. That
#' is the whole of the blinding, and it holds only as long as each labeler is
#' given its own two files and not the key. `key_dir` exists so the key can go
#' somewhere the labelers are not pointed at; leaving it beside the shards
#' makes the blinding nominal, and the verbose output says so.
#'
#' @section Why the template is pre-keyed:
#' `grant_id`, `population` and `shard` are filled in before the labeler sees
#' the file. A labeler asked to type a 16-character fingerprint onto 50 rows
#' will eventually type it wrong, and `population` is the one column whose
#' being wrong makes every row silently unusable rather than visibly broken.
#'
#' @section What it refuses:
#' **An existing shard file.** A part-written file is a labeler's work in
#' progress and overwriting it is unrecoverable. Pass `overwrite = TRUE` only
#' when the round is being re-dealt from scratch.
#'
#' @param shards A `pf_shards` from [pf_truth_shards()].
#' @param dir Directory for the per-shard files. Created if absent.
#' @param cases Optional frame keyed by `grant_id` with case columns to carry
#'   into the case files -- the recipient name, city, dollars, whatever the
#'   labeler works from.
#' @param key_dir Where `SHARD-KEY.csv` goes. Defaults to `dir`.
#' @param overwrite Allow replacing existing shard files.
#' @param verbose Print what was written.
#' @return The paths written, invisibly.
#' @seealso [pf_read_truth()] to read the filled templates back.
#' @export
pf_write_shards <- function(shards, dir, cases = NULL, key_dir = dir,
                            overwrite = FALSE, verbose = TRUE) {
  stopifnot(inherits(shards, "pf_shards"))
  for (d in unique(c(dir, key_dir)))
    if (!dir.exists(d)) dir.create(d, recursive = TRUE)

  have <- list.files(dir, pattern = "^shard-[0-9]+-(cases|truth)\\.csv$")
  if (length(have) && !overwrite)
    stop(sprintf(paste0(
      "%s already holds %d shard file(s): %s\n",
      "  A part-written truth file is a labeler's work in progress and",
      " overwriting it is unrecoverable.\n",
      "  Pass overwrite = TRUE only when re-dealing the round from scratch."),
      dir, length(have), paste(utils::head(have, 4), collapse = ", ")),
      call. = FALSE)


  # A REDEAL WITH FEWER SHARDS LEAVES THE OLD ONES BEHIND. Writing k = 5 over a
  # k = 8 round overwrites shards 1-5 and says nothing about 6-8, which then sit
  # in the live directory looking exactly like work to hand out. pf_read_truth()
  # does refuse their rows -- the key no longer deals those cases -- but it
  # refuses them on the way back in, after a labeler has done the work. So the
  # stale files go now, and the removal is reported rather than silent.
  will <- as.vector(outer(sprintf("shard-%02d", sort(unique(shards$shard))),
                          c("-cases.csv", "-truth.csv"), paste0))
  stale <- setdiff(have, will)
  if (length(stale)) {
    file.remove(file.path(dir, stale))
    .pf_say(verbose, "removed %d file(s) from a wider deal: %s",
            length(stale), paste(stale, collapse = ", "))
  }

  pop   <- attr(shards, "population")
  seed  <- attr(shards, "seed")
  blank <- setdiff(pf_shard_schema(),
                   c("grant_id", "population", "shard", "labeler"))
  ex <- if (is.null(cases)) NULL else as.data.frame(cases, stringsAsFactors = FALSE)
  if (!is.null(ex) && is.null(ex$grant_id))
    stop("`cases` needs a grant_id column to join on.", call. = FALSE)

  written <- character(0)
  for (s in sort(unique(shards$shard))) {
    rows <- shards[shards$shard == s, , drop = FALSE]
    set.seed(seed + s)
    rows <- rows[sample.int(nrow(rows)), , drop = FALSE]

    cf <- data.frame(grant_id = rows$grant_id, stratum = rows$stratum,
                     stringsAsFactors = FALSE)
    if (!is.null(ex)) {
      j <- match(cf$grant_id, as.character(ex$grant_id))
      for (nm in setdiff(names(ex), c("grant_id", names(cf))))
        cf[[nm]] <- ex[[nm]][j]
    }
    tf <- data.frame(grant_id   = rows$grant_id,
                     population = pop,
                     shard      = s,
                     labeler    = ifelse(is.na(rows$labeler), "", rows$labeler),
                     stringsAsFactors = FALSE)
    for (nm in blank) tf[[nm]] <- ""
    tf <- tf[, pf_shard_schema(), drop = FALSE]

    pc <- file.path(dir, sprintf("shard-%02d-cases.csv", s))
    pt <- file.path(dir, sprintf("shard-%02d-truth.csv", s))
    utils::write.csv(cf, pc, row.names = FALSE, na = "")
    utils::write.csv(tf, pt, row.names = FALSE, na = "")
    written <- c(written, pc, pt)
  }

  pk <- file.path(key_dir, "SHARD-KEY.csv")
  utils::write.csv(as.data.frame(shards), pk, row.names = FALSE, na = "")
  written <- c(written, pk)

  if (verbose) {
    .pf_hr(verbose)
    .pf_say(verbose, "wrote %d files for %d shards into %s",
            length(written) - 1L, length(unique(shards$shard)), dir)
    .pf_say(verbose, "  case files carry no overlap column and are shuffled")
    .pf_say(verbose, "  key: %s", pk)
    if (identical(normalizePath(key_dir, mustWork = FALSE),
                  normalizePath(dir, mustWork = FALSE)))
      .pf_say(verbose, "  the key names the overlap and sits beside the shards, so the")
    .pf_say(verbose, "  blinding holds only if each labeler is given its own two files")
  }
  invisible(written)
}

#' Read filled shard files back, validated
#'
#' The reader for a fanned-out round. Reads every `shard-NN-truth.csv`,
#' validates each against [pf_shard_schema()] and [pf_truth_levels()], checks
#' the rows against the key, and returns them long -- one row per
#' (case, labeler), so an overlap case has two. Collapsing to one row per case
#' is [pf_consolidate_truth()]'s job, and separating the two steps is
#' deliberate: a disagreement has to be visible before anything resolves it.
#'
#' @section What it refuses, and why each is a stop:
#' * **A missing schema column.** The same reason [pf_read_verdicts()] stops: a
#'   count over an absent column is `0` rather than an error.
#' * **`basis = "web"` with no `source_url`.** An asserted web basis is an
#'   inference wearing a web label, and `basis` is what a later analysis uses
#'   to decide which rows are allowed to grade a model arm.
#' * **A missing `basis` or `confidence`.** Both are filters downstream, and a
#'   row that cannot be filtered out is a row that will be used.
#' * **`ORG_FOUND` with no 9-digit `correct_ein`.** The row claims an answer it
#'   does not carry.
#' * **A blank `labeler`.** A fanned-out round whose rows do not say who
#'   produced them is one undifferentiated pile: a bad labeler cannot be cut
#'   out of it, and per-labeler accuracy is not computable.
#' * **Two rows from one labeler for one case.** Two answers from one reviewer
#'   double-count it in one direction and hide the disagreement.
#' * **Two labelers on a case the key did not deal twice.** That is a shard
#'   file that got copied, not an overlap, and it would read as agreement.
#' * **A row for a (case, shard) the key did not deal**, and **a mixed
#'   population**.
#'
#' Rows left entirely blank in the template are *not* an error: they are cases
#' that came back unlabelled, reported in the `missing` attribute. A round
#' comes back incomplete far more often than it comes back malformed, and a
#' stop there would block the agreement read the returned rows already support.
#'
#' @param x A directory of `shard-NN-truth.csv` files, a single frame, or a
#'   list of frames.
#' @param key The `pf_shards` assignment or a path to `SHARD-KEY.csv`. Without
#'   it the per-row checks still run; the cross-checks against what was dealt
#'   do not. Those are: rows for a (case, shard) pair that was never dealt, a
#'   case back from two labelers that was dealt to one shard, and -- when the
#'   key carries a roster -- a shard returned under a name the key did not deal
#'   it to. An unrostered key leaves the last of those with nothing to check,
#'   which is reported rather than treated as a failure.
#' @param population Fingerprint to enforce.
#' @param verbose Print the per-labeler counts.
#' @return A data frame classed `pf_truth_rows`, one row per (case, labeler),
#'   with `attr(, "missing")` listing dealt cases that came back unlabelled and
#'   `attr(, "by_labeler")` the counts.
#' @seealso [pf_labeler_agreement()], [pf_consolidate_truth()].
#' @export
pf_read_truth <- function(x, key = NULL, population = NULL, verbose = TRUE) {
  need <- pf_shard_schema()

  if (is.character(key) && length(key) == 1L) {
    if (!file.exists(key)) stop("shard key not found: ", key, call. = FALSE)
    key <- utils::read.csv(key, colClasses = "character", stringsAsFactors = FALSE)
    key$overlap <- toupper(as.character(key$overlap)) %in% c("TRUE", "T", "1")
    key$primary <- toupper(as.character(key$primary)) %in% c("TRUE", "T", "1")
  }

  parts <- if (is.character(x) && length(x) == 1L && dir.exists(x)) {
    f <- list.files(x, pattern = "^shard-[0-9]+-truth\\.csv$", full.names = TRUE)
    if (!length(f))
      stop(sprintf("no shard-NN-truth.csv files in %s", x), call. = FALSE)
    lapply(f, function(p) {
      d <- utils::read.csv(p, colClasses = "character", stringsAsFactors = FALSE)
      attr(d, "src") <- basename(p)
      d
    })
  } else if (is.data.frame(x)) list(x) else x

  rows <- lapply(parts, function(d) {
    src <- attr(d, "src")
    if (is.null(src)) src <- "<frame>"
    d <- as.data.frame(d, stringsAsFactors = FALSE)
    miss <- need[!need %in% names(d)]
    if (length(miss))
      stop(sprintf(paste0(
        "%s is missing these columns: %s\n  present: %s\n",
        "  A count over an absent column is 0 rather than an error."),
        src, paste(miss, collapse = ", "), paste(names(d), collapse = ", ")),
        call. = FALSE)
    for (nm in need) {
      z <- trimws(as.character(d[[nm]]))
      z[is.na(z) | !nzchar(z)] <- NA_character_
      d[[nm]] <- z
    }
    d$.src <- src
    d[, c(need, ".src"), drop = FALSE]
  })
  v <- do.call(rbind, rows)

  # An untouched template row is a case that came back unlabelled, not a
  # malformed one. Separating the two is why `missing` is an attribute and a
  # blank verdict is not a stop.
  filled <- !is.na(v$verdict)
  blank_ids <- v$grant_id[!filled]
  v <- v[filled, , drop = FALSE]
  if (!nrow(v))
    stop("every row in these shard files is blank: nothing came back labelled.",
         call. = FALSE)

  lv <- pf_truth_levels()
  for (nm in names(lv)) {
    bad <- setdiff(stats::na.omit(unique(v[[nm]])), lv[[nm]])
    if (length(bad))
      stop(sprintf(paste0(
        "`%s` carries %s, outside the permitted set.\n  permitted: %s\n",
        "  A level the code below does not mention is excluded from every",
        " count at once."),
        nm, paste(sprintf("`%s`", bad), collapse = ", "),
        paste(lv[[nm]], collapse = ", ")), call. = FALSE)
  }

  v$correct_ein <- .pf_ein(v$correct_ein)
  v$wrong_ein   <- .pf_ein(v$wrong_ein)

  bad <- which(is.na(v$basis) | is.na(v$confidence))
  if (length(bad))
    stop(sprintf(paste0(
      "%d rows carry no basis or no confidence: %s\n",
      "  Both are filters downstream (min_confidence, and basis for which",
      " rows may grade\n",
      "  a model arm). A row that cannot be filtered out is a row that will",
      " be used."),
      length(bad), paste(utils::head(v$grant_id[bad], 5), collapse = ", ")),
      call. = FALSE)

  bad <- which(v$basis == "web" & is.na(v$source_url))
  if (length(bad))
    stop(sprintf(paste0(
      "%d rows claim basis = \"web\" and name no source_url: %s\n",
      "  An asserted web basis is an inference wearing a web label. `basis`",
      " decides which\n",
      "  rows may grade a model arm, so it has to be earned rather than",
      " typed."),
      length(bad), paste(utils::head(v$grant_id[bad], 5), collapse = ", ")),
      call. = FALSE)

  bad <- which(v$verdict == "ORG_FOUND" & is.na(v$correct_ein))
  if (length(bad))
    stop(sprintf("%d ORG_FOUND rows name no 9-digit EIN: %s", length(bad),
                 paste(utils::head(v$grant_id[bad], 5), collapse = ", ")),
         call. = FALSE)

  bad <- which(is.na(v$labeler))
  if (length(bad))
    stop(sprintf(paste0(
      "%d rows carry no labeler: %s\n",
      "  A fanned-out round whose rows do not say who produced them is one\n",
      "  undifferentiated pile -- a bad labeler cannot be cut out of it."),
      length(bad), paste(utils::head(v$grant_id[bad], 5), collapse = ", ")),
      call. = FALSE)

  dup <- duplicated(paste(v$grant_id, v$labeler))
  if (any(dup))
    stop(sprintf(paste0(
      "%d (case, labeler) pairs appear twice, e.g. %s\n",
      "  Two answers from one reviewer double-count the case and hide the",
      " disagreement."),
      sum(dup), paste(utils::head(unique(v$grant_id[dup]), 5), collapse = ", ")),
      call. = FALSE)

  # An id from before ids were content-derived. `R<k>` was a position among the
  # deduplicated recipients, so re-attaching one to a frame rebuilt since is
  # not a near miss -- it lands on an unrelated organisation while the
  # population fingerprint still agrees, because the grant file really is the
  # same (dev/ADJ-ROUND-STAGE1-20261103.log). Nothing downstream can detect
  # that, so it is refused here, where the shape of the id still shows it.
  pos <- grepl("^R[0-9]+$", as.character(v$grant_id))
  if (any(pos))
    stop(sprintf(paste0(
      "%d labelled rows carry positional ids (%s), which predate",
      " pf_identity_id().\n",
      "  R<k> was a position among the deduplicated recipients: a rebuild that",
      " merged\n  duplicates renumbered everything after it, so these ids now",
      " name DIFFERENT\n  organisations while still matching the population.",
      " They cannot be repaired\n  from the file -- relabel them, or map them",
      " through the frame they were drawn\n  from if it is still on disk."),
      sum(pos), paste(utils::head(unique(v$grant_id[pos]), 3), collapse = ", ")),
      call. = FALSE)

  vpop <- unique(stats::na.omit(v$population))
  if (length(vpop) > 1L)
    stop(sprintf(paste0(
      "these shard files mix populations (%s); an id means something only\n",
      "  within one, so grading across them would be meaningless."),
      paste(vpop, collapse = ", ")), call. = FALSE)
  if (!length(vpop))
    stop(paste0(
      "no labelled row carries a population fingerprint, so these labels\n",
      "  cannot be re-attached to any grant file."), call. = FALSE)
  if (!is.null(population) && !identical(as.character(population), vpop))
    stop(sprintf(paste0(
      "population mismatch: the round is %s, the shard files say %s.\n",
      "  These ids belong to a different grant file and are not comparable."),
      population, vpop), call. = FALSE)

  missing_ids <- unique(blank_ids)
  if (!is.null(key)) {
    key <- as.data.frame(key, stringsAsFactors = FALSE)
    dealt <- paste(as.character(key$grant_id), as.integer(key$shard))
    got   <- paste(v$grant_id, as.integer(v$shard))
    extra <- unique(got[!got %in% dealt])
    if (length(extra))
      stop(sprintf(paste0(
        "%d rows are for (case, shard) pairs the key did not deal: %s\n",
        "  A review over a different set than the one dealt is not a review",
        " of it."),
        length(extra), paste(utils::head(extra, 5), collapse = ", ")),
        call. = FALSE)

    twice <- names(which(table(v$grant_id) > 1L))
    ov <- unique(as.character(key$grant_id[key$overlap %in% TRUE]))
    bad <- setdiff(twice, ov)
    if (length(bad))
      stop(sprintf(paste0(
        "%d cases came back from two labelers but were dealt to one shard: %s\n",
        "  That is a shard file that got copied, not an overlap, and it would",
        " read as agreement."),
        length(bad), paste(utils::head(bad, 5), collapse = ", ")),
        call. = FALSE)

    # THE ROSTER, WHEN THE KEY CARRIES ONE. pf_truth_shards(labelers = ) exists
    # so that a shard cannot come back under a name nobody agreed to, and the
    # roxygen for it has claimed this check since the function was written --
    # but the check itself was never here. A wrong name is not cosmetic: it
    # means the shard was labelled by something other than what the round
    # records, or that one labeler's file reached another labeler, and either
    # way every per-labeler figure downstream is attributed to the wrong
    # producer. An unrostered key (labeler NA or blank, which is what a round
    # dealt without a roster writes) has nothing to enforce, and that stays a
    # report rather than a refusal.
    kl <- as.character(key$labeler)
    kl[!nzchar(trimws(kl))] <- NA_character_
    if (any(!is.na(kl))) {
      roster <- tapply(kl, as.integer(key$shard), function(z)
        unique(stats::na.omit(z))[1L])
      want <- roster[as.character(as.integer(v$shard))]
      off <- which(!is.na(want) & v$labeler != want)
      if (length(off)) {
        d <- unique(data.frame(shard = as.integer(v$shard)[off],
                               got = v$labeler[off], want = want[off],
                               stringsAsFactors = FALSE))
        stop(sprintf(paste0(
          "%d rows carry a labeler the key did not deal that shard to:\n%s\n",
          "  The round records who labelled what, so a shard returned under",
          " another\n  name is either the wrong labeler's work or the wrong",
          " labeler's file --\n  and every per-labeler figure built on it",
          " would name the wrong producer."),
          length(off),
          paste(sprintf("    shard %d: got `%s`, dealt to `%s`",
                        d$shard, d$got, d$want), collapse = "\n")),
          call. = FALSE)
      }
    }

    missing_ids <- unique(c(missing_ids,
                            setdiff(as.character(key$grant_id), v$grant_id)))
  }

  by_lab <- table(labeler = v$labeler)
  rownames(v) <- NULL
  attr(v, "missing")    <- sort(missing_ids)
  attr(v, "by_labeler") <- by_lab
  attr(v, "population") <- vpop
  class(v) <- c("pf_truth_rows", "data.frame")

  if (verbose) {
    nov <- sum(table(v$grant_id) > 1L)
    .pf_hr(verbose)
    .pf_say(verbose, "read %d labelled rows over %d cases from %d labelers",
            nrow(v), length(unique(v$grant_id)), length(by_lab))
    .pf_say(verbose, "  %s", paste(sprintf("%s %d", names(by_lab),
                                           as.integer(by_lab)), collapse = " | "))
    .pf_say(verbose, "  basis: %s",
            paste(sprintf("%s %d", names(table(v$basis)),
                          as.integer(table(v$basis))), collapse = " | "))
    .pf_say(verbose, "  %d cases carry two labelers (the overlap)", nov)
    if (length(missing_ids))
      .pf_say(verbose, "  %d dealt cases came back unlabelled, reported not counted wrong",
              length(missing_ids))
    if (!nov)
      .pf_say(verbose, "  no overlap returned: pf_labeler_agreement() has nothing to read")
  }
  v
}

#' Agreement between labelers on the blinded overlap
#'
#' The gate on a fanned-out round. Reports how often the labelers who saw the
#' same case reached the same answer, with a Wilson interval, overall and per
#' labeler.
#'
#' @section Agreement is not accuracy, and that is the whole point:
#' Two models that agree can both be wrong, and on this tier they will tend to
#' be wrong together -- a model labeler and the deep arm share a training
#' distribution and a tool. So a high figure here licenses nothing on its own.
#' It rules out the cheap failure only: labelers that disagree so often the
#' truth set cannot support any claim. What converts agreement into accuracy is
#' a hand-labelled slice scored with [pf_grade_verdicts()], and nothing else in
#' this package does it.
#'
#' @section Two rates, because grading uses only one of them:
#' `strict` counts a case agreed when the verdict and the EIN both match.
#' `effective` collapses the three `NO_ORG_*` reasons together, because
#' [pf_evaluate()] keys on `^NO_ORG` and does not distinguish them -- so two
#' labelers who both found no organisation and differed on why are a
#' disagreement that changes no downstream figure. Reporting only `strict`
#' understates the usable truth; reporting only `effective` hides a labeler
#' that cannot tell an individual payee from an unfindable org.
#'
#' @param truth A `pf_truth_rows` from [pf_read_truth()], or any frame with
#'   `grant_id`, `labeler`, `verdict` and `correct_ein`.
#' @param min_n Below this many overlap cases a cell is marked unusable rather
#'   than read as a rate. Default 20, as [pf_grade_by()].
#' @return A list of `summary` (the two rates with intervals) and `by_labeler`
#'   (each labeler's agreement with whoever else saw its overlap cases),
#'   classed `pf_agreement`. `attr(, "detail")` is the per-case frame.
#' @seealso [pf_consolidate_truth()], which marks the disagreements
#'   `UNRESOLVED` rather than picking a winner.
#' @export
pf_labeler_agreement <- function(truth, min_n = 20L) {
  d <- as.data.frame(truth, stringsAsFactors = FALSE)
  for (nm in c("grant_id", "labeler", "verdict"))
    if (is.null(d[[nm]]))
      stop(sprintf("`%s` is not a column of this frame.", nm), call. = FALSE)
  if (is.null(d$correct_ein)) d$correct_ein <- NA_character_

  n_lab <- tapply(d$labeler, d$grant_id, function(z) length(unique(z)))
  ids <- names(n_lab)[n_lab > 1L]
  if (!length(ids))
    stop(paste0(
      "no case in this frame carries two labelers, so agreement is not\n",
      "  measurable. Either the overlap was dealt at 0, or it has not come",
      " back yet."), call. = FALSE)
  o <- d[d$grant_id %in% ids, , drop = FALSE]

  strict <- paste(o$verdict, ifelse(is.na(o$correct_ein), "", o$correct_ein))
  eff    <- paste(ifelse(grepl("^NO_ORG", o$verdict), "NO_ORG", o$verdict),
                  ifelse(is.na(o$correct_ein), "", o$correct_ein))
  agree1 <- tapply(strict, o$grant_id, function(z) length(unique(z)) == 1L)
  agree2 <- tapply(eff,    o$grant_id, function(z) length(unique(z)) == 1L)

  rate <- function(k, n, what) {
    w <- pf_wilson(k, n)
    data.frame(basis = what, k = k, n = n,
               rate = if (n > 0) k / n else NA_real_,
               lo = w[1, "lo"], hi = w[1, "hi"], usable = n >= min_n,
               stringsAsFactors = FALSE)
  }
  n <- length(agree1)
  s <- rbind(rate(sum(agree1), n, "strict"), rate(sum(agree2), n, "effective"))

  # Per labeler: of the overlap cases this labeler saw, how many did the
  # others agree with it on. A single bad labeler shows up here and nowhere in
  # the pooled figure, which is the reason the pooled figure is not enough.
  labs <- sort(unique(o$labeler))
  bl <- do.call(rbind, lapply(labs, function(l) {
    mine <- unique(o$grant_id[o$labeler == l])
    k <- sum(agree2[mine] %in% TRUE)
    w <- pf_wilson(k, length(mine))
    data.frame(labeler = l, n = length(mine), agreed = k,
               rate = if (length(mine)) k / length(mine) else NA_real_,
               lo = w[1, "lo"], hi = w[1, "hi"],
               usable = length(mine) >= min_n, stringsAsFactors = FALSE)
  }))
  rownames(s) <- NULL
  rownames(bl) <- NULL

  det <- data.frame(grant_id = names(agree1),
                    agree_strict = as.logical(agree1),
                    agree_effective = as.logical(agree2),
                    stringsAsFactors = FALSE)
  structure(list(summary = s, by_labeler = bl), detail = det,
            class = "pf_agreement")
}

#' @export
print.pf_agreement <- function(x, ...) {
  s <- x$summary
  cat("<pf_agreement>  ", s$n[1], " cases dealt to two labelers\n", sep = "")
  for (i in seq_len(nrow(s)))
    cat(sprintf("  %-9s %4d/%-4d = %5.1f%% [%.1f, %.1f]%s\n",
                s$basis[i], s$k[i], s$n[i], 100 * s$rate[i],
                100 * s$lo[i], 100 * s$hi[i],
                if (s$usable[i]) "" else "   UNUSABLE (n below min_n)"))
  cat("  per labeler, on the effective basis:\n")
  b <- x$by_labeler
  for (i in seq_len(nrow(b)))
    cat(sprintf("    %-24s %3d/%-3d = %5.1f%% [%.1f, %.1f]\n",
                b$labeler[i], b$agreed[i], b$n[i], 100 * b$rate[i],
                100 * b$lo[i], 100 * b$hi[i]))
  cat("\n  Agreement is NOT accuracy: two labelers sharing a training\n")
  cat("  distribution and a tool will be wrong together. What converts this\n")
  cat("  into accuracy is a hand-labelled slice scored with pf_grade_verdicts().\n")
  invisible(x)
}

#' Collapse a fanned-out round to one row per case
#'
#' Turns the long frame from [pf_read_truth()] into the one-row-per-case table
#' [pf_evaluate()] and [pf_grade_verdicts()] read, which means deciding what a
#' contested case is worth.
#'
#' @section What it does with a disagreement, and why it is not a tie-break:
#' A contested case becomes `UNRESOLVED`, with `correct_ein` dropped and both
#' answers recorded in `note`. `UNRESOLVED` is already a [pf_truth_levels()]
#' verdict and [pf_grade_verdicts()] already excludes it from the denominator,
#' so the case costs the round one row rather than contaminating it. The
#' alternative -- keeping the more confident labeler's answer -- produces a
#' truth row whose entire authority is that two labelers disagreed and one of
#' them sounded surer, and self-reported confidence is the thing
#' `ADJUDICATION-PREREQS.md` T3 exists to test rather than to rely on.
#'
#' Where two labelers *agree*, the row keeps the **weaker** `basis` and
#' `confidence` of the two. Two labelers reaching one answer does not make
#' either one's evidence stronger than it was, and `min_confidence` downstream
#' should see the weaker figure.
#'
#' @param truth A `pf_truth_rows` from [pf_read_truth()].
#' @param verbose Print the reconciliation.
#' @return A data frame of one row per `grant_id` with [pf_truth_schema()]
#'   columns first, then `labeler` (joined with `+` where two agreed), `note`
#'   and `source_url`. Attributes: `contested`, `agreed`, `unresolved`.
#' @seealso [pf_labeler_agreement()] to read the disagreement rate before
#'   collapsing it away.
#' @export
pf_consolidate_truth <- function(truth, verbose = TRUE) {
  d <- as.data.frame(truth, stringsAsFactors = FALSE)
  if (is.null(d$labeler))
    stop("`labeler` is not a column: this frame is not a fanned-out round.",
         call. = FALSE)
  if (is.null(d$note)) d$note <- NA_character_
  if (is.null(d$source_url)) d$source_url <- NA_character_

  BRANK <- c(inference = 1L, reference = 2L, web = 3L)
  CRANK <- c(low = 1L, medium = 2L, high = 3L)
  answer <- function(r) paste(ifelse(grepl("^NO_ORG", r$verdict), "NO_ORG",
                                     r$verdict),
                              ifelse(is.na(r$correct_ein), "", r$correct_ein))

  parts <- split(seq_len(nrow(d)), d$grant_id)
  contested <- 0L
  agreed    <- 0L
  unresolved <- 0L

  out <- do.call(rbind, lapply(parts, function(i) {
    r <- d[i, , drop = FALSE]
    if (nrow(r) == 1L) return(r)
    contested <<- contested + 1L
    if (length(unique(answer(r))) == 1L) {
      agreed <<- agreed + 1L
      # Keep the weakest evidence of the two: concurrence is not corroboration.
      o <- r[1L, , drop = FALSE]
      o$basis      <- names(BRANK)[min(BRANK[r$basis])]
      o$confidence <- names(CRANK)[min(CRANK[r$confidence])]
      o$labeler    <- paste(sort(unique(r$labeler)), collapse = "+")
      o$note       <- sprintf("agreed by %s", o$labeler)
      return(o)
    }
    unresolved <<- unresolved + 1L
    o <- r[1L, , drop = FALSE]
    o$verdict     <- "UNRESOLVED"
    o$correct_ein <- NA_character_
    o$wrong_ein   <- NA_character_
    o$basis       <- "inference"
    o$confidence  <- "low"
    o$labeler     <- paste(sort(unique(r$labeler)), collapse = "+")
    o$note <- paste("contested:",
                    paste(sprintf("%s said %s", r$labeler, answer(r)),
                          collapse = "; "))
    o
  }))

  keep <- c(pf_truth_schema(), "labeler", "note", "source_url")
  out <- out[, c(keep, setdiff(names(out), c(keep, ".src"))), drop = FALSE]
  out <- out[order(out$grant_id), , drop = FALSE]
  rownames(out) <- NULL
  attr(out, "contested")  <- contested
  attr(out, "agreed")     <- agreed
  attr(out, "unresolved") <- unresolved

  if (verbose) {
    .pf_hr(verbose)
    .pf_say(verbose, "consolidated %d rows to %d cases", nrow(d), nrow(out))
    .pf_say(verbose, "  %d cases had two labelers: %d agreed, %d contested -> UNRESOLVED",
            contested, agreed, unresolved)
    .pf_say(verbose, "  a contested case is not tie-broken on confidence: that is the")
    .pf_say(verbose, "  self-report T3 exists to test, not to resolve truth with")
    .pf_say(verbose, "  where two agreed, the WEAKER basis and confidence is kept")
  }
  out
}
