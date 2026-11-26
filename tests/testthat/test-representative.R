# Which member of a cluster the cascade sees.
#
# pf_recipients() used to take the longest name. In a cluster of spelling
# variants that is the most decorated one, and on the TY2021-2024 file it lost
# whole clusters: New Venture Fund's 1,986 rows were matched as "NEW VENTURE
# FUND FOR PROJECT UNLOADED" and came back NO (dev/REPRESENTATIVE-NAME-NOTE.md).

rep_frame <- function(names, street = "1201 CONNECTICUT AVE NW", zip5 = "20036",
                      state = "DC", city = "WASHINGTON", tax_year = "2023",
                      uid = 1L) {
  n <- length(names)
  data.frame(
    grant_id = sprintf("G%04d", seq_len(n)),
    recip_name = names, recip_name_alt = NA_character_,
    recip_street = rep_len(street, n), recip_unit = NA_character_,
    recip_city = rep_len(city, n), recip_state = rep_len(state, n),
    recip_zip5 = rep_len(zip5, n), TAX_YEAR = rep_len(tax_year, n),
    recip_state_raw = rep_len(state, n), recipient_type = "public_charity",
    recipient_type_detail = "public_charity", looks_personal = FALSE,
    oos_reason = NA_character_,
    in_scope = TRUE, recipient_uid = rep_len(uid, n),
    recipient_id = paste0("ID", rep_len(uid, n)),
    stringsAsFactors = FALSE)
}

nvf_cluster <- function() {
  g <- rep_frame(c(rep("NEW VENTURE FUND", 50), "NEW VENTURE FUND FOR PROJECT X"))
  # the decorated row is the longest AND the most complete, so only the
  # frequency rule can pass over it
  g$recip_street[1:50] <- NA
  g
}

test_that("the representative is the cluster's most common spelling", {
  r <- pf_recipients(nvf_cluster())
  expect_equal(nrow(r), 1L)
  expect_equal(r$recip_name, "NEW VENTURE FUND")
  expect_equal(r$recipient_name_n, 50L)
  expect_equal(r$grant_id, "ID1")
})

test_that("spellings are counted after case and punctuation are folded", {
  g <- rep_frame(c("Harvard University", "HARVARD UNIVERSITY", "HARVARD UNIVERSITY.",
                   "HARVARD UNIVERSITY (HARVARD GRADUATE SCHOOL OF EDUCATION)",
                   "HARVARD UNIVERSITY (HARVARD GRADUATE SCHOOL OF EDUCATION)"))
  r <- pf_recipients(g)
  expect_equal(pfmatch:::.pf_rep_key(r), "HARVARD UNIVERSITY")
  expect_equal(r$recipient_name_n, 3L)
})

test_that("ties go to address fields, then the latest tax year, then length", {
  g <- rep_frame(c("ALPHA ORG", "ALPHA ORGANIZATION"))
  g$recip_street[2] <- NA
  expect_equal(pf_recipients(g)$recip_name, "ALPHA ORG")
  g <- rep_frame(c("ALPHA ORG", "ALPHA ORGANIZATION"), tax_year = c("2024", "2021"))
  expect_equal(pf_recipients(g)$recip_name, "ALPHA ORG")
  g <- rep_frame(c("ALPHA ORG", "ALPHA ORGANIZATION"))
  expect_equal(pf_recipients(g)$recip_name, "ALPHA ORGANIZATION")
})

test_that("the choice does not depend on row order", {
  g <- nvf_cluster()
  set.seed(1)
  a <- pf_recipients(g)
  b <- pf_recipients(g[sample(nrow(g)), ])
  expect_equal(a$recip_name, b$recip_name)
  g <- rep_frame(c("BETA A", "BETA B"))
  expect_equal(pf_recipients(g)$recip_name, pf_recipients(g[2:1, ])$recip_name)
})

test_that("a blank name never wins on frequency", {
  g <- rep_frame(c(NA, NA, NA, "GAMMA CENTER"))
  expect_equal(pf_recipients(g)$recip_name, "GAMMA CENTER")
})

nvf_bmf <- function() data.frame(
  ein = c("201234567", "301234567"),
  org_name_join = c("NEW VENTURE FUND", "NEW VISIONS FOR PUBLIC SCHOOLS"),
  dba_name = c("", ""),
  org_addr_street = c("1201 CONNECTICUT AVE NW", "205 E 42ND ST"),
  org_addr_city = c("WASHINGTON", "NEW YORK"), org_addr_state = c("DC", "NY"),
  org_addr_zip5 = c("20036", "10017"), org_addr_zip4 = c("", ""),
  stringsAsFactors = FALSE)

test_that("the New Venture Fund cluster resolves on its common name", {
  skip_if_not_installed("npmatch")
  ref <- pf_build_reference(nvf_bmf())
  r <- pf_recipients(nvf_cluster())
  m <- pf_match_grants(r, ref, passes = pf_staged_passes("lean"),
                       verbose = FALSE, check_reference = "ignore")
  st <- pf_status(m)
  expect_equal(as.character(st$status), "YES")
  expect_equal(st$ein, "201234567")
})
