# Grading a reviewed round against ground truth.
#
# These run on synthetic labels on purpose. The labelled round
# (dev/ADJUDICATION-PREREQS.md T1) does not exist and no code produces it, so
# what is testable beforehand is the arithmetic and the denominators -- which is
# where the three dev/adjudicate-*-score.R scripts each went their own way.
#
# The two tests that matter most here are the ones that pin a REFUSAL:
# unscoreable cases must not count as wrong, and layers over different case sets
# must not be compared at all. Both failures produce a plausible rate over the
# wrong population, which is the class dev/PLAUSIBLE-WRONG-NUMBERS.md catalogues.

POP <- "aaaaaaaaaaaaaaaa"

# One truth row per shape a verdict can be graded against, so every grade in
# pf_grade_levels() is reachable from this one fixture.
truth_tbl <- function(population = POP) data.frame(
  truth_id    = paste0("T", 1:8),
  grant_id    = paste0("G", 1:8),
  population  = population,
  verdict     = c("ORG_FOUND", "ORG_FOUND", "ORG_FOUND", "NO_ORG_INDIVIDUAL",
                  "NO_ORG_NOT_EXEMPT", "UNRESOLVED", "ORG_FOUND", "ORG_FOUND"),
  correct_ein = c("111111111", "222222222", "333333333", NA, NA, NA,
                  "777777777", "888888888"),
  wrong_ein   = c(NA, "999999999", NA, NA, NA, NA, NA, NA),
  basis       = c("web", "web", "reference", "web", "web", "web", "web", "web"),
  # G3 and G7 are `medium`: they survive the default floor and both drop at
  # min_confidence = "high", which is what the floor test counts.
  confidence  = c("high", "high", "medium", "high", "high", "high", "medium", "high"),
  stringsAsFactors = FALSE)

# G1 right | G2 names the ruled-out EIN | G3 names some other EIN |
# G4 declined where no org exists (right) | G5 named an EIN where none exists |
# G6 truth is UNRESOLVED | G7 declined where an EIN is known | G8 ambiguous
round_verdicts <- function() data.frame(
  grant_id       = paste0("G", 1:8),
  verdict        = c("MATCH", "MATCH", "MATCH", "NONE", "MATCH", "MATCH",
                     "NONE", "AMBIGUOUS"),
  ein            = c("111111111", "999999999", "444444444", NA, "555555555",
                     "666666666", NA, NA),
  confidence     = c("high", "high", "medium", "high", "low", "medium",
                     "low", "low"),
  evidence_class = c("QUOTE", "NTEE", "INFER", "QUOTE", "INFER", "INFER",
                     "NONE", "NONE"),
  evidence       = "because",
  runner_up_ein  = NA_character_,
  stringsAsFactors = FALSE)

## ---- pf_wilson() -----------------------------------------------------------

test_that("the interval stays inside [0, 1] where a normal approximation does not", {
  # PREREQS T8's two flags. 71% +- 1.96*sqrt(.71*.29/7) is [0.37, 1.05]; an
  # interval whose upper end is 105% is why this function exists.
  w <- pf_wilson(5, 7)
  expect_true(w[1, "hi"] <= 1)
  expect_true(w[1, "lo"] >= 0)
  expect_lt(w[1, "lo"], 0.5)          # n=7 cannot carry a shipping decision

  # T8's other flag, 60% on n=15: the interval spans 45 points, which is the
  # figure the note needs visible. Pinned to two decimals -- the third is
  # arithmetic, not a finding.
  expect_equal(unname(round(pf_wilson(9, 15)[1, ], 2)), c(0.36, 0.80))
  expect_gt(diff(pf_wilson(9, 15)[1, ]), 0.4)
})

test_that("it is vectorised, and n = 0 is NA rather than an interval over nothing", {
  w <- pf_wilson(c(1, 0, 5), c(2, 0, 5))
  expect_equal(nrow(w), 3L)
  expect_true(all(is.na(w[2, ])))
  expect_equal(unname(w[3, "hi"]), 1)
  expect_equal(unname(pf_wilson(0, 10)[1, "lo"]), 0)
})

test_that("k greater than n stops rather than returning a rate above 1", {
  expect_error(pf_wilson(11, 10), "cannot exceed")
})

## ---- pf_grade_verdicts(), the grades ---------------------------------------

