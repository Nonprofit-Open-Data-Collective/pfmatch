# Foreign recipients from the country field, and the name-based government flag.

raw_grants <- function(name, state, cntr, stat = "PC") {
  data.frame(
    grant_id = sprintf("G%03d", seq_along(name)),
    PF_15_G_PAID_RECIP_NAME_ORG_L1 = name,
    PF_15_G_PAID_RECIP_NAME_ORG_L2 = NA_character_,
    PF_15_G_PAID_RECIP_NAME_PERS   = NA_character_,
    PF_15_G_PAID_RECIP_ADDR_L1     = "1 MAIN ST",
    PF_15_G_PAID_RECIP_ADDR_L2     = NA_character_,
    PF_15_G_PAID_RECIP_ADDR_CITY   = "SOMEWHERE",
    PF_15_G_PAID_RECIP_ADDR_STATE  = state,
    PF_15_G_PAID_RECIP_ADDR_ZIP    = NA_character_,
    PF_15_G_PAID_RECIP_ADDR_CNTR   = cntr,
    PF_15_G_PAID_RECIP_STAT        = stat,
    PF_15_G_PAID_AMT               = 100,
    stringsAsFactors = FALSE)
}

test_that("a non-US country with a blank state is set aside as foreign", {
  g <- pf_prepare_grants(raw_grants(
    name  = c("UNIVERSITY OF ZURICH", "UNIVERSITY OF OXFORD", "LAZARUS HOUSE",
              "FILANTROPIA PUERTO RICO INC", "WEIZMANN INSTITUTE OF SCIENCE", "LAZARUS HOUSE"),
    state = c(NA, "", "MA", NA, "CA", NA),
    cntr  = c("SZ", "UK", NA, "RQ", "IS", "US")), placeholders = FALSE)
  expect_equal(g$in_scope, c(FALSE, FALSE, TRUE, TRUE, TRUE, TRUE))
  expect_equal(g$oos_reason[1:2], c("foreign address", "foreign address"))
  # a US territory code is not foreign; a US state beside a foreign country is
  # contradictory, so it is flagged and still matched
  expect_equal(g$flag_foreign_country, c(TRUE, TRUE, FALSE, FALSE, TRUE, FALSE))
})

test_that("a frame without a country column scopes as before", {
  r <- raw_grants(c("UNIVERSITY OF ZURICH", "LAZARUS HOUSE"), c(NA, "MA"), NA)
  r$PF_15_G_PAID_RECIP_ADDR_CNTR <- NULL
  g <- pf_prepare_grants(r, placeholders = FALSE)
  expect_true(all(g$in_scope))
  expect_false(any(g$flag_foreign_country))
})

test_that("government-shaped names are flagged but stay in scope", {
  gov <- c("CITY OF BOSTON", "TOWN OF BURLINGTON", "READING SCHOOL DISTRICT",
           "WESTOVER HILLS POLICE DEPARTMENT", "LYONS RURAL FIRE DISTRICT")
  org <- c("UNITED WAY OF KING COUNTY", "CITY OF FOUNTAINS FOUNDATION",
           "FUND FOR PUBLIC SCHOOLS INC", "HAVRE PUBLIC SCHOOLS EDUCATION FOUNDATION",
           "DAVIS CORNER VOLUNTEER FIRE DEPARTMENT", "BOYS & GIRLS CLUB OF MANATEE COUNTY")
  g <- pf_prepare_grants(raw_grants(c(gov, org), "MA", NA), placeholders = FALSE)
  expect_equal(g$looks_government, rep(c(TRUE, FALSE), c(length(gov), length(org))))
  expect_true(all(g$in_scope))
})
