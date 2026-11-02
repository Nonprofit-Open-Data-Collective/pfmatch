# The adjudication sheet: pf_candidate_frame(), pf_bmf_context() and the
# pf_adjudicate() wrapper over them. Untested until now, which matters more than
# for most of the package: the sheet is the input to every later adjudication
# figure, so a defect here becomes a wrong number in a note rather than an error
# in a run. dev/ADJUDICATION-PREREQS.md T12.
#
# The requirement these tests exist to pin is Phase 4 step 1's: NTEE text,
# mission and program descriptions on *every* candidate, not only on the pick.
# Nothing asserted that, and a join that silently reached only the top row would
# have looked exactly like a working one in every figure computed from it.

# three grants, with 3 / 2 / 1 scored candidates, so k, rank and is_top_pick are
# all separable. G1's winner is deliberately NOT its highest-scoring pair: the
# result frame picks 222222222, which is what is_top_pick has to follow.
sheet_match <- function() {
  res <- data.frame(
    .id            = c("G1", "G2"),
    tier           = c("MAYBE", "MAYBE"),
    overall_ein    = c("222222222", "444444444"),
    overall_name_y = c("RIVER ARTS COUNCIL", "HILLSIDE ACADEMY"),
    overall_score  = c(0.71, 0.66),
    overall_name_sim = c(0.80, 0.74),
    overall_margin = c(0.01, 0.02),
    n_close        = c(2L, 1L),
    stringsAsFactors = FALSE)
  attr(res, "pairs") <- data.frame(
    .id    = c("G1", "G1", "G1", "G2", "G2", "G3"),
    .ein   = c("111111111", "222222222", "333333333",
               "444444444", "555555555", "666666666"),
    name_y = c("RIVER ARTS CO", "RIVER ARTS COUNCIL", "RIVERSIDE ARTS",
               "HILLSIDE ACADEMY", "HILLSIDE SCHOOL", "NOBODY HOME"),
    score  = c(0.74, 0.71, 0.55, 0.66, 0.60, 0.50),
    name_key = c(0.83, 0.80, 0.61, 0.74, 0.70, 0.52),
    street_y = "1 MAIN ST",
    city_y = c("BOZEMAN", "BOZEMAN", "BILLINGS", "HILLSIDE", "HILLSIDE", "FARGO"),
    state_y = c("MT", "MT", "MT", "NJ", "NJ", "ND"),
    zip5_y = c("59715", "59715", "59101", "07205", "07205", "58102"),
    geo_state = c(1, 1, 1, 1, 1, 0),
    geo_zip5  = c(1, 1, 0, 1, 1, 0),
    pass = "A1-name-zip5",
    veto_soft = FALSE,
    veto_soft_reason = NA_character_,
    stringsAsFactors = FALSE)
  grants <- data.frame(
    grant_id = c("G1", "G2", "G3"),
    ORG_EIN = "411111111", FILERNAME1 = "A FOUNDATION",
    PF_15_G_PAID_PURPOSE = c("GENERAL SUPPORT", "SCHOLARSHIPS", "GENERAL"),
    PF_15_G_PAID_AMT = c("25000", "10000", "5000"),
    TAX_YEAR = "2022",
    PF_15_G_PAID_RECIP_STAT = "PC",
    in_scope = TRUE,
    recip_name = c("RIVER ARTS COUNCIL", "HILLSIDE ACADEMY", "SOMETHING ELSE"),
    recip_name_alt = NA_character_,
    recip_street = "1 MAIN ST",
    recip_city = c("BOZEMAN", "HILLSIDE", "FARGO"),
    recip_state_raw = c("MT", "NJ", "ND"),
    recip_zip5 = c("59715", "07205", "58102"),
    recipient_type = "public_charity",
    recipient_type_detail = NA_character_,
    looks_personal = FALSE,
    oos_reason = NA_character_,
    stringsAsFactors = FALSE)
  structure(list(result = res, grants = grants,
                 in_scope = c("G1", "G2", "G3"), out_of_scope = character(0)),
            class = "pf_match")
}

# a context carrying every candidate EIN, so "did enrichment reach all of them"
# is answerable rather than confounded with "was the EIN in the BMF at all"
sheet_context <- function(eins = c("111111111", "222222222", "333333333",
                                   "444444444", "555555555", "666666666",
                                   "411111111")) {
  data.frame(
    ein = eins,
    BMF_org_addr_state = "MT",
    BMF_org_addr_city = "BOZEMAN",
    BMF_ntee_code_clean = "A26",
    BMF_ntee_code_definition = "Arts council",
    BMF_nteev2_subsector = "ART",
    BMF_activity_code_definitions = "Community arts programming",
    BMF_asset_amount = "100000",
    stringsAsFactors = FALSE)
}

test_that("one row per scored candidate, ranked by score within grant", {
  s <- pf_candidate_frame(sheet_match(), ids = c("G1", "G2"))
  expect_equal(nrow(s), 5L)
  expect_equal(as.integer(table(s$grant_id)[c("G1", "G2")]), c(3L, 2L))
  g1 <- s[s$grant_id == "G1", ]
  expect_equal(g1$rank, 1:3)
  expect_true(all(diff(g1$score) <= 0))
})

test_that("k truncates per grant, and keeps the best k rather than the first k", {
  s <- pf_candidate_frame(sheet_match(), ids = c("G1", "G2"), k = 2)
  expect_equal(nrow(s), 4L)
  g1 <- s[s$grant_id == "G1", ]
  expect_equal(g1$rank, 1:2)
  # the 0.55 pair is the one dropped, not an arbitrary row
  expect_false("333333333" %in% g1$ein)
  expect_setequal(g1$ein, c("111111111", "222222222"))
})

