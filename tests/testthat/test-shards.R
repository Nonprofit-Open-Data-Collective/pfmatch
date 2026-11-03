# Sharding the truth round across labelers.
#
# The tests that matter are the refusals, for the same reason as test-round.R:
# the labels are the expensive part, so an error found after the round comes
# back is an error found after the money is spent. Three of them are specific
# to fanning the work out rather than doing it once:
#
#   * a web basis with no URL, which is an inference wearing a web label and
#     would be allowed to grade a model arm;
#   * two labelers on a case the key dealt once, which is a copied shard file
#     and reads as perfect agreement;
#   * a blank labeler, which turns N labelers into one undifferentiated pile
#     that no per-labeler cut can see into.
#
# The second group covers the arithmetic: that dealing is balanced within
# stratum, that the overlap is really dealt to a DIFFERENT shard, and that
# consolidation neither tie-breaks a disagreement nor strengthens the evidence
# behind a concurrence.

# Ids shaped as pf_identity_id() makes them. pf_read_truth() refuses R<k>,
# which predates content-derived ids, so the fixtures use the real shape.
sid <- function(i) sprintf("PFI-%016x", as.integer(i))

shard_draw <- function(n = 60L, strata = c("a", "b", "c")) {
  d <- data.frame(grant_id = sid(seq_len(n)),
                  stratum = rep(strata, length.out = n),
                  stringsAsFactors = FALSE)
  attr(d, "population") <- "cb3c78ff0f1a9546"
  d
}

# A filled shard file, as a labeler returns it.
shard_rows <- function(ids, labeler, shard = 1L, verdict = "ORG_FOUND",
                       ein = NULL, basis = "reference",
                       confidence = "high", url = NA_character_) {
  n <- length(ids)
  data.frame(
    truth_id = sprintf("OID%s|T1", ids),
    grant_id = ids,
    population = "cb3c78ff0f1a9546",
    verdict = rep_len(verdict, n),
    correct_ein = if (is.null(ein)) sprintf("%09d", seq_along(ids)) else rep_len(ein, n),
    wrong_ein = NA_character_,
    basis = rep_len(basis, n),
    confidence = rep_len(confidence, n),
    labeler = labeler,
    shard = shard,
    source_url = rep_len(url, n),
    note = "because",
    stringsAsFactors = FALSE)
}

## ---- the refusals, dealing -------------------------------------------------

test_that("an assignment with no seed is refused", {
  # same reason as pf_round_sample(): the labels outlive the session
  expect_error(pf_truth_shards(shard_draw(), k = 4, verbose = FALSE),
               "cannot be redealt")
})

test_that("dealing without a population fingerprint is refused", {
  # a draw read back from CSV has lost the attribute, which is the real case
  d <- shard_draw()
  attr(d, "population") <- NULL
  expect_error(pf_truth_shards(d, k = 4, seed = 1, verbose = FALSE),
               "no population fingerprint")
  # and is allowed only for a dry run whose labels are thrown away
  s <- pf_truth_shards(d, k = 4, seed = 1, require_population = FALSE,
                       verbose = FALSE)
  expect_true(is.na(attr(s, "population")))
})

test_that("an overlap with one shard is refused rather than silently dropped", {
  expect_error(pf_truth_shards(shard_draw(), k = 1, overlap = 0.1, seed = 1,
                               verbose = FALSE),
               "no second\\s+labeler|no second labeler")
  # k = 1 with no overlap is a legitimate single-labeler round
  s <- pf_truth_shards(shard_draw(), k = 1, overlap = 0, seed = 1,
                       verbose = FALSE)
  expect_equal(nrow(s), 60L)
})

test_that("a draw with a repeated case is refused", {
  d <- shard_draw(10L)
  d <- rbind(d, d[1, ])
  attr(d, "population") <- "cb3c78ff0f1a9546"
  expect_error(pf_truth_shards(d, k = 2, seed = 1, verbose = FALSE),
               "appear twice in the draw")
})


