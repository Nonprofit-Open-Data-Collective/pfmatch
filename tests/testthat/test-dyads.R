## Fixtures ------------------------------------------------------------------
# A minimal Schedule A / Schedule R pair of extracts covering every case the
# classifier is supposed to separate.

sched_a <- function() data.frame(
  ego_ein = c(
    "111111111",                       # exclusive arm of 222222222
    rep("999999999", 6L),              # a grantmaking supporting org: fan-out 6
    "333333333"),                      # arm of a c(4): subsection mismatch
  alter_ein = c(
    "222222222",
    c("801000001","801000002","801000003","801000004","801000005","801000006"),
    "444444444"),
  tax_year = c("2022", rep("2022", 6L), "2022"),
  ego_name = c("EAGLE RANCH FOUNDATION", rep("BIG GRANTMAKER SUPPORT ORG", 6L),
               "ACTION GROUP FOUNDATION"),
  alter_name = c("EAGLE RANCH", paste("CHARITY", 1:6), "ACTION GROUP"),
  alter_state = "GA", alter_city = "FLOWERY BRANCH",
  rel_type = "supported_org", direction = "ego_to_alter",
  stringsAsFactors = FALSE)

sched_r <- function() data.frame(
  ego_ein   = c("555555555", "777777777"),
  alter_ein = c("666666666", "888888888"),
  tax_year  = c("2021", "2022"),
  ego_name  = c("MAYO CLINIC HEALTH SYSTEM FAIRMONT", "RIVERSIDE MUSEUM"),
  alter_name= c("MAYO CLINIC HEALTH SYSTEM LAKE CITY", "RIVERSIDE MUSEUM FOUNDATION"),
  alter_state = "MN", alter_city = "LAKE CITY",
  rel_type = "related_exempt", direction = "undirected",
  stringsAsFactors = FALSE)

fake_bmf <- function() data.frame(
  ein = c("111111111","222222222","333333333","444444444","555555555",
          "666666666","777777777","888888888",
          paste0("80100000", 1:6), "999999999"),
  org_name_join = c("EAGLE RANCH FOUNDATION", "EAGLE RANCH",
                    "ACTION GROUP FOUNDATION", "ACTION GROUP",
                    "MAYO CLINIC HEALTH SYSTEM FAIRMONT",
                    "MAYO CLINIC HEALTH SYSTEM LAKE CITY",
                    "RIVERSIDE MUSEUM", "RIVERSIDE MUSEUM FOUNDATION",
                    paste("CHARITY", 1:6), "BIG GRANTMAKER SUPPORT ORG"),
  org_addr_city  = c(rep("FLOWERY BRANCH", 4L), "FAIRMONT", "LAKE CITY",
                     "RIVERSIDE", "RIVERSIDE", rep("ANYTOWN", 6L), "ANYTOWN"),
  org_addr_state = c(rep("GA", 4L), "MN", "MN", "CA", "CA", rep("NY", 6L), "NY"),
  subsection_code = c("03","03","03","04", rep("03", 4L), rep("03", 6L), "03"),
  stringsAsFactors = FALSE)

build <- function(...) pf_build_dyads(sched_a(), sched_r(), bmf = fake_bmf(),
                                      verbose = FALSE, ...)

## ---------------------------------------------------------------------------
test_that("the table is symmetric, deduplicated, and keyed a < b", {
  d <- build()
  expect_true(all(d$ein_a < d$ein_b))
  expect_equal(anyDuplicated(paste(d$ein_a, d$ein_b)), 0L)
  # 1 exclusive + 6 fan-out + 1 mismatch + 2 Schedule R
  expect_equal(nrow(d), 10L)
})

test_that("an exclusive supporter licenses substitution", {
  d <- build()
  expect_equal(pf_dyad_lookup(d, "111111111", "222222222"), "substitutable")
  # and the lookup is order-insensitive
  expect_equal(pf_dyad_lookup(d, "222222222", "111111111"), "substitutable")
})

test_that("a one-to-many supporter does not", {
  # This is the YMCA Retirement Fund case: a 509(a)(3) supporting hundreds of
  # unrelated bodies. Its edges are related, never substitutable.
  d <- build()
  cls <- pf_dyad_lookup(d, rep("999999999", 6L), sprintf("80100000%d", 1:6))
  expect_true(all(cls == "related"))
  expect_true(all(grepl("not_exclusive", d[d$ein_b == "999999999" |
                                           d$ein_a == "999999999", ]$dyad_reason)))
})

