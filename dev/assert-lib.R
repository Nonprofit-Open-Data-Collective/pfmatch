#!/usr/bin/env Rscript
# ============================================================================
# assert-lib.R -- the three one-line checks that would have stopped defects
# 5, 6 and 7 in dev/PLAUSIBLE-WRONG-NUMBERS.md. Issue #15, proposal 1.
#
# Not a script when sourced: sourcing it runs nothing. Running it runs the
# self-check at the bottom.
#
# WHAT THIS IS FOR. The dominant defect class on this project is a number that
# is wrong and looks right, and three of the seven catalogued instances reduce
# to a check that is one line and was absent:
#
#   need_cols()    the column exists                          (defect 5)
#   need_levels()  the level exists, before filtering on it    (defects 6, 7)
#   need_rows()    the denominator is the population you think (defect 6)
#
# with two more that fall out of them:
#
#   need_vocab()   no level OUTSIDE the set the code handles -- the other
#                  direction of defect 6, for an enum that moves underneath
#   keep_level()   the level check and the filter in one line
#
# WHY A STOP AND NOT A WARNING. Each of these failures is silent by
# construction -- `d$typo` is NULL, `sum(NULL %in% TRUE)` is 0, and
# `x != "ABSENT_LEVEL"` is TRUE for every row. A warning scrolls past in a run
# log that is already hundreds of lines long; the run then prints a well-formed
# table and the number gets published. These stop, and say which figure below
# them is not to be read.
#
# WHY THE MESSAGES ARE LONG. The guard fires in a 400-line measurement script
# at an hour's remove from the mistake. Naming the near-miss column, or the
# levels the data actually carries, is the difference between the message and a
# second debugging session: defect 5 was a frame that DID carry the column,
# under a merge suffix, and the useful message is the one that says so.
#
# WHY NOT stopifnot(). It is one line too, and stopifnot(!is.null(a$ein_o)) at
# dev/adjudicate-15-no-arms.R:92 is what caught defect 5 once it was suspected.
# What it cannot do is tell you what the frame holds instead, and it has no
# form at all for the level check -- which is the half of this class that
# produced 6 and 7.
#
# USAGE  source(file.path(PF, "dev", "assert-lib.R"))
#        Rscript dev/assert-lib.R      # self-check against the real defects
# ============================================================================

# Columns whose name is close enough to `k` to be what the caller meant. The
# merge-suffix family comes first, since that is defect 5's shape.
.near_cols <- function(k, have) {
  stem <- sub("_[A-Za-z0-9]+$", "", have)
  unique(c(have[stem == k],                      # ein_in_ref -> ein_in_ref_o
           have[startsWith(have, k)],            # a longer name sharing the head
           have[tolower(have) == tolower(k)]))   # differs only in case
}

.what <- function(what) if (is.null(what)) "" else sprintf(" [%s]", what)

#' Every named column is present
#'
#' @param d A data.frame or data.table.
#' @param ... Column names, as strings or a character vector.
#' @param what What the columns are being read FOR, named in the message.
#' @return `d`, invisibly, so a call can wrap the frame it guards.
need_cols <- function(d, ..., what = NULL) {
  want <- unlist(list(...), use.names = FALSE)
  have <- names(d)
  gone <- vapply(want, function(k) !k %in% have || is.null(d[[k]]), logical(1))
  miss <- want[gone]
  if (length(miss)) {
    hint <- vapply(miss, function(k) {
      n <- setdiff(.near_cols(k, have), k)
      if (length(n)) sprintf("    %-28s did you mean: %s", k, paste(n, collapse = ", "))
      else           sprintf("    %-28s no column resembles it", k)
    }, character(1))
    stop(sprintf(paste0(
      "need_cols%s: %d of %d columns absent from a frame of %d rows.\n%s\n",
      "  Reading an absent column returns NULL, not an error, and\n",
      "  sum(NULL %%in%% TRUE) is 0 -- the figure below would have read as a\n",
      "  zero count rather than failing. Do not read it.\n",
      "  (defect 5, dev/PLAUSIBLE-WRONG-NUMBERS.md)"),
      .what(what), length(miss), length(want), nrow(d),
      paste(hint, collapse = "\n")), call. = FALSE)
  }
  invisible(d)
}

#' Every expected level actually occurs, before anything filters on it
#'
#' The guard for a filter against a label that is not there -- which selects
#' every row under `!=` and no rows under `==`, and complains in neither case.
#'
#' @param x A column, or any vector. Factors are compared as characters.
#' @param expect The label(s) the code is about to filter on.
#' @param what What the filter is FOR, named in the message.
#' @return The observed level counts, invisibly.
need_levels <- function(x, expect, what = NULL) {
  tab <- table(as.character(x), useNA = "no")
  lv  <- names(tab)
  seen <- if (length(lv))
    paste(sprintf("%s (%d)", lv, as.integer(tab)), collapse = ", ") else "none"
  gone <- setdiff(as.character(expect), lv)
  if (length(gone))
    stop(sprintf(paste0(
      "need_levels%s: no row carries %s.\n",
      "  observed in %d non-missing values: %s\n",
      "  A filter on an absent label is silent in both directions: `!=` keeps\n",
      "  every row and `==` keeps none, so the figure below is computed over\n",
      "  the wrong population rather than erroring. Do not read it.\n",
      "  (defects 6 and 7, dev/PLAUSIBLE-WRONG-NUMBERS.md)"),
      .what(what), paste(sprintf("`%s`", gone), collapse = ", "),
      sum(tab), seen), call. = FALSE)
  invisible(tab)
}

