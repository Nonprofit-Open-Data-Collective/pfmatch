## The secondary-unit line as adjudication evidence -------------------------
# ADDR_L2 is a free-text field that filers use for suites, for street
# continuations, for cities, for PO boxes and for sequential record counters.
# Everything here is a value observed in the corpus, so the rejections are the
# point of the tests as much as the parses are.
#
# The parse now comes from npmatch (np_normalize()'s `street_unit`); what is
# asserted here is what pfmatch still owns -- the two local rejections and the
# comparison semantics -- plus the corpus-derived behaviours that were measured
# under the old local parser and must survive the delegation. See
# dev/UNIT-UPSTREAM-SYNC.md §5 for why each of those matters.

test_that("a suite is parsed whatever designator the filer used", {
  u <- pf_street_unit(c("SUITE 400", "Suite 400", "STE 400", "ste 400", "#400"))
  # npmatch canon: a hash is its own designator, and folds into the room-level
  # class at comparison time rather than at parse time
  expect_equal(u, c(rep("STE 400", 4L), "# 400"))
  expect_equal(pf_unit_evidence("#400", "STE 400"), "agree")
})

test_that("room-level designators are interchangeable but levels are not", {
  # UNIT 1200 and STE 1200 are the same door written two ways
  expect_equal(pf_unit_evidence("UNIT 1200", "STE 1200"), "agree")
  expect_equal(pf_unit_evidence("APT 3B", "UNIT 3B"), "agree")
  # a bare identifier is a room, since a filer writing "206" means suite 206
  expect_equal(pf_unit_evidence("Suite 206", "206"), "agree")
  # but floor 2 is not suite 2. npmatch's own pair annotation compares
  # street_unit_id alone and would call this agreement; here it must not.
  expect_equal(pf_unit_evidence("FL 2", "STE 2"), "conflict")
  expect_equal(pf_street_unit("2 FLOOR"), "FL 2")
  # nor is a mailbox or a department a door
  expect_equal(pf_unit_evidence("PMB 136", "STE 136"), "conflict")
  expect_equal(pf_unit_evidence("DEPT 400", "STE 400"), "conflict")
})

test_that("different suites conflict", {
  expect_equal(pf_unit_evidence("STE 200", "STE 420"), "conflict")
  expect_equal(pf_unit_evidence("332", "324"), "conflict")
})

test_that("a hyphenated identifier is not truncated to its first token", {
  # STE T-700 and STE T-205 both collapsed to "T" and were reported as the
  # same suite. A false `agree` is worse than a false `conflict`, because a
  # conflict gets looked at and an agreement never does.
  expect_equal(pf_street_unit(c("STE T-700", "STE T-205")),
               c("STE T700", "STE T205"))
  expect_equal(pf_unit_evidence("STE T-700", "STE T-205"), "conflict")
  # and a sub-identifier reads as a different door, deliberately
  expect_equal(pf_unit_evidence("STE 1150-291", "STE 1150"), "conflict")
})

test_that("line 2 content that is not a unit is rejected", {
  junk <- c("PO BOX 1367", "P O BOX 42", "BOX 19960", "114 HIGH ST",
            "1124 West Carson Street", "312 SW 1ST AVE", "STREET",
            "LAS VEGAS", "C/O JOHN SMITH", "NORTH TOWER", "")
  u <- pf_street_unit(junk)
  expect_true(all(!nzchar(u)),
              info = paste("parsed:", paste(junk[nzchar(u)], collapse = " | ")))
  # and so two rejected values never produce a conflict
  expect_equal(pf_unit_evidence("PO BOX 1", "PO BOX 2"), "absent")
  expect_equal(pf_unit_evidence("114 HIGH ST", "312 SW 1ST AVE"), "absent")
})

test_that("the digitless rejection applies to bare values only", {
  # STREET, WAY and CONSERVANCY are real line-2 values, and npmatch's
  # bare-identifier path reads each as a unit id. The digit requirement is
  # pfmatch's and it stops them.
  expect_equal(pf_street_unit(c("STREET", "WAY", "CONSERVANCY")), rep("", 3L))
  expect_equal(pf_unit_evidence("STREET", "STREET"), "absent")
  # but it must not take a real suite with it: SUITE B carries no digit, and
  # the old local parser rejected it for that reason
  expect_equal(pf_street_unit("SUITE B"), "STE B")
  expect_equal(pf_unit_evidence("SUITE B", "SUITE B "), "agree")
})

