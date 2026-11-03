# Drawing the labelling round.
#
# The tests that matter are the refusals. A draw that silently returns fewer
# cases than asked for, or that reports strata it did not actually stratify on,
# produces a round whose power calculation is wrong in a direction nobody
# checks -- and the labels are the expensive part, so the error is found after
# the money is spent. PREREQS section 6b.2 sizes the round from the cell that
# has to separate; every stop below protects that cell.

round_match <- function(n = 60L, flagged = 10L) {
  ids <- sprintf("G%03d", seq_len(n))
  passes <- rep(c("A1-name-zip5", "B1-token-state", "C1-name-any"), length.out = n)
  res <- data.frame(
    .id = ids, tier = "MAYBE",
    overall_ein = sprintf("%09d", seq_len(n)),
    overall_name_y = "SOME ORG", overall_score = 0.7,
    overall_name_sim = 0.8,
    overall_margin = rep(c(0.01, 0.08), length.out = n),
    n_close = rep(c(2L, 1L), length.out = n), stringsAsFactors = FALSE)
  attr(res, "pairs") <- data.frame(
    .id = ids, .ein = sprintf("%09d", seq_len(n)), name_y = "SOME ORG",
    score = 0.7, state_y = "MT", city_y = "BOZEMAN", zip5_y = "59715",
    geo_state = 1, geo_zip5 = 1, pass = passes, stringsAsFactors = FALSE)
  grants <- data.frame(
    grant_id = ids, OBJECTID = sprintf("OID%03d", seq_len(n)),
    ORG_EIN = "411111111", FILERNAME1 = "A FOUNDATION",
    PF_15_G_PAID_RECIP_STAT = "PC", in_scope = TRUE,
    recip_name = "SOME ORG", recip_name_alt = NA_character_,
    recip_city = "BOZEMAN", recip_state_raw = "MT", recip_zip5 = "59715",
    recipient_type = "public_charity", recipient_type_detail = NA_character_,
    looks_personal = FALSE, oos_reason = NA_character_, stringsAsFactors = FALSE)
  m <- structure(list(result = res, grants = grants, in_scope = ids,
                      out_of_scope = character(0)), class = "pf_match")
  attr(m, "flags") <- data.frame(
    grant_id = ids,
    flag_arm_shape = c(rep(TRUE, flagged), rep(FALSE, n - flagged)),
    stringsAsFactors = FALSE)
  m
}

## ---- the refusals ----------------------------------------------------------

test_that("a draw with no seed is refused", {
  # the labels outlive the session, so an unredrawable round is not auditable
  expect_error(pf_round_sample(round_match(), n = 10, verbose = FALSE),
               "`seed` is required")
  expect_error(pf_round_sample(round_match(), n = 10, verbose = FALSE),
               "cannot be audited")
})

test_that("asking for more than the frame holds stops with both counts", {
  expect_error(pf_round_sample(round_match(n = 30), n = 1000, seed = 1,
                               verbose = FALSE),
               "asked for 1,000 cases but the frame holds 30")
  # and says why short-returning is worse than stopping
  expect_error(pf_round_sample(round_match(n = 30), n = 1000, seed = 1,
                               verbose = FALSE), "power calculation")
})

test_that("a stratifying column absent from the frame stops", {
  expect_error(pf_round_sample(round_match(), n = 10, by = c("tier", "nope"),
                               seed = 1, verbose = FALSE),
               "not in the frame")
  expect_error(pf_round_sample(round_match(), n = 10, by = c("tier", "nope"),
                               seed = 1, verbose = FALSE),
               "unstratified draw that reports strata")
})

test_that("an oversample floor larger than its population stops, with the width", {
  # T8's instance: a flag with 10 cases cannot carry a 100-case floor, and the
  # message gives the interval width that is the reason the floor was set
  m <- round_match(flagged = 10L)
  expect_error(
    pf_round_sample(m, n = 20, extra = attr(m, "flags"),
                    oversample = list(flag_arm_shape = 100), seed = 1,
                    verbose = FALSE),
    "has 10 cases in the frame but a floor of 100")
  expect_error(
    pf_round_sample(m, n = 20, extra = attr(m, "flags"),
                    oversample = list(flag_arm_shape = 100), seed = 1,
                    verbose = FALSE),
    "points wide")
})

