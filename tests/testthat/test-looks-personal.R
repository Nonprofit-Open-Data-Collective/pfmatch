## `.pf_looks_personal()` scores the recipient name with
## peopleparser::classify_names(). See the note in R/prepare.R for how the
## cutoff and the token precondition were chosen.

test_that("ordinary person names flag", {
  people <- c("JOEL BASS", "JONES MAURICE", "SMALL RANDALL", "MITCHELL MILLER",
              "BETH SMITH", "TANNER JONES", "JANELLE GARCIA", "SMITH JOHN A",
              "JOHN A SMITH")
  expect_true(all(pfmatch:::.pf_looks_personal(people)))
})

test_that("the given names the old 202-name whitelist missed now flag", {
  # dev/NO-RESIDUAL-AUDIT.md: these were routed into the matching path because
  # the hand-written list did not hold them.
  missed <- c("JOEL BASS", "MAURICE WILLIAMS", "RANDALL SMALL",
              "MITCHELL MILLER", "BETH JONES", "TANNER BAKER")
  expect_true(all(pfmatch:::.pf_looks_personal(missed)))
})

test_that("organisation names do not flag", {
  orgs <- c("HARLEM CHILDRENS ZONE", "FIRST PRESBYTERIAN CHURCH",
            "FORD FOUNDATION", "BARNARD COLLEGE", "CHARITY NAVIGATOR",
            "RONALD MCDONALD HOUSE", "SMITHSONIAN INSTITUTION",
            "UNITED WAY OF GREATER ATLANTA", "METROPOLITAN OPERA")
  expect_false(any(pfmatch:::.pf_looks_personal(orgs)))
})

test_that("acronyms and bare single tokens never flag", {
  # The 2-3 token precondition carries this: without it the model scores bare
  # surnames and acronyms as people.
  single <- c("ASPCA", "KQED", "WGBH", "UNICEF", "JDRF", "FRICK", "CHIP",
              "CISA", "MARC", "ELLIS", "THORN")
  expect_false(any(pfmatch:::.pf_looks_personal(single)))
})

test_that("four or more tokens never flag", {
  expect_false(any(pfmatch:::.pf_looks_personal(
    c("JOHN JACOB JINGLEHEIMER SCHMIDT", "MARY ANN SMITH JONES BROWN"))))
})

test_that("blank, NA and punctuation-only input is FALSE, not an error", {
  x <- c(NA_character_, "", "   ", "---", "123", "&&&")
  out <- pfmatch:::.pf_looks_personal(x)
  expect_length(out, length(x))
  expect_false(any(out))
  expect_type(out, "logical")
})

test_that("the result is positional and length-stable with duplicates", {
  # The implementation scores distinct names once and maps back; this is the
  # guard on that mapping.
  x <- c("BETH SMITH", "FORD FOUNDATION", "BETH SMITH", NA, "ASPCA",
         "FORD FOUNDATION", "TANNER JONES")
  out <- pfmatch:::.pf_looks_personal(x)
  expect_equal(out, c(TRUE, FALSE, TRUE, FALSE, FALSE, FALSE, TRUE))
})

test_that("case and surrounding punctuation do not change the verdict", {
  expect_equal(pfmatch:::.pf_looks_personal(c("beth smith", "BETH SMITH",
                                              "  Beth Smith  ", "BETH SMITH.")),
               rep(TRUE, 4))
})

test_that("the cutoff is honoured", {
  # SMALL RANDALL scores 0.0156: inside the default 0.05, outside a tighter one.
  expect_true(pfmatch:::.pf_looks_personal("SMALL RANDALL"))
  expect_false(pfmatch:::.pf_looks_personal("SMALL RANDALL", cutoff = 0.001))
})

test_that("zero-length input returns zero-length logical", {
  out <- pfmatch:::.pf_looks_personal(character(0))
  expect_type(out, "logical")
  expect_length(out, 0)
})
