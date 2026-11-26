# The placeholder sidebar: rows whose "recipient" is a note are set out of
# scope before matching (dev/PLACEHOLDER-SIDEBAR-NOTE.md).

test_that("every lexicon example is caught, in its own category", {
  lx <- pf_placeholder_lexicon()
  ex <- ifelse(lx$example == "(blank)", "", lx$example)
  d <- pf_detect_placeholders(ex, lx)
  expect_true(all(d$is_placeholder), info = paste(ex[!d$is_placeholder], collapse = " | "))
  expect_equal(d$category, lx$category)
})

test_that("real recipients that share the keywords stay in scope", {
  x <- c("VARIOUS ARTISTS COLLECTIVE INC", "LOW INCOME HOUSING FUND",
         "SCHOLARSHIP AMERICA", "STUDENTS FOR LIFE", "ALCOHOLICS ANONYMOUS",
         "NARCOTICS ANONYMOUS", "SEE INTERNATIONAL", "HELP ME SEE",
         "STATEMENT ARTS INC", "EXHIBIT ENVOY", "MULTIPLE SCLEROSIS SOCIETY",
         "OTHER SIDE ACADEMY", "ANGELICA PATIENT ASSISTANCE PROGRAM INC",
         "N A A C P LEGAL DEFENSE FUND", "NO ONE LEFT BEHIND", "THE TRUSTEES",
         "MISCARRIAGE ABORTION HOTLINE", "SMALL BUSINESS MAJORITY",
         "NEW VENTURE FUND", "HARVARD UNIVERSITY", "UNITED WAY OF KING COUNTY")
  d <- pf_detect_placeholders(x)
  expect_false(any(d$is_placeholder), info = paste(x[d$is_placeholder], collapse = " | "))
  expect_true(all(is.na(d$category)))
})

test_that("a reference that names a payee keeps the payee", {
  x <- c("SEE ATTACHED - UNITED WAY", "FIDELITY CHARITABLE - SEE ATTACHMENT A",
         "LINDA VISTA FOUNDATION SEE ATTACHED", "INDIANA UNIVERSITY VARIOUS STUDENTS",
         "SUNY CORTLAND FBO VARIOUS INDIVIDUALS")
  d <- pf_detect_placeholders(x)
  expect_false(any(d$is_placeholder))
  expect_true(all(d$category == "reference_with_name"))
  expect_equal(d$residual, c("UNITED WAY", "FIDELITY CHARITABLE",
                             "LINDA VISTA FOUNDATION", "INDIANA UNIVERSITY",
                             "SUNY CORTLAND"))
})

test_that("a residual that is only a list word or generic stays a placeholder", {
  x <- c("SEE ATTACHED LIST", "THE FOUNDATION - SEE ATTACHMENT A",
         "CASH GRANTS SEE ATTACHED", "SEE ATTACHED - VARIOUS",
         "ASSISTANCE TO NEEDY FAMILIES", "VARIOUS INDIVIDUALS")
  d <- pf_detect_placeholders(x)
  expect_true(all(d$is_placeholder), info = paste(x[!d$is_placeholder], collapse = " | "))
  expect_true(all(is.na(d$residual)))
})

raw_grants <- function(name, street = "1 MAIN ST", amt = "1000") {
  n <- length(name)
  data.frame(
    PF_15_G_PAID_RECIP_NAME_PERS = NA_character_,
    PF_15_G_PAID_RECIP_NAME_ORG_L1 = name,
    PF_15_G_PAID_RECIP_NAME_ORG_L2 = NA_character_,
    PF_15_G_PAID_RECIP_ADDR_L1 = rep_len(street, n),
    PF_15_G_PAID_RECIP_ADDR_L2 = NA_character_,
    PF_15_G_PAID_RECIP_ADDR_CITY = "SEATTLE",
    PF_15_G_PAID_RECIP_ADDR_STATE = "WA",
    PF_15_G_PAID_RECIP_ADDR_ZIP = "98101",
    PF_15_G_PAID_RECIP_STAT = "PC",
    PF_15_G_PAID_AMT = rep_len(amt, n),
    stringsAsFactors = FALSE)
}

test_that("pf_prepare_grants sets placeholders out of scope, on by default", {
  g <- pf_prepare_grants(raw_grants(c("SEE ATTACHED", "VARIOUS INDIVIDUALS",
                                      "SEE ATTACHED - UNITED WAY",
                                      "VARIOUS ARTISTS COLLECTIVE INC",
                                      "HIPPA REGULATIONS PREVENT THE LISTING OF NAMES")))
  expect_equal(g$in_scope, c(FALSE, FALSE, TRUE, TRUE, FALSE))
  expect_equal(g$oos_reason[c(1, 2, 5)],
               c("placeholder:attachment_reference",
                 "placeholder:aggregate_individuals",
                 "placeholder:privacy_withheld"))
  expect_equal(g$recip_name[3], "UNITED WAY")
  expect_equal(g$recip_name_filed[3], "SEE ATTACHED - UNITED WAY")
  expect_equal(g$placeholder_category[3], "reference_with_name")
  expect_equal(g$placeholder_sink[1], "UNITEMIZED")
  # a set-aside row is never also read as a person
  expect_false(any(g$looks_personal[!g$in_scope]))
})

test_that("placeholders = FALSE restores the earlier scoping", {
  g <- pf_prepare_grants(raw_grants(c("SEE ATTACHED", "SEE ATTACHED - UNITED WAY")),
                         placeholders = FALSE)
  expect_true(all(g$in_scope))
  expect_equal(g$recip_name, c("SEE ATTACHED", "SEE ATTACHED - UNITED WAY"))
  expect_true(all(is.na(g$placeholder_category)))
})

test_that("a one-character name with a street is left for street recovery", {
  g <- pf_prepare_grants(raw_grants(c("X", "X"), street = c("FRIENDS OF THE PARK", NA)))
  expect_true(g$in_scope[1])
  expect_equal(g$oos_reason[2], "placeholder:unknown_or_none")
})