test_that("oversample must be named, and name a real column", {
  m <- round_match()
  expect_error(pf_round_sample(m, n = 10, oversample = list(5), seed = 1,
                               verbose = FALSE), "NAMED list")
  expect_error(pf_round_sample(m, n = 10, oversample = list(ghost = 2), seed = 1,
                               verbose = FALSE), "not in the frame")
})

test_that("an empty tier stops rather than returning an empty round", {
  m <- round_match()
  r <- as.data.frame(m$result); r$tier <- "YES"
  attr(r, "pairs") <- attr(m$result, "pairs"); m$result <- r
  expect_error(pf_round_sample(m, n = 5, tiers = "MAYBE", seed = 1,
                               verbose = FALSE), "nothing to draw")
})

## ---- the draw --------------------------------------------------------------

test_that("the draw is exactly n, and reproducible from the seed", {
  a <- pf_round_sample(round_match(), n = 24, seed = 42, verbose = FALSE)
  b <- pf_round_sample(round_match(), n = 24, seed = 42, verbose = FALSE)
  c3 <- pf_round_sample(round_match(), n = 24, seed = 43, verbose = FALSE)
  expect_equal(nrow(a), 24L)
  expect_identical(a$grant_id, b$grant_id)
  expect_false(identical(sort(a$grant_id), sort(c3$grant_id)))
  expect_equal(attr(a, "seed"), 42)
  expect_false(anyDuplicated(a$grant_id) > 0)
})

test_that("allocation sums to n, so largest-remainder rounding is not off by a few", {
  # floor() alone would under-fill; this is the assertion that catches it
  for (n in c(7L, 13L, 24L, 31L)) {
    r <- pf_round_sample(round_match(), n = n, seed = 7, verbose = FALSE)
    expect_equal(sum(attr(r, "allocation")), n)
    expect_equal(nrow(r), n)
  }
})

test_that("the pass is read from the pair the result frame picked", {
  r <- pf_round_sample(round_match(), n = 30, seed = 5, verbose = FALSE)
  expect_true(all(r$pass %in% c("A1-name-zip5", "B1-token-state", "C1-name-any")))
  expect_gt(length(unique(r$stratum)), 1L)
  # the stratum is built from the by= columns, in order
  expect_true(all(grepl("^MAYBE \\| ", r$stratum)))
})

test_that("an oversample floor is met and reported", {
  m <- round_match(n = 60L, flagged = 20L)
  r <- pf_round_sample(m, n = 30, extra = attr(m, "flags"),
                       oversample = list(flag_arm_shape = 15), seed = 3,
                       verbose = FALSE)
  expect_equal(nrow(r), 30L)
  expect_gte(sum(r$flag_arm_shape %in% TRUE), 15L)
  expect_equal(attr(r, "oversample")$flag_arm_shape, 15L)
  # without the floor, 20-of-60 would land near 10 by proportion
  plain <- pf_round_sample(m, n = 30, extra = attr(m, "flags"), seed = 3,
                           verbose = FALSE)
  expect_lt(sum(plain$flag_arm_shape %in% TRUE), 15L)
})

test_that("the population fingerprint travels with the draw", {
  r <- pf_round_sample(round_match(), n = 10, seed = 1, verbose = FALSE)
  expect_match(attr(r, "population"), "^[0-9a-f]{16}$")
  expect_equal(attr(r, "population"), pf_population_id(round_match()$grants))
})

test_that("a frame with no OBJECTID draws, but records that it is unfingerprinted", {
  # the archived GT extracts have none; the draw must still work and must say so
  m <- round_match(); m$grants$OBJECTID <- NULL
  r <- pf_round_sample(m, n = 10, seed = 1, verbose = FALSE)
  expect_equal(nrow(r), 10L)
  expect_true(is.na(attr(r, "population")))
})

test_that("stage is recorded, for the staged design", {
  r <- pf_round_sample(round_match(), n = 10, stage = "stage2", seed = 1,
                       verbose = FALSE)
  expect_true(all(r$stage == "stage2"))
})
