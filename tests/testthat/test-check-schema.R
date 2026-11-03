# A reference that is missing a blocking column produces an empty pass, not an
# error. These tests pin the three things that makes bearable: the required
# columns come off the pass specs rather than a hand-kept list, a derived column
# is a warning while a source column is fatal, and the run refuses to start
# when a pass could not possibly fire.

ref_cols <- function() c("name_key", "dba_key", "street_key", "zip5", "state",
                         "name_acro", "name_pre", "name_is_acro")

fake_ref <- function(cols = ref_cols(), stamp = TRUE, companions = TRUE) {
  d <- as.data.frame(stats::setNames(
    replicate(length(cols), c("a", "b"), simplify = FALSE), cols),
    stringsAsFactors = FALSE)
  out <- list(reference = d)
  if (companions) {
    out$name_freq <- 1L
    out$token_idf <- 1L
    out$ref_index <- list(token_col = "name_key")
  }
  if (isTRUE(stamp))
    out$normalizer <- tryCatch(npmatch::np_normalize_signature(),
                               error = function(e) "v1-test")
  else if (is.character(stamp)) out$normalizer <- stamp
  out
}

lean <- function() c(pf_staged_passes("lean"), pf_recovery_passes(state = TRUE))

status_of <- function(out, check) out$status[match(check, out$check)]

# ---------------------------------------------------------------------------
# the required columns are read off the specs
# ---------------------------------------------------------------------------

test_that(".pf_pass_columns reads by, by_x / by_y and token_col", {
  p <- lean()
  y <- pfmatch:::.pf_pass_columns(p, side = "y")
  x <- pfmatch:::.pf_pass_columns(p, side = "x")

  # A3 joins the query's name to the reference's dba, so the two sides differ
  expect_setequal(y[["A3-name-dba"]], c("state", "dba_key"))
  expect_setequal(x[["A3-name-dba"]], c("state", "name_key"))
  # ... and A4 is the mirror of it
  expect_setequal(y[["A4-dba-name"]], c("state", "name_key"))
  expect_setequal(x[["A4-dba-name"]], c("state", "dba_key"))

  # a token pass with no token_col falls back to np_block()'s own default
  expect_setequal(y[["B1-token-state"]], c("state", "name_key"))
  # ... and one that names a column uses it
  expect_setequal(y[["D1-acronym"]], c("state", "name_acro"))
  # D2 blocks on the prefix and ZIP5 with no `by`
  expect_setequal(y[["D2-prefix"]], c("name_pre", "zip5"))
})

test_that("a pass added to the spec is picked up without touching the check", {
  extra <- list(list(name = "Z9-invented", desc = "made up",
                     args = list(by = NULL, by_x = "name_key",
                                 by_y = "no_such_column", token = FALSE)))
  out <- pf_check_schema(fake_ref(), passes = extra, verbose = FALSE)
  expect_equal(status_of(out, "Z9-invented"), "FAIL")
  expect_match(out$detail[out$check == "Z9-invented"], "no_such_column absent")
})

# ---------------------------------------------------------------------------
# a complete bundle
# ---------------------------------------------------------------------------

test_that("a complete, stamped bundle passes every check", {
  out <- pf_check_schema(fake_ref(), passes = lean(), verbose = FALSE)
  expect_equal(sum(out$status == "FAIL"), 0L)
  expect_equal(sum(out$status == "WARN"), 0L)
  expect_equal(status_of(out, "normalizer stamp"), "PASS")
  expect_true(all(c("A1-name-zip5", "D1-acronym", "D2-prefix") %in% out$check))
})

test_that("the report names the release beside the signature", {
  skip_if_not(is.data.frame(tryCatch(npnormalize::np_signature_history(),
                                     error = function(e) NULL)))
  out <- pf_check_schema(fake_ref(), passes = lean(), verbose = FALSE)
  # not a bare hash: the release that introduced it is named
  expect_match(out$detail[out$check == "normalizer stamp"], "npnormalize")
})

# ---------------------------------------------------------------------------
# severity: derived columns are repairable, source columns are not
# ---------------------------------------------------------------------------

test_that("missing recovery keys warn when the run will rebuild them", {
  r <- fake_ref(setdiff(ref_cols(), c("name_acro", "name_pre", "name_is_acro")))
  out <- pf_check_schema(r, passes = lean(), recover = TRUE, verbose = FALSE)
  expect_equal(status_of(out, "D1-acronym"), "WARN")
  expect_equal(status_of(out, "D2-prefix"), "WARN")
  expect_equal(sum(out$status == "FAIL"), 0L)
  expect_match(out$detail[out$check == "D1-acronym"], "saved bundle is incomplete")
  # the state-blocked exact passes are untouched by their absence
  expect_equal(status_of(out, "A1-name-zip5"), "PASS")
})

test_that("the same absence is fatal when nothing will rebuild them", {
  r <- fake_ref(setdiff(ref_cols(), c("name_acro", "name_pre", "name_is_acro")))
  out <- pf_check_schema(r, passes = lean(), recover = FALSE, verbose = FALSE)
  expect_equal(status_of(out, "D1-acronym"), "FAIL")
  expect_equal(status_of(out, "D2-prefix"), "FAIL")
  expect_match(out$detail[out$check == "D1-acronym"], "recover = FALSE")
})