test_that("a repeated labeler name is refused, because it holes the overlap", {
  # Not extra capacity: pf_labeler_agreement() needs two DIFFERENT names on a
  # case, and pf_read_truth() refuses one labeler answering a case twice -- so
  # the overlap between the two shards sharing a name comes back unusable,
  # after the labelling is paid for.
  expect_error(
    pf_truth_shards(shard_draw(60L), k = 4, overlap = 0.1, seed = 1,
                    labelers = c("a", "b", "a", "c"), verbose = FALSE),
    "repeats `a`")
  # with the overlap deliberately off there is no agreement read to hole
  expect_silent(
    pf_truth_shards(shard_draw(60L), k = 4, overlap = 0, seed = 1,
                    labelers = c("a", "b", "a", "c"), verbose = FALSE))
})

test_that("a named roster stamps the key and the templates", {
  dir <- withr::local_tempdir()
  roster <- sprintf("m/truth-%02d", 1:5)
  s <- pf_truth_shards(shard_draw(400L), k = 5, overlap = 0.15, seed = 1,
                       labelers = roster, verbose = FALSE)
  expect_equal(sort(unique(s$labeler)), sort(roster))
  # every row of a shard carries that shard's labeler, overlap rows included
  for (i in 1:5)
    expect_equal(unique(s$labeler[s$shard == i]), roster[i])
  pf_write_shards(s, dir, verbose = FALSE)
  tf <- utils::read.csv(file.path(dir, "shard-03-truth.csv"),
                        colClasses = "character")
  expect_equal(unique(tf$labeler), roster[3])
})

test_that("an impossible overlap or labeler list is refused", {
  expect_error(pf_truth_shards(shard_draw(), k = 4, overlap = 0.9, seed = 1,
                               verbose = FALSE), "fraction in \\[0, 0.5\\]")
  expect_error(pf_truth_shards(shard_draw(), k = 4, seed = 1,
                               labelers = c("a", "b"), verbose = FALSE),
               "names 2 labelers for 4 shards")
  expect_error(pf_truth_shards(shard_draw(5L), k = 8, seed = 1, verbose = FALSE),
               "8 shards over 5 cases")
})

## ---- the dealing itself ----------------------------------------------------

test_that("every case is dealt exactly once as a primary, and shards are even", {
  s <- pf_truth_shards(shard_draw(60L), k = 4, overlap = 0, seed = 1,
                       verbose = FALSE)
  expect_equal(sort(s$grant_id[s$primary]), sort(shard_draw(60L)$grant_id))
  expect_true(all(table(s$shard) == 15L))
})

test_that("dealing is balanced WITHIN stratum, not across the row order", {
  # the point of the round-robin: a weak labeler must not arrive as a stratum
  # effect, because a stratum effect is what the round is measuring
  s <- pf_truth_shards(shard_draw(60L), k = 4, overlap = 0, seed = 1,
                       verbose = FALSE)
  tb <- table(s$shard, s$stratum)
  expect_true(all(abs(tb - 5L) <= 1L))
})

test_that("the overlap goes to a different shard and is marked in the key", {
  s <- pf_truth_shards(shard_draw(60L), k = 4, overlap = 0.1, seed = 1,
                       verbose = FALSE)
  expect_equal(attr(s, "overlap_n"), 6L)
  expect_equal(nrow(s), 66L)
  ov <- unique(s$grant_id[s$overlap])
  expect_length(ov, 6L)
  for (id in ov) {
    sh <- s$shard[s$grant_id == id]
    expect_length(sh, 2L)
    expect_length(unique(sh), 2L)   # two shards, not the same one twice
  }
  # and every non-overlap case appears once
  expect_true(all(table(s$grant_id[!s$overlap]) == 1L))
})

