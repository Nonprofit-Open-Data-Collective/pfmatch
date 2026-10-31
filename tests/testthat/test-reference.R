# pf_reference(): where the reference comes from. An explicit BMF is honoured,
# matchdb is used when nothing is named, and every failure on the matchdb side
# falls back to the local bundle with a message, or errors when matchdb was
# required.

tiny_bmf <- function() {
  data.frame(ein = c("131234567", "521234567"),
             org_name_join = c("ALPHA TRUST", "BETA FUND"), dba_name = c("", ""),
             org_addr_street = c("1 MAIN ST", "2 OAK AVE"),
             org_addr_city = c("CHICAGO", "BOSTON"), org_addr_state = c("IL", "MA"),
             org_addr_zip5 = c("60601", "02108"), org_addr_zip4 = c("", ""),
             stringsAsFactors = FALSE)
}

test_that("a BMF given is built locally, whatever matchdb could offer", {
  r <- pf_reference(tiny_bmf(), cache = NULL, verbose = FALSE)
  expect_equal(r$source, "local")
  expect_equal(nrow(r$reference), 2)
  expect_true(all(c("name_acro", "name_pre") %in% names(r$reference)))   # recovery keys
})

test_that("the local bundle is cached and read back as local", {
  f <- tempfile(fileext = ".rds")
  a <- pf_reference(tiny_bmf(), cache = f, verbose = FALSE)
  b <- pf_reference(cache = f, source = "local", verbose = FALSE)
  expect_equal(b$source, "local")
  expect_identical(b$reference, a$reference)
})

test_that("with no BMF, no cache and no matchdb there is a clear error", {
  skip_if(requireNamespace("matchdb", quietly = TRUE), "matchdb is installed")
  expect_error(pf_reference(cache = tempfile(), source = "matchdb", verbose = FALSE),
               "matchdb is not installed")
  expect_message(
    expect_error(pf_reference(cache = tempfile(), verbose = FALSE), "no reference"),
    "unavailable")
})

test_that("with no BMF the matchdb tier is used, with recovery keys added", {
  skip_if_not_installed("matchdb")
  local <- pf_build_reference(tiny_bmf())
  seen <- NULL
  testthat::local_mocked_bindings(
    md_reference = function(label, ..., fetch, build_index) {
      seen <<- list(label = label, fetch = fetch)
      c(local[c("reference", "name_freq", "token_idf", "ref_index")],
        list(clusters = data.frame(cluster_id = character(0), ein = character(0)),
             stamp = list(spec_hash = "abc123", normalize_signature = "v1-test")))
    }, .package = "matchdb")
  r <- pf_reference(cache = NULL, tier = "active-observed", verbose = FALSE)
  expect_equal(r$source, "matchdb")
  expect_equal(seen, list(label = "active-observed", fetch = "missing"))
  expect_true("name_acro" %in% names(r$reference))
  expect_equal(r$stamp$spec_hash, "abc123")
})

# The default is a decision, not an implementation detail: `active-observed`
# matched the benchmark in half the time of the augmented BMF and cleared a
# point higher (dev/BENCH-MD-REFERENCE.log), and `unified-observed` buys 0.1
# point for two and a half times the match time. Pin it so a change is
# deliberate.
test_that("the default matchdb tier is active-observed, and the option overrides it", {
  skip_if_not_installed("matchdb")
  local <- pf_build_reference(tiny_bmf())
  seen <- NULL
  stub <- function(label, ..., fetch, build_index) {
    seen <<- label
    c(local[c("reference", "name_freq", "token_idf", "ref_index")],
      list(clusters = data.frame(cluster_id = character(0), ein = character(0)),
           stamp = list(spec_hash = "abc123", normalize_signature = "v1-test")))
  }
  testthat::local_mocked_bindings(md_reference = stub, .package = "matchdb")
  pf_reference(cache = NULL, verbose = FALSE)
  expect_equal(seen, "active-observed")

  old <- options(pfmatch.matchdb_tier = "unified-observed")
  on.exit(options(old), add = TRUE)
  pf_reference(cache = NULL, verbose = FALSE)
  expect_equal(seen, "unified-observed")
})

test_that("a matchdb failure falls back to the local bundle, or errors when required", {
  skip_if_not_installed("matchdb")
  f <- tempfile(fileext = ".rds")
  pf_reference(tiny_bmf(), cache = f, verbose = FALSE)
  testthat::local_mocked_bindings(
    md_reference = function(...) stop("bundle was built by normalizer v1-old"),
    .package = "matchdb")
  expect_message(r <- pf_reference(cache = f, verbose = FALSE), "v1-old); using the local bundle", fixed = TRUE)
  expect_equal(r$source, "local")
  expect_error(pf_reference(cache = f, source = "matchdb", verbose = FALSE), "v1-old")
})
