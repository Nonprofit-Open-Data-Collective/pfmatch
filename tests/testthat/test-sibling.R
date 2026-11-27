# The sibling-superset downgrade (dev/MISSED-GRANTS-NOTE.md section 2).

sib_status <- function(q, b, s = "YES")
  data.frame(recip_name = q, bmf_name = b, status = factor(s, pf_status_levels()),
             stringsAsFactors = FALSE)

test_that("the reviewed sibling errors are downgraded", {
  st <- sib_status(
    c("ADL", "PHILADELPHIA MUSEUM OF ART", "COLUMBIA BUSINESS SCHOOL",
      "MCLEAN HOSPITAL", "ARIZONA STATE UNIVERSITY"),
    c("ADL PROFESSIONAL STAFF ASSOCIATION",
      "WOMEN'S COMMITTEE OF THE PHILADELPHIA MUSEUM OF ART",
      "COLUMBIA BUSINESS SCHOOL ALUMNI CLUB OF NEW YORK",
      "MCLEAN HOSPITAL EMPLOYEES MEDICAL TRUST",
      "ARIZONA STATE UNIVERSITY FRATERNITY COLONY"))
  out <- pf_sibling_guard(st)
  expect_true(all(out$sibling_guard))
  expect_true(all(as.character(out$status) == "MAYBE"))
  expect_true(all(out$status_before_sibling == "YES"))
})

test_that("ordinary matches, and non-YES rows, are left alone", {
  st <- sib_status(
    c("HARVARD UNIVERSITY", "AMERICAN RED CROSS", "ADL", "UNIVERSITY OF X",
      "GUILD OF CARILLONNEURS", "ADL"),
    c("PRESIDENT AND FELLOWS OF HARVARD COLLEGE", "AMERICAN NATIONAL RED CROSS",
      "ANTI-DEFAMATION LEAGUE", "UNIVERSITY OF X FOUNDATION",
      "GUILD OF CARILLONNEURS IN NORTH AMERICA", "ADL STAFF ASSOCIATION"),
    c("YES", "YES", "YES", "YES", "YES", "MAYBE"))
  out <- pf_sibling_guard(st)
  expect_false(any(out$sibling_guard))
  expect_equal(as.character(out$status), as.character(st$status))
})
