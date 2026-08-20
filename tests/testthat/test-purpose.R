test_that("contentfulness gates on IDF mass, not on length", {
  # short but contentful
  expect_true(all(pfmatch:::pf_purpose_is_contentful(
    c("SCHOLARSHIP", "EDUCATION", "Culture", "YOUTH"))))
  # long but contentless -- this is why a character-length gate does not work
  expect_false(any(pfmatch:::pf_purpose_is_contentful(c(
    "TO SUPPORT THE MISSION OF THE ORGANIZATION",
    "A GRANT TO FURTHER THE DONEE'S EXEMPT PURPOSE",
    "GENERAL DONATION TO SUPPORT ORGANIZATION'S ACTIVITIES."))))
  expect_false(pfmatch:::pf_purpose_is_contentful(""))
})

test_that("coverage is NA rather than 0 when undefined", {
  idf <- c(FOOD = 5, PANTRY = 6, HOSPITAL = 4)
  # no content tokens in the query
  expect_true(is.na(pfmatch:::pf_purpose_coverage("GENERAL SUPPORT", "FOOD PANTRY", idf)))
  # nothing to compare against
  expect_true(is.na(pfmatch:::pf_purpose_coverage("FOOD PANTRY", "", idf)))
  # a zero score is only produced when there is real evidence of disagreement
  expect_equal(pfmatch:::pf_purpose_coverage("FOOD PANTRY", "HOSPITAL", idf), 0)
})

test_that("coverage is asymmetric and bounded", {
  idf <- c(FOOD = 5, PANTRY = 5, COUNTY = 1)
  full <- pfmatch:::pf_purpose_coverage("FOOD PANTRY", "GREEN COUNTY FOOD PANTRY INC", idf)
  half <- pfmatch:::pf_purpose_coverage("FOOD PANTRY", "GREEN COUNTY FOOD BANK", idf)
  expect_equal(full, 1)
  expect_gt(full, half)
  expect_true(half > 0 && half < 1)
  # document length must not depress the score
  expect_equal(
    pfmatch:::pf_purpose_coverage("FOOD PANTRY",
      paste(rep("FOOD PANTRY OPERATIONS", 200), collapse = " "), idf), 1)
})

test_that("the tiebreak config carries npmatch's own gates by default", {
  cfg <- pf_tiebreak_config()
  expect_equal(cfg$tie_band, 0.05)
  expect_equal(cfg$tie_high, 0.95)
  expect_equal(cfg$keys, c("cov_all", "has_mission"))
})
