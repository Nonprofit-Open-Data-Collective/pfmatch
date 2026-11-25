## `flag_placeholder` is the union of pf_placeholder_pattern() and
## peopleparser's placeholder class. See vignette("identifying-people").

test_that("pointer names are placeholders", {
  x <- c("SEE ATTACHED", "SEE ATTACHED SCHEDULE", "SEE SCHEDULE ATTACHED",
         "VARIOUS", "VARIOUS RECIPIENTS", "AVAILABLE UPON REQUEST",
         "SEE STATEMENT", "SEVERAL SOURCES", "MISCELLANEOUS DONATIONS",
         "MISC 250")
  expect_true(all(pfmatch:::.pf_placeholder(x)))
})

test_that("real recipients are not placeholders", {
  x <- c("HARLEM CHILDRENS ZONE", "FORD FOUNDATION", "BARNARD COLLEGE",
         "BETH SMITH", "METROPOLITAN OPERA", "ASPCA")
  expect_false(any(pfmatch:::.pf_placeholder(x)))
})

test_that("^MISC does not swallow a real organisation", {
  # The pattern was `^MISC` until 2026-11-24, which discarded this EIN-holding
  # organisation as a pointer. The misspelling has to survive the fix.
  expect_false(pfmatch:::.pf_placeholder("MISCARRIAGE ABORTION HOTLINE"))
  expect_true(pfmatch:::.pf_placeholder("MISCELLEANOUS"))
  expect_true(pfmatch:::.pf_placeholder("MISCELLANEOUS"))
  expect_true(pfmatch:::.pf_placeholder("MISC"))
})

test_that("the model catches pointer shapes the pattern does not", {
  # Measured on inputs/ef100k_grants.csv: these are the regex's blind spots.
  x <- c("ALL OTHERS 1000 OR LESS PER DONEE", "ALL OTHER MEDICAL MISSIONS",
         "THE BOARD OF TRUSTEES")
  expect_true(all(pfmatch:::.pf_placeholder(x)))
  expect_false(any(pfmatch:::.pf_placeholder(x, use_model = FALSE)))
})

test_that("use_model = FALSE is the pattern alone", {
  expect_true(pfmatch:::.pf_placeholder("SEE ATTACHED", use_model = FALSE))
  expect_false(pfmatch:::.pf_placeholder("ALL OTHER MEDICAL MISSIONS",
                                         use_model = FALSE))
})

test_that("a placeholder is never also flagged as a person", {
  # `SEE ATTACHED` is two tokens with no institutional word, which is exactly
  # the shape the person score rewards -- 99 rows per 100k before the veto.
  x <- c("SEE ATTACHED", "SEE STATEMENT", "SEE SCHEDULE ATTACHED",
         "SEE ATTACHED LIST", "SCHEDULE ATTACHED")
  ph  <- pfmatch:::.pf_placeholder(x)
  raw <- pfmatch:::.pf_looks_personal(x)
  expect_true(all(ph))
  # the bare score does fire on these -- which is why the veto has to exist
  expect_true(any(raw))
  # `raw & !ph` is the expression pf_prepare_grants assigns to looks_personal
  expect_false(any(raw & !ph))
})

test_that("pf_is_placeholder reads a frame and honours name_col", {
  g <- data.frame(recip_name = c("SEE ATTACHED", "FORD FOUNDATION"),
                  other = c("FORD FOUNDATION", "SEE ATTACHED"),
                  stringsAsFactors = FALSE)
  expect_equal(pf_is_placeholder(g), c(TRUE, FALSE))
  expect_equal(pf_is_placeholder(g, name_col = "other"), c(FALSE, TRUE))
})

test_that("blank, NA and zero-length input behave", {
  expect_equal(pfmatch:::.pf_placeholder(c(NA_character_, "", "  ")),
               rep(FALSE, 3))
  out <- pfmatch:::.pf_placeholder(character(0))
  expect_type(out, "logical")
  expect_length(out, 0)
})

test_that("the pattern is matched case-insensitively via upper-casing", {
  expect_true(all(pfmatch:::.pf_placeholder(
    c("see attached", "See Attached", "SEE ATTACHED", " see attached "))))
})
