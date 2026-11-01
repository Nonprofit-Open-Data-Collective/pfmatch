# Tests for the character-level recovery pass. The frames here carry only the
# five columns pf_fuzzy_candidates() reads, built by hand rather than through
# np_normalize(): the unit under test is the blocking-and-similarity logic, and
# routing it through the normalizer would make a test failure ambiguous between
# this code and an npmatch release.

ref_fix <- function() data.frame(
  .ein = c("580566206", "390833608", "222092362", "111111111", "222222222"),
  name_key = c("WESTMINSTER SCHOOLS", "CONCORDIA UNIVERSITY",
               "PASSIONIST MISSIONARIES", "ATLANTA ANGELS", "SEE SCHEDULE O"),
  zip5  = c("30327", "53097", "11432", "30327", "30327"),
  city  = c("ATLANTA", "MEQUON", "JAMAICA", "ATLANTA", "ATLANTA"),
  state = c("GA", "WI", "NY", "GA", "GA"),
  name_placeholder = c(FALSE, FALSE, FALSE, FALSE, TRUE),
  stringsAsFactors = FALSE)

q_fix <- function(name_key, zip5 = "30327", city = "ATLANTA", state = "GA",
                  placeholder = FALSE) data.frame(
  .id = paste0("G", seq_along(name_key)), name_key = name_key, zip5 = zip5,
  city = city, state = state, name_placeholder = placeholder,
  stringsAsFactors = FALSE)

test_that("a one-character typo in the same ZIP5 is recovered", {
  skip_if_not_installed("stringdist")
  b <- pf_fuzzy_candidates(q_fix("WESMINSTER SCHOOL"), ref_fix(), verbose = FALSE)
  expect_s3_class(b, "np_blocks")
  expect_equal(nrow(b), 1L)
  expect_equal(ref_fix()$.ein[b$.y], "580566206")
  expect_gt(attr(b, "sim"), 0.93)
})

test_that("the cutoff is respected in both directions", {
  skip_if_not_installed("stringdist")
  # PASSONISTS against PASSIONIST MISSIONARIES sits at 0.857: it clears 0.85
  # and must not clear the 0.90 default. This is the pair the measured cutoff
  # trade-off turns on, so it is pinned.
  q <- q_fix("PASSONISTS", zip5 = "11432", city = "JAMAICA", state = "NY")
  expect_equal(nrow(pf_fuzzy_candidates(q, ref_fix(), cutoff = 0.90, verbose = FALSE)), 0L)
  b <- pf_fuzzy_candidates(q, ref_fix(), cutoff = 0.85, verbose = FALSE)
  expect_equal(nrow(b), 1L)
  expect_equal(ref_fix()$.ein[b$.y], "222092362")
})

test_that("an empty result is still a well-formed np_blocks", {
  skip_if_not_installed("stringdist")
  b <- pf_fuzzy_candidates(q_fix("ENTIRELY UNRELATED ORGANISATION"), ref_fix(),
                           verbose = FALSE)
  expect_s3_class(b, "np_blocks")
  expect_equal(nrow(b), 0L)
  expect_equal(names(b), c(".x", ".y"))
  expect_equal(attr(b, "n_reference"), 5L)
})

test_that("a placeholder is dropped on either side", {
  skip_if_not_installed("stringdist")
  # SEE SCHEDULE ATTACHED against SEE SCHEDULE O scores 0.91 and was the single
  # false offer across the 57 measured non-organisations. The reference row is
  # flagged, so nothing may be emitted even though it clears the cutoff.
  q <- q_fix("SEE SCHEDULE ATTACHED")
  expect_equal(nrow(pf_fuzzy_candidates(q, ref_fix(), verbose = FALSE)), 0L)
  # and a flagged query row is dropped before scoring at all
  q2 <- q_fix("WESMINSTER SCHOOL", placeholder = TRUE)
  expect_equal(nrow(pf_fuzzy_candidates(q2, ref_fix(), verbose = FALSE)), 0L)
})

