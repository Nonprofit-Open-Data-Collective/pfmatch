# The verdict seam: pf_read_verdicts() and pf_apply_verdicts().
#
# These tests pin two things the package did not previously own. First, that a
# reviewed sheet is validated rather than trusted -- every rejection below is a
# failure that would otherwise produce a plausible count over the wrong set.
# Second, that reconciliation accepts nothing: the tests assert the result frame
# and tiers are untouched, because auto-acceptance failed validation at 72%
# precision and the thresholds for selective acceptance are unmeasured.

verdict_match <- function() {
  res <- data.frame(
    .id = c("G1", "G2"), tier = c("MAYBE", "MAYBE"),
    overall_ein = c("222222222", "444444444"),
    overall_name_y = c("RIVER ARTS COUNCIL", "HILLSIDE ACADEMY"),
    overall_score = c(0.71, 0.66), overall_name_sim = c(0.80, 0.74),
    overall_margin = c(0.01, 0.02), n_close = c(2L, 1L),
    stringsAsFactors = FALSE)
  attr(res, "pairs") <- data.frame(
    .id = c("G1", "G2"), .ein = c("222222222", "444444444"),
    name_y = c("RIVER ARTS COUNCIL", "HILLSIDE ACADEMY"),
    score = c(0.71, 0.66), state_y = c("MT", "NJ"),
    city_y = c("BOZEMAN", "HILLSIDE"), zip5_y = c("59715", "07205"),
    geo_state = c(1, 1), geo_zip5 = c(1, 1), stringsAsFactors = FALSE)
  grants <- data.frame(
    grant_id = c("G1", "G2", "G3"), ORG_EIN = "411111111",
    FILERNAME1 = "A FOUNDATION", PF_15_G_PAID_RECIP_STAT = "PC",
    in_scope = TRUE,
    recip_name = c("RIVER ARTS COUNCIL", "HILLSIDE ACADEMY", "NO PAIR AT ALL"),
    recip_name_alt = NA_character_, recip_city = c("BOZEMAN", "HILLSIDE", "FARGO"),
    recip_state_raw = c("MT", "NJ", "ND"), recip_zip5 = c("59715", "07205", "58102"),
    recipient_type = "public_charity", recipient_type_detail = NA_character_,
    looks_personal = FALSE, oos_reason = NA_character_, stringsAsFactors = FALSE)
  structure(list(result = res, grants = grants,
                 in_scope = c("G1", "G2", "G3"), out_of_scope = character(0)),
            class = "pf_match")
}

ok_verdicts <- function()
  data.frame(
    grant_id = c("G1", "G2", "G3"),
    verdict = c("MATCH", "MATCH", "NONE"),
    ein = c("222222222", "999999999", NA),
    confidence = c("high", "medium", "low"),
    evidence_class = c("QUOTE", "INFER", "NONE"),
    evidence = c("the packet names it", "inferred from sector", "nothing found"),
    runner_up_ein = c(NA, "444444444", NA),
    stringsAsFactors = FALSE)

## ---- pf_read_verdicts() ----------------------------------------------------

test_that("a clean sheet reads, with the contract columns first", {
  v <- pf_read_verdicts(ok_verdicts())
  expect_equal(names(v)[seq_along(pf_verdict_cols())], pf_verdict_cols())
  expect_equal(nrow(v), 3L)
  expect_equal(attr(v, "missing"), character(0))
})

test_that("extra columns survive and the EIN is normalized", {
  d <- ok_verdicts()
  d$ein <- c("22-2222222", "999999999", NA)
  d$search_confirmed <- c("CONFIRMED", "NOT_SEARCHED", "NOT_SEARCHED")
  v <- pf_read_verdicts(d)
  expect_equal(v$ein[1], "222222222")
  expect_true("search_confirmed" %in% names(v))
})

test_that("an absent contract column stops, and names what is present", {
  d <- ok_verdicts(); d$verdict <- NULL
  expect_error(pf_read_verdicts(d), "verdict columns are absent")
  # the message has to say what WAS there, or the caller cannot see the rename
  expect_error(pf_read_verdicts(d), "present:")
})

test_that("a level outside the permitted set stops rather than being dropped", {
  d <- ok_verdicts(); d$verdict[2] <- "PROBABLY"
  expect_error(pf_read_verdicts(d), "PROBABLY")
  d2 <- ok_verdicts(); d2$evidence_class[1] <- "VIBES"
  expect_error(pf_read_verdicts(d2), "outside the permitted set")
})

