## Checkpoint stamping -------------------------------------------------------
# The failure being guarded is silent, so these tests are about the guard
# refusing, not about it permitting: a checkpoint that is wrongly reused
# produces output nothing distinguishes from a real run
# (dev/REFIT-1K-FINDINGS.md 3a).

fake_ref <- function(n = 3L) list(reference = data.frame(
  ein = sprintf("%09d", seq_len(n)), name_key = letters[seq_len(n)],
  stringsAsFactors = FALSE))

fake_dyads <- function(n = 2L) data.frame(
  ein_a = rep("111111111", n), ein_b = rep("222222222", n),
  dyad_class = rep("substitutable", n), stringsAsFactors = FALSE)

mk <- function(ref = fake_ref(), passes = pf_staged_passes("lean"),
               config = npmatch::np_config(), method = "hier",
               recover = TRUE, self_guard = TRUE,
               dyads = NULL, dyad_config = pf_dyad_config())
  pfmatch:::.pf_run_stamp(ref, passes, config, method, recover, self_guard,
                          dyads, dyad_config)

test_that("the same call stamps the same, twice", {
  expect_identical(mk(), mk())
  expect_identical(mk(dyads = fake_dyads()), mk(dyads = fake_dyads()))
})

test_that("every setting that changes the answer changes the stamp", {
  base <- mk(dyads = fake_dyads())
  expect_false(identical(base, mk(dyads = fake_dyads(),
                                  dyad_config = pf_dyad_config(policy = "operating"))))
  expect_false(identical(base, mk(dyads = fake_dyads(),
                                  dyad_config = pf_dyad_config(keep_soft_veto = FALSE))))
  # a rebuilt dyad table with a different number of pairs
  expect_false(identical(base, mk(dyads = fake_dyads(3L))))
  # swapping the reference: this is the active-vs-augmented case
  expect_false(identical(base, mk(dyads = fake_dyads(), ref = fake_ref(4L))))
  expect_false(identical(base, mk(dyads = fake_dyads(), method = "sum")))
  expect_false(identical(base, mk(dyads = fake_dyads(), recover = FALSE)))
  expect_false(identical(base, mk(dyads = fake_dyads(), self_guard = FALSE)))
  expect_false(identical(base, mk(dyads = fake_dyads(),
                                  passes = pf_staged_passes("full"))))
  # turning the collapse off entirely
  expect_false(identical(base, mk()))
})

test_that("a reference gaining a column stamps differently", {
  r <- fake_ref(); r2 <- r; r2$reference$name_acro <- "x"
  expect_false(identical(mk(ref = r), mk(ref = r2)))
})

test_that("dyad_config is ignored when there are no dyads", {
  # it does not run, so it cannot change the answer, and stamping it would
  # refuse a resume for a setting that had no effect
  expect_identical(mk(dyad_config = pf_dyad_config(policy = "top")),
                   mk(dyad_config = pf_dyad_config(policy = "arm")))
})

test_that("an unstamped checkpoint is refused, not trusted", {
  expect_error(pfmatch:::.pf_check_stamp(NULL, mk(), "batch-0001.rds"),
               "no run stamp")
})

test_that("a mismatched checkpoint names what differs", {
  cached <- mk(dyads = fake_dyads())
  now    <- mk(dyads = fake_dyads(),
               dyad_config = pf_dyad_config(policy = "operating"))
  expect_error(pfmatch:::.pf_check_stamp(cached, now, "batch-0007.rds"),
               "dyad_config")
  expect_error(pfmatch:::.pf_check_stamp(cached, now, "batch-0007.rds"),
               "batch-0007.rds")
  expect_error(pfmatch:::.pf_check_stamp(cached, now, "batch-0007.rds"),
               "resume = FALSE")
})

test_that("a matching checkpoint passes silently", {
  s <- mk(dyads = fake_dyads())
  expect_true(pfmatch:::.pf_check_stamp(s, s, "batch-0001.rds"))
})

## The guard in place --------------------------------------------------------
# One identity and a batch size above it means every batch is cached, so
# pf_run_batches() never reaches the cascade and needs no real reference.

write_ckpt <- function(dir, stamp) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  st <- data.frame(grant_id = "G1", status = "YES", stringsAsFactors = FALSE)
  attr(st, "pf_stamp") <- stamp
  saveRDS(st, file.path(dir, "batch-0001.rds"), compress = FALSE)
}

test_that("pf_run_batches stops rather than reuse a stale checkpoint", {
  dir <- file.path(tempdir(), "pf-stale-ckpt")
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  write_ckpt(dir, mk(dyads = fake_dyads(), recover = FALSE))
  # the exact shape of the 1k finding: same dir, same dyads, different policy
  expect_error(
    pf_run_batches(data.frame(x = 1), fake_ref(), dir = dir, batch_size = 10L,
                   passes = pf_staged_passes("lean"), recover = FALSE,
                   dyads = fake_dyads(),
                   dyad_config = pf_dyad_config(policy = "operating"),
                   verbose = FALSE),
    "different settings")
})

test_that("a checkpoint written by this call is reused", {
  dir <- file.path(tempdir(), "pf-good-ckpt")
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  write_ckpt(dir, mk(dyads = fake_dyads(), recover = FALSE))
  got <- pf_run_batches(data.frame(x = 1), fake_ref(), dir = dir,
                        batch_size = 10L, passes = pf_staged_passes("lean"),
                        recover = FALSE, dyads = fake_dyads(),
                        dyad_config = pf_dyad_config(), verbose = FALSE)
  expect_equal(nrow(got), 1L)
  expect_equal(got$grant_id, "G1")
})

test_that("resume = FALSE overrides a stale checkpoint without erroring", {
  dir <- file.path(tempdir(), "pf-override-ckpt")
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  write_ckpt(dir, mk(dyads = fake_dyads(), recover = FALSE))
  # resume = FALSE recomputes, so it reaches the cascade and fails there on this
  # toy reference -- but NOT with the stamp error, which is the point
  err <- tryCatch(pf_run_batches(data.frame(x = 1), fake_ref(), dir = dir,
                                 batch_size = 10L, passes = pf_staged_passes("lean"),
                                 recover = FALSE, dyads = fake_dyads(),
                                 dyad_config = pf_dyad_config(policy = "operating"),
                                 resume = FALSE, verbose = FALSE),
                  error = function(e) conditionMessage(e))
  expect_false(grepl("different settings", paste(err, collapse = " ")))
})
