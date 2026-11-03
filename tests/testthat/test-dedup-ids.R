# The identity id, and the one property it exists for.
#
# `recipient_uid` is a position: match(key, unique(key)) numbers identities in
# order of first appearance and the fuzzy pass renumbers again by taking each
# component's smallest uid. So inserting ONE identity renumbers every identity
# after it, and a label keyed on the number lands on a different organisation.
#
# It happened. Two builds of the same grant population, the second after a
# normalizer change merged 682 duplicates: joined on R<uid> the recipient names
# did not agree at all, while pf_population_id() was identical both times
# because the grant file really was the same one
# (dev/ADJ-ROUND-STAGE1-20261103.log). Every test below is that scenario in
# miniature, and the one that matters is "renumbering does not move the id".

dedup_frame <- function(rows) {
  d <- data.frame(
    grant_id    = sprintf("G%03d", seq_len(nrow(rows))),
    OBJECTID    = sprintf("OID%03d", seq_len(nrow(rows))),
    recip_name  = rows$name,
    recip_name_alt = NA_character_,
    recip_street   = rows$street,
    recip_unit     = NA_character_,
    recip_city     = rows$city,
    recip_state    = rows$state,
    recip_zip5     = rows$zip5,
    in_scope       = TRUE,
    stringsAsFactors = FALSE)
  d
}

three_orgs <- function() dedup_frame(data.frame(
  name   = c("SMITH FAMILY FOUNDATION", "BOZEMAN FOOD BANK", "TROUT UNLIMITED"),
  street = c("100 MAIN ST", "200 OAK AVE", "300 PINE RD"),
  city   = c("BOZEMAN", "BOZEMAN", "HELENA"),
  state  = c("MT", "MT", "MT"),
  zip5   = c("59715", "59715", "59601"),
  stringsAsFactors = FALSE))

## ---- the failure this closes ------------------------------------------------

test_that("renumbering does not move an identity's id", {
  # one new identity inserted FIRST, which shifts every uid after it
  a <- pf_dedup(three_orgs(), method = "exact", verbose = FALSE)
  more <- dedup_frame(data.frame(
    name = c("NEW ORG HERE", "SMITH FAMILY FOUNDATION", "BOZEMAN FOOD BANK",
             "TROUT UNLIMITED"),
    street = c("1 FIRST ST", "100 MAIN ST", "200 OAK AVE", "300 PINE RD"),
    city = c("MISSOULA", "BOZEMAN", "BOZEMAN", "HELENA"),
    state = c("MT", "MT", "MT", "MT"),
    zip5 = c("59801", "59715", "59715", "59601"), stringsAsFactors = FALSE))
  b <- pf_dedup(more, method = "exact", verbose = FALSE)

  smith_a <- a$recipient_id[a$recip_name == "SMITH FAMILY FOUNDATION"]
  smith_b <- b$recipient_id[b$recip_name == "SMITH FAMILY FOUNDATION"]
  expect_equal(smith_a, smith_b)

  # and the positional id DID move, which is the point
  expect_false(identical(a$recipient_uid[a$recip_name == "SMITH FAMILY FOUNDATION"],
                         b$recipient_uid[b$recip_name == "SMITH FAMILY FOUNDATION"]))
})

test_that("row order does not move an identity's id", {
  a <- pf_dedup(three_orgs(), method = "exact", verbose = FALSE)
  b <- pf_dedup(three_orgs()[3:1, ], method = "exact", verbose = FALSE)
  key <- function(x) x$recipient_id[match("TROUT UNLIMITED", x$recip_name)]
  expect_equal(key(a), key(b))
})

test_that("dropping an identity does not move the others' ids", {
  a <- pf_dedup(three_orgs(), method = "exact", verbose = FALSE)
  b <- pf_dedup(three_orgs()[-1, ], method = "exact", verbose = FALSE)
  for (nm in c("BOZEMAN FOOD BANK", "TROUT UNLIMITED"))
    expect_equal(a$recipient_id[a$recip_name == nm],
                 b$recipient_id[b$recip_name == nm])
})

## ---- the shape of the id ----------------------------------------------------

