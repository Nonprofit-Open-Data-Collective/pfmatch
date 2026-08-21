#' Stage 6 — checkpointed batch driver for the full grant file
#'
#' A 12.5M-row run is measured in tens of hours, so it cannot be a single call
#' that loses everything on an interrupt. This driver splits the work into
#' batches, writes each batch's result to disk as it completes, and skips
#' finished batches on restart.
#'
#' @section What is computed once and shared:
#' The BMF reference — read, normalize, name-frequency table, token IDF, blocking
#' index, and the stage-4 recovery keys — is a function of the reference alone.
#' It is built once and handed to every batch, which is the difference between a
#' 5-minute setup and a 5-minute setup *per batch*.
#'
#' @section Batching by identity, not by row:
#' Batches are formed over deduplicated `recipient_uid` values from [pf_dedup()],
#' so a cluster is never split across batches and every row of a cluster inherits
#' the one match computed for it (see [pf_propagate_matches()]).
#'
#' @name pf_batch_doc
NULL
#' Run the cascade over a large grant file in checkpointed batches
#'
#' @param grants A prepared frame from [pf_prepare_grants()], ideally already
#'   deduplicated by [pf_dedup()] and reduced with [pf_recipients()].
#' @param ref A reference bundle from [pf_build_reference()].
#' @param dir Checkpoint directory. Created if absent.
#' @param batch_size Identities per batch. Smaller batches checkpoint more often
#'   and lose less on an interrupt; larger ones amortise per-batch overhead.
#' @param passes,config,method,recover Passed to [pf_match_grants()].
#' @param self_guard Apply [pf_drop_self_matches()] to each batch.
#' @param dyads Optional dyad table from [pf_build_dyads()]. When given,
#'   [pf_dyad_collapse()] runs on each batch before the status frame is built,
#'   and the status gains `dyad_collapsed`, `dyad_id`, `dyad_alt_ein` and
#'   `dyad_class`. See *Where the collapse runs*.
#' @param dyad_config Settings for that collapse; see [pf_dyad_config()].
#' @param resume Skip batches whose checkpoint file already exists.
#' @param verbose Per-batch progress.
#' @return A data frame: the concatenated per-identity [pf_status()] frames, with
#'   a `batch` column. Timings are attached as `attr(, "timing")`.
#'
#' @section Where the collapse runs:
#' Between [pf_drop_self_matches()] and [pf_status()], because that is the only
#' point at which the scored pairs still exist — the status frame keeps just the
#' winning candidate. Collapsing is resolved **within one grant's candidate list
#' only**, so a per-batch collapse is identical to a whole-file one; batching
#' cannot change the answer. Changing `dyads` or `dyad_config` invalidates the
#' checkpoints in `dir`, which `resume` will otherwise happily reuse.
#' @export
pf_run_batches <- function(grants, ref, dir = "data-dev/batches",
                           batch_size = 25000L,
                           passes = c(pf_staged_passes("lean"),
                                      pf_recovery_passes(state = TRUE)),
                           config = npmatch::np_config(), method = "hier",
                           recover = TRUE, self_guard = TRUE,
                           dyads = NULL, dyad_config = pf_dyad_config(),
                           resume = TRUE, verbose = TRUE) {
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
  say <- function(...) if (verbose) cat(sprintf(...), "\n")
  n <- nrow(grants)
  idx <- split(seq_len(n), ceiling(seq_len(n) / batch_size))
  say("pf_run_batches: %s rows in %d batches of %s",
      format(n, big.mark = ","), length(idx), format(batch_size, big.mark = ","))
  # Build the recovery keys on the reference ONCE rather than per batch --
  # pf_match_grants() would otherwise rebuild them for every call.
  if (recover && is.null(ref$reference$name_acro)) {
    t0 <- proc.time()[["elapsed"]]
    ref$reference <- pf_add_recovery_keys(ref$reference)
    say("  built stage-4 reference keys once (%.1f s)", proc.time()[["elapsed"]] - t0)
  }
  timing <- numeric(0)
  out <- vector("list", length(idx))
  for (b in seq_along(idx)) {
    f <- file.path(dir, sprintf("batch-%04d.rds", b))
    if (resume && file.exists(f)) {
      out[[b]] <- readRDS(f)
      say("  [%3d/%3d] cached (%s rows)", b, length(idx), format(nrow(out[[b]]), big.mark = ","))
      next
    }
    sub <- grants[idx[[b]], , drop = FALSE]
    ok <- tryCatch({
      t0 <- proc.time()[["elapsed"]]
      m <- pf_match_grants(sub, ref, config = config, method = method,
                           passes = passes, recover = recover, verbose = FALSE)
      if (self_guard) m <- pf_drop_self_matches(m, verbose = FALSE)
      # The dyad collapse has to run HERE. It needs the scored pairs, and
      # pf_status() is where they stop being available -- the status frame keeps
      # only the winning candidate. Collapsing is resolved strictly within one
      # grant's candidate list, so doing it per batch gives the same answer as
      # doing it over the whole file.
      if (!is.null(dyads))
        m <- suppressMessages(pf_dyad_collapse(m, dyads, dyad_config,
                                               np_config = config))
      st <- pf_status(m)
      if (!is.null(dyads)) st <- .pf_attach_dyad_cols(st, m)
      st$batch <- b
      el <- proc.time()[["elapsed"]] - t0
      timing <<- c(timing, el)
      saveRDS(st, f, compress = FALSE)   # write only after the batch succeeded
      out[[b]] <- st
      tb <- table(factor(st$status, pf_status_levels()))
      say("  [%3d/%3d] %6s rows | YES %5d MAYBE %5d NO %5d OOS %4d | %6.1f s (%.1f s/1k)",
          b, length(idx), format(nrow(st), big.mark = ","),
          tb[["YES"]], tb[["MAYBE"]], tb[["NO"]], tb[["OOS"]],
          el, el / nrow(st) * 1000)
      TRUE
    }, error = function(e) { say("  [%3d/%3d] FAILED: %s", b, length(idx), conditionMessage(e)); FALSE })
    # a failed batch leaves no checkpoint, so a later resume retries just that one
    if (!ok) out[[b]] <- NULL
  }
  done <- !vapply(out, is.null, logical(1))
  if (!any(done)) stop("every batch failed; nothing to return.", call. = FALSE)
  if (!all(done)) say("WARNING: %d batch(es) failed and were skipped; re-run to retry",
                      sum(!done))
  res <- as.data.frame(data.table::rbindlist(out[done], fill = TRUE))
  attr(res, "timing") <- timing
  attr(res, "n_batches") <- length(idx)
  attr(res, "n_failed") <- sum(!done)
  res
}
#' Summarize a batched run
#'
#' @param status The frame returned by [pf_run_batches()].
#' @return Invisibly, the outcome table. Prints a summary with throughput.
pf_batch_report <- function(status) {
  tb <- table(factor(status$status, pf_status_levels()))
  el <- attr(status, "timing")
  cat(sprintf("identities matched .... %s over %d batches (%d failed)\n",
              format(nrow(status), big.mark = ","), attr(status, "n_batches"),
              attr(status, "n_failed") %||% 0L))
  for (s in pf_status_levels())
    cat(sprintf("  %-6s %8d  (%4.1f%%)\n", s, tb[[s]], 100 * tb[[s]] / nrow(status)))
  att <- nrow(status) - tb[["OOS"]]
  cat(sprintf("  match rate on attempted: %.1f%% YES, %.1f%% YES+MAYBE\n",
              100 * tb[["YES"]] / att, 100 * (tb[["YES"]] + tb[["MAYBE"]]) / att))
  if (length(el)) {
    cat(sprintf("\nruntime: %.1f h total, %.1f s per 1,000 identities\n",
                sum(el) / 3600, sum(el) / nrow(status) * 1000))
    cat(sprintf("  slowest batch %.0f s | fastest %.0f s\n", max(el), min(el)))
  }
  invisible(tb)
}
`%||%` <- function(a, b) if (is.null(a)) b else a

# pf_status() builds a fixed set of columns, so the dyad audit trail has to be
# joined back on afterwards or it is lost at the batch boundary. `dyad_alt_ein`
# is the partner that was merged away: an analyst aggregating grants to a
# recipient needs it whether or not the collapse changed the reported EIN.
.pf_attach_dyad_cols <- function(st, m) {
  res <- as.data.frame(m$result)
  i <- match(st$grant_id, res$.id)
  st$dyad_collapsed <- !is.na(i) & (res$dyad_collapsed[i] %in% TRUE)
  for (col in c("dyad_id", "dyad_from_ein")) {
    v <- if (!is.null(res[[col]])) res[[col]][i] else NA_character_
    st[[col]] <- v
  }
  st
}
