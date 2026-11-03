# Comparing two runs.
#
# Most of these tests pin REFUSALS. That is deliberate: every number this
# function can return is correct arithmetic over whatever it was handed, so the
# only place it can protect a reader is at the door. The three refusals each
# close a failure that happened on this project -- positional ids joining to a
# base rate, an empty intersection reading as "nothing moved", and two
# conventions meeting.

ids3 <- pf_identity_id(c("A ORG\r1 MAIN ST\r59715",
                         "B ORG\r2 OAK AVE\r10001",
                         "C ORG\r3 ELM RD\r94107"))

fake_run <- function(ids = ids3,
                     status = c("YES", "MAYBE", "NO"),
                     ein = c("123456789", "234567891", NA),
                     score = c(0.98, 0.94, 0.80),
                     margin = c(0.06, 0.004, 0.01),
                     n_close = c(1, 2, 3),
                     pass = c("A1-name-state", "B2-token", NA),
                     name = c("A ORG", "B ORG", "C ORG"),
                     city = c("BOZEMAN", "NEW YORK", "SAN FRANCISCO"),
                     state = c("MT", "NY", "CA"),
                     stamp = NULL) {
  d <- data.frame(grant_id = ids, recip_name = name, recip_city = city,
                  recip_state = state,
                  status = factor(status, pf_status_levels()),
                  ein = ein, score = score, margin = margin,
                  n_close = n_close, match_pass = pass,
                  stringsAsFactors = FALSE)
  if (!is.null(stamp)) attr(d, "pf_stamp") <- stamp
  d
}

# ---------------------------------------------------------------- stamp diff

test_that("identical stamps report every setting as same and none moved", {
  s <- list(method = "fast", recover = TRUE, normalizer = "v1-abc")
  d <- pf_stamp_diff(structure(1, pf_stamp = s), structure(1, pf_stamp = s))
  expect_true(all(d$status == "same"))
  expect_equal(nrow(d), 3L)
  expect_match(paste(capture.output(print(d)), collapse = "\n"),
               "0 of 3 settings moved")
})

test_that("a changed scalar is named with both values", {
  d <- pf_stamp_diff(structure(1, pf_stamp = list(method = "fast")),
                     structure(1, pf_stamp = list(method = "full")))
  expect_equal(d$status, "changed")
  expect_equal(d$before, "fast")
  expect_equal(d$after, "full")
})

test_that("a setting present on one side only is added or removed, not changed", {
  d <- pf_stamp_diff(structure(1, pf_stamp = list(method = "fast")),
                     structure(1, pf_stamp = list(method = "fast", dyads = NULL)))
  expect_equal(d$status[d$key == "dyads"], "added")
})

test_that("value equality beats representation, as in the resume check", {
  # the CI failure this mirrors: two np_config() calls serialized differently
  # on one platform and identically on another
  d <- pf_stamp_diff(structure(1, pf_stamp = list(k = 1L)),
                     structure(1, pf_stamp = list(k = 1)))
  expect_equal(d$status, "same")
})

test_that("a config component is named, with absent on the side that lacks it", {
  a <- list(config = list(threshold = 0.9))
  b <- list(config = list(threshold = 0.9, distinct_name_min_idf = 6.5))
  d <- pf_stamp_diff(structure(1, pf_stamp = a), structure(1, pf_stamp = b))
  expect_equal(d$status[is.na(d$item)], "changed")
  sub <- d[!is.na(d$item), ]
  expect_equal(sub$item, "distinct_name_min_idf")
  expect_equal(sub$status, "added")
  expect_true(is.na(sub$before))
  expect_equal(sub$after, "6.5")
  expect_match(paste(capture.output(print(d)), collapse = "\n"),
               "distinct_name_min_idf: absent -> 6.5")
})

test_that("a column set reports what was added and removed, not a mismatch count", {
  a <- list(ref_cols = c("ein", "name_key", "state"))
  b <- list(ref_cols = c("ein", "name_key", "state", "n_cand"))
  d <- pf_stamp_diff(structure(1, pf_stamp = a), structure(1, pf_stamp = b))
  sub <- d[!is.na(d$item), ]
  expect_equal(sub$item, "added")
  expect_equal(sub$after, "n_cand")
})