test_that("every grade is reachable and lands on the right case", {
  g <- pf_grade_verdicts(round_verdicts(), truth = truth_tbl(), verbose = FALSE)
  gr <- stats::setNames(as.character(g$grade), g$grant_id)
  expect_equal(gr[["G1"]], "CORRECT")
  expect_equal(gr[["G2"]], "RULED_OUT")      # narrower and worse than WRONG_EIN
  expect_equal(gr[["G3"]], "WRONG_EIN")
  expect_equal(gr[["G4"]], "CORRECT")        # NONE where no org exists IS right
  expect_equal(gr[["G5"]], "FALSE_MATCH")    # named an EIN where none exists
  expect_equal(gr[["G6"]], "UNSCOREABLE")    # truth UNRESOLVED
  expect_equal(gr[["G7"]], "MISSED")         # declined, but an EIN is known
  expect_equal(gr[["G8"]], "AMBIGUOUS")
  expect_setequal(levels(g$grade), pf_grade_levels())
})

test_that("an unscoreable case is excluded from accuracy, not counted wrong", {
  # the arithmetic this file exists for: 8 verdicts, 1 unscoreable, so the
  # denominator is 7 and not 8. Counting UNRESOLVED as a miss understates
  # accuracy by exactly the number of cases nobody could label.
  g <- pf_grade_verdicts(round_verdicts(), truth = truth_tbl(), verbose = FALSE)
  a <- attr(g, "accuracy")
  expect_equal(a$n, 7L)
  expect_equal(a$k, 2L)                      # G1 and G4
  expect_true(is.na(g$is_correct[g$grant_id == "G6"]))
  expect_equal(round(a$rate, 4), round(2 / 7, 4))
  expect_lt(a$lo, a$rate); expect_gt(a$hi, a$rate)
})

test_that("AMBIGUOUS is scoreable and not correct", {
  # it has to count against accuracy -- a reviewer who answers AMBIGUOUS
  # everywhere would otherwise score 100% on an empty denominator
  g <- pf_grade_verdicts(round_verdicts(), truth = truth_tbl(), verbose = FALSE)
  expect_false(g$is_correct[g$grant_id == "G8"])
  expect_true("G8" %in% g$grant_id[!is.na(g$is_correct)])
})

test_that("a verdict with no truth row is excluded and reported", {
  v <- round_verdicts()
  v$grant_id[3] <- "G99"
  g <- pf_grade_verdicts(v, truth = truth_tbl(), verbose = FALSE)
  expect_equal(as.character(g$grade[g$grant_id == "G99"]), "UNSCOREABLE")
  expect_equal(attr(g, "counts")$unlabelled, 1L)
})

test_that("the confidence floor drops weak truth rows and says how many", {
  g <- pf_grade_verdicts(round_verdicts(), truth = truth_tbl(),
                         min_confidence = "high", verbose = FALSE)
  # G3 is medium and G7 low, so both lose their label at this floor
  expect_equal(attr(g, "counts")$dropped_below_confidence, 2L)
  expect_equal(as.character(g$grade[g$grant_id == "G3"]), "UNSCOREABLE")
  expect_equal(attr(g, "accuracy")$n, 5L)
})

## ---- pf_grade_verdicts(), the refusals -------------------------------------

test_that("a population mismatch stops, because positional ids join anyway", {
  expect_error(
    pf_grade_verdicts(round_verdicts(), truth = truth_tbl(),
                      population = "bbbbbbbbbbbbbbbb", verbose = FALSE),
    "population mismatch")
  # and the message has to explain why a join is not evidence
  expect_error(
    pf_grade_verdicts(round_verdicts(), truth = truth_tbl(),
                      population = "bbbbbbbbbbbbbbbb", verbose = FALSE),
    "positional")
})

test_that("a truth table mixing populations stops", {
  t2 <- truth_tbl(); t2$population[4:8] <- "cccccccccccccccc"
  expect_error(pf_grade_verdicts(round_verdicts(), truth = t2, verbose = FALSE),
               "mixes populations")
})

test_that("a truth table missing a schema column stops with the column named", {
  t2 <- truth_tbl(); t2$wrong_ein <- NULL
  expect_error(pf_grade_verdicts(round_verdicts(), truth = t2, verbose = FALSE),
               "wrong_ein")
})

test_that("a round with no labels at all stops rather than reporting 0/0", {
  t2 <- truth_tbl(); t2$grant_id <- paste0("Z", 1:8)
  expect_error(pf_grade_verdicts(round_verdicts(), truth = t2, verbose = FALSE),
               "none of the")
})

test_that("an unvalidated verdict frame is validated on the way in", {
  v <- round_verdicts(); v$verdict[1] <- "PROBABLY"
  expect_error(pf_grade_verdicts(v, truth = truth_tbl(), verbose = FALSE),
               "PROBABLY")
})

## ---- pf_grade_by(): T3, T4, T8 ---------------------------------------------