test_that("overlap load is balanced across labelers, not just in expectation", {
  # The regression this guards: sampling both halves of the overlap uniformly
  # left stage 1 with 7 overlap cases on one labeler and 15 on another against
  # an expectation of 10, and pf_labeler_agreement() reads a per-labeler cell
  # under min_n as unusable. Checked over many seeds because the defect it
  # replaces passed any single seed roughly half the time.
  for (seed in 1:40) {
    s <- pf_truth_shards(shard_draw(400L), k = 5, overlap = 0.15, seed = seed,
                         verbose = FALSE)
    ovs <- as.integer(table(factor(s$shard[s$overlap], levels = 1:5)))
    expect_equal(sum(ovs), 2L * attr(s, "overlap_n"))
    expect_lte(max(ovs) - min(ovs), 1L)        # k divides 60: exact
    expect_gte(min(ovs), 20L)                  # clears min_n, every seed
  }
})

test_that("a shard gives up as many overlap cases as it receives", {
  s <- pf_truth_shards(shard_draw(400L), k = 5, overlap = 0.15, seed = 7,
                       verbose = FALSE)
  gave <- table(factor(s$shard[s$overlap & s$primary], levels = 1:5))
  got  <- table(factor(s$shard[s$overlap & !s$primary], levels = 1:5))
  expect_equal(as.integer(gave), as.integer(got))
})

test_that("the overlap is not a fixed pairing of labelers", {
  # A fixed lag makes the agreement figure about one pair of labelers rather
  # than about the round, so every available lag should be in use.
  s <- pf_truth_shards(shard_draw(400L), k = 5, overlap = 0.15, seed = 3,
                       verbose = FALSE)
  ov <- unique(s$grant_id[s$overlap])
  lag <- vapply(ov, function(id) {
    sh <- s$shard[s$grant_id == id]
    (diff(range(sh)) %% 5L)
  }, integer(1))
  expect_gt(length(unique(lag)), 1L)
  pairs <- vapply(ov, function(id)
    paste(sort(s$shard[s$grant_id == id]), collapse = "-"), character(1))
  # no pair carries more than half the overlap
  expect_lt(max(table(pairs)), length(ov) / 2)
})

test_that("an uneven overlap is spread rather than stacked on shard 1", {
  # 7 does not divide by 4, so somebody gets the extra; it must not always be
  # the low-numbered labelers, who would then be systematically better
  # measured than the rest.
  first <- vapply(1:30, function(seed) {
    s <- pf_truth_shards(shard_draw(100L), k = 4, overlap = 0.07, seed = seed,
                         verbose = FALSE)
    as.integer(table(factor(s$shard[s$overlap & s$primary], levels = 1:4)))[1]
  }, integer(1))
  expect_gt(length(unique(first)), 1L)
})

test_that("the deal says what each labeler got, and warns when it is short", {
  out <- capture.output(
    pf_truth_shards(shard_draw(400L), k = 8, overlap = 0.1, seed = 1,
                    verbose = TRUE))
  expect_true(any(grepl("overlap per labeler", out)))
  expect_true(any(grepl("min_n of 20", out)))
  quiet <- capture.output(
    pf_truth_shards(shard_draw(400L), k = 5, overlap = 0.15, seed = 1,
                    verbose = TRUE))
  expect_true(any(grepl("overlap per labeler", quiet)))
  expect_false(any(grepl("min_n of 20", quiet)))
})

test_that("the same seed deals the same assignment", {
  a <- pf_truth_shards(shard_draw(), k = 4, seed = 99, verbose = FALSE)
  b <- pf_truth_shards(shard_draw(), k = 4, seed = 99, verbose = FALSE)
  expect_equal(as.data.frame(a), as.data.frame(b))
  c2 <- pf_truth_shards(shard_draw(), k = 4, seed = 100, verbose = FALSE)
  expect_false(identical(as.data.frame(a), as.data.frame(c2)))
})

## ---- writing ---------------------------------------------------------------

test_that("the case file is blinded and the template is pre-keyed", {
  d <- file.path(tempfile("shards")); on.exit(unlink(d, recursive = TRUE))
  s <- pf_truth_shards(shard_draw(40L), k = 4, overlap = 0.1, seed = 7,
                       labelers = sprintf("lab%d", 1:4), verbose = FALSE)
  pf_write_shards(s, d, verbose = FALSE)

  cf <- utils::read.csv(file.path(d, "shard-01-cases.csv"),
                        colClasses = "character")
  # the labeler must not be able to tell which of its cases are the overlap
  expect_false("overlap" %in% names(cf))
  expect_false("primary" %in% names(cf))

  tf <- utils::read.csv(file.path(d, "shard-01-truth.csv"),
                        colClasses = "character")
  expect_equal(names(tf), pf_shard_schema())
  expect_true(all(tf$population == "cb3c78ff0f1a9546"))
  expect_true(all(tf$labeler == "lab1"))
  expect_true(all(tf$verdict == ""))          # nothing pre-answered
  expect_true(file.exists(file.path(d, "SHARD-KEY.csv")))
})


