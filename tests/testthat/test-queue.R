# The dollar-sorted review queue.
#
# The test that matters most here is the dedup one. pf_recipients() keeps one
# representative row per identity and carries no dollar total, so a queue built
# from a deduped match alone is ordered by an arbitrary cluster member's amount.
# At the measured 3.72x collapse that is a convincingly ordered list of the wrong
# quantity -- the failure shape dev/PLAUSIBLE-WRONG-NUMBERS.md catalogues -- so
# the function refuses rather than guesses, and this file pins the refusal.

queue_match <- function(deduped = FALSE, amounts = c(100, 50, 10),
                        names3 = c("BIG ORG", "MID ORG", "SMALL ORG"),
                        oos = c(NA_character_, NA_character_, NA_character_)) {
  ids <- c("G1", "G2", "G3")
  res <- data.frame(
    .id = ids, tier = c("MAYBE", "MAYBE", "MAYBE"),
    overall_ein = c("111111111", "222222222", "333333333"),
    overall_name_y = names3, overall_score = c(0.7, 0.7, 0.7),
    overall_name_sim = 0.8, overall_margin = 0.01, n_close = 1L,
    stringsAsFactors = FALSE)
  attr(res, "pairs") <- data.frame(
    .id = ids, .ein = c("111111111", "222222222", "333333333"),
    name_y = names3, score = 0.7, state_y = "MT", city_y = "BOZEMAN",
    zip5_y = "59715", geo_state = 1, geo_zip5 = 1, stringsAsFactors = FALSE)
  g <- data.frame(
    grant_id = ids, ORG_EIN = "411111111", FILERNAME1 = "A FOUNDATION",
    PF_15_G_PAID_AMT = as.character(amounts),
    PF_15_G_PAID_RECIP_STAT = "PC", in_scope = TRUE,
    recip_name = names3, recip_name_alt = NA_character_,
    recip_street = "1 MAIN ST", recip_city = "BOZEMAN",
    recip_state_raw = "MT", recip_zip5 = "59715",
    recipient_type = "public_charity", recipient_type_detail = NA_character_,
    looks_personal = FALSE, oos_reason = oos, stringsAsFactors = FALSE)
  if (deduped) g$recipient_uid <- seq_along(ids)
  structure(list(result = res, grants = g, in_scope = ids,
                 out_of_scope = character(0)), class = "pf_match")
}

test_that("the queue is ordered by dollars and carries a coverage curve", {
  q <- pf_review_queue(queue_match(), verbose = FALSE)
  expect_equal(q$grant_id, c("G1", "G2", "G3"))
  expect_equal(q$dollars, c(100, 50, 10))
  expect_equal(q$rank, 1:3)
  expect_equal(round(q$cum_share, 4), c(0.625, 0.9375, 1))
  expect_equal(as.integer(attr(q, "coverage")[["50%"]]), 1L)
  expect_equal(attr(q, "counts")$reviewable_dollars, 160)
})

test_that("a deduped match refuses rather than pricing the representative row", {
  # the whole point of the function. The message has to say what to pass.
  expect_error(pf_review_queue(queue_match(deduped = TRUE), verbose = FALSE),
               "deduped identities")
  expect_error(pf_review_queue(queue_match(deduped = TRUE), verbose = FALSE),
               "pf_prepare")
})

test_that("with the every-row frame, dollars are summed per identity", {
  # Keyed the way pf_recipients() keys the cascade: R<recipient_uid>. Three
  # grants collapse into two identities, and R1 holds two of them -- so the
  # representative row would price R1 at 60 where the identity is worth 120,
  # and R1 and R2 would be a coin toss instead of a clear first.
  m <- queue_match(deduped = TRUE)
  m$grants$grant_id <- c("R1", "R2", "R3")
  m$in_scope <- c("R1", "R2", "R3")
  r <- as.data.frame(m$result); r$.id <- c("R1", "R2", "R3")
  p <- as.data.frame(attr(m$result, "pairs")); p$.id <- c("R1", "R2", "R3")
  attr(r, "pairs") <- p
  m$result <- r

  every_row <- data.frame(
    recipient_uid = c(1, 1, 2),
    PF_15_G_PAID_AMT = c("60", "60", "50"),
    recip_name = c("BIG ORG", "BIG ORG DUP", "MID ORG"),
    stringsAsFactors = FALSE)

  q <- pf_review_queue(m, grants = every_row, verbose = FALSE)
  expect_equal(q$grant_id, c("R1", "R2"))
  expect_equal(q$dollars, c(120, 50))      # 60 + 60, not one 60
  expect_equal(q$n_grants, c(2L, 1L))
})

test_that("placeholders and foreign recipients are excluded and reported", {
  m <- queue_match(names3 = c("BIG ORG", "SEE ATTACHED SCHEDULE", "SMALL ORG"),
                   oos = c(NA, NA, "foreign address"))
  q <- pf_review_queue(m, verbose = FALSE)
  expect_equal(q$grant_id, "G1")
  cn <- attr(q, "counts")
  expect_equal(cn$placeholder_rows, 1L)
  expect_equal(cn$placeholder_dollars, 50)
  expect_equal(cn$foreign_rows, 1L)
  expect_equal(cn$foreign_dollars, 10)
  # reported, not merely absent: the dollars behind each exclusion are visible
  expect_equal(cn$reviewable_dollars, 100)
})

test_that("an unreadable amount keeps the identity and is counted, not zeroed", {
  m <- queue_match(amounts = c(100, NA, 10))
  m$grants$PF_15_G_PAID_AMT <- c("100", "not a number", "10")
  q <- pf_review_queue(m, verbose = FALSE)
  expect_equal(attr(q, "counts")$rows_without_amount, 1L)
  expect_equal(attr(q, "counts")$reviewable_dollars, 110)
  expect_true("G2" %in% q$grant_id)        # kept, at 0 dollars
  expect_equal(q$dollars[q$grant_id == "G2"], 0)
})

test_that("currency formatting in the amount column is read, not refused", {
  m <- queue_match()
  m$grants$PF_15_G_PAID_AMT <- c("$1,200", "50", "10")
  q <- pf_review_queue(m, verbose = FALSE)
  expect_equal(q$dollars[q$grant_id == "G1"], 1200)
})

test_that("an absent amount column stops with the column named", {
  m <- queue_match(); m$grants$PF_15_G_PAID_AMT <- NULL
  expect_error(pf_review_queue(m, verbose = FALSE), "PF_15_G_PAID_AMT")
})

test_that("tiers is validated, and NO can be queued alongside MAYBE", {
  expect_error(pf_review_queue(queue_match(), tiers = "PROBABLY", verbose = FALSE),
               "must be among")
  m <- queue_match()
  r <- as.data.frame(m$result); r$tier <- c("MAYBE", "NO", "MAYBE")
  attr(r, "pairs") <- attr(m$result, "pairs"); m$result <- r
  q <- pf_review_queue(m, tiers = c("MAYBE", "NO"), verbose = FALSE)
  expect_setequal(q$tier, c("MAYBE", "NO"))
  expect_equal(nrow(q), 3L)
})

test_that("an empty tier stops rather than returning an empty queue", {
  m <- queue_match()
  r <- as.data.frame(m$result); r$tier <- "YES"
  attr(r, "pairs") <- attr(m$result, "pairs"); m$result <- r
  expect_error(pf_review_queue(m, tiers = "MAYBE", verbose = FALSE),
               "nothing to queue")
})