test_that("a missing source column is fatal however recover is set", {
  r <- fake_ref(setdiff(ref_cols(), "dba_key"))
  for (rc in c(TRUE, FALSE)) {
    out <- pf_check_schema(r, passes = lean(), recover = rc, verbose = FALSE)
    expect_equal(status_of(out, "A3-name-dba"), "FAIL")
    expect_equal(status_of(out, "C2-dba-any"), "FAIL")
    # and the name passes that do not touch it are still fine
    expect_equal(status_of(out, "A2-name-state"), "PASS")
  }
})

test_that("strict turns a FAIL into an error naming the passes", {
  r <- fake_ref(setdiff(ref_cols(), "dba_key"))
  expect_error(pf_check_schema(r, passes = lean(), strict = TRUE, verbose = FALSE),
               "A3-name-dba")
  # a WARN is not an error, even under strict
  r2 <- fake_ref(setdiff(ref_cols(), c("name_acro", "name_pre", "name_is_acro")))
  expect_silent(pf_check_schema(r2, passes = lean(), strict = TRUE, verbose = FALSE))
})

# ---------------------------------------------------------------------------
# the stamp and the precomputed companions
# ---------------------------------------------------------------------------

test_that("an unstamped bundle warns and a wrongly stamped one fails", {
  expect_equal(status_of(pf_check_schema(fake_ref(stamp = FALSE), passes = lean(),
                                         verbose = FALSE),
                         "normalizer stamp"), "WARN")
  expect_equal(status_of(pf_check_schema(fake_ref(stamp = "v1-0000000000000000"),
                                         passes = lean(), verbose = FALSE),
                         "normalizer stamp"), "FAIL")
})

test_that("a bundle with no precomputed companions warns, once each", {
  out <- pf_check_schema(fake_ref(companions = FALSE), passes = lean(),
                         verbose = FALSE)
  for (el in c("name_freq", "token_idf", "ref_index"))
    expect_equal(status_of(out, paste("bundle", el)), "WARN")
  expect_false("ref_index token_col" %in% out$check)
})

# ---------------------------------------------------------------------------
# the query side, which needs a different set of columns
# ---------------------------------------------------------------------------

test_that("a bare frame is read as the query side", {
  q <- fake_ref()$reference
  out <- pf_check_schema(q, passes = lean(), verbose = FALSE)
  expect_equal(out$detail[out$check == "side"], "query")
  expect_equal(sum(out$status == "FAIL"), 0L)
  # no stamp row: a query frame is normalized at run time, so it has nothing
  # to be stale against
  expect_false("normalizer stamp" %in% out$check)
})

test_that("the query side is checked against by_x, not by_y", {
  # drop dba_key: on the query side that breaks A4/A5 (which read the query's
  # dba) and leaves A3/C2 (which read the reference's) alone
  q <- fake_ref(setdiff(ref_cols(), "dba_key"))$reference
  out <- pf_check_schema(q, passes = lean(), side = "query", verbose = FALSE)
  expect_equal(status_of(out, "A4-dba-name"), "FAIL")
  expect_equal(status_of(out, "A5-dba-dba"), "FAIL")
  expect_equal(status_of(out, "A3-name-dba"), "PASS")
  expect_equal(status_of(out, "C2-dba-any"), "PASS")
})

test_that("a frame with no columns is refused rather than reported on", {
  expect_error(pf_check_schema(data.frame()), "no columns")
})

# ---------------------------------------------------------------------------
# an un-normalized frame has no keys yet, and that is not a failure
# ---------------------------------------------------------------------------

test_that("a frame with no name_key is reported as unchecked, not as broken", {
  raw <- list(reference = data.frame(ein = "123456789", name = "A CHARITY",
                                     stringsAsFactors = FALSE),
              normalizer = tryCatch(npmatch::np_normalize_signature(),
                                    error = function(e) "v1-test"))
  out <- pf_check_schema(raw, passes = lean(), verbose = FALSE)
  expect_equal(status_of(out, "normalized"), "WARN")
  expect_equal(sum(out$status == "FAIL"), 0L)
  # none of the per-pass rows are reported, because none could be evaluated
  expect_false(any(grepl("^[A-D][0-9]", out$check)))
  # and strict does not turn an unchecked frame into an error
  expect_silent(pf_check_schema(raw, passes = lean(), strict = TRUE,
                                verbose = FALSE))
})

# ---------------------------------------------------------------------------
# the run refuses to start
# ---------------------------------------------------------------------------

test_that("pf_run_batches stops before matching when a pass cannot fire", {
  r <- fake_ref(setdiff(ref_cols(), "dba_key"))
  g <- data.frame(grant_id = c("PFI-aaaa", "PFI-bbbb"), in_scope = TRUE,
                  stringsAsFactors = FALSE)
  d <- file.path(tempdir(), "pf-schema-batches")
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  expect_error(
    pf_run_batches(g, r, dir = d, passes = lean(), verbose = FALSE),
    "block on")
  # nothing was written: the refusal came before the first batch
  expect_equal(length(list.files(d, pattern = "^batch-")), 0L)
})

test_that("check_reference = ignore turns the schema check off too", {
  r <- fake_ref(setdiff(ref_cols(), "dba_key"))
  g <- data.frame(grant_id = c("PFI-aaaa", "PFI-bbbb"), in_scope = TRUE,
                  stringsAsFactors = FALSE)
  d <- file.path(tempdir(), "pf-schema-batches-ignore")
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  # it still fails -- these grants have no name columns to match on -- but it
  # gets as far as matching, which is what "ignore" is for
  err <- tryCatch({
    suppressWarnings(pf_run_batches(g, r, dir = d, passes = lean(),
                                    verbose = FALSE, check_reference = "ignore"))
    ""
  }, error = function(e) conditionMessage(e))
  expect_false(grepl("block on", err))
})