#' No level outside the set the code knows how to handle
#'
#' The other direction of defect 6, and a different assertion from
#' [need_levels()] rather than a variant of it: this one does NOT require every
#' allowed level to be populated, because a run on a smaller grant file
#' legitimately has empty tiers. What it catches is the level that should not
#' be there at all -- an enum extended upstream, or a convention swapped under
#' the code reading it, which is how a share stops covering its own frame.
#'
#' @param x A column, or any vector.
#' @param allowed Every level the code below handles.
#' @param what What the vocabulary belongs to, named in the message.
#' @return The observed level counts, invisibly.
need_vocab <- function(x, allowed, what = NULL) {
  tab <- table(as.character(x), useNA = "no")
  extra <- setdiff(names(tab), as.character(allowed))
  if (length(extra))
    stop(sprintf(paste0(
      "need_vocab%s: %s outside the handled set.\n",
      "  handled : %s\n  observed: %s\n",
      "  Every comparison below names its levels literally, so a level the\n",
      "  code does not mention is silently excluded from all of them -- the\n",
      "  shares still sum to something, over a smaller frame than the one\n",
      "  reported. Do not read them.\n",
      "  (defect 6, dev/PLAUSIBLE-WRONG-NUMBERS.md)"),
      .what(what), paste(sprintf("`%s`", extra), collapse = ", "),
      paste(allowed, collapse = ", "),
      paste(sprintf("%s (%d)", names(tab), as.integer(tab)), collapse = ", ")),
      call. = FALSE)
  invisible(tab)
}

#' The denominator is the population you think it is
#'
#' The cheapest integrity check available, and free on every table. Defect 6
#' was caught by nothing cleverer than noticing that a table of "the cases the
#' BMF should not hold" had 91 rows where that population is 57.
#'
#' @param d A frame, or a count.
#' @param n Exact expected row count, where it is known independently.
#' @param min,max Bounds, where it is not. `min = 1L` is the empty-stratum guard.
#' @param what What the population IS, named in the message.
#' @return `d`, invisibly.
need_rows <- function(d, n = NULL, min = NULL, max = NULL, what = NULL) {
  k <- if (is.null(dim(d))) as.integer(d) else nrow(d)
  bad <- function(fmt, ...) stop(sprintf(paste0(
    "need_rows%s: %s\n",
    "  A figure over the wrong denominator is still a well-formed figure.\n",
    "  (defect 6, dev/PLAUSIBLE-WRONG-NUMBERS.md)"),
    .what(what), sprintf(fmt, ...)), call. = FALSE)
  if (!is.null(n)   && k != n)   bad("%d rows, expected exactly %d.", k, n)
  if (!is.null(min) && k <  min) bad("%d rows, expected at least %d.", k, min)
  if (!is.null(max) && k >  max) bad("%d rows, expected at most %d.", k, max)
  invisible(d)
}

#' Filter to a level, having first proven the level is there
#'
#' The two checks in one line, for the shape that produced both 6 and 7:
#' `d[col == "LABEL"]` where the label is misremembered. Prints the denominator
#' it kept, because practice 4 is free here.
#'
#' @param d A data.frame or data.table.
#' @param col One column name.
#' @param level The level(s) to keep.
#' @param what What the subset IS, named in the message and the printed line.
#' @param quiet Suppress the kept-rows line.
#' @return The subset, same class as `d`.
keep_level <- function(d, col, level, what = NULL, quiet = FALSE) {
  need_cols(d, col, what = what)
  need_levels(d[[col]], level, what = what)
  keep <- as.character(d[[col]]) %in% as.character(level)
  out  <- if (inherits(d, "data.table")) d[which(keep)] else d[which(keep), , drop = FALSE]
  if (!quiet)
    cat(sprintf("guard: %s in %s keeps %d of %d rows%s\n", col,
                paste(level, collapse = "/"), nrow(out), nrow(d),
                if (is.null(what)) "" else sprintf("  (%s)", what)))
  out
}