test_that("a narrower redeal takes the wider deal's leftover shards with it", {
  # Writing k = 5 over a k = 8 round used to overwrite shards 1-5 and leave
  # 6-8 in the live directory, where they look exactly like work to hand out.
  # pf_read_truth() refuses their rows, but only once a labeler has done them.
  dir <- withr::local_tempdir()
  wide <- pf_truth_shards(shard_draw(400L), k = 8, overlap = 0.2, seed = 1,
                          verbose = FALSE)
  pf_write_shards(wide, dir, verbose = FALSE)
  expect_true(file.exists(file.path(dir, "shard-08-truth.csv")))

  narrow <- pf_truth_shards(shard_draw(400L), k = 5, overlap = 0.15, seed = 1,
                            verbose = FALSE)
  out <- capture.output(
    pf_write_shards(narrow, dir, overwrite = TRUE, verbose = TRUE))
  expect_false(file.exists(file.path(dir, "shard-06-truth.csv")))
  expect_false(file.exists(file.path(dir, "shard-08-cases.csv")))
  expect_true(file.exists(file.path(dir, "shard-05-truth.csv")))
  expect_true(any(grepl("removed 6 file", out, fixed = TRUE)))
  expect_length(list.files(dir, pattern = "^shard-"), 10L)
})

test_that("writing over a labeler's part-written file is refused", {
  d <- file.path(tempfile("shards")); on.exit(unlink(d, recursive = TRUE))
  s <- pf_truth_shards(shard_draw(20L), k = 2, overlap = 0, seed = 3,
                       verbose = FALSE)
  pf_write_shards(s, d, verbose = FALSE)
  expect_error(pf_write_shards(s, d, verbose = FALSE), "already holds")
  expect_silent(pf_write_shards(s, d, overwrite = TRUE, verbose = FALSE))
})

## ---- the refusals, reading -------------------------------------------------

test_that("a missing schema column is a stop, naming what is present", {
  r <- shard_rows(sid(1:5), "lab1")
  r$basis <- NULL
  expect_error(pf_read_truth(r, verbose = FALSE), "missing these columns: basis")
})

test_that("a web basis with no source_url is refused", {
  # an asserted web basis is an inference wearing a web label, and basis is
  # what decides which rows may grade a model arm
  r <- shard_rows(sid(1:5), "lab1", basis = "web")
  expect_error(pf_read_truth(r, verbose = FALSE), "name no source_url")
  r$source_url <- "https://example.org/about"
  expect_equal(nrow(pf_read_truth(r, verbose = FALSE)), 5L)
})

test_that("a missing basis or confidence is refused", {
  r <- shard_rows(sid(1:5), "lab1")
  r$confidence[2] <- ""
  expect_error(pf_read_truth(r, verbose = FALSE), "no basis or no confidence")
})

test_that("ORG_FOUND with no EIN, and a blank labeler, are both stops", {
  r <- shard_rows(sid(1:5), "lab1")
  r$correct_ein[3] <- ""
  expect_error(pf_read_truth(r, verbose = FALSE), "name no 9-digit EIN")

  r <- shard_rows(sid(1:5), "lab1")
  r$labeler[2] <- ""
  expect_error(pf_read_truth(r, verbose = FALSE), "carry no labeler")
})

test_that("an unknown level is a stop", {
  r <- shard_rows(sid(1:5), "lab1")
  r$verdict[1] <- "MATCH"     # a pf_verdict_levels() value, not a truth one
  expect_error(pf_read_truth(r, verbose = FALSE), "outside the permitted set")
})