test_that("max_fanout is the knob that decides it, and the degree cap outranks it", {
  # Raising max_fanout alone is not enough: the supporter then has 6 partners
  # and the degree cap takes it back out. Both guards have to be relaxed, which
  # is the intended belt-and-braces behaviour.
  still_capped <- build(max_fanout = 10L)
  cls <- pf_dyad_lookup(still_capped, rep("999999999", 6L), sprintf("80100000%d", 1:6))
  expect_true(all(cls == "related"))
  expect_true(all(grepl("degree > 5",
    still_capped[still_capped$ein_b == "999999999" |
                 still_capped$ein_a == "999999999", ]$dyad_reason)))

  loosened <- build(max_fanout = 10L, max_degree = 10L)
  cls2 <- pf_dyad_lookup(loosened, rep("999999999", 6L), sprintf("80100000%d", 1:6))
  expect_true(all(cls2 == "substitutable"))
})

test_that("a subsection mismatch is demoted", {
  # ACTION GROUP FOUNDATION (c3) supports ACTION GROUP (c4). Exclusive, same
  # name core, and still not a substitute: a private foundation's grant cannot
  # land on the c(4).
  d <- build()
  expect_equal(pf_dyad_lookup(d, "333333333", "444444444"), "related")
  r <- d[d$ein_a == "333333333" & d$ein_b == "444444444", ]$dyad_reason
  expect_match(r, "subsection mismatch")
})

test_that("a bare Schedule R edge between different bodies stays related", {
  d <- build()
  expect_equal(pf_dyad_lookup(d, "555555555", "666666666"), "related")
})

test_that("an identical name core in the same state is substitutable", {
  d <- build()
  expect_equal(pf_dyad_lookup(d, "777777777", "888888888"), "substitutable")
  expect_match(d[d$ein_a == "777777777", ]$dyad_reason, "same_name_core")
})

test_that("the degree cap demotes federated networks", {
  # Ten same-named lodges in one state: every pair passes the name test, so the
  # cap is the only thing standing between us and a 10-clique.
  n <- 10L
  eins <- sprintf("6%08d", seq_len(n))
  sr <- data.frame(
    ego_ein = rep(eins[1], n - 1L), alter_ein = eins[-1], tax_year = "2022",
    ego_name = "ANCIENT FREE MASONS LODGE", alter_name = "ANCIENT FREE MASONS LODGE",
    alter_state = "SC", alter_city = "COLUMBIA",
    rel_type = "related_exempt", direction = "undirected", stringsAsFactors = FALSE)
  bmf <- data.frame(ein = eins, org_name_join = "ANCIENT FREE MASONS LODGE",
                    org_addr_city = "COLUMBIA", org_addr_state = "SC",
                    subsection_code = "03", stringsAsFactors = FALSE)
  capped <- pf_build_dyads(NULL, sr, bmf = bmf, max_degree = 5L, verbose = FALSE)
  expect_true(all(capped$dyad_class == "related"))
  expect_true(all(grepl("degree > 5", capped$dyad_reason)))
  # without the cap they would all be substitutable, which is the failure mode
  uncapped <- pf_build_dyads(NULL, sr, bmf = bmf, max_degree = 0L, verbose = FALSE)
  expect_true(all(uncapped$dyad_class == "substitutable"))
})

test_that("the efile_ variants are rejected with a useful message", {
  # These tables carry OBJECTID and no filer EIN, so they cannot produce dyads.
  efile <- data.frame(OBJECTID = "OID-1", TAX_YEAR = "2022",
                      SA_01_PCSTAT_ORG_EIN = "222222222", stringsAsFactors = FALSE)
  expect_error(pf_build_dyads(efile, NULL, verbose = FALSE),
               "do not carry the filer EIN")
})

test_that("lookup returns NA for absent pairs, self-pairs and bad EINs", {
  d <- build()
  expect_true(is.na(pf_dyad_lookup(d, "111111111", "555555555")))
  expect_true(is.na(pf_dyad_lookup(d, "111111111", "111111111")))
  expect_true(is.na(pf_dyad_lookup(d, "111111111", "not-an-ein")))
  expect_true(is.na(pf_dyad_lookup(d, "111111111", NA_character_)))
})

