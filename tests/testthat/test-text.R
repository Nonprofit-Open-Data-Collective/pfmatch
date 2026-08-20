test_that("the bundled NTEE lookup is keyed both ways", {
  n <- pf_ntee_text()
  expect_named(n, c("by_v2", "by_legacy", "codes"))
  expect_gt(nrow(n$by_v2), 1000)
  expect_gt(nrow(n$by_legacy), 400)
  expect_true(all(nzchar(n$by_v2$key)))
  expect_false(any(duplicated(n$by_legacy$key)))
  # the legacy key is the three-character code, the v2 key the three-part one
  expect_true(any(n$by_legacy$key == "A23"))
  expect_true(any(grepl("^[A-Z]{3}-", n$by_v2$key)))
})

test_that("a replacement lookup must have the right shape", {
  expect_error(pf_ntee_text(list(by_v2 = data.frame())), "by_v2.*by_legacy")
})