test_that("one labeler answering a case twice is a stop", {
  r <- shard_rows(sid(1:5), "lab1")
  r <- rbind(r, r[1, ])
  expect_error(pf_read_truth(r, verbose = FALSE), "appear twice")
})

test_that("mixed populations are refused, and so is a mismatch", {
  r <- shard_rows(sid(1:5), "lab1")
  r$population[3] <- "0b5126ef02f2a8b0"
  expect_error(pf_read_truth(r, verbose = FALSE), "mix populations")

  r <- shard_rows(sid(1:5), "lab1")
  expect_error(pf_read_truth(r, population = "0b5126ef02f2a8b0", verbose = FALSE),
               "population mismatch")
})

test_that("blank template rows are reported as missing, not counted wrong", {
  # a round comes back incomplete far more often than malformed, and a stop
  # here would block the agreement read the returned rows already support
  r <- shard_rows(sid(1:5), "lab1")
  r[4:5, setdiff(names(r), c("grant_id", "population", "shard", "labeler"))] <- ""
  out <- pf_read_truth(r, verbose = FALSE)
  expect_equal(nrow(out), 3L)
  expect_equal(attr(out, "missing"), sid(4:5))
})

test_that("two labelers on a case the key dealt once is a stop", {
  # What a copied shard file actually looks like: shard-01-truth.csv duplicated
  # with the labeler name changed, so the (case, shard) pairs are all ones the
  # key really dealt and only the second labeler is spurious. Without this
  # check it reads as perfect agreement on every case in the shard.
  s <- pf_truth_shards(shard_draw(20L), k = 2, overlap = 0, seed = 5,
                       verbose = FALSE)
  one <- s$grant_id[s$shard == 1][1:3]
  r <- rbind(shard_rows(one, "lab1", shard = 1L),
             shard_rows(one, "lab2", shard = 1L))
  expect_error(pf_read_truth(r, key = s, verbose = FALSE),
               "dealt to one shard")
})


test_that("a shard returned under an unrostered name is refused", {
  # pf_truth_shards(labelers = )'s roxygen has always claimed pf_read_truth()
  # enforces the roster; the check was not there. A wrong name means the wrong
  # labeler's work or the wrong labeler's file, and every per-labeler figure
  # built on it names the wrong producer.
  roster <- sprintf("m/truth-%02d", 1:4)
  s <- pf_truth_shards(shard_draw(80L), k = 4, overlap = 0.1, seed = 1,
                       labelers = roster, verbose = FALSE)
  rows <- do.call(rbind, lapply(1:4, function(i)
    shard_rows(s$grant_id[s$shard == i], roster[i], shard = i)))
  expect_s3_class(pf_read_truth(rows, key = s, verbose = FALSE),
                  "pf_truth_rows")

  wrong <- rows
  wrong$labeler[wrong$shard == 3] <- "m/truth-99"
  expect_error(pf_read_truth(wrong, key = s, verbose = FALSE),
               "shard 3: got `m/truth-99`, dealt to `m/truth-03`")
})

test_that("two labelers swapping shard files is caught by the roster", {
  # The copied-file case the overlap check cannot see: both files are complete
  # and internally consistent, they are just attributed to each other.
  roster <- sprintf("m/truth-%02d", 1:4)
  s <- pf_truth_shards(shard_draw(80L), k = 4, overlap = 0.1, seed = 2,
                       labelers = roster, verbose = FALSE)
  swap <- c(2L, 1L, 3L, 4L)
  rows <- do.call(rbind, lapply(1:4, function(i)
    shard_rows(s$grant_id[s$shard == i], roster[swap[i]], shard = i)))
  expect_error(pf_read_truth(rows, key = s, verbose = FALSE),
               "did not deal that shard to")
})