test_that("ids are distinct per identity and shaped as content ids", {
  a <- pf_dedup(three_orgs(), method = "exact", verbose = FALSE)
  expect_equal(length(unique(a$recipient_id)), 3L)
  expect_true(all(grepl("^PFI-[0-9a-f]{16}$", a$recipient_id)))
})

test_that("rows of one identity share one id, and carry the canonical key", {
  d <- dedup_frame(data.frame(
    name = rep("SMITH FAMILY FOUNDATION", 3L),
    street = rep("100 MAIN ST", 3L), city = rep("BOZEMAN", 3L),
    state = rep("MT", 3L), zip5 = rep("59715", 3L), stringsAsFactors = FALSE))
  a <- pf_dedup(d, method = "exact", verbose = FALSE)
  expect_equal(length(unique(a$recipient_id)), 1L)
  expect_equal(length(unique(a$recipient_key)), 1L)
  expect_equal(a$recipient_id[1], pf_identity_id(a$recipient_key[1]))
})

test_that("a row with neither name nor address is marked not content-identified", {
  d <- dedup_frame(data.frame(
    name = c("SMITH FAMILY FOUNDATION", NA), street = c("100 MAIN ST", NA),
    city = c("BOZEMAN", NA), state = c("MT", NA), zip5 = c("59715", NA),
    stringsAsFactors = FALSE))
  a <- pf_dedup(d, method = "exact", verbose = FALSE)
  expect_true(any(grepl("^PFX-", a$recipient_id)))
  expect_true(any(grepl("^PFI-", a$recipient_id)))
})

test_that("a no-content row is keyed on OBJECTID, so it is file-stable", {
  mk <- function(oid) {
    d <- dedup_frame(data.frame(
      name = c("SMITH FAMILY FOUNDATION", NA), street = c("100 MAIN ST", NA),
      city = c("BOZEMAN", NA), state = c("MT", NA), zip5 = c("59715", NA),
      stringsAsFactors = FALSE))
    d$OBJECTID <- c("OID001", oid)
    pf_dedup(d, method = "exact", verbose = FALSE)
  }
  x <- mk("OID999"); y <- mk("OID999"); z <- mk("OID888")
  pfx <- function(a) a$recipient_id[grepl("^PFX-", a$recipient_id)]
  expect_equal(pfx(x), pfx(y))
  expect_false(identical(pfx(x), pfx(z)))
})

## ---- what the rest of the pipeline keys on ----------------------------------

test_that("pf_recipients keys the cascade on the stable id", {
  a <- pf_dedup(three_orgs(), method = "exact", verbose = FALSE)
  r <- pf_recipients(a)
  expect_equal(sort(r$grant_id), sort(unique(a$recipient_id)))
  expect_false(any(grepl("^R[0-9]+$", r$grant_id)))
})

test_that("pf_recipients warns and falls back when there is no stable id", {
  a <- pf_dedup(three_orgs(), method = "exact", verbose = FALSE)
  a$recipient_id <- NULL
  expect_warning(r <- pf_recipients(a), "not stable across rebuilds")
  expect_true(all(grepl("^R[0-9]+$", r$grant_id)))
})

test_that("pf_propagate_matches joins on the id the status frame was keyed on", {
  a <- pf_dedup(three_orgs(), method = "exact", verbose = FALSE)
  r <- pf_recipients(a)
  st <- data.frame(grant_id = r$grant_id, status = "YES",
                   ein = sprintf("%09d", seq_len(nrow(r))),
                   bmf_name = "SOME ORG", score = 0.9,
                   match_pass = "A1-name-zip5", stringsAsFactors = FALSE)
  out <- pf_propagate_matches(a, st)
  expect_true(all(out$status == "YES"))
  expect_equal(out$ein, st$ein[match(a$recipient_id, st$grant_id)])
})

test_that("propagating a frame against the wrong run stops rather than joining nothing", {
  # the reverse of the silent failure: ids that do not belong together must not
  # quietly produce a frame of NA outcomes
  a <- pf_dedup(three_orgs(), method = "exact", verbose = FALSE)
  st <- data.frame(grant_id = c("PFI-0000000000000000"), status = "YES",
                   ein = "123456789", bmf_name = "X", score = 1,
                   match_pass = "A1-name-zip5", stringsAsFactors = FALSE)
  expect_error(pf_propagate_matches(a, st), "nothing would")
})