test_that("lookup recycles and preserves input order", {
  d <- build()
  got <- pf_dyad_lookup(d, "111111111", c("222222222", "555555555", "222222222"))
  expect_equal(got, c("substitutable", NA, "substitutable"))
})

test_that("min_years drops single-year pairs", {
  d <- build(min_years = 2L)
  expect_equal(nrow(d), 0L)   # every fixture row is a single tax year
})

## --------------------------------------------------- collapse, on a fake run
fake_match <- function() {
  pairs <- data.frame(
    .id   = c("G1","G1","G2","G2","G3","G3"),
    .ein  = c("111111111","222222222",   # one body, two EINs
              "555555555","666666666",   # related but not substitutable
              "777777777","888888888"),  # one body, two EINs
    name_y = c("EAGLE RANCH FOUNDATION","EAGLE RANCH",
               "MAYO CLINIC HEALTH SYSTEM FAIRMONT","MAYO CLINIC HEALTH SYSTEM LAKE CITY",
               "RIVERSIDE MUSEUM FOUNDATION","RIVERSIDE MUSEUM"),
    score = c(0.98, 0.96, 0.98, 0.96, 0.98, 0.96),
    veto  = FALSE, stringsAsFactors = FALSE)
  res <- data.frame(.id = c("G1","G2","G3"),
                    overall_ein = c("111111111","555555555","777777777"),
                    overall_name_y = c("EAGLE RANCH FOUNDATION",
                                       "MAYO CLINIC HEALTH SYSTEM FAIRMONT",
                                       "RIVERSIDE MUSEUM FOUNDATION"),
                    overall_score = c(0.98, 0.98, 0.98),
                    stringsAsFactors = FALSE)
  attr(res, "pairs") <- pairs
  structure(list(result = res, grants = data.frame(grant_id = c("G1","G2","G3"))),
            class = "pf_match")
}

test_that("collapse merges substitutable candidates and leaves related ones alone", {
  d <- build()
  out <- suppressMessages(pf_dyad_collapse(fake_match(), d, rescore = FALSE))
  r <- as.data.frame(out$result)
  expect_equal(r$dyad_collapsed, c(TRUE, FALSE, TRUE))
  expect_equal(r$dyad_n_before[r$.id == "G1"], 2L)
  expect_equal(r$dyad_n_after[r$.id == "G1"],  1L)
  # G2 is the Mayo pair: related, so untouched
  expect_true(is.na(r$dyad_n_after[r$.id == "G2"]))
})

test_that("the operating policy reports the non-arm member", {
  d <- build()
  out <- suppressMessages(pf_dyad_collapse(
    fake_match(), d, pf_dyad_config(policy = "operating"), rescore = FALSE))
  r <- as.data.frame(out$result)
  # G1 was won by EAGLE RANCH FOUNDATION; the operating rule swaps in EAGLE RANCH
  expect_equal(r$overall_ein[r$.id == "G1"], "222222222")
  expect_equal(r$dyad_from_ein[r$.id == "G1"], "111111111")
})

test_that("the arm and top policies do what they say", {
  d <- build()
  arm <- suppressMessages(pf_dyad_collapse(
    fake_match(), d, pf_dyad_config(policy = "arm"), rescore = FALSE))
  expect_equal(as.data.frame(arm$result)$overall_ein[1], "111111111")
  top <- suppressMessages(pf_dyad_collapse(
    fake_match(), d, pf_dyad_config(policy = "top"), rescore = FALSE))
  expect_equal(as.data.frame(top$result)$overall_ein[1], "111111111")
  # "top" never rewrites a pick, so it never records a source EIN
  expect_true(all(is.na(as.data.frame(top$result)$dyad_from_ein)))
})