test_that("skip_personal removes flagged rows and nothing else", {
  skip_if_not_installed("stringdist")
  q <- q_fix(c("WESMINSTER SCHOOL", "WESMINSTER SCHOOL"))
  p <- c(TRUE, FALSE)
  b <- pf_fuzzy_candidates(q, ref_fix(), personal = p, verbose = FALSE)
  expect_equal(nrow(b), 1L)
  expect_equal(b$.x, 2L)
  b2 <- pf_fuzzy_candidates(q, ref_fix(), personal = p, skip_personal = FALSE,
                            verbose = FALSE)
  expect_equal(nrow(b2), 2L)
  expect_error(pf_fuzzy_candidates(q, ref_fix(), personal = TRUE, verbose = FALSE))
})

test_that("city_state is a fallback and not an extra pass", {
  skip_if_not_installed("stringdist")
  # ZIP5 99999 matches no reference row, so the city/state block is used.
  q <- q_fix("WESMINSTER SCHOOL", zip5 = "99999")
  expect_equal(nrow(pf_fuzzy_candidates(q, ref_fix(), block = "zip5",
                                        verbose = FALSE)), 0L)
  b <- pf_fuzzy_candidates(q, ref_fix(), verbose = FALSE)
  expect_equal(nrow(b), 1L)
  # With a ZIP5 that DOES hit, the city block is never consulted, so a
  # reference row sharing the city but not the ZIP cannot be emitted.
  r <- ref_fix(); r$zip5[1] <- "30328"
  expect_equal(nrow(pf_fuzzy_candidates(q_fix("WESMINSTER SCHOOL"), r,
                                        block = "zip5", verbose = FALSE)), 0L)
})

test_that("top_k caps what one query row can emit", {
  skip_if_not_installed("stringdist")
  r <- ref_fix()
  r$name_key[1:4] <- c("ATLANTA ANGEL", "ATLANTA ANGELS", "ATLANTA ANGELS INC",
                       "ATLANTA ANGEL S")
  r$zip5 <- "30327"; r$city <- "ATLANTA"; r$state <- "GA"
  q <- q_fix("ATLANTA ANGELS")
  expect_equal(nrow(pf_fuzzy_candidates(q, r, top_k = 2L, verbose = FALSE)), 2L)
  expect_gt(nrow(pf_fuzzy_candidates(q, r, top_k = 5L, verbose = FALSE)), 2L)
})

test_that("emitted pairs come back in descending similarity", {
  skip_if_not_installed("stringdist")
  r <- ref_fix()
  r$name_key[1:3] <- c("ATLANTA ANGELS", "ATLANTA ANGEL", "ATLANTA ANGELS INC")
  r$zip5 <- "30327"; r$city <- "ATLANTA"; r$state <- "GA"
  b <- pf_fuzzy_candidates(q_fix("ATLANTA ANGELS"), r, cutoff = 0.80, verbose = FALSE)
  s <- attr(b, "sim")
  expect_equal(s, sort(s, decreasing = TRUE))
  expect_equal(nrow(b), length(s))
})

test_that("a missing required column is an error, not a silent empty", {
  q <- q_fix("WESMINSTER SCHOOL"); q$zip5 <- NULL
  expect_error(pf_fuzzy_candidates(q, ref_fix(), verbose = FALSE), "zip5")
})

test_that("max_pool refuses an oversized block rather than scoring it", {
  skip_if_not_installed("stringdist")
  b <- pf_fuzzy_candidates(q_fix("WESMINSTER SCHOOL"), ref_fix(),
                           max_pool = 1L, verbose = FALSE)
  expect_equal(nrow(b), 0L)
})

# ---------------------------------------------------------------------------
# pf_fuzzy_recover(). Everything above tests the generator on hand-built
# frames; this runs the whole pass -- np_compare / np_score / np_veto, the
# union, the dedup, the re-tier and the movement report -- against a real
# reference built by pf_build_reference() and a real cascade. It is here
# because the tail of this function reached production with `union$fuzzy_sim`
# still referring to a renamed local: R resolves `union` to base::union in call
# position, so the file parsed, installed and ran, and the typo surfaced only
# two hours into a full-file regression, in the one branch nothing covered.
#
# The fixture is the shape of the failure the function exists for. The name is
# a SINGLE token, so a one-letter typo leaves no shared token, no acronym and
# no prefix to block on -- give the recipient two tokens and the token pass
# surfaces the record on the other one, the cascade clears it, and the pass
# under test never sees it. The street differs too, so no address pass can
# block either. G1 is therefore ABSENT from the result frame entirely, which is
# the residual case taken from the result frame alone would miss.
fz_bmf <- function() data.frame(
  ein = c("131234567", "521234567"),
  org_name_join = c("PASSIONISTS", "BETA FUND"), dba_name = c("", ""),
  org_addr_street = c("1424 W PACES FERRY RD NW", "2 OAK AVE"),
  org_addr_city = c("ATLANTA", "BOSTON"), org_addr_state = c("GA", "MA"),
  org_addr_zip5 = c("30327", "02108"), org_addr_zip4 = c("", ""),
  stringsAsFactors = FALSE)

