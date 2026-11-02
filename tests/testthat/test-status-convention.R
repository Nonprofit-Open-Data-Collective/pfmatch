# The seam between pf_status()'s per-grant convention and the result frame's.
# pf_status() has to account for every grant, so an identity with no pair
# anywhere is reported as NO and an out-of-scope one as OOS; the result frame
# holds a row only where a pair was scored, so both are simply absent. The
# tests below pin the disagreement rather than remove it: a later change that
# quietly aligned the two conventions would break them, which is the point,
# because a comparison reading one side from each double-counts the gap. See
# the two-conventions section of ?pf_report.

# four identities, one per cell of the seam:
#   G1  in scope, pair scored YES      -> YES   both sides
#   G2  in scope, pair scored NO       -> NO    both sides (below the floor)
#   G3  in scope, NO PAIR AT ALL       -> NO    in pf_status, ABSENT in result
#   G4  out of scope, never cascaded   -> OOS   in pf_status, ABSENT in result
seam_match <- function() {
  res <- data.frame(
    .id            = c("G1", "G2"),
    tier           = c("YES", "NO"),
    overall_ein    = c("111111111", "222222222"),
    overall_name_y = c("EAGLE RANCH FOUNDATION", "RIVERSIDE MUSEUM"),
    overall_score  = c(0.97, 0.61),
    overall_name_sim = c(0.98, 0.70),
    overall_margin = c(0.21, 0.02),
    n_close        = c(0L, 1L),
    stringsAsFactors = FALSE)
  attr(res, "pairs") <- data.frame(
    .id = c("G1", "G2"), .ein = res$overall_ein,
    name_y = res$overall_name_y, score = res$overall_score,
    state_y = c("MN", "CA"), city_y = c("ROCHESTER", "RIVERSIDE"),
    zip5_y = c("55901", "92501"), geo_state = c(1, 1), geo_zip5 = c(1, 0),
    stringsAsFactors = FALSE)
  grants <- data.frame(
    grant_id       = c("G1", "G2", "G3", "G4"),
    # the schema columns pf_status() reads through .pf_col()
    ORG_EIN        = "411111111",
    FILERNAME1     = "A FOUNDATION",
    PF_15_G_PAID_RECIP_STAT = c("PC", "PC", NA, "N/A"),
    in_scope       = c(TRUE, TRUE, TRUE, FALSE),
    recip_name     = c("EAGLE RANCH FOUNDATION", "RIVERSIDE MUSEUM",
                       "SOME ORG NOBODY BLOCKED WITH", "JANE DOE"),
    recip_name_alt = NA_character_,
    recip_city     = c("ROCHESTER", "RIVERSIDE", "FARGO", "AUSTIN"),
    recip_state_raw = c("MN", "CA", "ND", "TX"),
    recip_zip5     = c("55901", "92501", "58102", "78701"),
    recipient_type = c("public_charity", "public_charity",
                       "public_charity", "individual"),
    recipient_type_detail = NA_character_,
    looks_personal = c(FALSE, FALSE, FALSE, TRUE),
    oos_reason     = c(NA, NA, NA, "natural_person"),
    stringsAsFactors = FALSE)
  structure(list(result = res, grants = grants,
                 in_scope = c("G1", "G2", "G3"), out_of_scope = "G4"),
            class = "pf_match")
}

test_that("an identity with no pair is NO under pf_status() and absent under pf_result_tiers()", {
  x  <- seam_match()
  st <- pf_status(x)
  tr <- pf_result_tiers(x)

  # G3 surfaced no candidate at all. Each side says so in its own convention.
  expect_equal(as.character(st$status[st$grant_id == "G3"]), "NO")
  expect_false("G3" %in% names(tr))

  # and the same identity is not quietly carried in with an NA tier instead
  expect_equal(unname(tr["G3"]), NA_character_)
  expect_equal(length(tr), 2L)
})

test_that("pf_status()'s NO conflates two populations the result frame keeps apart", {
  x  <- seam_match()
  st <- pf_status(x)
  tr <- pf_result_tiers(x)

  # G2 scored below the review floor; G3 never scored. pf_status() reports both
  # as NO because nothing was accepted either way.
  expect_setequal(as.character(st$grant_id[st$status == "NO"]), c("G2", "G3"))
  # the result frame holds only the one that was scored
  expect_equal(names(tr)[tr == "NO"], "G2")

  # so the counts disagree, and they disagree in this direction: pf_status()
  # reports at least as many NO as the result frame, never fewer, and the gap
  # is exactly the in-scope identities with no pair.
  n_status <- sum(st$status == "NO")
  n_result <- sum(tr == "NO")
  expect_gt(n_status, n_result)
  expect_equal(n_status - n_result,
               length(setdiff(x$in_scope, names(tr))))
})

test_that("an out-of-scope identity is OOS under pf_status() and absent under pf_result_tiers()", {
  x  <- seam_match()
  st <- pf_status(x)
  tr <- pf_result_tiers(x)

  expect_equal(as.character(st$status[st$grant_id == "G4"]), "OOS")
  expect_false("G4" %in% names(tr))
  # pf_status() covers every grant; pf_result_tiers() covers only scored ones
  expect_equal(nrow(st), 4L)
  expect_equal(length(tr), 2L)
})

test_that("pf_result_tiers() asserts the columns it reads instead of returning nothing", {
  x <- seam_match()
  r <- as.data.frame(x$result)
  r$tier <- NULL
  x$result <- r
  # a dropped `tier` would otherwise come back as a zero-length vector, which
  # reads as "no identity was scored" -- a plausible wrong number, not an error
  expect_error(pf_result_tiers(x), "tier")
  expect_error(pf_result_tiers(as.data.frame(seam_match()$result)), "pf_match")
})

test_that("pf_result_tiers() reads the recovery pass's return, so both sides of a comparison can use it", {
  # pf_fuzzy_recover() hands back a plain list, not a pf_match. If the accessor
  # took only a pf_match, the AFTER side of the one before/after comparison it
  # exists for would have to read $result$tier by hand -- which is how the two
  # conventions got mixed and 159 identities were reported as moved where 28
  # had. The shape is the same, so the accessor takes it.
  x  <- seam_match()
  fr <- list(result = x$result, before = NULL, after = NULL, moved = NULL)
  expect_identical(pf_result_tiers(fr), pf_result_tiers(x))
  # and a before/after over the two reads one convention on both sides
  after <- fr
  r <- as.data.frame(after$result); r$tier[r$.id == "G2"] <- "YES"
  after$result <- r
  b <- pf_result_tiers(x); a <- pf_result_tiers(after)
  expect_identical(names(b)[b != a[names(b)]], "G2")
  # G3 has no pair on either side, so it is absent from both and cannot appear
  # as movement -- the property the whole seam section is about
  expect_false("G3" %in% union(names(b), names(a)))
})
