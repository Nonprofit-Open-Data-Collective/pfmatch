## The secondary-unit line as adjudication evidence -------------------------
# ADDR_L2 is a free-text field that filers use for suites, for street
# continuations, for cities, for PO boxes and for sequential record counters.
# Everything here is a value observed in the corpus, so the rejections are the
# point of the tests as much as the parses are.

test_that("a suite is parsed whatever designator the filer used", {
  p <- pf_parse_unit(c("SUITE 400", "Suite 400", "STE 400", "ste 400", "#400"))
  expect_equal(p$id, rep("400", 5L))
  expect_equal(unique(p$type), "STE")
})

test_that("room-level designators are interchangeable but levels are not", {
  # UNIT 1200 and STE 1200 are the same door written two ways
  expect_equal(pf_unit_evidence("UNIT 1200", "STE 1200"), "agree")
  expect_equal(pf_unit_evidence("APT 3B", "UNIT 3B"), "agree")
  # a bare identifier is a room, since a filer writing "206" means suite 206
  expect_equal(pf_unit_evidence("Suite 206", "206"), "agree")
  # but floor 2 is not suite 2
  expect_equal(pf_unit_evidence("FL 2", "STE 2"), "conflict")
  expect_equal(pf_parse_unit("2 FLOOR")$type, "FL")
})

test_that("different suites conflict", {
  expect_equal(pf_unit_evidence("STE 200", "STE 420"), "conflict")
  expect_equal(pf_unit_evidence("332", "324"), "conflict")
})

test_that("a hyphenated identifier is not truncated to its first token", {
  # STE T-700 and STE T-205 both collapsed to "T" and were reported as the
  # same suite. A false `agree` is worse than a false `conflict`, because a
  # conflict gets looked at and an agreement never does.
  p <- pf_parse_unit(c("STE T-700", "STE T-205"))
  expect_equal(p$id, c("T700", "T205"))
  expect_equal(pf_unit_evidence("STE T-700", "STE T-205"), "conflict")
})

test_that("line 2 content that is not a unit is rejected", {
  junk <- c("PO BOX 1367", "P O BOX 42", "BOX 19960", "114 HIGH ST",
            "1124 West Carson Street", "312 SW 1ST AVE", "STREET",
            "LAS VEGAS", "C/O JOHN SMITH", "NORTH TOWER", "")
  p <- pf_parse_unit(junk)
  expect_true(all(!nzchar(p$id)),
              info = paste("parsed:", paste(junk[nzchar(p$id)], collapse = " | ")))
  # and so two rejected values never produce a conflict
  expect_equal(pf_unit_evidence("PO BOX 1", "PO BOX 2"), "absent")
  expect_equal(pf_unit_evidence("114 HIGH ST", "312 SW 1ST AVE"), "absent")
})

test_that("a bare number at a PO box street is a box number, not a door", {
  # 211 EMMET STREET SOUTH PO BOX, with 400891 on line 2: the digits are the
  # box, and comparing them against another box reported a false conflict.
  expect_equal(pf_parse_unit("400891", "211 EMMET STREET SOUTH PO BOX")$id, "")
  expect_equal(pf_unit_evidence("400331", "400891",
                                "211 EMMET STREET SOUTH PO BOX",
                                "211 EMMET STREET SOUTH PO BOX"), "absent")
  # without the street it cannot know, and says what it sees
  expect_equal(pf_unit_evidence("400331", "400891"), "conflict")
})

test_that("silence is not disagreement", {
  expect_equal(pf_unit_evidence("STE 400", ""), "one_sided")
  expect_equal(pf_unit_evidence("", "STE 400"), "one_sided")
  expect_equal(pf_unit_evidence("", ""), "absent")
  expect_equal(pf_unit_evidence(NA_character_, NA_character_), "absent")
})

test_that("vectorized and length-stable", {
  a <- c("STE 1", "STE 1", "", NA, "PO BOX 9")
  b <- c("STE 1", "STE 2", "STE 3", "STE 4", "STE 5")
  e <- pf_unit_evidence(a, b)
  expect_length(e, 5L)
  expect_equal(e, c("agree", "conflict", "one_sided", "one_sided", "one_sided"))
  expect_equal(nrow(pf_parse_unit(character(0))), 0L)
})

test_that("the fixture's recorded evidence reproduces", {
  v <- pfmatch::pf_variants
  expect_identical(
    pf_unit_evidence(v$a_unit, v$b_unit, v$a_street, v$b_street),
    v$unit_evidence)
  # conflict is rare by design; if it ever becomes common, the parser has
  # started reading junk as units and the flag has stopped meaning anything
  expect_lt(mean(v$unit_evidence == "conflict"), 0.02)
})
