## The variant corpus as a normalizer regression test ------------------------
# pf_variants holds 5,410 pairs that reached the comparator and split. Each
# carries the raw filed strings AND the keys np_normalize() made of them, so
# the keys can be recomputed and compared. Two kinds of test here:
#
#   1. INVARIANTS that should hold under any sane normalizer -- a leading THE
#      is dropped, & and AND agree, a USPS suffix spelling does not matter.
#      These must never break.
#   2. A PINNED check that every recorded key still reproduces. This one is
#      version-scoped: it skips when the installed normalizer is not the one
#      the fixture was built under, because an intentional improvement SHOULD
#      move keys. When it skips, rebuild with data-raw/make-pf-variants.R.

keys_for <- function(name, street, unit, city, state, zip5) {
  g <- data.frame(grant_id = seq_along(name), recip_name = name,
                  recip_name_alt = NA_character_, recip_street = street,
                  recip_unit = unit, recip_city = city, recip_state = state,
                  recip_zip5 = zip5, stringsAsFactors = FALSE)
  as.data.frame(npmatch::np_normalize(npmatch::np_query(g, pf_map_grants())))
}
side <- function(v, s) keys_for(v[[paste0(s, "_name")]], v[[paste0(s, "_street")]],
                                v[[paste0(s, "_unit")]], v[[paste0(s, "_city")]],
                                v[[paste0(s, "_state")]], v[[paste0(s, "_zip5")]])

test_that("the corpus is shaped as documented", {
  v <- pfmatch::pf_variants
  expect_s3_class(v, "data.frame")
  expect_gt(nrow(v), 5000L)
  expect_true(all(v$a_status == "YES"), info = "side a is the resolved rendering")
  expect_true(all(v$b_status == "MAYBE"))
  # the group key pins ZIP5, so it can never disagree inside a pair
  expect_true(all(v$zip5_equal))
  expect_true(all(v$a_zip5 == v$b_zip5))
})

test_that("labels are present only where a basis is recorded", {
  v <- pfmatch::pf_variants
  # never FALSE: absence of evidence is recorded as NA, not as a negative
  expect_setequal(unique(v$expected_same_org), c(TRUE, NA))
  expect_true(all(v$label_basis[is.na(v$expected_same_org)] == "unadjudicated"))
  expect_true(all(v$label_basis[!is.na(v$expected_same_org)] != "unadjudicated"))
  expect_true(all(is.na(v$label_confidence) == is.na(v$expected_same_org)))
  # a label is only claimed where the address is identical
  expect_true(all(v$addr_class[!is.na(v$expected_same_org)] == "identical"))
})

test_that("no individual's name is shipped as test data", {
  v <- pfmatch::pf_variants
  expect_false(any(pfmatch:::.pf_looks_personal(v$a_name)))
  expect_false(any(pfmatch:::.pf_looks_personal(v$b_name)))
})

## 1. invariants ---------------------------------------------------------------

test_that("a leading THE never decides a name key", {
  v <- pfmatch::pf_variants[pfmatch::pf_variants$name_class == "leading THE", ]
  skip_if(nrow(v) == 0L)
  expect_identical(side(v, "a")$name_key, side(v, "b")$name_key)
})

test_that("& and AND normalize together", {
  v <- pfmatch::pf_variants[pfmatch::pf_variants$name_class == "and vs ampersand", ]
  skip_if(nrow(v) == 0L)
  expect_identical(side(v, "a")$name_key, side(v, "b")$name_key)
})

## These two were written against the fixture's recorded `street_key_equal`,
## which made them look like invariants while actually pinning them to the
## normalizer that built the fixture. When npmatch's word-boundary fix landed
## they failed, and the failure was the stale column, not a regression. State
## the invariant on literal strings instead, so it holds across any normalizer,
## and leave fixture-column comparisons to the signature-gated test below.

street_key_of <- function(st) {
  g <- data.frame(grant_id = seq_along(st), recip_name = "X",
                  recip_name_alt = NA_character_, recip_street = st,
                  recip_unit = NA_character_, recip_city = "A",
                  recip_state = "VA", recip_zip5 = "22030",
                  stringsAsFactors = FALSE)
  as.data.frame(npmatch::np_normalize(
    npmatch::np_query(g, pf_map_grants())))$street_key
}

test_that("street normalization reconciles the spellings it must", {
  # A spelled-out suffix, a separated suite in any of its three forms, and a
  # directional: these are what the street normalizer exists for.
  expect_equal(length(unique(street_key_of(c("2 Oak Road", "2 OAK RD")))), 1L)
  expect_equal(length(unique(street_key_of(
    c("2121 I Street NW", "2121 I ST NW")))), 1L)
  expect_equal(length(unique(street_key_of(
    c("1 Main Street Suite 5", "1 MAIN ST STE 5", "1 MAIN ST # 5")))), 1L)
})

test_that("street normalization does not over-reach", {
  # Genuinely different streets must stay different. A normalizer that
  # collapsed these would merge distinct addresses and inflate every group.
  expect_equal(length(unique(street_key_of(c("1 MAIN ST", "2 MAIN ST")))), 2L)
  expect_equal(length(unique(street_key_of(c("1 MAIN ST", "1 MAIN AVE")))), 2L)
  expect_equal(length(unique(street_key_of(c("1 N MAIN ST", "1 S MAIN ST")))), 2L)
})

test_that("a suite fused to the street word is NOT silently split", {
  # "4550 WEST 77TH STREETSUITE 200" has no boundary before SUITE. npmatch
  # deliberately refuses it: the pattern that caught this form also matched
  # inside ordinary words, false on 27,954 BMF rows (SHERMAN WAY giving room
  # "AN WAY"), and masked the real unit on 3,636 of them. pfmatch measured 9
  # pairs reconciled by the permissive form; that is the price and it is worth
  # paying. Asserted so nobody "fixes" it back.
  k <- street_key_of(c("4550 WEST 77TH STREETSUITE 200",
                       "4550 West 77th Street Suite 200"))
  expect_false(identical(k[1], k[2]))
})

test_that("city spelling cannot change a blocked pass", {
  # The cascade blocks on name_key/dba_key crossed with zip5/state and never
  # reads city (pf_staged_passes()). FT LAUDERDALE against Fort Lauderdale is
  # therefore cosmetic: blocking must remain intact across every such pair.
  v <- pfmatch::pf_variants
  v <- v[v$city_differs & !v$state_differs, ]
  skip_if(nrow(v) == 0L)
  expect_true(all(v$blocking_intact))
})

## 2. pinned to the normalizer the fixture was built under ---------------------

test_that("every recorded key reproduces under the pinned normalizer", {
  v <- pfmatch::pf_variants
  built <- attr(v, "normalizer")
  live  <- tryCatch(npmatch::np_normalize_signature(), error = function(e) NA_character_)
  skip_if(is.na(built) || is.na(live))
  skip_if_not(identical(built, live),
              sprintf(paste("normalizer moved (fixture %s, installed %s);",
                            "rebuild with data-raw/make-pf-variants.R"), built, live))
  ka <- side(v, "a"); kb <- side(v, "b")
  expect_identical(ka$name_key,   v$a_name_key)
  expect_identical(kb$name_key,   v$b_name_key)
  expect_identical(ka$street_key, v$a_street_key)
  expect_identical(kb$street_key, v$b_street_key)
  # and the derived comparisons the corpus is read through
  expect_identical(ka$name_key == kb$name_key & nzchar(ka$name_key), v$name_key_equal)
  expect_identical(ka$street_key == kb$street_key, v$street_key_equal)
})
