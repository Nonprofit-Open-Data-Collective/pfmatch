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

## ---- the variant screen ------------------------------------------------------

screen_bmf <- function() data.frame(
  ein = c("042103580", "111111111", "222222222"),
  org_name_join = c("PRESIDENT AND FELLOWS OF HARVARD COLLEGE", "ALPHA FUND",
                    "BETA TRUST"),
  dba_name = c("HARVARD UNIVERSITY", "", ""),
  org_addr_street = c("1350 MASSACHUSETTS AVE", "1 MAIN ST", "1 MAIN ST"),
  org_addr_city = c("CAMBRIDGE", "BOSTON", "BOSTON"),
  org_addr_state = c("MA", "MA", "MA"),
  org_addr_zip5 = c("02138", "02108", "02108"), org_addr_zip4 = "",
  stringsAsFactors = FALSE)

# A status frame in which every identity failed, so the screen is the only
# thing that can resolve it.
failed_status <- function(r) {
  data.frame(grant_id = r$grant_id, recip_name = r$recip_name,
             status = factor("NO", pf_status_levels()), ein = NA_character_,
             bmf_name = NA_character_, score = NA_real_,
             match_pass = NA_character_, stringsAsFactors = FALSE)
}

screen_grants <- function() {
  a <- rep_frame(c(rep("HARVARD GSE PROGRAM OFFICE", 3), "HARVARD UNIVERSITY"),
                 street = "1350 MASSACHUSETTS AVE", city = "CAMBRIDGE",
                 state = "MA", zip5 = "02138", uid = 1L)
  b <- rep_frame(c("ALPHA FUND", "ALPHA FUND", "BETA TRUST", "GAMMA THING"),
                 street = "1 MAIN ST", city = "BOSTON", state = "MA",
                 zip5 = "02108", uid = 2L)
  c <- rep_frame(c("DELTA SOLO", "DELTA SOLO"), street = "9 ELM ST",
                 city = "BOSTON", state = "MA", zip5 = "02108", uid = 3L)
  g <- rbind(a, b, c)
  g$grant_id <- sprintf("G%04d", seq_len(nrow(g)))
  g
}

test_that("a spelling the representative hid resolves the identity", {
  skip_if_not_installed("npmatch")
  ref <- pf_build_reference(screen_bmf())
  g <- screen_grants()
  r <- pf_recipients(g)
  st <- pf_screen_variants(g, failed_status(r), ref, verbose = FALSE)
  h <- st[st$grant_id == "ID1", ]
  expect_equal(as.character(h$status), "YES")
  expect_equal(h$ein, "042103580")
  expect_equal(h$variant_screen, "resolved")
  expect_equal(h$variant_name, "HARVARD UNIVERSITY")
  expect_equal(as.character(h$status_main), "NO")
  expect_match(h$match_pass, "^variant:A")
})

test_that("spellings that resolve to different EINs make the identity MAYBE", {
  skip_if_not_installed("npmatch")
  ref <- pf_build_reference(screen_bmf())
  g <- screen_grants()
  # make GAMMA THING the representative so both ALPHA and BETA are variants
  g$recip_name[g$recipient_uid == 2L] <- c("GAMMA THING", "GAMMA THING",
                                           "ALPHA FUND", "BETA TRUST")
  r <- pf_recipients(g)
  st <- pf_screen_variants(g, failed_status(r), ref, verbose = FALSE)
  x <- st[st$grant_id == "ID2", ]
  expect_equal(as.character(x$status), "MAYBE")
  expect_equal(x$variant_screen, "conflict")
  expect_setequal(strsplit(x$variant_eins, ";")[[1]], c("111111111", "222222222"))
})

test_that("a YES the variants contradict is audited down only with scope = 'all'", {
  skip_if_not_installed("npmatch")
  ref <- pf_build_reference(screen_bmf())
  g <- screen_grants()
  r <- pf_recipients(g)               # ID2 is represented by ALPHA FUND
  st <- failed_status(r)
  st$status[st$grant_id == "ID2"] <- "YES"
  st$ein[st$grant_id == "ID2"] <- "111111111"
  a <- pf_screen_variants(g, st, ref, verbose = FALSE)
  expect_equal(as.character(a$status[a$grant_id == "ID2"]), "YES")
  expect_true(is.na(a$variant_screen[a$grant_id == "ID2"]))
  b <- pf_screen_variants(g, st, ref, scope = "all", verbose = FALSE)
  expect_equal(as.character(b$status[b$grant_id == "ID2"]), "MAYBE")
  expect_equal(b$variant_screen[b$grant_id == "ID2"], "conflict")
  expect_equal(b$ein[b$grant_id == "ID2"], "111111111")
})

test_that("single-spelling identities are not screened", {
  skip_if_not_installed("npmatch")
  ref <- pf_build_reference(screen_bmf())
  g <- screen_grants()
  st <- pf_screen_variants(g, failed_status(pf_recipients(g)), ref,
                           verbose = FALSE)
  expect_true(is.na(st$variant_screen[st$grant_id == "ID3"]))
  expect_equal(as.character(st$status[st$grant_id == "ID3"]), "NO")
})
