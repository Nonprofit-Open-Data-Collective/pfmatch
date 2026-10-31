#' End-to-end wrappers
#'
#' The granular functions in this package are deliberately small and separately
#' testable, which is right for development and wrong for use: `dev/run-full-file.R`
#' had to hand-assemble nine calls in the correct order, and every caller
#' reproduced that order. These wrappers name the four stages and compose them.
#'
#' Three levels of entry, from coarse to fine:
#' \describe{
#'   \item{[pf_run()]}{one call, grants in, results out.}
#'   \item{[pf_prepare()], [pf_reference()], [pf_link()], [pf_adjudicate()]}{the
#'     four stages, for when you want to cache between them or vary one.}
#'   \item{everything else}{the individual steps, unchanged.}
#' }
#'
#' The wrappers add no logic of their own — they order existing calls, thread the
#' cache paths, and time each stage. Anything a wrapper does that you disagree
#' with can be done by calling the stage functions directly.
#'
#' @name pf_pipeline
NULL

.pf_tick <- function() proc.time()[["elapsed"]]
.pf_say  <- function(verbose, ...) if (verbose) cat(sprintf(...), "\n")
.pf_hr   <- function(verbose) if (verbose) cat(strrep("-", 70), "\n")

#' Stage 1 — read, repair, scope, and collapse to identities
#'
#' Wraps [pf_read_grants()] (which itself calls [pf_prepare_grants()], and so
#' [pf_standardize_status()]), then [pf_recover_name_from_street()],
#' [pf_dedup()], and [pf_recipients()].
#'
#' The dedup step is the scale lever, not a nicety: grants repeat heavily, and
#' matching distinct recipient identities rather than grant rows removes most of
#' the work without removing recall. It also *adds* recall, because a match found
#' for any cluster member propagates to all of them.
#'
#' @param grants A directory of grant CSVs, a vector of file paths, or an
#'   already-read data frame.
#' @param pattern Regex selecting files when `grants` is a directory.
#' @param dedup `"fuzzy"` (default), `"exact"`, or `"none"`.
#' @param threshold Name-similarity threshold for fuzzy clustering.
#' @param verbose Print progress.
#' @return A list of class `pf_prepared` with `grants` (every row, scoped and
#'   assigned a `recipient_uid`), `recipients` (one row per identity, in scope),
#'   and `timing`.
#' @export
pf_prepare <- function(grants, pattern = "grants.*[.]csv$",
                       dedup = c("fuzzy", "exact", "none"),
                       threshold = 0.92, verbose = TRUE) {
  dedup <- match.arg(dedup)
  t0 <- .pf_tick()
  .pf_hr(verbose); .pf_say(verbose, "STAGE 1  prepare")

  g <- if (is.data.frame(grants)) pf_prepare_grants(grants)
       else pf_read_grants(grants, pattern = pattern)
  g <- pf_recover_name_from_street(g)
  .pf_say(verbose, "  grant rows ......... %s", format(nrow(g), big.mark = ","))
  .pf_say(verbose, "  in scope ........... %s (%.1f%%)",
          format(sum(g$in_scope), big.mark = ","), 100 * mean(g$in_scope))

  if (dedup == "none") {
    g$recipient_uid <- seq_len(nrow(g))
    g$recipient_n <- 1L
    recips <- g[g$in_scope, , drop = FALSE]
  } else {
    g <- pf_dedup(g, method = dedup, threshold = threshold, verbose = verbose)
    recips <- pf_recipients(g[g$in_scope, , drop = FALSE])
    .pf_say(verbose, "  distinct identities  %s (%.2fx collapse)",
            format(nrow(recips), big.mark = ","),
            if (nrow(recips)) sum(g$in_scope) / nrow(recips) else NA_real_)
  }
  el <- .pf_tick() - t0
  .pf_say(verbose, "  elapsed %.1f s", el)
  structure(list(grants = g, recipients = recips, timing = c(prepare = el)),
            class = "pf_prepared")
}