test_that("a pass table is diffed by pass name and argument", {
  mk <- function(idf) list(
    list(name = "A1-name-state", args = list(by = c("state", "name_key"))),
    list(name = "B2-token", args = list(token = TRUE, min_pair_idf = idf)))
  a <- list(passes = mk(4.0))
  b <- list(passes = mk(6.5))
  d <- pf_stamp_diff(structure(1, pf_stamp = a), structure(1, pf_stamp = b))
  expect_equal(d$before[is.na(d$item)], "2 passes")
  sub <- d[!is.na(d$item), ]
  expect_equal(sub$item, "B2-token / min_pair_idf")
  expect_equal(sub$before, "4")
  expect_equal(sub$after, "6.5")
})

test_that("a pass added or removed is named as such", {
  a <- list(passes = list(list(name = "A1", args = list())))
  b <- list(passes = list(list(name = "A1", args = list()),
                          list(name = "D1-acro", args = list())))
  d <- pf_stamp_diff(structure(1, pf_stamp = a), structure(1, pf_stamp = b))
  sub <- d[!is.na(d$item), ]
  expect_equal(sub$item, "D1-acro")
  expect_equal(sub$status, "added")
})

test_that("an unstamped side errors and says which side and what to do", {
  s <- structure(1, pf_stamp = list(method = "fast"))
  expect_error(pf_stamp_diff(data.frame(x = 1), s), "before carries no pf_stamp")
  expect_error(pf_stamp_diff(s, data.frame(x = 1)), "after carries no pf_stamp")
  expect_error(pf_stamp_diff(s, data.frame(x = 1)), "pf_run_batches")
})

test_that("stamps are read from a path as well as an object", {
  f <- withr::local_tempfile(fileext = ".rds")
  saveRDS(structure(data.frame(x = 1), pf_stamp = list(method = "fast")), f)
  d <- pf_stamp_diff(f, structure(1, pf_stamp = list(method = "full")))
  expect_equal(d$before, "fast")
  expect_error(pf_stamp_diff("no-such-file.rds", f), "no such file")
})

test_that("print warns when more than one setting moved", {
  a <- list(method = "fast", recover = TRUE)
  b <- list(method = "full", recover = FALSE)
  out <- paste(capture.output(print(pf_stamp_diff(
    structure(1, pf_stamp = a), structure(1, pf_stamp = b)))), collapse = "\n")
  expect_match(out, "2 of 2 settings moved")
  expect_match(out, "no effect can be attributed")
})

# --------------------------------------------------------------- compare runs

test_that("the flow matrix is computed, and reports a promotion", {
  a <- fake_run()
  b <- fake_run(status = c("YES", "YES", "NO"))
  cm <- pf_compare_runs(a, b)
  expect_s3_class(cm, "pf_compare")
  expect_equal(cm$ids$n_both, 3L)
  expect_equal(cm$flow["MAYBE", "YES"], 1L)
  expect_equal(cm$flow["YES", "YES"], 1L)
  expect_equal(cm$net$delta[cm$net$tier == "YES"], 1L)
  expect_equal(cm$net$delta[cm$net$tier == "MAYBE"], -1L)
  expect_equal(nrow(cm$transitions), 1L)
  expect_equal(cm$transitions$from, "MAYBE")
  expect_equal(cm$transitions$to, "YES")
})

test_that("churn is reported alongside the net, and is the larger number", {
  a <- fake_run(status = c("YES", "MAYBE", "NO"))
  b <- fake_run(status = c("MAYBE", "YES", "NO"))
  cm <- pf_compare_runs(a, b)
  # one each way: net zero, churn two
  expect_equal(cm$net$delta[cm$net$tier == "YES"], 0L)
  expect_equal(sum(cm$net$churn_out), 2L)
  expect_match(paste(capture.output(print(cm)), collapse = "\n"),
               "churn is the number to read")
})

