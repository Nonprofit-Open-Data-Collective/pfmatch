# Drawing the labelling round.
#
# The tests that matter are the refusals. A draw that silently returns fewer
# cases than asked for, or that reports strata it did not actually stratify on,
# produces a round whose power calculation is wrong in a direction nobody
# checks -- and the labels are the expensive part, so the error is found after
# the money is spent. PREREQS section 6b.2 sizes the round from the cell that
# has to separate; every stop below protects that cell.
#
# The second group covers the input shapes. Drawing against the runs on disk
# found that the production run is serialized as list(status, grants) with no
# pairs attribute, so a pf_match is not the only frame a real round comes from
# (dev/ADJ-ROUND-STAGE1-20261102.log).

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

# The production shape: an identity-grain status frame beside a grant-grain
# source, no result and no pairs. The ids differ by design -- the status frame
# is keyed on recipient identity (R1..Rn) and the grants on grant (G001..).
round_status <- function(n = 60L) {
  list(
    status = data.frame(
      grant_id = sprintf("R%d", seq_len(n)),
      status = factor("MAYBE", levels = pf_status_levels()),
      match_pass = rep(c("A1-name-zip5", "B1-token-state", "C1-name-any"),
                       length.out = n),
      margin = rep(c(0.004, 0.42), length.out = n),
      n_close = rep(c(3L, 1L), length.out = n),
      stringsAsFactors = FALSE),
    grants = data.frame(
      grant_id = sprintf("G%03d", seq_len(n * 2L)),
      OBJECTID = sprintf("OID%03d", seq_len(n * 2L)),
      recipient_uid = rep(seq_len(n), each = 2L),
      stringsAsFactors = FALSE))
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
  # T8's instance, and the one the real frame hit: flag_ntee_support holds 60
  # cases against section 6b.3's floor of 100, so this stop is what a real
  # round runs into rather than a hypothetical
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

test_that("an unfingerprintable frame stops by default", {
  # the labels could never be re-attached: grant_id is positional and names
  # agree on 0% of ids joined across the two known vintages
  m <- round_match(); m$grants$OBJECTID <- NULL
  expect_error(pf_round_sample(m, n = 10, seed = 1, verbose = FALSE),
               "cannot be fingerprinted")
  expect_error(pf_round_sample(m, n = 10, seed = 1, verbose = FALSE),
               "require_population = FALSE")
  # and it stops before drawing, so an impossible n is not what surfaces first
  expect_error(pf_round_sample(m, n = 10000, seed = 1, verbose = FALSE),
               "cannot be fingerprinted")
})

test_that("a by column that is present but all NA stops", {
  # the pass does this when a run records it in neither the result frame nor
  # the pairs: one cell for every case, reported as several strata
  x <- round_status(n = 30L)
  x$status$match_pass <- NA_character_
  expect_error(pf_round_sample(x, n = 10, by = c("tier", "pass"), seed = 1,
                               verbose = FALSE), "entirely NA")
  expect_error(pf_round_sample(x, n = 10, by = c("tier", "pass"), seed = 1,
                               verbose = FALSE),
               "unstratified draw that reports strata")
  # dropping it from by= is the way out, and still draws
  r <- pf_round_sample(x, n = 10, by = "tier", seed = 1, verbose = FALSE)
  expect_equal(nrow(r), 10L)
})

test_that("a result frame with no pass column falls back to the pairs", {
  # pf_status() reads the pass off the result frame; where there is none the
  # pairs still carry it, and taking NA would collapse the pass strata
  m <- round_match(n = 30L)
  expect_null(as.data.frame(m$result)$pass)
  r <- pf_round_sample(m, n = 30, by = c("tier", "pass"), seed = 2,
                       verbose = FALSE)
  expect_equal(sort(unique(r$pass)),
               c("A1-name-zip5", "B1-token-state", "C1-name-any"))
})

test_that("a frame of the wrong shape stops naming what was passed", {
  expect_error(pf_round_sample(1:10, n = 2, seed = 1, verbose = FALSE),
               "must be a pf_match")
  expect_error(pf_round_sample(list(a = 1), n = 2, seed = 1, verbose = FALSE),
               "must be a pf_match")
  expect_error(pf_round_sample(data.frame(x = 1:3), n = 2, seed = 1,
                               grants = round_match()$grants, verbose = FALSE),
               "needs `grant_id` and `status`")
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

test_that("a pf_match keeps the unrounded margin that pf_status() rounds away", {
  # pf_status() rounds margin to 3 dp. On the real run the two differ by up to
  # 5e-04, immaterial to a band but not to a threshold, so the result frame's
  # own value wins where there is one.
  m <- round_match(n = 12L)
  r <- as.data.frame(m$result)
  r$overall_margin <- rep(c(0.01049, 0.08051), length.out = 12L)
  attr(r, "pairs") <- attr(m$result, "pairs"); m$result <- r
  d <- pf_round_sample(m, n = 12, seed = 1, verbose = FALSE)
  expect_true(any(abs(d$margin - round(d$margin, 3)) > 0))
})

test_that("an oversample floor is met, and reports realized against floor", {
  m <- round_match(n = 60L, flagged = 20L)
  r <- pf_round_sample(m, n = 30, extra = attr(m, "flags"),
                       oversample = list(flag_arm_shape = 15), seed = 3,
                       verbose = FALSE)
  expect_equal(nrow(r), 30L)
  expect_gte(sum(r$flag_arm_shape %in% TRUE), 15L)
  os <- attr(r, "oversample")
  expect_equal(os$column, "flag_arm_shape")
  expect_equal(os$floor, 15L)
  # realized is what the round actually holds, which proportional allocation
  # can push above the floor -- reporting the floor alone understates it
  expect_equal(os$realized, sum(r$flag_arm_shape %in% TRUE))
  expect_gte(os$realized, os$floor)
  # without the floor, 20-of-60 would land near 10 by proportion
  plain <- pf_round_sample(m, n = 30, extra = attr(m, "flags"), seed = 3,
                           verbose = FALSE)
  expect_lt(sum(plain$flag_arm_shape %in% TRUE), 15L)
  expect_equal(nrow(attr(plain, "oversample")), 0L)
})

test_that("two overlapping floors report realized above what the second drew", {
  # the real draw's instance: 31 of the 60 flag_ntee_support cases were already
  # taken by the arm-shape floor, so the second floor drew 42 and the round
  # held 60. Reporting 42 would have understated the cell that carries T8.
  m <- round_match(n = 60L, flagged = 30L)
  fl <- attr(m, "flags")
  fl$flag_b <- c(rep(FALSE, 15L), rep(TRUE, 25L), rep(FALSE, 20L))
  r <- pf_round_sample(m, n = 40, extra = fl,
                       oversample = list(flag_arm_shape = 25, flag_b = 20),
                       seed = 11, verbose = FALSE)
  os <- attr(r, "oversample")
  expect_equal(nrow(os), 2L)
  expect_true(all(os$realized >= os$floor))
  expect_equal(os$realized[os$column == "flag_b"],
               sum(r$flag_b %in% TRUE))
})

test_that("the population fingerprint travels with the draw", {
  r <- pf_round_sample(round_match(), n = 10, seed = 1, verbose = FALSE)
  expect_match(attr(r, "population"), "^[0-9a-f]{16}$")
  expect_equal(attr(r, "population"), pf_population_id(round_match()$grants))
})

test_that("a dry run on an unfingerprintable frame draws, and says so", {
  # the archived GT extracts have none; the draw must still work when it is
  # explicitly a dry run, and must record that the labels are throwaway
  m <- round_match(); m$grants$OBJECTID <- NULL
  r <- pf_round_sample(m, n = 10, seed = 1, require_population = FALSE,
                       verbose = FALSE)
  expect_equal(nrow(r), 10L)
  expect_true(is.na(attr(r, "population")))
})

test_that("stage is recorded, for the staged design", {
  r <- pf_round_sample(round_match(), n = 10, stage = "stage2", seed = 1,
                       verbose = FALSE)
  expect_true(all(r$stage == "stage2"))
})

## ---- the production input shape ---------------------------------------------

test_that("a list(status, grants) run draws, fingerprinted from the grants", {
  x <- round_status(n = 60L)
  r <- pf_round_sample(x, n = 30, by = c("tier", "pass"), seed = 9,
                       verbose = FALSE)
  expect_equal(nrow(r), 30L)
  expect_equal(attr(r, "frame_size"), 60L)
  expect_equal(attr(r, "population"), pf_population_id(x$grants))
  # the case features come off the status frame's own columns
  expect_true(all(r$pass %in% c("A1-name-zip5", "B1-token-state", "C1-name-any")))
  expect_true(all(r$margin %in% c(0.004, 0.42)))
  expect_true(all(r$n_close %in% c(1L, 3L)))
  # the ids are the identity ids, not the grant ids
  expect_true(all(grepl("^R[0-9]+$", r$grant_id)))
})

test_that("a bare status frame needs grants= to be fingerprintable", {
  x <- round_status(n = 40L)
  expect_error(pf_round_sample(x$status, n = 10, seed = 1, verbose = FALSE),
               "cannot be fingerprinted")
  r <- pf_round_sample(x$status, n = 10, grants = x$grants, seed = 1,
                       verbose = FALSE)
  expect_equal(attr(r, "population"), pf_population_id(x$grants))
})

test_that("a status frame missing a case feature leaves it NA rather than failing", {
  # the NO tier has no pair, so these are absent for real rows too
  x <- round_status(n = 30L)
  x$status$margin <- NULL; x$status$n_close <- NULL
  r <- pf_round_sample(x, n = 10, by = c("tier", "pass"), seed = 1,
                       verbose = FALSE)
  expect_true(all(is.na(r$margin)))
  expect_true(all(is.na(r$n_close)))
  # but stratifying on the absent column is still a stop
  expect_error(pf_round_sample(x, n = 10, by = c("tier", "dollar_band"),
                               seed = 1, verbose = FALSE), "not in the frame")
})