test_that("a suite is read out of a line 2 that holds a whole street", {
  # filers repeat the street on line 2 and put the suite after it. The old
  # local parser rejected the whole value on the street-type word; the suite
  # is right there and is the thing worth comparing.
  expect_equal(pf_street_unit("68 JAY STREET SUITE 425"), "STE 425")
  expect_equal(pf_unit_evidence("68 JAY STREET SUITE 425", "68 JAY ST SUITE 425"),
               "agree")
})

test_that("a bare number at a box street is a box number, not a door", {
  # 211 EMMET STREET SOUTH PO BOX, with 400891 on line 2: the digits are the
  # box, and comparing them against another box reported a false conflict.
  expect_equal(pf_street_unit("400891", "211 EMMET STREET SOUTH PO BOX"), "")
  expect_equal(pf_unit_evidence("400331", "400891",
                                "211 EMMET STREET SOUTH PO BOX",
                                "211 EMMET STREET SOUTH PO BOX"), "absent")
  # a campus box and a suite's mail box are boxes too
  expect_equal(pf_street_unit("3440", "300 KENAN CENTER DRIVE - CAMPUS BOX"), "")
  expect_equal(pf_street_unit("184", "4347 W NORTHWEST HWY STE 130 BOX"), "")
  # without the street it cannot know, and says what it sees
  expect_equal(pf_unit_evidence("400331", "400891"), "conflict")
  # a street whose name merely begins with BOX is not a box street
  expect_equal(pf_street_unit("206", "211 BOXWOOD LANE"), "# 206")
  expect_equal(pf_street_unit("206", "100 BOXER ST"), "# 206")
  # and an explicit designator is read as a unit even at a box street
  expect_equal(pf_street_unit("STE 206", "211 EMMET STREET SOUTH PO BOX"),
               "STE 206")
})

test_that("the two designators npmatch excludes are gone", {
  # R/unit.R used to list NO and OFC. npmatch's BMF scan excludes both for
  # measured reasons -- NO is North far more often than Number, and the USPS
  # C2 designators match street names -- and shipping them was a defect.
  expect_equal(pf_street_unit(c("NO 5", "OFC 200", "OFFICE 200",
                                "OFC PIERCE ST", "KEYSER AVE", "SIDEHILL RD")),
               rep("", 6L))
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
  expect_length(pf_street_unit(character(0)), 0L)
  # the parse de-duplicates internally, so a repeated value must still come
  # back in position
  expect_equal(pf_street_unit(c("STE 9", "FL 9", "STE 9", "", "FL 9")),
               c("STE 9", "FL 9", "STE 9", "", "FL 9"))
})

test_that("conflict stays rare on the corpus", {
  # conflict is rare by design; if it ever becomes common, the parser has
  # started reading junk as units and the flag has stopped meaning anything.
  # This holds whatever normalizer is installed, which is why it is not gated.
  v <- pfmatch::pf_variants
  e <- pf_unit_evidence(v$a_unit, v$b_unit, v$a_street, v$b_street)
  expect_length(e, nrow(v))
  expect_setequal(unique(e), c("absent", "agree", "conflict", "one_sided"))
  expect_lt(mean(e == "conflict"), 0.02)
})

test_that("the fixture's recorded evidence reproduces under the pinned normalizer", {
  # Version-scoped for the same reason as test-variants.R's pinned block: the
  # parse is npmatch's now, so an intentional normalizer improvement SHOULD be
  # able to move a verdict. The fixture is on v1-6dcb298522cc5118 and the
  # retirement of the local parser moved 22 of the 5,410 pairs; every one is
  # traced in dev/UNIT-UPSTREAM-SYNC.md §4. Rebuilding needs a triangulation
  # run under the current normalizer, not just a fixture rebuild, so this
  # skips until that measurement pass happens.
  v <- pfmatch::pf_variants
  built <- attr(v, "normalizer")
  live  <- tryCatch(npmatch::np_normalize_signature(), error = function(e) NA_character_)
  skip_if(is.na(built) || is.na(live))
  skip_if_not(identical(built, live),
              sprintf(paste("normalizer moved (fixture %s, installed %s);",
                            "rebuild with data-raw/make-pf-variants.R"), built, live))
  expect_identical(
    pf_unit_evidence(v$a_unit, v$b_unit, v$a_street, v$b_street),
    v$unit_evidence)
})