fz_grants <- function() data.frame(
  grant_id = c("G1", "G2"),
  recip_name = c("PASSONISTS", "BETA FUND"), recip_name_alt = c(NA, NA),
  recip_street = c("PO BOX 9981", "2 OAK AVE"), recip_unit = c(NA, NA),
  recip_city = c("ATLANTA", "BOSTON"), recip_state = c("GA", "MA"),
  recip_zip5 = c("30327", "02108"), in_scope = TRUE, stringsAsFactors = FALSE)

fz_match <- function() {
  ref <- pf_build_reference(fz_bmf())
  m <- pf_match_grants(fz_grants(), ref,
                       passes = pf_staged_passes("lean", concat = TRUE),
                       verbose = FALSE, check_reference = "ignore")
  list(m = m, ref = ref)
}

test_that("the pass recovers a typo the cascade never retrieved, end to end", {
  skip_if_not_installed("stringdist")
  skip_if_not_installed("npmatch")
  f <- fz_match()
  # the premise: the typo'd identity is not in the result frame at all
  expect_false("G1" %in% as.character(as.data.frame(f$m$result)$.id))

  fr <- pf_fuzzy_recover(f$m, f$ref, cutoff = 0.90, verbose = FALSE)
  expect_equal(fr$n[["residual"]], 1L)
  expect_equal(fr$n[["pairs"]], 1L)
  expect_equal(fr$n[["promoted"]], 1L)
  expect_equal(fr$after[["YES"]], fr$before[["YES"]] + 1L)

  mv <- as.data.frame(fr$moved)
  expect_equal(nrow(mv), 1L)
  expect_equal(as.character(mv$.id), "G1")
  expect_equal(pfmatch:::.pf_ein(mv$overall_ein), "131234567")
  expect_equal(mv$tier_before, "ABSENT", ignore_attr = TRUE)
  # the line the typo lived on. An NA here means overall_ein and .ein were
  # compared in different EIN formats and every similarity is lost.
  expect_false(is.na(mv$fuzzy_sim))
  expect_gt(mv$fuzzy_sim, 0.90)
})

test_that("the already-cleared identity keeps its pair and its tier", {
  skip_if_not_installed("stringdist")
  skip_if_not_installed("npmatch")
  f <- fz_match()
  fr <- pf_fuzzy_recover(f$m, f$ref, cutoff = 0.90, verbose = FALSE)
  r0 <- as.data.frame(f$m$result); r1 <- as.data.frame(fr$result)
  i <- match("G2", as.character(r0$.id)); j <- match("G2", as.character(r1$.id))
  expect_equal(as.character(r1$tier[j]), as.character(r0$tier[i]))
  expect_equal(r1$overall_ein[j], r0$overall_ein[i])
  expect_equal(r1$overall_score[j], r0$overall_score[i])
})

test_that("a cutoff nothing reaches returns the result untouched", {
  skip_if_not_installed("stringdist")
  skip_if_not_installed("npmatch")
  f <- fz_match()
  fr <- pf_fuzzy_recover(f$m, f$ref, cutoff = 0.99, verbose = FALSE)
  expect_equal(fr$n[["pairs"]], 0L)
  expect_null(fr$after)
  expect_equal(nrow(fr$moved), 0L)
  expect_identical(fr$result, f$m$result)
})

test_that("an object without retained pairs is refused, not silently empty", {
  skip_if_not_installed("npmatch")
  f <- fz_match()
  attr(f$m$result, "pairs") <- NULL
  expect_error(pf_fuzzy_recover(f$m, f$ref, verbose = FALSE), "no `pairs`")
})