test_that("a case that keeps its tier and changes EIN is counted, not hidden", {
  a <- fake_run()
  b <- fake_run(ein = c("999999999", "234567891", NA))
  cm <- pf_compare_runs(a, b)
  expect_equal(sum(cm$flow[cbind(1:4, 1:4)]), 3L)   # nothing moved tier
  expect_equal(cm$same_tier_new_ein, 1L)
  expect_true(any(cm$moved$ein_changed))
  expect_equal(cm$moved$before_ein[cm$moved$ein_changed], "123456789")
  expect_match(paste(capture.output(print(cm)), collapse = "\n"),
               "invisible in the matrix above")
})

test_that("a pass change with the same tier and EIN still reaches the moved frame", {
  a <- fake_run()
  b <- fake_run(pass = c("D1-acro", "B2-token", NA))
  cm <- pf_compare_runs(a, b)
  expect_equal(nrow(cm$moved), 1L)
  expect_true(cm$moved$pass_changed)
  expect_equal(cm$moved$before_pass, "A1-name-state")
  expect_equal(cm$moved$after_pass, "D1-acro")
})

test_that("score and margin deltas are carried per case", {
  a <- fake_run()
  b <- fake_run(status = c("YES", "YES", "NO"), score = c(0.98, 0.98, 0.80),
                margin = c(0.06, 0.058, 0.01))
  cm <- pf_compare_runs(a, b)
  m <- cm$moved[cm$moved$before_status == "MAYBE", ]
  expect_equal(m$score_delta, 0.04)
  expect_equal(m$before_margin, 0.004)
  expect_equal(m$after_margin, 0.058)
})

test_that("positional ids refuse the join and name both shapes", {
  a <- fake_run(ids = c("R1", "R2", "R3"))
  b <- fake_run()
  expect_error(pf_compare_runs(a, b), "cannot be joined on id")
  expect_error(pf_compare_runs(a, b), "\\^R\\[0-9\\]\\+\\$", fixed = FALSE)
  expect_error(pf_compare_runs(a, b), "PF\\[IX\\]")
  # and it says what to do instead
  expect_error(pf_compare_runs(a, b), "by = \"name\"")
  expect_error(pf_compare_runs(a, b), "base rate")
})

test_that("positional ids on BOTH sides are refused too", {
  # the dangerous case: the shapes agree, so a shape comparison alone passes
  a <- fake_run(ids = c("R1", "R2", "R3"))
  b <- fake_run(ids = c("R1", "R2", "R3"))
  expect_error(pf_compare_runs(a, b), "cannot be joined on id")
})

test_that("a name join is allowed, marked approximate, and drops ambiguous keys", {
  a <- fake_run(ids = c("R1", "R2", "R3"))
  b <- fake_run(ids = c("R7", "R8", "R9"), status = c("YES", "YES", "NO"))
  cm <- pf_compare_runs(a, b, by = "name")
  expect_true(cm$approximate)
  expect_equal(cm$ids$n_both, 3L)
  expect_equal(cm$flow["MAYBE", "YES"], 1L)
  expect_match(paste(capture.output(print(cm)), collapse = "\n"), "APPROXIMATE")

  # two identities with the same name, city and state cannot be joined 1:1
  a2 <- fake_run(ids = c("R1", "R2", "R3"), name = c("A ORG", "A ORG", "C ORG"),
                 city = c("BOZEMAN", "BOZEMAN", "SAN FRANCISCO"),
                 state = c("MT", "MT", "CA"))
  cm2 <- pf_compare_runs(a2, a2, by = "name")
  expect_equal(cm2$ids$n_ambiguous, 1L)
  expect_equal(cm2$ids$n_both, 1L)
  expect_match(paste(capture.output(print(cm2)), collapse = "\n"),
               "not unique on both sides")
})

test_that("an empty intersection errors rather than reporting that nothing moved", {
  a <- fake_run()
  b <- fake_run(ids = pf_identity_id(c("X\r\r", "Y\r\r", "Z\r\r")))
  expect_error(pf_compare_runs(a, b), "share no cases")
  expect_error(pf_compare_runs(a, b), "nothing moved")
})

