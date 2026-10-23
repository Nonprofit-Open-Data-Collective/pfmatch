# Every branch of pf_efilepf_dedup(), on fixtures small enough to reason about.
#
# The corpus run that would exercise these naturally takes a long time and only
# ~10 contexts in 967,425 reach the `kept_flagged` path, so a real run leaves
# the most consequential branch untested. These fixtures cover all of them, and
# in particular the two invariants that must never break: a short-period filing
# is never dropped for sharing a tax year with a full-year one, and an
# amendment supersedes only within its own reporting context.

grant_row <- function(objectid, table_id, ein2 = "EIN-11-1111111",
                      year = "2023", amended = "FALSE", partial = "FALSE",
                      group = "FALSE", ts = "2024-05-01 10:00:00",
                      recip = "ALPHA FUND", amt = "100") {
  data.frame(
    OBJECTID = objectid, TABLE_ID = as.character(table_id),
    EIN2 = ein2, TAX_YEAR = year,
    RETURN_AMENDED_X = amended, RETURN_PARTIAL_X = partial,
    RETURN_GROUP_X = group, RETURN_TIME_STAMP = ts,
    PF_15_G_PAID_RECIP_NAME_ORG_L1 = recip,
    PF_15_G_PAID_AMT = amt,
    stringsAsFactors = FALSE)
}

test_that("a lone filing is kept untouched", {
  d <- grant_row("A", 1)
  out <- pf_efilepf_dedup(d, verbose = FALSE)
  expect_equal(nrow(out), 1L)
  expect_equal(out$dedup_action, "kept")
  expect_false(out$dedup_flag)
})

test_that("identical filings collapse to one, deterministically", {
  d <- rbind(grant_row("B", 1), grant_row("A", 1))   # same content, two OBJECTIDs
  out <- pf_efilepf_dedup(d, verbose = FALSE)
  expect_equal(nrow(out), 1L)
  expect_equal(unique(out$OBJECTID), "A")            # lowest OBJECTID wins
  expect_equal(unique(out$dedup_action), "kept")
})

test_that("an amended filing supersedes the original even when content differs", {
  d <- rbind(
    grant_row("A", 1, recip = "ALPHA FUND",   amt = "100"),
    grant_row("B", 1, recip = "ALPHA FUND 2", amt = "250", amended = "TRUE",
              ts = "2024-09-01 10:00:00"))
  out <- pf_efilepf_dedup(d, verbose = FALSE)
  expect_equal(nrow(out), 1L)
  expect_equal(unique(out$OBJECTID), "B")
  expect_equal(unique(out$dedup_action), "kept_amended")
  expect_false(any(out$dedup_flag))
})

test_that("differing filings with no amendment are ALL kept and flagged", {
  d <- rbind(
    grant_row("A", 1, recip = "ALPHA FUND", amt = "100"),
    grant_row("B", 1, recip = "BETA TRUST", amt = "900"))
  out <- pf_efilepf_dedup(d, verbose = FALSE)
  expect_equal(nrow(out), 2L)                        # nothing lost
  expect_true(all(out$dedup_flag))
  expect_equal(unique(out$dedup_action), "kept_flagged")
})

test_that("a short-period filing is never dropped for sharing a tax year", {
  # the measured case: 310 org-years hold a partial beside a full-year return,
  # and in 97 of them the PARTIAL one reports MORE grants
  d <- rbind(
    grant_row("A", 1, partial = "FALSE", recip = "FULL YEAR GRANT"),
    grant_row("B", 1, partial = "TRUE",  recip = "SHORT PERIOD GRANT"),
    grant_row("B", 2, partial = "TRUE",  recip = "SHORT PERIOD GRANT 2"))
  out <- pf_efilepf_dedup(d, verbose = FALSE)
  expect_equal(nrow(out), 3L)
  expect_setequal(unique(out$OBJECTID), c("A", "B"))
  expect_false(any(out$dedup_flag))                  # distinct contexts, not a conflict
})

test_that("an amended partial supersedes only the original partial", {
  d <- rbind(
    grant_row("A", 1, partial = "FALSE", recip = "FULL YEAR"),
    grant_row("B", 1, partial = "TRUE",  recip = "SHORT ORIG"),
    grant_row("C", 1, partial = "TRUE",  recip = "SHORT AMENDED",
              amended = "TRUE", ts = "2025-01-01 10:00:00"))
  out <- pf_efilepf_dedup(d, verbose = FALSE)
  expect_equal(nrow(out), 2L)
  expect_setequal(unique(out$OBJECTID), c("A", "C"))  # full year survives untouched
  expect_false("B" %in% out$OBJECTID)
})

test_that("group and primary returns are never merged", {
  d <- rbind(
    grant_row("A", 1, group = "FALSE", recip = "PRIMARY GRANT"),
    grant_row("B", 1, group = "TRUE",  recip = "GROUP GRANT"))
  out <- pf_efilepf_dedup(d, verbose = FALSE)
  expect_equal(nrow(out), 2L)
  expect_false(any(out$dedup_flag))
})

test_that("different EINs and different years never interact", {
  d <- rbind(
    grant_row("A", 1, ein2 = "EIN-11-1111111", year = "2023"),
    grant_row("B", 1, ein2 = "EIN-22-2222222", year = "2023"),
    grant_row("C", 1, ein2 = "EIN-11-1111111", year = "2022"))
  out <- pf_efilepf_dedup(d, verbose = FALSE)
  expect_equal(nrow(out), 3L)
})

test_that("the newest wins when several amendments exist", {
  d <- rbind(
    grant_row("A", 1, amended = "FALSE", ts = "2024-01-01 10:00:00"),
    grant_row("B", 1, amended = "TRUE",  ts = "2024-06-01 10:00:00", amt = "200"),
    grant_row("C", 1, amended = "TRUE",  ts = "2025-02-01 10:00:00", amt = "300"))
  out <- pf_efilepf_dedup(d, verbose = FALSE)
  expect_equal(nrow(out), 1L)
  expect_equal(unique(out$OBJECTID), "C")
})

test_that("flag encodings follow the ef2 conventions", {
  for (v in c("X", "x", "TRUE", "T", "1", "Y", "YES")) {
    d <- rbind(grant_row("A", 1),
               grant_row("B", 1, amended = v, amt = "999"))
    out <- pf_efilepf_dedup(d, verbose = FALSE)
    expect_equal(unique(out$OBJECTID), "B", info = paste("encoding:", v))
  }
  for (v in c("", "FALSE", "N", "0")) {
    d <- rbind(grant_row("A", 1, amt = "1"), grant_row("B", 1, amended = v, amt = "2"))
    out <- pf_efilepf_dedup(d, verbose = FALSE)
    expect_true(all(out$dedup_flag), info = paste("non-flag:", v))
  }
})

test_that("missing ef2 metadata is refused with an actionable message", {
  d <- grant_row("A", 1)
  d$EIN2 <- NULL
  expect_error(pf_efilepf_dedup(d, verbose = FALSE), "EIN2")
  expect_error(pf_efilepf_dedup(d, verbose = FALSE), "schema")
})

test_that("TABLE_ID is excluded from the content comparison", {
  # two identical filings must still look identical even though TABLE_ID, a
  # per-filing row counter, differs between them
  expect_false("TABLE_ID" %in% pf_grant_content_cols())
})
