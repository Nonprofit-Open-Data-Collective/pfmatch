# ============================================================================
# The v2 build appends year by year with fwrite(append = TRUE), which writes
# POSITIONALLY against the header the first year wrote. A year missing one of
# the mapped columns gets it added as a blank -- and data.table adds a new
# column at the END of the frame, not in the position the other years carry it.
#
# That shipped, and it shifted every one of 2025's 658,811 rows two columns out
# of register: PF_15_G_PAID_AMT came out empty and the purpose text landed in
# PF_15_G_PAID_RECIP_STAT. It survived review because 2025 is the only year the
# published schema differs, and the equivalence check that would have caught it
# was run on 2023.
#
# These tests reproduce it on a two-row synthetic cache, so they need neither
# the network nor the 7 GB local extract.
# ============================================================================

# A minimal extract: the mapped columns plus the metadata the build and the
# dedup need. Column ORDER matters here -- that is the whole point.
fake_extract <- function(year, n = 3L, drop = character(0)) {
  m <- pf_efilepf_map()
  d <- data.table::data.table(
    OBJECTID = sprintf("OID-%d%05d", year, seq_len(n)),
    TABLE_ID = as.character(seq_len(n)),
    EIN2     = sprintf("%09d", 100000000L + seq_len(n)),
    ORG_EIN  = sprintf("%09d", 100000000L + seq_len(n)),
    TAX_YEAR = as.character(year))
  for (v in setdiff(unname(m), names(d))) d[, (v) := ""]
  # populate the three the assertions read, in the published order
  d[, PF_15_G_PAID_RECIP_NAME_ORG_L1 := sprintf("ORG %s %d", LETTERS[seq_len(n)], year)]
  d[, PF_15_G_PAID_RECIP_ADDR_CITY   := "SPRINGFIELD"]
  d[, PF_15_G_PAID_AMT               := as.character(seq_len(n) * 1000L)]
  d[, PF_15_G_PAID_RECIP_STAT        := "PC"]
  d[, PF_15_G_PAID_PURPOSE           := "GENERAL SUPPORT"]
  if (length(drop)) d[, (drop) := NULL]
  d[]
}

write_cache <- function(dir, years, drop_in = NULL) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  for (y in years) {
    dd <- if (!is.null(drop_in) && y %in% drop_in$year) drop_in$cols else character(0)
    data.table::fwrite(fake_extract(y, drop = dd),
                       file.path(dir, sprintf("%s-%d.CSV", pf_efilepf_table(), y)))
  }
  dir
}

test_that("a year missing a mapped column does not shift the appended block", {
  dir <- file.path(tempdir(), "pf-build-shift")
  out <- file.path(tempdir(), "pf-build-shift.csv")
  on.exit(unlink(c(dir, out), recursive = TRUE), add = TRUE)
  # 2024 complete; 2025 missing PF_15_G_PAID_RECIP_STAT, exactly as published
  write_cache(dir, 2024:2025,
              drop_in = list(year = 2025, cols = "PF_15_G_PAID_RECIP_STAT"))

  pf_efilepf_build(dir = dir, out = out, years = 2024:2025, schema = "v2",
                   dedup = FALSE, verbose = FALSE)
  d <- data.table::fread(out, colClasses = "character", na.strings = NULL)

  a <- d[TAX_YEAR == "2024"]; b <- d[TAX_YEAR == "2025"]
  expect_equal(nrow(a), 3L)
  expect_equal(nrow(b), 3L)

  # the amount is the column the shift emptied
  expect_equal(b$PF_15_G_PAID_AMT, c("1000", "2000", "3000"))
  expect_false(any(b$PF_15_G_PAID_AMT == ""))

  # ... and the purpose is what it used to land in
  expect_true(all(b$PF_15_G_PAID_RECIP_STAT == ""))
  expect_true(all(b$PF_15_G_PAID_PURPOSE == "GENERAL SUPPORT"))

  # the name must still be the name, not a neighbour's value
  expect_true(all(grepl("^ORG [A-C] 2025$", b$PF_15_G_PAID_RECIP_NAME_ORG_L1)))
  expect_true(all(b$PF_15_G_PAID_RECIP_ADDR_CITY == "SPRINGFIELD"))

  # both years sit under one header with one column set
  expect_identical(names(a), names(b))
})

test_that("a year publishing an unexpected column is refused, not appended", {
  dir <- file.path(tempdir(), "pf-build-extra")
  out <- file.path(tempdir(), "pf-build-extra.csv")
  on.exit(unlink(c(dir, out), recursive = TRUE), add = TRUE)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  data.table::fwrite(fake_extract(2024),
    file.path(dir, sprintf("%s-2024.CSV", pf_efilepf_table())))
  x <- fake_extract(2025)
  x[, PF_15_G_PAID_SOMETHING_NEW := "?"]
  data.table::fwrite(x, file.path(dir, sprintf("%s-2025.CSV", pf_efilepf_table())))

  # silently appending it would write every 2025 row one column wide
  expect_error(
    pf_efilepf_build(dir = dir, out = out, years = 2024:2025, schema = "v2",
                     dedup = FALSE, verbose = FALSE),
    "PF_15_G_PAID_SOMETHING_NEW")
})

test_that("the legacy gtdc path keeps its fixed column order", {
  dir <- file.path(tempdir(), "pf-build-gtdc")
  out <- file.path(tempdir(), "pf-build-gtdc.csv")
  on.exit(unlink(c(dir, out), recursive = TRUE), add = TRUE)
  write_cache(dir, 2024:2025,
              drop_in = list(year = 2025, cols = "PF_15_G_PAID_RECIP_STAT"))
  pf_efilepf_build(dir = dir, out = out, years = 2024:2025, schema = "gtdc",
                   dedup = FALSE, verbose = FALSE)
  d <- data.table::fread(out, colClasses = "character", na.strings = NULL)
  # the gtdc path renames TAX_YEAR to the v1 name
  expect_equal(d[TAXYEAR == "2025", SIGOCPYAMOUN], c("1000", "2000", "3000"))
  expect_true(all(d[TAXYEAR == "2025", SIGOCPYRFSTA] == ""))
})

test_that("finding no extracts is an error, not an empty build", {
  dir <- file.path(tempdir(), "pf-build-empty")
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  expect_error(
    pf_efilepf_build(dir = dir, out = file.path(tempdir(), "nope.csv"),
                     years = 2024:2025, verbose = FALSE),
    "found no source extracts")
})

test_that("pf_efilepf_dir() is not doubled on Windows", {
  # path.expand("~") is the Documents folder on Windows, so the old
  # file.path(path.expand("~"), "Documents", ...) resolved to
  # C:/Users/<u>/Documents/Documents/grants/efilepf and every year was
  # reported MISSING -- which the build then treated as a successful build.
  old <- Sys.getenv("PF_EFILEPF_DIR", unset = NA)
  on.exit(if (is.na(old)) Sys.unsetenv("PF_EFILEPF_DIR")
          else Sys.setenv(PF_EFILEPF_DIR = old), add = TRUE)

  Sys.unsetenv("PF_EFILEPF_DIR")
  d <- pf_efilepf_dir()
  expect_false(grepl("Documents[/\\\\]Documents", d))
  expect_match(d, "grants[/\\\\]efilepf$")

  Sys.setenv(PF_EFILEPF_DIR = "D:/somewhere/else")
  expect_equal(pf_efilepf_dir(), "D:/somewhere/else")
})
