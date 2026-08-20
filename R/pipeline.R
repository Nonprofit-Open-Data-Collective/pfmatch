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

#' Stage 2 — the BMF reference bundle
#'
#' Wraps [pf_build_reference()] with an on-disk cache and adds the stage-4
#' recovery keys ([pf_add_recovery_keys()]), so the bundle handed to the cascade
#' is complete. This is preprocessing and is excluded from match timings.
#'
#' @param bmf Processed BMF: a path or a data frame.
#' @param cache Path to cache the bundle (`.rds`). `NULL` disables caching.
#' @param active_col Optional BMF-active flag column.
#' @param recovery Add acronym / prefix blocking keys to the reference.
#' @param verbose Print progress.
#' @return The reference bundle list from [pf_build_reference()].
#' @export
pf_reference <- function(bmf, cache = "data-dev/BMF-REFERENCE-BUNDLE.rds",
                         active_col = NULL, recovery = TRUE, verbose = TRUE) {
  if (!is.null(cache) && file.exists(cache)) {
    .pf_say(verbose, "STAGE 2  reference (cached: %s)", cache)
    return(readRDS(cache))
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
#' @param verbose Print progress.
#' @return A list of class `pf_linked` with identity-level `status`, row-level
#'   `grants`, and `timing`.
#' @export
pf_link <- function(prepared, ref, dir = "data-dev/batches", batch_size = 25000L,
                    passes = NULL, config = npmatch::np_config(),
                    method = "hier", verbose = TRUE) {
  stopifnot(inherits(prepared, "pf_prepared"))
  t0 <- .pf_tick()
  .pf_hr(verbose); .pf_say(verbose, "STAGE 3  link")
  if (is.null(passes))
    passes <- c(pf_staged_passes("lean"), pf_recovery_passes(state = TRUE))

  status <- pf_run_batches(prepared$recipients, ref, dir = dir,
                           batch_size = batch_size, passes = passes,
                           config = config, method = method, verbose = verbose)
  g <- pf_propagate_matches(prepared$grants, status)
  g$status[!g$in_scope] <- "OOS"
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
#' @param bmf,ref_cache Passed to [pf_reference()].
#' @param dir,batch_size Passed to [pf_link()].
#' @param report Print the outcome tables when done.
#' @param verbose Print progress.
#' @param ... Further arguments to [pf_link()].
#' @return A list of class `pf_run` with `grants`, `recipients`, `status`, and
#'   `timing`. The reference bundle is deliberately **not** returned — it is
#'   ~1.3 GB and is on disk at `ref_cache`.
#' @export
pf_run <- function(grants, bmf, pattern = "grants.*[.]csv$",
                   dedup = c("fuzzy", "exact", "none"),
                   ref_cache = "data-dev/BMF-REFERENCE-BUNDLE.rds",
                   dir = "data-dev/batches", batch_size = 25000L,
                   report = TRUE, verbose = TRUE, ...) {
  t0 <- .pf_tick()
  prep <- pf_prepare(grants, pattern = pattern, dedup = match.arg(dedup),
                     verbose = verbose)
  ref  <- pf_reference(bmf, cache = ref_cache, verbose = verbose)
  lnk  <- pf_link(prep, ref, dir = dir, batch_size = batch_size,
                  verbose = verbose, ...)
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