test_that("an unrostered key reports what arrived instead of refusing it", {
  # What a round dealt without a roster writes: labeler NA in the object and
  # blank in the CSV. There is nothing to enforce, and that is not an error.
  s <- pf_truth_shards(shard_draw(80L), k = 4, overlap = 0.1, seed = 1,
                       verbose = FALSE)
  rows <- do.call(rbind, lapply(1:4, function(i)
    shard_rows(s$grant_id[s$shard == i], sprintf("whoever-%02d", i), shard = i)))
  expect_s3_class(pf_read_truth(rows, key = s, verbose = FALSE),
                  "pf_truth_rows")
  blank <- s
  blank$labeler <- ""
  expect_s3_class(pf_read_truth(rows, key = blank, verbose = FALSE),
                  "pf_truth_rows")
})

test_that("a row for a case the shard was not dealt is a stop", {
  s <- pf_truth_shards(shard_draw(20L), k = 2, overlap = 0, seed = 5,
                       verbose = FALSE)
  mine <- s$grant_id[s$shard == 1][1:3]
  r <- shard_rows(mine, "lab2", shard = 2L)     # right cases, wrong shard
  expect_error(pf_read_truth(r, key = s, verbose = FALSE),
               "the key did not deal")
})

test_that("a full round trips through disk", {
  d <- file.path(tempfile("shards")); on.exit(unlink(d, recursive = TRUE))
  s <- pf_truth_shards(shard_draw(40L), k = 4, overlap = 0.1, seed = 11,
                       labelers = sprintf("lab%d", 1:4), verbose = FALSE)
  pf_write_shards(s, d, verbose = FALSE)

  # fill every template as its assigned labeler would
  for (sh in 1:4) {
    p <- file.path(d, sprintf("shard-%02d-truth.csv", sh))
    tf <- utils::read.csv(p, colClasses = "character")
    tf$truth_id <- sprintf("OID%s|T1", tf$grant_id)
    tf$verdict <- "ORG_FOUND"
    tf$correct_ein <- sprintf("%09d", match(tf$grant_id, s$grant_id))
    tf$basis <- "reference"
    tf$confidence <- "high"
    tf$note <- "BMF row"
    utils::write.csv(tf, p, row.names = FALSE, na = "")
  }
  out <- pf_read_truth(d, key = file.path(d, "SHARD-KEY.csv"), verbose = FALSE)
  expect_equal(nrow(out), nrow(s))
  expect_length(attr(out, "missing"), 0L)
  expect_equal(length(attr(out, "by_labeler")), 4L)
})

## ---- agreement -------------------------------------------------------------

test_that("agreement is unmeasurable without an overlap, and says so", {
  r <- shard_rows(sid(1:5), "lab1")
  out <- pf_read_truth(r, verbose = FALSE)
  expect_error(pf_labeler_agreement(out), "agreement is not\\s+measurable")
})

test_that("strict and effective agreement differ on the NO_ORG reasons", {
  # pf_evaluate() keys on ^NO_ORG and does not distinguish them, so two
  # labelers differing only on WHY no org exists change no downstream figure
  ids <- sid(1:4)
  a <- shard_rows(ids, "lab1", shard = 1L, verdict = "NO_ORG_INDIVIDUAL",
                  ein = NA_character_)
  b <- shard_rows(ids, "lab2", shard = 2L, verdict = "NO_ORG_UNFINDABLE",
                  ein = NA_character_)
  g <- pf_labeler_agreement(pf_read_truth(rbind(a, b), verbose = FALSE),
                            min_n = 1L)
  expect_equal(g$summary$k[g$summary$basis == "strict"], 0L)
  expect_equal(g$summary$k[g$summary$basis == "effective"], 4L)
})

test_that("a single bad labeler shows up per labeler, not in the pooled rate", {
  ids <- sid(1:6)
  a <- shard_rows(ids, "good1", shard = 1L)
  b <- shard_rows(ids, "good2", shard = 2L)
  # bad3 agrees on nothing: a different EIN on every case
  c3 <- shard_rows(ids, "bad3", shard = 3L,
                   ein = sprintf("%09d", 900 + seq_along(ids)))
  g <- pf_labeler_agreement(pf_read_truth(rbind(a, b, c3), verbose = FALSE),
                            min_n = 1L)
  bl <- g$by_labeler
  expect_equal(bl$rate[bl$labeler == "bad3"], 0)
  expect_true(all(bl$rate[bl$labeler != "bad3"] == 0))  # disagreement is mutual
  expect_equal(g$summary$rate[g$summary$basis == "effective"], 0)
})