test_that("is_top_pick follows the result frame, not the score order", {
  # G1's best-scoring pair is 111111111 at 0.74; the result frame picked
  # 222222222. A sheet that flagged the top row by score would mark the wrong
  # candidate, and every "the model agreed with the pick" figure would be wrong.
  s <- pf_candidate_frame(sheet_match(), ids = "G1")
  expect_equal(s$ein[s$rank == 1], "111111111")
  expect_equal(s$ein[s$is_top_pick == 1L], "222222222")
  expect_equal(sum(s$is_top_pick), 1L)
})

test_that("the default id set is the MAYBE tier, and ids overrides it", {
  m <- sheet_match()
  expect_setequal(unique(pf_candidate_frame(m)$grant_id), c("G1", "G2"))
  # G3 has a scored pair but is NO under pf_status(), so it is not in the
  # default sheet; asking for it explicitly still works.
  expect_equal(unique(pf_candidate_frame(m, ids = "G3")$grant_id), "G3")
})

test_that("an id with no scored candidate stops rather than returning nothing", {
  # silently returning zero rows would read as "nothing to adjudicate"
  expect_error(pf_candidate_frame(sheet_match(), ids = "G99"),
               "no scored candidates")
})

test_that("enrichment reaches EVERY candidate, not only the pick", {
  # Phase 4 step 1's requirement, and the reason this file exists. A join that
  # landed only on is_top_pick rows would leave the model reading NTEE text for
  # the pick and nothing for its rivals -- which is precisely the comparison
  # the packet is for.
  s <- pf_candidate_frame(sheet_match(), ids = c("G1", "G2"),
                          bmf_context = sheet_context())
  expect_true(all(c("CAND_ntee_code_definition", "CAND_nteev2_subsector",
                    "CAND_activity_code_definitions") %in% names(s)))
  expect_equal(sum(!is.na(s$CAND_ntee_code_definition)), nrow(s))
  expect_equal(sum(!is.na(s$CAND_activity_code_definitions)), nrow(s))
  expect_gt(sum(s$is_top_pick == 0L), 0L)   # there are rivals to get it wrong on
})

test_that("a candidate absent from the context is NA, not silently dropped", {
  ctx <- sheet_context(c("111111111", "222222222", "411111111"))
  s <- pf_candidate_frame(sheet_match(), ids = "G1", bmf_context = ctx)
  expect_equal(nrow(s), 3L)                       # still three candidates
  expect_true(is.na(s$CAND_ntee_code_definition[s$ein == "333333333"]))
  expect_false(any(is.na(s$CAND_ntee_code_definition[s$ein != "333333333"])))
})

test_that("foundation context is attached under FDN_ and compared, not conflated", {
  s <- pf_candidate_frame(sheet_match(), ids = "G1", bmf_context = sheet_context())
  expect_true(all(c("FDN_nteev2_subsector", "same_sector",
                    "fdn_recip_same_state") %in% names(s)))
  # the fixture gives filer and candidates the same subsector and state
  expect_true(all(s$same_sector))
  expect_true(all(s$fdn_recip_same_state))
})

test_that("pf_bmf_context() keys on a normalized EIN and de-duplicates it", {
  bmf <- data.frame(ein = c("41-1111111", "411111111", "22-2222222"),
                    ntee_code_clean = c("A26", "B01", "C02"),
                    stringsAsFactors = FALSE)
  ctx <- pf_bmf_context(bmf)
  expect_equal(nrow(ctx), 2L)                     # the two spellings collapse
  expect_true(all(nchar(ctx$ein) == 9L))
  expect_true("BMF_ntee_code_clean" %in% names(ctx))
  expect_equal(ctx$BMF_ntee_code_clean[ctx$ein == "411111111"], "A26")
})

test_that("pf_adjudicate() returns the enriched sheet for the MAYBE tier", {
  bmf <- data.frame(ein = c("111111111", "222222222", "333333333",
                            "444444444", "555555555", "411111111"),
                    ntee_code_clean = "A26",
                    nteev2_subsector = "ART",
                    stringsAsFactors = FALSE)
  s <- pf_adjudicate(sheet_match(), bmf = bmf, verbose = FALSE)
  expect_setequal(unique(s$grant_id), c("G1", "G2"))
  expect_true("CAND_ntee_code_clean" %in% names(s))
  expect_equal(sum(!is.na(s$CAND_ntee_code_clean)), nrow(s))
})

test_that("a context missing the comparison columns gives NA, not an error", {
  # pf_bmf_context() keeps whatever the BMF it was handed held, so a caller can
  # legitimately pass a context with no org_addr_state and no nteev2_subsector.
  # This used to stop with "replacement has 0 rows": ifelse() over a NULL side
  # returns logical(0), which is the `is.na(NULL)` member of the same family as
  # `sum(NULL %in% TRUE)` being 0 -- no error, no column named, just a crash two
  # frames away from the missing input.
  ctx <- data.frame(ein = c("111111111", "222222222", "333333333", "411111111"),
                    BMF_ntee_code_clean = "A26", stringsAsFactors = FALSE)
  s <- pf_candidate_frame(sheet_match(), ids = "G1", bmf_context = ctx)
  expect_equal(nrow(s), 3L)
  expect_true(all(is.na(s$same_sector)))
  expect_true(all(is.na(s$fdn_recip_same_state)))
  expect_equal(sum(!is.na(s$CAND_ntee_code_clean)), 3L)
})
