## The grant-side dictionary -------------------------------------------------
# A dictionary built from a pipeline's own output can attach one organisation's
# EIN to another organisation's grants, so the tests are mostly about the
# guards: what it refuses to key on, what it refuses to promote, and that it
# never looks at a row the cascade already cleared.

mk <- function(name, street, city = "RESTON", state = "VA", zip5 = "20190",
               status = "YES", ein = "111111111", grant_id = NULL) {
  n <- length(name)
  data.frame(
    grant_id = grant_id %||% sprintf("G%03d", seq_len(n)),
    recip_name = name, recip_street = street, recip_city = rep_len(city, n),
    recip_state = rep_len(state, n), recip_zip5 = rep_len(zip5, n),
    status = rep_len(status, n), ein = rep_len(ein, n),
    stringsAsFactors = FALSE)
}

test_that("it refuses input it cannot key on", {
  expect_error(pf_grant_dictionary(data.frame(a = 1)), "needs column")
  expect_error(pf_grant_dictionary(mk("A", "1 MAIN ST", status = "MAYBE")),
               "no rows left")
  # an unusable EIN is not a dictionary entry
  expect_error(pf_grant_dictionary(mk("A", "1 MAIN ST", ein = "12345")),
               "no rows left")
})

test_that("it builds only from cleared rows", {
  g <- rbind(mk("ALPHA FUND", "1 MAIN ST", status = "YES", ein = "111111111"),
             mk("BETA TRUST", "2 OAK RD", status = "MAYBE", ein = "222222222"),
             mk("GAMMA INC",  "3 ELM AVE", status = "NO", ein = "333333333"))
  d <- pf_grant_dictionary(g, verbose = FALSE)
  expect_equal(attr(d, "n_eins"), 1L)
  expect_equal(nrow(d$reference), 1L)
  # and MAYBE can be opted into deliberately
  d2 <- pf_grant_dictionary(g, keep = c("YES", "MAYBE"), verbose = FALSE)
  expect_equal(attr(d2, "n_eins"), 2L)
})

test_that("exclude keeps a row from answering itself", {
  g <- mk(c("ALPHA FUND", "ALPHA FOUNDATION"), c("1 MAIN ST", "1 MAIN ST"),
          grant_id = c("KEEP", "DROP"))
  d <- pf_grant_dictionary(g, exclude = "DROP", key_col = "grant_id",
                           verbose = FALSE)
  expect_equal(attr(d, "n_renderings"), 1L)
  expect_error(pf_grant_dictionary(g, exclude = "DROP", key_col = "nope",
                                   verbose = FALSE))
})

test_that("an ambiguous (name, zip5) is dropped, not guessed", {
  # One rendering, one ZIP, two EINs: the collision this must never resolve by
  # picking. HABITAT FOR HUMANITY is 39 EINs in the real dictionary.
  g <- rbind(mk("HABITAT FOR HUMANITY", "1 MAIN ST", ein = "111111111"),
             mk("HABITAT FOR HUMANITY", "9 OTHER ST", ein = "222222222"))
  # Here every entry is ambiguous, so the dictionary empties and says so rather
  # than handing a zero-row reference onward.
  expect_error(pf_grant_dictionary(g, verbose = FALSE), "dictionary is empty")
  expect_error(pf_grant_dictionary(g, verbose = FALSE), "ambiguous")
})

test_that("an ambiguous key is dropped while the rest survive", {
  g <- rbind(mk("HABITAT FOR HUMANITY", "1 MAIN ST", ein = "111111111"),
             mk("HABITAT FOR HUMANITY", "9 OTHER ST", ein = "222222222"),
             mk("ALPHA FUND", "3 ELM AVE", ein = "333333333"))
  d <- pf_grant_dictionary(g, verbose = FALSE)
  expect_equal(attr(d, "ambiguous_dropped"), 2L)
  expect_equal(nrow(d$reference), 1L)
  expect_equal(attr(d, "n_eins"), 1L)
})

test_that("the same name in different ZIPs is kept", {
  g <- rbind(mk("HABITAT FOR HUMANITY", "1 MAIN ST", zip5 = "20190",
                ein = "111111111"),
             mk("HABITAT FOR HUMANITY", "9 OTHER ST", zip5 = "22180",
                ein = "222222222"))
  d <- pf_grant_dictionary(g, verbose = FALSE)
  expect_equal(attr(d, "ambiguous_dropped"), 0L)
  expect_equal(nrow(d$reference), 2L)
})

test_that("the bundle carries the normalizer and the statistics it used", {
  d <- pf_grant_dictionary(mk("ALPHA FUND", "1 MAIN ST"), verbose = FALSE)
  expect_named(d, c("reference", "name_freq", "token_idf", "ref_index",
                    "normalizer"), ignore.order = TRUE)
  live <- tryCatch(npmatch::np_normalize_signature(), error = function(e) NA_character_)
  skip_if(is.na(live))
  expect_identical(d$normalizer, live)
  expect_silent(pf_check_reference(d))
})

test_that("statistics can be borrowed instead of computed", {
  g <- mk(c("ALPHA FUND", "BETA TRUST"), c("1 MAIN ST", "2 OAK RD"),
          zip5 = c("20190", "22180"), ein = c("111111111", "222222222"))
  own <- pf_grant_dictionary(g, verbose = FALSE)
  lent <- pf_grant_dictionary(g, stats = own, verbose = FALSE)
  expect_identical(lent$name_freq, own$name_freq)
  expect_identical(lent$token_idf, own$token_idf)
})

## the acceptance rule -------------------------------------------------------
# Tested apart from the cascade: this is the decision the whole pass turns on.

test_that("accept = agree promotes only corroborated recoveries", {
  hit    <- c(TRUE, TRUE, TRUE, FALSE)
  agrees <- c(TRUE, FALSE, NA,   TRUE)
  expect_equal(pfmatch:::.pf_dict_accept(hit, agrees, "agree"),
               c(TRUE, FALSE, FALSE, FALSE))
  expect_equal(pfmatch:::.pf_dict_accept(hit, agrees, "all"),
               c(TRUE, TRUE, TRUE, FALSE))
  expect_equal(pfmatch:::.pf_dict_accept(hit, agrees, "none"), rep(FALSE, 4L))
})

test_that("an uncorroborated agreement is not an agreement", {
  # NA means the BMF named no candidate, so there is nothing to corroborate the
  # dictionary against. That is a new claim, not a confirmation.
  expect_false(pfmatch:::.pf_dict_accept(TRUE, NA, "agree"))
  expect_false(pfmatch:::.pf_dict_accept(NA, TRUE, "agree"))
})

test_that("the recovery pass refuses malformed input and short-circuits", {
  d <- pf_grant_dictionary(mk("ALPHA FUND", "1 MAIN ST"), verbose = FALSE)
  rec <- data.frame(grant_id = "G001", stringsAsFactors = FALSE)
  expect_error(pf_recover_from_dictionary(data.frame(x = 1), d, rec),
               "grant_id")
  expect_error(pf_recover_from_dictionary(
    data.frame(grant_id = "G001", status = "MAYBE", ein = NA_character_,
               stringsAsFactors = FALSE), d, data.frame(x = 1)), "grant_id")
  # nothing unresolved: it must not run a cascade at all
  allyes <- data.frame(grant_id = "G001", status = "YES", ein = "111111111",
                       stringsAsFactors = FALSE)
  out <- pf_recover_from_dictionary(allyes, d, rec, verbose = FALSE)
  expect_equal(attr(out, "counts")[["retried"]], 0L)
  expect_equal(nrow(out), 1L)
})