test_that("collapse never merges through a non-candidate third party", {
  # 111111111 and 222222222 are a dyad; 222222222 and a third EIN are too. If
  # only the first and third are candidates, nothing may merge, because the
  # bridge is not in this grant's candidate list.
  sa <- rbind(sched_a()[1, ], sched_a()[1, ])
  sa$ego_ein[2]   <- "222222222"
  sa$alter_ein[2] <- "aaa"; sa$alter_ein[2] <- "121212121"
  sa$ego_name[2]  <- "EAGLE RANCH"; sa$alter_name[2] <- "EAGLE RANCH TRUST"
  bmf <- rbind(fake_bmf(),
               data.frame(ein = "121212121", org_name_join = "EAGLE RANCH TRUST",
                          org_addr_city = "FLOWERY BRANCH", org_addr_state = "GA",
                          subsection_code = "03", stringsAsFactors = FALSE))
  d <- pf_build_dyads(sa, NULL, bmf = bmf, verbose = FALSE)
  expect_equal(pf_dyad_lookup(d, "111111111", "121212121"), NA_character_)

  x <- fake_match()
  pr <- attr(x$result, "pairs")
  pr <- pr[pr$.id == "G1", ]
  pr$.ein[2] <- "121212121"; pr$name_y[2] <- "EAGLE RANCH TRUST"
  res <- as.data.frame(x$result)[1, ]
  attr(res, "pairs") <- pr
  x2 <- structure(list(result = res, grants = data.frame(grant_id = "G1")),
                  class = "pf_match")
  out <- suppressMessages(pf_dyad_collapse(x2, d, rescore = FALSE))
  expect_false(as.data.frame(out$result)$dyad_collapsed[1])
})

test_that("max_band caps the candidates entering the quadratic pairing", {
  n <- 60L
  pr <- data.frame(.id = "G1", .ein = sprintf("7%08d", seq_len(n)),
                   name_y = paste("ORG", seq_len(n)),
                   score = 0.9, veto = FALSE, stringsAsFactors = FALSE)
  res <- data.frame(.id = "G1", overall_ein = pr$.ein[1],
                    overall_name_y = pr$name_y[1], overall_score = 0.9,
                    stringsAsFactors = FALSE)
  attr(res, "pairs") <- pr
  x <- structure(list(result = res, grants = data.frame(grant_id = "G1")),
                 class = "pf_match")
  band <- pfmatch:::.pf_dyad_band(x, pf_dyad_config(max_band = 10L))
  expect_equal(nrow(band), 10L)
  unbanded <- pfmatch:::.pf_dyad_band(x, pf_dyad_config(max_band = Inf))
  expect_equal(nrow(unbanded), n)
})

test_that("annotate adds context without changing any pick", {
  d <- build()
  x <- fake_match()
  out <- suppressMessages(pf_dyad_annotate(x, d))
  r <- as.data.frame(out$result)
  expect_equal(r$overall_ein, as.data.frame(x$result)$overall_ein)
  expect_equal(r$dyad_alt_ein[r$.id == "G1"], "222222222")
  # annotate reports BOTH classes: it is context for a reader and a rollup key,
  # not a licence to substitute, so the Mayo pair is surfaced as `related`
  # rather than suppressed. Only pf_dyad_collapse() filters on the class.
  expect_equal(r$dyad_class, c("substitutable", "related", "substitutable"))
})

## ------------------------------------------- soft veto carried across a merge
veto_match <- function() {
  # G1: the ARM outscores the operating entity and carries a soft veto, which is
  # what affiliate_suffix does on a real "X FOUNDATION" / "X" pair.
  pairs <- data.frame(
    .id    = c("G1", "G1"),
    .ein   = c("111111111", "222222222"),
    name_y = c("EAGLE RANCH FOUNDATION", "EAGLE RANCH"),
    score  = c(0.98, 0.96),
    veto   = FALSE,
    veto_soft = c(TRUE, FALSE),
    veto_soft_reason = c("affiliate_suffix", NA_character_),
    stringsAsFactors = FALSE)
  # np_select() always emits overall_veto_soft, and the guard reads the veto off
  # the PICK rather than off the band, so the fixture has to carry it too. The
  # pick here is the arm, which is the vetoed row.
  res <- data.frame(.id = "G1", overall_ein = "111111111",
                    overall_name_y = "EAGLE RANCH FOUNDATION",
                    overall_score = 0.98, overall_veto_soft = TRUE,
                    stringsAsFactors = FALSE)
  attr(res, "pairs") <- pairs
  structure(list(result = res, grants = data.frame(grant_id = "G1")),
            class = "pf_match")
}