# ---------------------------------------------------------------------------
# Self-check. Practice 6: a guard that only the guarded code tests is not a
# guard. Each case below reconstructs one of the three defects in miniature at
# its real size, prints the number the defect reported, and then shows the
# guard stopping it.
#
#   Rscript dev/assert-lib.R
# ---------------------------------------------------------------------------
if (sys.nframe() == 0L) {

  fails <- 0L
  ok <- function(label, expr, expect_stop = TRUE) {
    e <- tryCatch({ force(expr); NULL }, error = function(e) e)
    good <- if (expect_stop) !is.null(e) else is.null(e)
    if (!good) fails <<- fails + 1L
    cat(sprintf("%-4s %s\n", if (good) "ok" else "FAIL", label))
    if (!is.null(e))
      cat(paste0("       ", gsub("\n", "\n       ", conditionMessage(e)), "\n"))
    invisible(NULL)
  }

  cat(strrep("=", 78), "\n")
  cat("assert-lib self-check: each guard against the defect it is for\n")
  cat(strrep("=", 78), "\n")

  ## defect 5 -- merge(suffixes=) renames only the columns both frames share,
  ## so the Opus side of a shared column is ein_in_ref_o. Reading the
  ## unsuffixed name reported "Opus recoverable: 0 of 91". It was 33 of 91.
  o <- data.frame(grant_id = sprintf("G%03d", 1:91),
                  ein_in_ref = c(rep(TRUE, 33), rep(FALSE, 58)))
  h <- data.frame(grant_id = sprintf("G%03d", 1:91), ein_in_ref = rep(FALSE, 91))
  d5 <- merge(o, h, by = "grant_id", suffixes = c("_o", "_h"))
  cat(sprintf("\ndefect 5: the unguarded line reports %d of %d; the truth is 33 of 91\n",
              sum(d5$ein_in_ref %in% TRUE), nrow(d5)))
  ok("need_cols() stops on the unsuffixed name, and names the suffixed pair",
     need_cols(d5, "ein_in_ref", what = "recoveries"))
  ok("need_cols() passes on the names the merge actually produced",
     need_cols(d5, "ein_in_ref_o", "ein_in_ref_h", what = "recoveries"),
     expect_stop = FALSE)
  stopifnot(sum(d5$ein_in_ref_o %in% TRUE) == 33L)

  ## defect 6 -- the risk table filtered bmf_expectation != "IN_BMF", a level
  ## that does not exist, so it matched all 91 rows. The population is 57.
  d6 <- data.frame(grant_id = sprintf("G%03d", 1:91),
                   bmf_expectation = c(rep("LISTED", 34), rep("NOT_LISTED", 40),
                                       rep("UNCERTAIN", 17)))
  cat(sprintf("\ndefect 6: != \"IN_BMF\" selects %d of %d rows; the population is 57\n",
              sum(d6$bmf_expectation != "IN_BMF"), nrow(d6)))
  ok("need_levels() stops on the label that is not there, and lists the ones that are",
     need_levels(d6$bmf_expectation, "IN_BMF", what = "false-positive risk"))
  ok("need_levels() passes on the label the enum really uses",
     need_levels(d6$bmf_expectation, "LISTED", what = "false-positive risk"),
     expect_stop = FALSE)
  ok("need_rows() stops when the denominator is not the population",
     need_rows(d6[d6$bmf_expectation != "IN_BMF", ], n = 57L, what = "not-listed cases"))
  ok("need_vocab() catches the level the code below does not handle",
     need_vocab(d6$bmf_expectation, c("LISTED", "NOT_LISTED"),
                what = "bmf_expectation enum"))
  ok("need_vocab() does not require an allowed level to be populated",
     need_vocab(d6$bmf_expectation, c("LISTED", "NOT_LISTED", "UNCERTAIN", "WITHDRAWN"),
                what = "bmf_expectation enum"),
     expect_stop = FALSE)

  ## defect 7 -- the stratum label is A-estimation, and == "A" returned an
  ## empty frame rather than the 91 rows that are there.
  d7 <- data.frame(grant_id = sprintf("G%03d", 1:120),
                   stratum = c(rep("A-estimation", 91), rep("B-audit", 29)))
  cat(sprintf("\ndefect 7: == \"A\" keeps %d rows; the stratum holds 91\n",
              sum(d7$stratum == "A")))
  ok("keep_level() stops on the truncated label rather than returning nothing",
     keep_level(d7, "stratum", "A", what = "stratum A"))
  ok("need_rows(min=1) is the empty-stratum guard",
     need_rows(d7[d7$stratum == "A", ], min = 1L, what = "stratum A"))
  a <- keep_level(d7, "stratum", "A-estimation", what = "stratum A")
  ok("keep_level() keeps the 91 rows under the real label",
     need_rows(a, n = 91L, what = "stratum A"), expect_stop = FALSE)

  ## the frame type the dev scripts actually carry these in
  if (requireNamespace("data.table", quietly = TRUE)) {
    dt <- data.table::as.data.table(d7)
    b  <- keep_level(dt, "stratum", "A-estimation", what = "stratum A (data.table)")
    ok("keep_level() returns a data.table for a data.table, with the same rows",
       stopifnot(data.table::is.data.table(b), nrow(b) == 91L),
       expect_stop = FALSE)
  } else {
    cat("skip: data.table not installed, so the data.table path is unchecked\n")
  }

  cat(sprintf("\n%s\n%d failures\n", strrep("=", 78), fails))
  if (fails) quit(status = 1L)
}