test_that("NA is permitted in a level column; only wrong values are not", {
  d <- ok_verdicts(); d$confidence[2] <- NA
  expect_silent(v <- pf_read_verdicts(d))
  expect_true(is.na(v$confidence[2]))
})

test_that("two verdicts for one identity stop", {
  d <- rbind(ok_verdicts(), ok_verdicts()[1, ])
  expect_error(pf_read_verdicts(d), "more than one verdict")
})

test_that("a MATCH with no EIN stops", {
  d <- ok_verdicts(); d$ein[1] <- NA
  expect_error(pf_read_verdicts(d), "name no EIN")
})

test_that("ids catches a review of the wrong set, in both directions", {
  # a verdict for something never sent is an error
  expect_error(pf_read_verdicts(ok_verdicts(), ids = c("G1", "G2")),
               "not sent for review")
  # something sent and not returned is reported, not silently absent
  v <- pf_read_verdicts(ok_verdicts(), ids = c("G1", "G2", "G3", "G4"))
  expect_equal(attr(v, "missing"), "G4")
})

## ---- pf_apply_verdicts() ---------------------------------------------------

test_that("reconciliation reports agreement, contradiction and new EINs", {
  m <- pf_apply_verdicts(verdict_match(), ok_verdicts(), verbose = FALSE)
  a <- m$adjudication
  expect_equal(nrow(a), 3L)
  # G1 confirms the pick; G2 names a different EIN; G3 declines
  expect_true(a$agrees_with_pick[a$grant_id == "G1"])
  expect_false(a$agrees_with_pick[a$grant_id == "G2"])
  expect_true(a$names_new_ein[a$grant_id == "G2"])
  expect_true(is.na(a$agrees_with_pick[a$grant_id == "G3"]))
  expect_equal(m$adjudication_counts$agrees, 1L)
  expect_equal(m$adjudication_counts$contradicts, 1L)
  expect_equal(m$adjudication_counts$new_ein, 1L)
})

test_that("tier_before uses pf_status()'s convention, so no-pair identities keep a tier", {
  # G3 has no pair anywhere. Under the result frame it is simply absent, and
  # reading the prior tier from there would drop it from the reconciliation --
  # which is most of the NO tier in a real run.
  m <- pf_apply_verdicts(verdict_match(), ok_verdicts(), verbose = FALSE)
  a <- m$adjudication
  expect_equal(a$tier_before[a$grant_id == "G3"], "NO")
  expect_true(is.na(a$pick_ein[a$grant_id == "G3"]))
  expect_equal(m$adjudication_counts$no_pick, 1L)
  expect_equal(sum(a$grant_id %in% names(pf_result_tiers(verdict_match()))), 2L)
})

test_that("nothing is accepted: the result frame and the tiers are untouched", {
  m0 <- verdict_match()
  m1 <- pf_apply_verdicts(m0, ok_verdicts(), verbose = FALSE)
  expect_identical(as.data.frame(m1$result), as.data.frame(m0$result))
  expect_identical(pf_result_tiers(m1), pf_result_tiers(m0))
  expect_identical(pf_status(m1)$status, pf_status(m0)$status)
  # G2's verdict names 999999999 and the pick stays 444444444
  expect_equal(pf_result_tiers(m1)[["G2"]], "MAYBE")
  expect_equal(as.data.frame(m1$result)$overall_ein[2], "444444444")
})

test_that("a verdict for an identity not in this match stops", {
  d <- ok_verdicts(); d$grant_id[3] <- "G999"
  expect_error(pf_apply_verdicts(verdict_match(), d, verbose = FALSE),
               "absent from this match")
})

test_that("an already-read frame is not re-read, and a raw one is", {
  v <- pf_read_verdicts(ok_verdicts())
  expect_silent(pf_apply_verdicts(verdict_match(), v, verbose = FALSE))
  # a raw frame still goes through validation
  d <- ok_verdicts(); d$verdict[1] <- "NOPE"
  expect_error(pf_apply_verdicts(verdict_match(), d, verbose = FALSE), "NOPE")
})

test_that("the contract is stable, because dev/ and the package must agree on it", {
  expect_equal(pf_verdict_cols(),
               c("grant_id", "verdict", "ein", "confidence", "evidence_class",
                 "evidence", "runner_up_ein"))
  expect_equal(pf_verdict_levels()$verdict, c("MATCH", "NONE", "AMBIGUOUS"))
  expect_equal(pf_verdict_levels()$evidence_class,
               c("QUOTE", "NTEE", "INFER", "NONE"))
})
