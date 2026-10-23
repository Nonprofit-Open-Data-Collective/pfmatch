## Reference partitioning -----------------------------------------------------
# Every test here is a defect that actually occurred while validating the
# partition against BASELINE-2026-08, not a hypothetical. Each one cost a
# ~20-minute validation run to find.

fake_bundle <- function() {
  r <- data.frame(
    .ein  = sprintf("%09d", 1:9),
    name  = c("ALPHA", "BETA", "GAMMA", "DELTA", "EPS", "ZETA", "ETA", "THETA", "IOTA"),
    name_key = c("ALPHA", "BETA", "GAMMA", "DELTA", "EPS", "ZETA", "ETA", "THETA", "IOTA"),
    name_acro = paste(c("ALPHA","BETA","GAMMA","DELTA","EPS","ZETA","ETA","THETA","IOTA"), "X"),
    state = c("CA", "CA", "CA", "NY", "NY", "TX", NA, "", "WY"),
    zip5  = sprintf("%05d", 1:9),
    stringsAsFactors = FALSE)
  list(reference = r,
       ref_index = npmatch::np_ref_index(r),
       name_freq = npmatch::np_name_freq(r$name_key),
       token_idf = npmatch::np_token_idf(r$name_key))
}

test_that("every reference row lands in exactly one shard", {
  p <- pf_partition_reference(fake_bundle(), min_rows = 1L, verbose = FALSE)
  n <- sum(vapply(p, function(s) nrow(s$reference), integer(1)))
  expect_equal(n, 9L)
  eins <- unlist(lapply(p, function(s) s$reference$.ein), use.names = FALSE)
  expect_equal(anyDuplicated(eins), 0L)
})

test_that("rows with no state get their own shard rather than being dropped", {
  # A query with no state can still match a reference row with no state under a
  # state-blocked pass -- the block key is built from the field as it stands.
  # Dropping them lost HILLENGALE HHH -> HIS HELPING HANDS from the benchmark.
  p <- pf_partition_reference(fake_bundle(), min_rows = 1L, verbose = FALSE)
  expect_true("_NONE" %in% names(p))
  expect_equal(nrow(p[["_NONE"]]$reference), 2L)   # one NA, one ""
})

test_that("shards carry WHOLE-CORPUS statistics, not slice-local ones", {
  # This is the entire reason a shard can reproduce the unsliced blocking:
  # np_block() gates on document frequency and log(n_ref / df), both of which
  # describe California rather than the country if rebuilt on a slice.
  b <- fake_bundle()
  p <- pf_partition_reference(b, min_rows = 1L, verbose = FALSE)
  for (s in p) {
    expect_identical(s$ref_index$n_reference, b$ref_index$n_reference)
    expect_identical(s$ref_index$df_base, b$ref_index$df_base)
    expect_identical(s$ref_index$df_concat, b$ref_index$df_concat)
  }
  # ...while the row indices must be slice-positional, or the join returns rows
  # from a frame the shard does not hold
  expect_true(all(p[["CA"]]$ref_index$base$row <= nrow(p[["CA"]]$reference)))
})

test_that("an index is built for every token column the passes block on", {
  # np_block() silently rebuilds an index whose token_col does not match, using
  # the reference it was handed -- the slice -- which reintroduces slice-local
  # gating for that pass alone. D1-acronym blocks on name_acro.
  p <- pf_partition_reference(fake_bundle(), min_rows = 1L, verbose = FALSE)
  expect_true(all(c("name_key", "name_acro") %in% names(p[["CA"]]$ref_index_by)))
  expect_identical(p[["CA"]]$ref_index_by$name_acro$token_col, "name_acro")
  expect_identical(p[["CA"]]$ref_index_by$name_key$token_col, "name_key")
})

test_that("small states are merged so the territories do not each pay a process", {
  p <- pf_partition_reference(fake_bundle(), min_rows = 2L, verbose = FALSE)
  expect_true("_SMALL" %in% names(p))
  expect_false("WY" %in% names(p))     # 1 row, under min_rows
})

## Routing --------------------------------------------------------------------

test_that("queries route on the normalized state, and stateless ones are kept", {
  q <- data.frame(state = c("CA", "NY", NA, "", "ZZ"), stringsAsFactors = FALSE)
  r <- pf_route_queries(q, c("CA", "NY", "_NONE", "_SMALL"))
  expect_equal(r[1:2], c("CA", "NY"))
  expect_equal(r[3:4], c("_NONE", "_NONE"))
  expect_equal(r[5], "_SMALL")         # unknown state falls to the merged shard
})

test_that("with no _SMALL shard an unknown state still routes somewhere", {
  q <- data.frame(state = "ZZ", stringsAsFactors = FALSE)
  expect_equal(pf_route_queries(q, c("CA", "_NONE")), "_NONE")
})

## The pass split -------------------------------------------------------------

test_that("nine of the eleven production passes are state-local", {
  P <- c(pf_staged_passes("lean", concat = TRUE), pf_recovery_passes(state = TRUE))
  nms <- vapply(P, function(p) p$name, character(1))
  local <- nms[nms %in% pfmatch:::.PF_STATE_LOCAL]
  cross <- setdiff(nms, local)
  expect_equal(length(local), 9L)
  # the two that genuinely cross state lines are also the cheapest in the cascade
  expect_setequal(cross, c("C1-name-any", "C2-dba-any"))
})