test_that("the result-frame convention is refused against the status convention", {
  a <- fake_run()
  b <- fake_run()
  b$status <- c("YES", "MAYBE", "REVIEW")
  expect_error(pf_compare_runs(a, b), "not pf_status_levels")
  expect_error(pf_compare_runs(a, b), "pf_result_tiers")
  expect_error(pf_compare_runs(a, b), "REVIEW")
})

test_that("a missing status is an error, not a dropped case", {
  a <- fake_run()
  b <- fake_run()
  b$status <- factor(c("YES", NA, "NO"), pf_status_levels())
  expect_error(pf_compare_runs(a, b), "no status")
  expect_error(pf_compare_runs(a, b), "denominator")
})

test_that("a frame that is not one row per identity is refused", {
  a <- fake_run()
  dup <- rbind(a, a)
  expect_error(pf_compare_runs(dup, a), "duplicated grant_id")
  expect_error(pf_compare_runs(dup, a), "concatenated twice")
})

test_that("a frame missing the comparison columns says so, naming them", {
  a <- fake_run()
  expect_error(pf_compare_runs(data.frame(grant_id = "PFI-0"), a),
               "missing status")
  expect_error(pf_compare_runs(data.frame(status = "YES"), a),
               "missing grant_id")
  expect_error(pf_compare_runs(list(nope = 1), a), "not a pf_status")
})

test_that("population entries and exits are counted apart from outcome changes", {
  a <- fake_run()
  b <- fake_run(ids = c(ids3[1:2], pf_identity_id("NEW\r\r")),
                status = c("YES", "MAYBE", "YES"))
  cm <- pf_compare_runs(a, b)
  expect_equal(cm$ids$n_both, 2L)
  expect_equal(cm$ids$n_before_only, 1L)
  expect_equal(cm$ids$n_after_only, 1L)
  # the arriving case is NOT counted as a promotion
  expect_equal(sum(cm$flow), 2L)
  expect_equal(nrow(cm$moved), 0L)
  out <- paste(capture.output(print(cm)), collapse = "\n")
  expect_match(out, "left the population")
  expect_match(out, "entered the population")
})

test_that("a status frame is read from a path, and from a list with $status", {
  f <- withr::local_tempfile(fileext = ".rds")
  saveRDS(fake_run(status = c("YES", "YES", "NO")), f)
  cm <- pf_compare_runs(fake_run(), f)
  expect_equal(cm$flow["MAYBE", "YES"], 1L)
  cm2 <- pf_compare_runs(fake_run(), list(status = fake_run(status = c("YES", "YES", "NO"))))
  expect_equal(cm2$flow["MAYBE", "YES"], 1L)
})

test_that("the stamp diff is attached when both sides carry one, and NULL otherwise", {
  a <- fake_run(stamp = list(method = "fast"))
  b <- fake_run(status = c("YES", "YES", "NO"), stamp = list(method = "full"))
  cm <- pf_compare_runs(a, b)
  expect_s3_class(cm$stamp, "pf_stamp_diff")
  expect_equal(cm$stamp$status, "changed")
  expect_match(paste(capture.output(print(cm)), collapse = "\n"),
               "WHAT CHANGED BETWEEN THE RUNS")

  plain <- pf_compare_runs(fake_run(), fake_run(status = c("YES", "YES", "NO")))
  expect_null(plain$stamp)
  expect_match(paste(capture.output(print(plain)), collapse = "\n"),
               "must not be claimed")
})

test_that("comparing a run against itself moves nothing", {
  # the zero-delta case is the right first test of the machinery: any non-zero
  # number here is a bug in the comparison, not a finding about the pipeline
  a <- fake_run()
  cm <- pf_compare_runs(a, a)
  expect_equal(sum(cm$net$churn_out), 0L)
  expect_equal(nrow(cm$moved), 0L)
  expect_equal(cm$same_tier_new_ein, 0L)
  expect_true(all(cm$net$delta == 0L))
  expect_equal(nrow(cm$transitions), 0L)
})
