## The reference bundle carries the normalizer that built it ----------------
# Checkpoints have been stamped since .pf_run_stamp(), but a fresh run against
# a cached REF-augmented.rds had nothing to catch a normalizer upgrade. The
# bundle holds name_key and street_key, and name_freq, token_idf and ref_index
# all derive from them, so the whole thing is a function of the normalizer. A
# stale bundle resolves fewer rows and says nothing about why -- which is the
# failure this guards, and the reason it stops rather than warns.

live <- tryCatch(npmatch::np_normalize_signature(), error = function(e) NA_character_)

bundle <- function(sig = live) {
  b <- list(reference = data.frame(ein = "123456789", name_key = "A",
                                   stringsAsFactors = FALSE),
            name_freq = NULL, token_idf = NULL, ref_index = NULL)
  if (!is.null(sig)) b$normalizer <- sig
  b
}

test_that("a bundle built by the installed normalizer passes", {
  skip_if(is.na(live))
  expect_silent(pf_check_reference(bundle()))
  expect_identical(pf_check_reference(bundle())$normalizer, live)
})

test_that("a bundle from a different normalizer is refused", {
  skip_if(is.na(live))
  b <- bundle("v1-deadbeefdeadbeef")
  expect_error(pf_check_reference(b), "built by a different normalizer")
  expect_error(pf_check_reference(b), "v1-deadbeefdeadbeef", fixed = TRUE)
  expect_error(pf_check_reference(b, "stop"))
  expect_warning(pf_check_reference(b, "warn"), "different normalizer")
  expect_silent(pf_check_reference(b, "ignore"))
})

test_that("an unstamped bundle warns rather than blocks", {
  skip_if(is.na(live))
  b <- bundle(NULL)
  expect_null(b$normalizer)
  expect_warning(pf_check_reference(b), "no normalizer stamp")
  expect_error(pf_check_reference(b, "stop"), "predates reference stamping")
  expect_warning(pf_check_reference(b, "warn"), "no normalizer stamp")
})

test_that("a bare reference frame is let through", {
  # Callers may pass a plain frame rather than a bundle; there is nothing to
  # check and refusing would break them.
  skip_if(is.na(live))
  expect_silent(pf_check_reference(
    data.frame(ein = "1", name_key = "A", stringsAsFactors = FALSE)))
})

test_that("pf_build_reference stamps what it returns", {
  # Exercised without a BMF: the stamp is added unconditionally, so a tiny
  # frame through the real function is enough to prove it is recorded.
  skip_if(is.na(live))
  skip_if_not_installed("npmatch")
  # Columns named from np_map_bmf() itself, so a rename upstream surfaces here
  # rather than being hard-coded into the fixture.
  bmf <- as.data.frame(stats::setNames(
    list(c("111111111", "222222222"), c("ALPHA FUND", "BETA TRUST"),
         c("", ""), c("1 MAIN ST", "2 OAK RD"), c("RESTON", "VIENNA"),
         c("VA", "VA"), c("20190", "22180"), c("", "")),
    unname(npmatch::np_map_bmf())), stringsAsFactors = FALSE)
  got <- pf_build_reference(bmf)
  expect_identical(got$normalizer, live)
  expect_silent(pf_check_reference(got))
})

test_that("a matchdb tier's own stamp is read, not reported as missing", {
  # pf_reference(source = "matchdb") returns a tier whose signature lives at
  # stamp$normalize_signature. Reading only `normalizer` would call a stamped
  # tier unstamped and downgrade a real mismatch to a warning.
  skip_if(is.na(live))
  tier <- function(sig) list(
    reference = data.frame(ein = "1", name_key = "A", stringsAsFactors = FALSE),
    source = "matchdb", stamp = list(spec_hash = "abc",
                                     normalize_signature = sig))
  expect_silent(pf_check_reference(tier(live)))
  expect_error(pf_check_reference(tier("v1-deadbeefdeadbeef")),
               "built by a different normalizer")
  # and a tier with no stamp at all still falls back to the warning
  t0 <- tier(live); t0$stamp$normalize_signature <- NULL
  expect_warning(pf_check_reference(t0), "no normalizer stamp")
})