test_that("a thin overlap is marked unusable rather than read as a rate", {
  ids <- sid(1:3)
  r <- rbind(shard_rows(ids, "lab1", shard = 1L),
             shard_rows(ids, "lab2", shard = 2L))
  g <- pf_labeler_agreement(pf_read_truth(r, verbose = FALSE), min_n = 20L)
  expect_false(any(g$summary$usable))
  expect_output(print(g), "UNUSABLE")
  expect_output(print(g), "NOT accuracy")
})

## ---- consolidation ---------------------------------------------------------

test_that("two labelers who agree keep the WEAKER basis and confidence", {
  # concurrence is not corroboration: agreeing does not strengthen the
  # evidence either labeler actually had
  ids <- sid(1:4)
  a <- shard_rows(ids, "lab1", shard = 1L, basis = "web", confidence = "high",
                  url = "https://example.org")
  b <- shard_rows(ids, "lab2", shard = 2L, basis = "inference",
                  confidence = "medium")
  out <- pf_consolidate_truth(pf_read_truth(rbind(a, b), verbose = FALSE),
                              verbose = FALSE)
  expect_equal(nrow(out), 4L)
  expect_true(all(out$basis == "inference"))
  expect_true(all(out$confidence == "medium"))
  expect_true(all(out$labeler == "lab1+lab2"))
  expect_equal(attr(out, "agreed"), 4L)
  expect_equal(attr(out, "unresolved"), 0L)
})

test_that("a contested case becomes UNRESOLVED and is not tie-broken", {
  # the alternative keeps an answer whose whole authority is that one labeler
  # sounded surer, and self-reported confidence is what T3 exists to test
  ids <- sid(1:3)
  a <- shard_rows(ids, "lab1", shard = 1L, ein = "111111111",
                  confidence = "high")
  b <- shard_rows(ids, "lab2", shard = 2L, ein = "222222222",
                  confidence = "low")
  out <- pf_consolidate_truth(pf_read_truth(rbind(a, b), verbose = FALSE),
                              verbose = FALSE)
  expect_true(all(out$verdict == "UNRESOLVED"))
  expect_true(all(is.na(out$correct_ein)))
  expect_true(all(out$confidence == "low"))
  expect_equal(attr(out, "unresolved"), 3L)
  expect_true(all(grepl("contested:", out$note)))
  # the high-confidence labeler's EIN survives nowhere
  expect_false(any(out$correct_ein %in% "111111111"))
})

test_that("consolidated output satisfies the grading schema", {
  # the whole point: pf_evaluate() and pf_grade_verdicts() read this untouched
  ids <- sid(1:6)
  r <- rbind(shard_rows(ids[1:4], "lab1", shard = 1L),
             shard_rows(ids[5:6], "lab2", shard = 2L))
  out <- pf_consolidate_truth(pf_read_truth(r, verbose = FALSE),
                              verbose = FALSE)
  expect_equal(nrow(out), 6L)
  expect_true(all(pf_truth_schema() %in% names(out)))
  expect_equal(names(out)[seq_along(pf_truth_schema())], pf_truth_schema())
  expect_false(anyDuplicated(out$grant_id) > 0)
})

test_that("the shard schema is a superset of the grading schema", {
  # stated as a test because adding labeler to pf_truth_schema() instead would
  # make PF-TRUTH-V2 unreadable by pf_evaluate() on the same day
  expect_true(all(pf_truth_schema() %in% pf_shard_schema()))
  expect_true("labeler" %in% pf_shard_schema())
  expect_false("labeler" %in% pf_truth_schema())
})

test_that("truth levels and verdict levels are deliberately different sets", {
  # a round that conflates them scores NONE as wrong wherever the org exists
  # and is simply not among the candidates -- 24 of 82 hard cases
  expect_false(any(pf_verdict_levels()$verdict %in% pf_truth_levels()$verdict))
  expect_true("UNRESOLVED" %in% pf_truth_levels()$verdict)
})