test_that("a soft veto on a dropped member is carried to the representative", {
  d <- build()
  x <- veto_match()
  pr <- pfmatch:::.pf_dyad_band(x, pf_dyad_config())
  expect_equal(nrow(pr), 2L)   # both candidates are in the band

  # with the guard on, the surviving row inherits the veto
  out <- suppressMessages(pf_dyad_collapse(
    x, d, pf_dyad_config(keep_soft_veto = TRUE), np_config = npmatch::np_config()))
  p <- as.data.frame(attr(out$result, "pairs"))
  expect_equal(nrow(p), 1L)                       # the arm was dropped
  expect_equal(p$.ein, "222222222")               # operating entity survives
  expect_true(p$veto_soft)                        # and carries the veto
  expect_match(p$veto_soft_reason, "affiliate_suffix")
})

test_that("keep_soft_veto = FALSE lets the veto vanish with the dropped member", {
  d <- build()
  out <- suppressMessages(pf_dyad_collapse(
    veto_match(), d, pf_dyad_config(keep_soft_veto = FALSE),
    np_config = npmatch::np_config()))
  p <- as.data.frame(attr(out$result, "pairs"))
  expect_equal(p$.ein, "222222222")
  expect_false(p$veto_soft %in% TRUE)
})

test_that("a soft veto on the KEPT member survives either way", {
  d <- build()
  x <- veto_match()
  pr <- attr(x$result, "pairs")
  pr$veto_soft <- c(FALSE, TRUE)          # veto now sits on the operating entity
  pr$veto_soft_reason <- c(NA_character_, "affiliate_suffix")
  attr(x$result, "pairs") <- pr
  # the pick is still the arm, which is no longer the vetoed row
  x$result$overall_veto_soft <- FALSE
  for (k in c(TRUE, FALSE)) {
    out <- suppressMessages(pf_dyad_collapse(
      x, d, pf_dyad_config(keep_soft_veto = k), np_config = npmatch::np_config()))
    p <- as.data.frame(attr(out$result, "pairs"))
    expect_true(p$veto_soft)
  }
})

## --------------------------------------------- policy = "query" follows the grant
q_match <- function(query_name) {
  pairs <- data.frame(
    .id = c("G1", "G1"), .ein = c("111111111", "222222222"),
    name_y = c("EAGLE RANCH FOUNDATION", "EAGLE RANCH"),
    score = c(0.98, 0.96), veto = FALSE, veto_soft = FALSE,
    veto_soft_reason = NA_character_, stringsAsFactors = FALSE)
  res <- data.frame(.id = "G1", overall_ein = "111111111",
                    overall_name_y = "EAGLE RANCH FOUNDATION",
                    overall_score = 0.98, overall_veto_soft = FALSE,
                    stringsAsFactors = FALSE)
  attr(res, "pairs") <- pairs
  structure(list(result = res,
                 grants = data.frame(grant_id = "G1", recip_name = query_name,
                                     stringsAsFactors = FALSE)),
            class = "pf_match")
}
pick <- function(x, policy) {
  o <- suppressMessages(pf_dyad_collapse(x, build(), pf_dyad_config(policy = policy),
                                         np_config = npmatch::np_config()))
  as.data.frame(o$result)$overall_ein
}

test_that("policy 'query' reports the arm when the grant names the arm", {
  # a funder who writes "EAGLE RANCH FOUNDATION" named the foundation
  expect_equal(pick(q_match("EAGLE RANCH FOUNDATION"), "query"), "111111111")
  # and the operating entity when the grant does not say FOUNDATION
  expect_equal(pick(q_match("EAGLE RANCH"), "query"), "222222222")
})

test_that("'operating' contradicts the grant record, which is why it is not the default", {
  # same grant, explicitly naming the foundation, still reports the ranch
  expect_equal(pick(q_match("EAGLE RANCH FOUNDATION"), "operating"), "222222222")
  # and 'arm' makes the mirror error on a grant that names no arm
  expect_equal(pick(q_match("EAGLE RANCH"), "arm"), "111111111")
})

test_that("'query' falls back to the operating entity when the grant name is missing", {
  x <- q_match(NA_character_)
  expect_equal(pick(x, "query"), "222222222")
  # and when the grants frame carries no recip_name column at all
  x2 <- q_match("EAGLE RANCH FOUNDATION")
  x2$grants$recip_name <- NULL
  expect_equal(pick(x2, "query"), "222222222")
})

test_that("the default policy is 'query'", {
  expect_equal(pf_dyad_config()$policy, "query")
})