#' Stage 2 — the reference bundle
#'
#' Returns the reference the cascade matches against, with the stage-4 recovery
#' keys ([pf_add_recovery_keys()]) added, so the bundle is complete. This is
#' preprocessing and is excluded from match timings.
#'
#' @section Where the reference comes from:
#' \describe{
#'   \item{`source = "matchdb"`}{A published matchdb reference,
#'     `matchdb::md_reference(tier, fetch = "missing")`: downloaded once from
#'     the public NCCS copy, checked against its md5s and against the installed
#'     npmatch normalizer, and cached under matchdb's data root. Nothing is
#'     built locally.}
#'   \item{`source = "local"`}{The bundle built here from `bmf` by
#'     [pf_build_reference()], cached at `cache`.}
#'   \item{`source = "auto"` (the default)}{A `bmf` given is a request for
#'     that file, so it is honoured: the local bundle, exactly as before.
#'     Without one, matchdb when the package is installed and the tier loads;
#'     otherwise, with a message saying why, the local bundle at `cache`. A
#'     matchdb bundle built by a different npmatch normalizer is refused by
#'     `md_reference()`, so a normalizer update falls back here until the tier
#'     is republished.}
#' }
#'
#' `tier = "active-observed"` is the default because it wins on both axes at
#' once: the `bmf_active` layer with legal, DBA and observed name variants,
#' 2.89M rows, it matched the 1k benchmark in 11.5 min against 23.2 for the
#' augmented BMF pfmatch built for itself, and cleared 63.8% against 62.8%
#' (`dev/BENCH-MD-REFERENCE.log`). `"unified-observed"` is the closer
#' correspondence to the augmented bundle — it adds the inactive tranche, so
#' every BMF release rather than the current one — but that is 1.76M more rows
#' for two and a half times the match time and +0.1 point. Ask for it when the
#' question is grantees that no longer exist, not for the clear rate. The
#' "Choosing a matching dictionary" vignette has the comparison;
#' `matchdb::md_reference()` lists the tiers.
#'
#' @param bmf Processed BMF: a path or a data frame. Needed only for the local
#'   bundle, and only when `cache` does not exist.
#' @param cache Path to cache the local bundle (`.rds`). `NULL` disables caching.
#' @param active_col Optional BMF-active flag column (local bundle only).
#' @param recovery Add acronym / prefix blocking keys to the reference.
#' @param verbose Print progress.
#' @param source `"auto"`, `"matchdb"` or `"local"`; see above.
#' @param tier The matchdb tier. Defaults to
#'   `getOption("pfmatch.matchdb_tier", "active-observed")`.
#' @return A reference bundle: `reference`, `name_freq`, `token_idf`,
#'   `ref_index`, and `source` (`"matchdb"` or `"local"`). A matchdb bundle also
#'   carries `clusters` and its publication `stamp`.
#' @export
pf_reference <- function(bmf = NULL, cache = "data-dev/BMF-REFERENCE-BUNDLE.rds",
                         active_col = NULL, recovery = TRUE, verbose = TRUE,
                         source = c("auto", "matchdb", "local"),
                         tier = getOption("pfmatch.matchdb_tier", "active-observed")) {
  source <- match.arg(source)
  if (source == "auto" && !is.null(bmf)) source <- "local"
  if (source != "local") {
    ref <- .pf_matchdb_reference(tier, recovery, verbose,
                                 required = source == "matchdb")
    if (!is.null(ref)) return(ref)
  }
  .pf_local_reference(bmf, cache, active_col, recovery, verbose)
}

# The matchdb tier, or NULL (with a message) when it cannot be had and the
# caller will fall back. `required` turns every failure into an error.
.pf_matchdb_reference <- function(tier, recovery, verbose, required) {
  fail <- function(why) {
    if (required) stop("matchdb reference ", tier, ": ", why, call. = FALSE)
    message(sprintf("STAGE 2  matchdb reference %s unavailable (%s); using the local bundle",
                    tier, why))
    NULL
  }
  if (!requireNamespace("matchdb", quietly = TRUE)) return(fail("matchdb is not installed"))
  t0 <- .pf_tick()
  .pf_hr(verbose); .pf_say(verbose, "STAGE 2  reference (matchdb %s)", tier)
  ref <- tryCatch(matchdb::md_reference(tier, fetch = "missing", build_index = TRUE),
                  error = function(e) e)
  if (inherits(ref, "error")) return(fail(conditionMessage(ref)))
  if (recovery) ref$reference <- pf_add_recovery_keys(ref$reference)
  ref$source <- "matchdb"
  .pf_say(verbose, "  %s records, spec %s, normalizer %s | elapsed %.1f s",
          format(nrow(ref$reference), big.mark = ","), ref$stamp$spec_hash,
          ref$stamp$normalize_signature, .pf_tick() - t0)
  ref
}