## ---- the normalizer stamp ---------------------------------------------------

test_that("the deal carries the draw's normalizer rather than re-reading it", {
  # the deal can happen days after the draw, under a different installed stack,
  # and the signature belongs to the run that produced the draw's tiers
  d <- shard_draw(n = 60L)
  attr(d, "normalizer") <- "v1-deadbeefdeadbeef"
  s <- pf_truth_shards(d, k = 4, seed = 1, verbose = FALSE)
  expect_equal(attr(s, "normalizer"), "v1-deadbeefdeadbeef")
})

test_that("a draw with no normalizer deals anyway, reporting NA", {
  # every draw read back from a CSV is this case: the attribute is gone
  s <- pf_truth_shards(shard_draw(n = 60L), k = 4, seed = 1, verbose = FALSE)
  expect_true(is.na(attr(s, "normalizer")))
  expect_equal(nrow(s[s$primary, ]), 60L)
})

test_that("the deal carries the frame id alongside the population", {
  d <- shard_draw(n = 60L)
  attr(d, "frame_id") <- "0123456789abcdef"
  s <- pf_truth_shards(d, k = 4, seed = 1, verbose = FALSE)
  expect_equal(attr(s, "frame_id"), "0123456789abcdef")
  expect_equal(attr(s, "population"), "cb3c78ff0f1a9546")
})

test_that("a draw with no frame id deals anyway, reporting NA", {
  s <- pf_truth_shards(shard_draw(n = 60L), k = 4, seed = 1, verbose = FALSE)
  expect_true(is.na(attr(s, "frame_id")))
})

test_that("a label carrying a pre-fix positional id is refused", {
  # R<k> was a position among the deduplicated recipients. Re-attaching one to a
  # frame rebuilt since does not miss -- it lands on an unrelated organisation
  # while the population fingerprint still agrees, which nothing downstream can
  # see. The id's shape is the last place it is visible.
  d <- data.frame(grant_id = sprintf("R%03d", 1:8),
                  stratum = rep(c("a", "b"), 4), stringsAsFactors = FALSE)
  attr(d, "population") <- "cb3c78ff0f1a9546"
  s <- pf_truth_shards(d, k = 2, overlap = 0, seed = 1, verbose = FALSE)
  dir <- withr::local_tempdir()
  pf_write_shards(s, dir, verbose = FALSE)
  p <- file.path(dir, "shard-01-truth.csv")
  tf <- utils::read.csv(p, colClasses = "character")
  tf$verdict <- "NO_ORG_INDIVIDUAL"; tf$basis <- "reference"
  tf$confidence <- "high"; tf$labeler <- "someone"
  tf$truth_id <- sprintf("T%d", seq_len(nrow(tf)))
  utils::write.csv(tf, p, row.names = FALSE, na = "")
  expect_error(pf_read_truth(dir, verbose = FALSE), "predate pf_identity_id")
})

test_that("content ids pass the same reader", {
  d <- data.frame(grant_id = pf_identity_id(sprintf("ORG %d\r\r", 1:8)),
                  stratum = rep(c("a", "b"), 4), stringsAsFactors = FALSE)
  attr(d, "population") <- "cb3c78ff0f1a9546"
  s <- pf_truth_shards(d, k = 2, overlap = 0, seed = 1, verbose = FALSE)
  dir <- withr::local_tempdir()
  pf_write_shards(s, dir, verbose = FALSE)
  for (f in list.files(dir, pattern = "truth", full.names = TRUE)) {
    tf <- utils::read.csv(f, colClasses = "character")
    tf$verdict <- "NO_ORG_INDIVIDUAL"; tf$basis <- "reference"
    tf$confidence <- "high"; tf$labeler <- "someone"
    tf$truth_id <- sprintf("T%s%d", basename(f), seq_len(nrow(tf)))
    utils::write.csv(tf, f, row.names = FALSE, na = "")
  }
  v <- pf_read_truth(dir, verbose = FALSE)
  expect_equal(nrow(v), 8L)
})
