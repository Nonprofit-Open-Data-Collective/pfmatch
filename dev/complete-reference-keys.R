# Complete data-dev/REF-augmented.rds with the stage-4 recovery keys.
#
# The bundle is missing name_acro, name_pre and name_is_acro. pf_reference()
# adds them on the line before it saves, so a bundle built through the package
# always carries them; this one was built on 2026-11-02 by an ad-hoc script that
# called pf_build_reference() and saveRDS() directly and skipped that line.
# Nothing reported it, because pf_run_batches() rebuilds them in flight and
# charged the run 197.5 s for doing so (dev/REF-REBUILD-20261103.log). Any
# caller that reads the bundle WITHOUT going through pf_run_batches() or
# pf_match_grants(recover = TRUE) blocks D1-acronym and D2-prefix on columns
# that are not there, and gets an empty pass rather than an error.
#
# No rebuild is needed: all three are a pure function of name_key
# (R/recover.R), so they are computed from the bundle's own column. That is
# only valid under the normalizer that produced that column, which is checked
# against the bundle's stamp before anything is written.
#
# This script is in the repo, and the one that dropped the columns was not.
# That is the other half of the fix: a bundle whose build cannot be re-run is
# not reproducible, whatever it happens to contain.
#
# Rscript dev/complete-reference-keys.R

suppressMessages(devtools::load_all(".", quiet = TRUE))
say <- function(...) { cat(sprintf(...), "\n", sep = ""); flush.console() }
gb  <- function(f) file.size(f) / 2^30
mins <- function(t0) as.numeric(difftime(Sys.time(), t0, units = "mins"))

RDS <- "data-dev/REF-augmented.rds"
TMP <- "data-dev/REF-augmented-COMPLETING.rds"
PASSES <- c(pf_staged_passes("lean"), pf_recovery_passes(state = TRUE))
KEYS <- c("name_acro", "name_pre", "name_is_acro")

complete_reference_keys <- function() {
  t_all <- Sys.time()
  say(strrep("=", 78))
  say("complete-reference-keys   %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
  say(strrep("=", 78))
  say("npnormalize %s, npmatch %s", utils::packageVersion("npnormalize"),
      utils::packageVersion("npmatch"))

  if (file.exists(TMP))
    stop(TMP, " already exists -- a previous run did not finish. Inspect it, ",
         "then delete it.", call. = FALSE)

  t0 <- Sys.time()
  say("")
  say("reading %s (%.2f GB) ...", RDS, gb(RDS))
  ref <- readRDS(RDS)
  n0 <- nrow(ref$reference)
  say("  %s rows, %d reference columns, read in %.1f min",
      format(n0, big.mark = ","), ncol(ref$reference), mins(t0))

  # --- the keys are normalizer-derived, so the stamp has to agree -----------
  sig  <- pfmatch:::.pf_ref_signature(ref)
  live <- npmatch::np_normalize_signature()
  say("  bundle stamp : %s", if (is.null(sig)) "(none)" else sig)
  say("  installed    : %s", live)
  if (is.null(sig))
    stop("this bundle carries no normalizer stamp, so name_key cannot be shown ",
         "to be current. Rebuild it with pf_reference() instead.", call. = FALSE)
  if (!identical(as.character(sig)[1], live))
    stop("the installed normalizer is not the one that built this bundle.\n",
         "  name_acro, name_pre and name_is_acro are derived from name_key, so\n",
         "  computing them now would pair current rules with stale keys.\n",
         "  Install ", sig, " first, or rebuild the bundle.", call. = FALSE)

  if (!is.null(ref$reference$name_acro)) {
    say("")
    say("name_acro is already present -- nothing to do.")
    return(invisible(FALSE))
  }

  # --- add them ------------------------------------------------------------
  say("")
  t0 <- Sys.time()
  say("adding %s ...", paste(KEYS, collapse = ", "))
  ref$reference <- pf_add_recovery_keys(ref$reference)
  say("  done in %.1f min, %d reference columns now", mins(t0),
      ncol(ref$reference))
  stopifnot(nrow(ref$reference) == n0, all(KEYS %in% names(ref$reference)))

  t0 <- Sys.time()
  say("writing %s ...", TMP)
  saveRDS(ref, TMP, compress = FALSE)
  say("  %.2f GB in %.1f min", gb(TMP), mins(t0))
  rm(ref); invisible(gc())

  # --- VERIFY FROM DISK ----------------------------------------------------
  # The Nov-2 build verified what it held in memory. What it wrote is what
  # every later run reads, and the two are the same only if nothing went wrong
  # between them, which is exactly what a verification is for.
  say("")
  say(strrep("=", 78))
  say("VERIFY (re-read from disk)")
  say(strrep("=", 78))
  t0 <- Sys.time()
  back <- readRDS(TMP)
  say("re-read in %.1f min", mins(t0))

  ok <- function(label, pass, detail = "") {
    say("  %-5s %-26s %s", if (pass) "PASS" else "FAIL", label, detail)
    if (!pass) stop("verification failed on: ", label, call. = FALSE)
  }
  ok("rows unchanged", nrow(back$reference) == n0,
     format(nrow(back$reference), big.mark = ","))
  ok("stamp unchanged",
     identical(as.character(pfmatch:::.pf_ref_signature(back))[1], live), live)
  ok("recovery keys present", all(KEYS %in% names(back$reference)),
     paste(KEYS, collapse = ", "))
  ok("companions present",
     all(vapply(c("name_freq", "token_idf", "ref_index"),
                function(e) !is.null(back[[e]]), logical(1))),
     "name_freq, token_idf, ref_index")

  # Recompute the three on a random sample and compare. This is the check that
  # the saved values are the ones pf_add_recovery_keys() produces, rather than
  # merely three columns of the right names.
  set.seed(20261103)
  i <- sort(sample.int(nrow(back$reference), min(100000L, nrow(back$reference))))
  chk <- pf_add_recovery_keys(
    data.frame(name_key = back$reference$name_key[i], stringsAsFactors = FALSE))
  for (k in KEYS)
    ok(paste("recomputes:", k), identical(back$reference[[k]][i], chk[[k]]),
       sprintf("%s rows sampled", format(length(i), big.mark = ",")))

  pf_check_reference(back, "stop")
  ok("pf_check_reference", TRUE, "accepted")

  sch <- pf_check_schema(back, passes = PASSES, verbose = FALSE)
  nf <- sum(sch$status == "FAIL"); nw <- sum(sch$status == "WARN")
  if (nf || nw) {
    bad <- sch[sch$status %in% c("WARN", "FAIL"), , drop = FALSE]
    for (j in seq_len(nrow(bad)))
      say("  %-5s %-26s %s", bad$status[j], bad$check[j], bad$detail[j])
  }
  ok("pf_check_schema", nf == 0L && nw == 0L,
     sprintf("%d passes, 0 FAIL, 0 WARN", sum(grepl("^[A-D][0-9]", sch$check))))
  rm(back); invisible(gc())

  # --- swap ----------------------------------------------------------------
  # Only now. The outgoing bundle is not kept: these three columns are
  # derivable from a column that has not changed, so a copy of the bundle
  # without them has nothing in it this one lacks.
  say("")
  say(strrep("=", 78))
  say("SWAP")
  say(strrep("=", 78))
  if (!file.rename(TMP, RDS))
    stop("could not rename ", TMP, " over ", RDS, " -- both are on disk and ",
         "the old bundle is intact.", call. = FALSE)
  say("%s is now the completed bundle, %.2f GB", RDS, gb(RDS))
  say("")
  say("done in %.1f min", mins(t_all))
  invisible(TRUE)
}

complete_reference_keys()
