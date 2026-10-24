# ============================================================================
# pf_validate_grants() exists because the failures that cost this project most
# were SILENT -- a column read as all-NA, two vintages concatenated, superseded
# filings left in. The per-year coverage check was added after a column shift
# emptied PF_15_G_PAID_AMT for all of 2025 while every corpus-wide check still
# passed, because 96% of rows were fine.
#
# The hard part of that check is not catching the shift; it is NOT firing on
# PF_15_G_PAID_RECIP_STAT, which the IRS genuinely stopped publishing in 2025.
# A check that fails on every sound file is one nobody reads.
# ============================================================================

# Minimal well-formed v2 grant frame spanning two tax years.
mk_grants <- function(years = c(2023L, 2025L), n = 40L) {
  d <- data.frame(
    OBJECTID = sprintf("OID-%05d", seq_len(n * length(years))),
    TABLE_ID = as.character(seq_len(n * length(years))),
    EIN2     = sprintf("%09d", 100000000L + seq_len(n * length(years))),
    TAX_YEAR = as.character(rep(years, each = n)),
    RETURN_AMENDED_X = "", RETURN_PARTIAL_X = "", RETURN_GROUP_X = "",
    PF_15_G_PAID_RECIP_NAME_ORG_L1 = "SOME FOUNDATION",
    PF_15_G_PAID_RECIP_ADDR_CITY   = "SPRINGFIELD",
    PF_15_G_PAID_RECIP_ADDR_STATE  = "IL",
    PF_15_G_PAID_RECIP_ADDR_ZIP    = "62701",
    PF_15_G_PAID_AMT               = "5000",
    PF_15_G_PAID_RECIP_STAT        = "PC",
    stringsAsFactors = FALSE)
  # the real data has none of this column from 2025 on
  d$PF_15_G_PAID_RECIP_STAT[d$TAX_YEAR >= "2025"] <- ""
  d
}
status_of <- function(res, check) res$status[res$check == check]

test_that("a sound two-year frame passes every check", {
  r <- pf_validate_grants(mk_grants(), verbose = FALSE)
  expect_false(any(r$status == "FAIL"))
  expect_equal(status_of(r, "schema"), "PASS")
  expect_equal(status_of(r, "row key OBJECTID|TABLE_ID"), "PASS")
})

test_that("a year emptied by a column shift is caught", {
  d <- mk_grants()
  d$PF_15_G_PAID_AMT[d$TAX_YEAR == "2025"] <- ""   # what the shift did
  r <- pf_validate_grants(d, verbose = FALSE)
  expect_equal(status_of(r, "per-year column coverage"), "FAIL")
  expect_match(r$detail[r$check == "per-year column coverage"], "PF_15_G_PAID_AMT")
  expect_match(r$detail[r$check == "per-year column coverage"], "2025")
})

test_that("the discontinued status column does NOT trip the check", {
  # present 2009-2024, absent 2025 onward -- correct data, not a fault
  r <- pf_validate_grants(mk_grants(), verbose = FALSE)
  expect_equal(status_of(r, "per-year column coverage"), "PASS")
  expect_match(r$detail[r$check == "per-year column coverage"], "expected")
})

test_that("an empty status column in a year that should HAVE it still fails", {
  d <- mk_grants(years = c(2022L, 2023L))
  d$PF_15_G_PAID_RECIP_STAT[d$TAX_YEAR == "2023"] <- ""
  r <- pf_validate_grants(d, verbose = FALSE)
  expect_equal(status_of(r, "per-year column coverage"), "FAIL")
  expect_match(r$detail[r$check == "per-year column coverage"], "2023")
})

test_that("a frame carrying both spellings of a column is a schema FAIL", {
  # what a concatenation of a v1 and a v2 build looks like: each schema's
  # columns present, and NA on the other schema's rows
  d <- mk_grants(years = 2023L, n = 10L)
  d$SIGOCPYRBNBN1 <- NA_character_
  expect_equal(.pf_schema_of(d), "mixed")
  r <- pf_validate_grants(d, verbose = FALSE)
  expect_equal(status_of(r, "schema"), "FAIL")
  expect_match(r$detail[r$check == "schema"], "double-counts|BOTH")
})

test_that("pf_read_grants() refuses to concatenate two schemas", {
  dir <- file.path(tempdir(), "pf-mixed-read")
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  v2 <- mk_grants(years = 2023L, n = 5L)
  v1 <- v2
  names(v1) <- vapply(names(v1), function(n) {
    m <- pf_efilepf_map(); i <- match(n, unname(m))
    if (is.na(i)) n else names(m)[i]
  }, character(1))
  data.table::fwrite(v2, file.path(dir, "a_grants.csv"))
  data.table::fwrite(v1, file.path(dir, "b_grants.csv"))
  # both carry OBJECTID, so the older vintage guard lets them through.
  # The guard runs before pf_prepare_grants(), which is the point: this
  # fixture is too thin for prepare, so only the refusal is asserted here.
  expect_error(pf_read_grants(dir), "different SCHEMAS")
})

test_that("a duplicated row key is a FAIL", {
  d <- mk_grants(years = 2023L, n = 10L)
  d$TABLE_ID[2] <- d$TABLE_ID[1]
  d$OBJECTID[2] <- d$OBJECTID[1]
  r <- pf_validate_grants(d, verbose = FALSE)
  expect_equal(status_of(r, "row key OBJECTID|TABLE_ID"), "FAIL")
})

test_that("strict = TRUE raises on a failure", {
  d <- mk_grants()
  d$PF_15_G_PAID_AMT[d$TAX_YEAR == "2025"] <- ""
  expect_error(pf_validate_grants(d, strict = TRUE, verbose = FALSE),
               "failure")
})