.pf_local_reference <- function(bmf, cache, active_col, recovery, verbose) {
  if (!is.null(cache) && file.exists(cache)) {
    .pf_say(verbose, "STAGE 2  reference (cached: %s)", cache)
    ref <- readRDS(cache)
    ref$source <- "local"
    return(ref)
  }
  if (is.null(bmf)) {
    stop("no reference: the matchdb tier is unavailable, `cache` (", cache %||% "NULL",
         ") does not exist, and no `bmf` was given to build one", call. = FALSE)
  }
  t0 <- .pf_tick()
  .pf_hr(verbose); .pf_say(verbose, "STAGE 2  reference (building)")
  ref <- pf_build_reference(bmf, active_col = active_col)
  if (recovery) ref$reference <- pf_add_recovery_keys(ref$reference)
  .pf_say(verbose, "  %s records | elapsed %.1f s",
          format(nrow(ref$reference), big.mark = ","), .pf_tick() - t0)
  if (!is.null(cache)) {
    if (!dir.exists(dirname(cache))) dir.create(dirname(cache), recursive = TRUE)
    saveRDS(ref, cache, compress = FALSE)
  }
  ref$source <- "local"
  ref
}

#' Stage 3 — run the cascade and propagate to grant rows
#'
#' Wraps [pf_run_batches()] (which applies [pf_drop_self_matches()] per batch)
#' and then [pf_propagate_matches()], so every grant row inherits the result
#' resolved for its identity cluster. Out-of-scope rows are marked `OOS`.
#'
#' @param prepared Output of [pf_prepare()].
#' @param ref Output of [pf_reference()].
#' @param dir Checkpoint directory. Completed batches are skipped on re-run.
#' @param batch_size Identities per checkpoint.
#' @param passes,config,method Passed to [pf_run_batches()].
#' @param dyads Optional dyad table from [pf_build_dyads()]. When supplied, the
#'   substitutable pairs inside each candidate list are collapsed before
#'   selection, which is what removes ties a grant has with itself. `NULL`
#'   disables it. See [pf_dyads] and `dev/DYAD-FINDINGS.md`.
#' @param dyad_config Settings for that collapse; see [pf_dyad_config()].
#' @param resume Reuse checkpoints in `dir` whose run stamp matches this call.
#'   A checkpoint written under different settings stops the run; `resume =
#'   FALSE` recomputes and overwrites. See [pf_run_batches()], *Checkpoints are
#'   stamped*.
#' @param verbose Print progress.
#' @return A list of class `pf_linked` with identity-level `status`, row-level
#'   `grants`, and `timing`.
#' @export
pf_link <- function(prepared, ref, dir = "data-dev/batches", batch_size = 25000L,
                    passes = NULL, config = npmatch::np_config(),
                    method = "hier", dyads = NULL,
                    dyad_config = pf_dyad_config(), resume = TRUE,
                    verbose = TRUE) {
  stopifnot(inherits(prepared, "pf_prepared"))
  t0 <- .pf_tick()
  .pf_hr(verbose); .pf_say(verbose, "STAGE 3  link")
  if (is.null(passes))
    passes <- c(pf_staged_passes("lean"), pf_recovery_passes(state = TRUE))
  if (is.character(dyads) && length(dyads) == 1L) dyads <- readRDS(dyads)
  if (!is.null(dyads))
    .pf_say(verbose, "  dyads: %s pairs, %s substitutable",
            format(nrow(dyads), big.mark = ","),
            format(sum(dyads$dyad_class == "substitutable"), big.mark = ","))

  status <- pf_run_batches(prepared$recipients, ref, dir = dir,
                           batch_size = batch_size, passes = passes,
                           config = config, method = method,
                           dyads = dyads, dyad_config = dyad_config,
                           resume = resume, verbose = verbose)
  g <- pf_propagate_matches(prepared$grants, status)
  g$status[!g$in_scope] <- "OOS"
  if (!is.null(status$dyad_collapsed))
    .pf_say(verbose, "  dyad collapse fired on %s identities (%.1f%%)",
            format(sum(status$dyad_collapsed, na.rm = TRUE), big.mark = ","),
            100 * mean(status$dyad_collapsed, na.rm = TRUE))
  el <- .pf_tick() - t0
  .pf_say(verbose, "  elapsed %.1f s", el)
  structure(list(status = status, grants = g,
                 timing = c(prepared$timing, link = el)), class = "pf_linked")
}