test_that("a cut carries its own interval per level, and small cells are marked", {
  g <- pf_grade_verdicts(round_verdicts(), truth = truth_tbl(), verbose = FALSE)
  b <- pf_grade_by(g, "evidence_class")
  expect_true(all(c("level", "k", "n", "rate", "lo", "hi", "usable") %in% names(b)))
  # the fixture has single-digit cells throughout: nothing here is usable, and
  # that is the point -- T8's n=15 and n=7 are the real instances
  expect_false(any(b$usable))
  expect_true(all(b$n < 20))
  # levels come out in the designed order, not alphabetically
  expect_equal(b$level, intersect(pf_verdict_levels()$evidence_class, b$level))
})

test_that("monotonicity is reported, and an inverted scale is a finding", {
  g <- pf_grade_verdicts(round_verdicts(), truth = truth_tbl(), verbose = FALSE)
  b <- pf_grade_by(g, "confidence")
  expect_true(attr(b, "monotone") %in% c("decreasing", "increasing", "neither"))

  # Build the measured failure deliberately: confidence rising as accuracy
  # falls (dev/adjudicate-15-no-arms.R). high is wrong, low is right.
  v <- round_verdicts()
  v$confidence <- c("high", "high", "high", "low", "high", "medium", "low", "low")
  v$ein[1] <- "999999999"        # make the high-confidence case wrong
  gi <- pf_grade_verdicts(v, truth = truth_tbl(), verbose = FALSE)
  bi <- pf_grade_by(gi, "confidence")
  expect_equal(bi$rate[bi$level == "high"], 0)
  expect_gt(bi$rate[bi$level == "low"], bi$rate[bi$level == "high"])
  expect_equal(attr(bi, "monotone"), "increasing")
})

test_that("separation is only claimed when the intervals are disjoint", {
  g <- pf_grade_verdicts(round_verdicts(), truth = truth_tbl(), verbose = FALSE)
  b <- pf_grade_by(g, "evidence_class")
  # at these cell sizes nothing can separate, which is T4's actual situation
  expect_false(attr(b, "separated"))
})

test_that("cutting on an absent column stops and lists what is there", {
  g <- pf_grade_verdicts(round_verdicts(), truth = truth_tbl(), verbose = FALSE)
  expect_error(pf_grade_by(g, "search_confirmed"), "not a column")
  expect_error(pf_grade_by(g, "search_confirmed"), "present:")
})

## ---- pf_grade_layers(): T5, T6 ---------------------------------------------

test_that("layers over different case sets are REFUSED, not silently intersected", {
  # PREREQS section 3: two packets produce two incomparable denominators. This
  # is the assertion that stops that becoming a routing table.
  a <- round_verdicts()
  b <- round_verdicts()[1:5, ]
  expect_error(pf_grade_layers(list(layer0 = a, layer1 = b), truth = truth_tbl()),
               "do not cover the same cases")
  # the message has to say how many are common and which layer is short
  expect_error(pf_grade_layers(list(layer0 = a, layer1 = b), truth = truth_tbl()),
               "5 cases are common")
})

test_that("layers over one case set compare, and the common count is carried", {
  a <- round_verdicts()
  b <- round_verdicts(); b$ein[3] <- "333333333"   # layer1 gets G3 right
  out <- pf_grade_layers(list(layer0 = a, layer1 = b), truth = truth_tbl())
  expect_equal(nrow(out), 2L)
  expect_equal(attr(out, "cases"), 8L)
  expect_gt(out$rate[out$layer == "layer1"], out$rate[out$layer == "layer0"])
  expect_true(all(out$n == 7L))                    # same denominator, both rows
})

test_that("a by= cut gives layer x tier, which is the routing table", {
  a <- round_verdicts(); b <- round_verdicts()
  g <- pf_grade_verdicts(a, truth = truth_tbl(), verbose = FALSE)
  a$tier_before <- c("MAYBE", "MAYBE", "MAYBE", "NO", "NO", "NO", "NO", "MAYBE")
  b$tier_before <- a$tier_before
  out <- pf_grade_layers(list(l0 = a, l1 = b), truth = truth_tbl(),
                         by = "tier_before")
  expect_true(all(c("layer", "level") %in% names(out)))
  expect_setequal(unique(out$level), c("MAYBE", "NO"))
  expect_equal(nrow(out), 4L)
})

test_that("one layer, or an unnamed list, stops", {
  a <- round_verdicts()
  expect_error(pf_grade_layers(list(only = a), truth = truth_tbl()),
               "at least two")
  expect_error(pf_grade_layers(list(a, a), truth = truth_tbl()), "NAMED list")
})
