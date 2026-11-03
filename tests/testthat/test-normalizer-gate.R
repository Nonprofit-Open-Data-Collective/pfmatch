# The normalizer gate itself.
#
# The gate decides whether four blocks of pinned assertions run, so it is the
# one piece of test infrastructure whose own failure is invisible: when it
# abstains wrongly, the summary line reads "SKIP 4" and nothing says the data
# and the installed normalizer disagree. This session watched that happen twice
# in one day, under 0.1.7 and then 0.1.8.
#
# It now skips in one direction and fails in the other, and that asymmetry is
# what these tests pin.

fake_fixture <- function(sig = "v1-doesnotmatch", npn = "0.1.8") {
  structure(data.frame(x = 1),
            normalizer = sig,
            normalizer_pkg = c(npnormalize = npn, npmatch = "0.1.1.9000"))
}

test_that("version comparison is numeric, not lexical", {
  # the trap this avoids: "0.1.10" < "0.1.8" as strings, so a string compare
  # would call a NEWER normalizer older and fail a correct install
  expect_true(.npn_older("0.1.7", "0.1.8"))
  expect_false(.npn_older("0.1.8", "0.1.8"))
  expect_false(.npn_older("0.1.9", "0.1.8"))
  expect_false(.npn_older("0.1.10", "0.1.8"))
  expect_true(.npn_older("0.1.8", "0.1.10"))
})

test_that("an unrecorded version on either side never fails", {
  # fixtures predating normalizer_pkg must still produce a usable skip
  expect_false(.npn_older("unrecorded", "0.1.8"))
  expect_false(.npn_older("0.1.8", "unrecorded"))
})

test_that("installed OLDER than the fixture fails, and names both versions", {
  # a broken environment, not a stale fixture. Claim the fixture was built on a
  # version no one has, so the installed one is necessarily older.
  v <- fake_fixture(npn = "99.0.0")
  expect_error(skip_if_normalizer_moved(v), "OLDER")
  expect_error(skip_if_normalizer_moved(v), "99.0.0")
  expect_error(skip_if_normalizer_moved(v), "broken environment")
  # and it points at the floor that would have prevented it
  expect_error(skip_if_normalizer_moved(v), "DESCRIPTION")
})

test_that("installed NEWER than the fixture skips, and says to rebuild", {
  v <- fake_fixture(npn = "0.0.1")
  expect_condition(skip_if_normalizer_moved(v), class = "skip")
  cond <- tryCatch(skip_if_normalizer_moved(v), skip = function(c) c)
  expect_match(conditionMessage(cond), "normalizer moved")
  expect_match(conditionMessage(cond), "make-pf-variants.R")
})

test_that("a matching signature runs the block rather than skipping it", {
  live <- tryCatch(npmatch::np_normalize_signature(), error = function(e) NA)
  skip_if(is.na(live))
  v <- fake_fixture(sig = live, npn = as.character(utils::packageVersion("npnormalize")))
  expect_true(skip_if_normalizer_moved(v))
})

test_that("the declared floor is not behind the shipped fixture", {
  # The failure this closes: DESCRIPTION said npnormalize (>= 0.1.5) while
  # pf_variants was built on 0.1.8, so a fresh install could resolve three
  # releases back and satisfy the floor. It could not be caught transitively
  # either -- npmatch's released v0.1.1 does not import npnormalize at all --
  # and the gate above would have reported it as skips.
  # Under R CMD check the tests run from <pkg>.Rcheck/tests, where
  # test_path("..", "..") is the check directory and holds no DESCRIPTION at
  # all -- so the source-tree path fails the whole file. The installed
  # package's own DESCRIPTION is the better source anyway: it is what a fresh
  # install declares, which is exactly what this test is about. devtools
  # resolves system.file() into the source tree, so one path serves both.
  f <- system.file("DESCRIPTION", package = "pfmatch")
  if (!nzchar(f)) f <- testthat::test_path("..", "..", "DESCRIPTION")
  d <- read.dcf(f, fields = "Imports")[1, 1]
  floor <- sub(".*npnormalize \\(>= ([0-9.]+)\\).*", "\\1", gsub("\n", " ", d))
  expect_match(floor, "^[0-9.]+$")

  built <- normalizer_versions(pfmatch::pf_variants)[["built"]]
  skip_if(built == "unrecorded")
  expect_false(utils::compareVersion(floor, built) < 0,
               info = sprintf("DESCRIPTION floor %s is behind the fixture's %s",
                              floor, built))
})