#' Stage 4 — build the adjudication sheet
#'
#' Wraps [pf_bmf_context()], [pf_candidate_frame()], and optionally
#' [pf_purpose_tiebreak()]. Produces the sheet a human or an LLM reviews.
#'
#' The tiebreak is **off by default**. It gains 1 grant and loses 0 of the 6
#' changes we can check against adjudicated truth, out of 75 it makes on a
#' 5,000-grant run — real in direction, unestablished in magnitude. See
#' `dev/PURPOSE-MATCH-FINDINGS.md` §10 before switching it on.
#'
#' @param x A `pf_match` (from [pf_match_grants()]) or a `pf_linked` batch run.
#' @param bmf Processed BMF, for candidate and foundation context.
#' @param ids Grant ids to include. Defaults to every MAYBE.
#' @param k Candidates per grant.
#' @param tiebreak `FALSE`, `TRUE` for defaults, or a [pf_tiebreak_config()].
#' @param org_text Output of [pf_build_org_text()]; required when `tiebreak` is
#'   not `FALSE`.
#' @param verbose Print progress.
#' @return A candidate-level data frame, one row per (grant, candidate).
#' @export
pf_adjudicate <- function(x, bmf, ids = NULL, k = 5, tiebreak = FALSE,
                          org_text = NULL, verbose = TRUE) {
  .pf_hr(verbose); .pf_say(verbose, "STAGE 4  adjudicate")
  if (!identical(tiebreak, FALSE)) {
    if (is.null(org_text))
      stop("tiebreak requires `org_text` from pf_build_org_text().", call. = FALSE)
    cfg <- if (isTRUE(tiebreak)) pf_tiebreak_config() else tiebreak
    x <- pf_purpose_tiebreak(x, org_text, cfg)
  }
  ctx <- pf_bmf_context(bmf)
  out <- pf_candidate_frame(x, ids = ids, k = k, bmf_context = ctx)
  .pf_say(verbose, "  %d candidate rows over %d grants",
          nrow(out), length(unique(out$grant_id)))
  out
}

#' Run the whole pipeline
#'
#' [pf_prepare()] -> [pf_reference()] -> [pf_link()] -> [pf_report()].
#'
#' @param grants,pattern,dedup Passed to [pf_prepare()].
#' @param bmf,ref_cache Passed to [pf_reference()]. With no `bmf`, the reference
#'   is the matchdb tier, falling back to the bundle at `ref_cache`.
#' @param ref_source,tier Passed to [pf_reference()] as `source` and `tier`.
#' @param dir,batch_size,dyads Passed to [pf_link()]. `dyads` may be a table or
#'   a path to a cached one.
#' @param report Print the outcome tables when done.
#' @param verbose Print progress.
#' @param ... Further arguments to [pf_link()].
#' @return A list of class `pf_run` with `grants`, `recipients`, `status`, and
#'   `timing`. The reference bundle is deliberately **not** returned — it is
#'   ~1.3 GB and is on disk (at `ref_cache`, or in matchdb's cache).
#' @export
pf_run <- function(grants, bmf = NULL, pattern = "grants.*[.]csv$",
                   dedup = c("fuzzy", "exact", "none"),
                   ref_cache = "data-dev/BMF-REFERENCE-BUNDLE.rds",
                   dir = "data-dev/batches", batch_size = 25000L,
                   dyads = NULL, report = TRUE, verbose = TRUE,
                   ref_source = c("auto", "matchdb", "local"),
                   tier = getOption("pfmatch.matchdb_tier", "active-observed"), ...) {
  t0 <- .pf_tick()
  prep <- pf_prepare(grants, pattern = pattern, dedup = match.arg(dedup),
                     verbose = verbose)
  ref  <- pf_reference(bmf, cache = ref_cache, verbose = verbose,
                       source = match.arg(ref_source), tier = tier)
  lnk  <- pf_link(prep, ref, dir = dir, batch_size = batch_size,
                  dyads = dyads, verbose = verbose, ...)
  rm(ref); invisible(gc())

  out <- structure(list(grants = lnk$grants, recipients = prep$recipients,
                        status = lnk$status,
                        timing = c(lnk$timing, total = .pf_tick() - t0)),
                   class = "pf_run")
  if (report) print(out)
  invisible(out)
}

#' @export
print.pf_run <- function(x, ...) {
  cat(sprintf("\npf_run: %s grant rows, %s distinct identities\n",
              format(nrow(x$grants), big.mark = ","),
              format(nrow(x$recipients), big.mark = ",")))
  tb <- table(factor(x$grants$status, pf_status_levels()))
  for (s in pf_status_levels())
    cat(sprintf("  %-6s %9s  (%4.1f%%)\n", s, format(tb[[s]], big.mark = ","),
                100 * tb[[s]] / nrow(x$grants)))
  cat(sprintf("  timing: %s\n",
              paste(sprintf("%s=%.1fs", names(x$timing), x$timing), collapse = "  ")))
  invisible(x)
}

#' @export
print.pf_prepared <- function(x, ...) {
  cat(sprintf("pf_prepared: %s rows, %s identities in scope\n",
              format(nrow(x$grants), big.mark = ","),
              format(nrow(x$recipients), big.mark = ",")))
  invisible(x)
}
