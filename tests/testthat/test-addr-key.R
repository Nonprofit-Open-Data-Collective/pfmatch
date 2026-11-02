## The address key pfmatch is about to adopt -----------------------------------
# `dev/PLACES-SYNC.md` §4 step 4 replaces the hand-rolled triangulation group
# key with npnormalize's, and says the parity test is what makes the switch
# safe, so write it first. This is that test. It changes no production code --
# nothing in R/ builds an address key yet -- and exists so that the switch is a
# measured change rather than a surprise, and so that a move upstream shows up
# here instead of in a grouping count nobody re-reads.
#
# WHAT PARITY MEANS HERE. Two keys over the same addresses:
#
#   hand-rolled  gsub("[^A-Z0-9]", "", toupper(ADDR_L1)) + "|" + ZIP5, with a
#                regex PO-box test. Built in dev/build-triangulation-sample.R
#                and dev/probe-triangulation-gates.R, and recorded in
#                pf_variants$addr_key.
#   npnormalize  np_addr_key(street_key, zip5): the normalized street key and
#                the zip joined by a space, blank for a box or mail-only
#                street.
#
# THE HEADLINE, measured below on all 5,410 shipped pairs under
# v1-5e901add4a04a5d6 (npnormalize 0.1.8): adopting the npnormalize key does
# NOT only merge renderings the hand-rolled key split -- which is what §4's
# 22.7% redundant-spelling figure led us to expect. It SPLITS 82 pairs the
# hand-rolled key grouped, in three distinct ways, and 49 of those splits are a
# loss. Pinning the decomposition is the point of the file: step 4 has to
# answer for the 49 before it ships.
#
# 2026-11-02, npnormalize 0.1.6 -> 0.1.8 (the join itself is #16 in 0.1.7; the
# intermediate signature v1-59c6e84c5f38e9f5 was that release -- per
# npnormalize's own signature registry, not inferred here -- and 0.1.8 is the
# compass carve-out noted below). The headline was 92 splits of which 59 were a
# loss, and the 10 that closed are all one class: the hyphenated house number.
# Queens writes 70-11 and both spellings are filed. 0.1.6 turned the hyphen
# into a space, so `70 11 150TH ST` and `7011 150TH ST` disagreed;
# 0.1.8 deletes it, and all 24 digits-hyphen-digits pairs in the corpus now
# agree. The loss this file was written to hold step 4 to is being repaid
# upstream, which is what a pinned decomposition is for -- and it cost one pair
# in the mirror image: `875-A ISLAND DRIVE` keys to `875A ISLAND DR` while the
# same address filed as `875 A ISLAND DRIVE` keeps its space. Net 11 pairs
# merged, 1 split, and both exemplars are pinned below.
#
# THE DELETION IS NOT BLANKET, and an earlier version of this comment said it
# was. Probed against the installed 0.1.8: the hyphen is deleted before digits
# (`70-11` -> `7011`) and before a lone non-compass letter (`875-A` -> `875A`,
# `57-C` -> `57C`), but before a lone COMPASS letter it still becomes a space
# (`1002-E SENECA ST` -> `1002 E SENECA ST`, `100-N 6TH ST` -> `100 N 6TH ST`),
# which is what keeps it agreeing with the spaced spelling of the same door
# rather than inventing the house number `1002E`. That carve-out moves nothing
# here -- the corpus holds 0 digits-hyphen-compass pairs and 4
# digits-hyphen-letter pairs, 1 of which splits -- so it changes no count
# below. It is recorded because the rule, not the count, is what a reader takes
# away from this block.

# the hand-rolled recipe, lifted verbatim so the comparison is honest
hand_key <- function(street, zip5) {
  sq <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; x }
  st <- toupper(gsub("[^A-Z0-9]", "", toupper(sq(street))))
  pobox <- grepl("^P?O?BOX|^POST", st)
  ifelse(nzchar(st) & !pobox & nzchar(sq(zip5)),
         paste(st, sq(zip5), sep = "|"), NA_character_)
}

np_key <- function(street_key, zip5) npnormalize::np_addr_key(street_key, zip5)

## 1. the contract, which holds under any version ------------------------------

test_that("np_addr_key() joins a street key to a zip and normalizes nothing", {
  # the separator is a single space, not the "|" the hand-rolled key used
  expect_identical(np_key("100 MAIN ST", "12210"), "100 MAIN ST 12210")

  # THE TRAP, and the reason this test exists. The argument is `street_keys`:
  # the function does not normalize, so handing it a raw ADDR_L1 reproduces
  # exactly the splitting that step 4 exists to remove.
  raw <- np_key(c("100 MAIN STREET", "100 MAIN ST"), c("12210", "12210"))
  expect_false(raw[1] == raw[2])
  expect_identical(raw, c("100 MAIN STREET 12210", "100 MAIN ST 12210"))

  # fed street_key instead, the renderings collapse -- including the suite,
  # which np_normalize() has already moved out of the street
  k <- npmatch::np_normalize(data.frame(
    name = "", dba = "", street = c("100 MAIN STREET", "100 MAIN ST",
                                    "100 MAIN STREET SUITE 3"),
    unit = "", city = "", state = "", zip5 = "12210", zip_plus4 = "",
    stringsAsFactors = FALSE))
  expect_identical(unique(np_key(k$street_key, k$zip5)), "100 MAIN ST 12210")
})

test_that("a box or mail-only street has no address key", {
  # this is the rule step 4 wants instead of the local regex: the blanking is
  # npnormalize's own box vocabulary, not a pattern pfmatch maintains
  expect_identical(np_key(c("PO BOX 1367", "GENERAL DELIVERY"), c("12210", "12210")),
                   c("", ""))
  expect_true(nzchar(np_key("100 MAIN ST", "12210")))

  # and the hand-rolled test it replaces misses spellings npnormalize catches,
  # which is why boxes reached the corpus at all (see the pinned block below)
  missed <- c("PO DRAWER 2440", "POB 2066", "GENERAL DELIVERY")
  expect_false(any(is.na(hand_key(missed, "12210"))))
})

## 2. pinned to the normalizer the fixture was built under ---------------------

test_that("on the shipped corpus the key is paste(street_key, zip5), or blank", {
  v <- pfmatch::pf_variants
  skip_if_normalizer_moved(v)
  k <- np_key(v$a_street_key, v$a_zip5)
  blank <- !nzchar(k)

  # 11 of 5,410 anchors key to nothing: a street npnormalize reads as a box or
  # as mail-only. Every one of them is a street the hand-rolled regex let in.
  expect_identical(sum(blank), 11L)
  expect_setequal(unique(v$a_street_key[blank]),
                  c("PO BOX 2440", "PO BOX 2066", "PO BOX 1076",
                    "PO BOX 40321", "PO BOX 294", "GENERAL DELIVERY"))
  expect_false(any(is.na(hand_key(v$a_street[blank], v$a_zip5[blank]))))

  # everywhere else it is exactly the documented rule, with no surprises
  expect_identical(k[!blank], paste(v$a_street_key[!blank], v$a_zip5[!blank]))
})

test_that("adopting the key splits 82 of 5,410 pairs, in three known ways", {
  v <- pfmatch::pf_variants
  skip_if_normalizer_moved(v)

  # every pair is at one hand-rolled key by construction -- the corpus was
  # selected that way -- so the only question a parity test can ask is which
  # pairs the npnormalize key would pull apart
  expect_identical(hand_key(v$a_street, v$a_zip5),
                   hand_key(v$b_street, v$b_zip5))

  ka <- np_key(v$a_street_key, v$a_zip5); kb <- np_key(v$b_street_key, v$b_zip5)
  split <- !(nzchar(ka) & nzchar(kb) & ka == kb)
  expect_identical(sum(split), 82L)
  expect_identical(sum(!split), 5328L)

  # (a) one side is a box or mail-only: 11 pairs that should never have been
  # grouped. npnormalize is right and the hand-rolled regex was wrong.
  blanked <- split & (!nzchar(ka) | !nzchar(kb))
  expect_identical(sum(blanked), 11L)

  # (b) the keys differ only in spacing: 49 pairs, and these are the loss. The
  # hand-rolled gsub() deleted every separator, so any two spellings that
  # differed only in where the spaces fell agreed; street_key keeps the filer's
  # spacing. What remains after 0.1.8 is spacing in the FILED text that no
  # separator rule reaches -- `2200 S W 10TH` against `2200 SW 10TH`,
  # `100 N6TH ST` against `100 N 6TH ST`, `1147CENTRALAVE` against
  # `1147 CENTRAL AVE`, `C/O` against `CO`. 47 of the 49 contain no hyphen
  # anywhere, so no separator rule upstream can reach them.
  rest <- split & !blanked
  spacing <- rest & gsub(" ", "", v$a_street_key) == gsub(" ", "", v$b_street_key)
  expect_identical(sum(spacing), 49L)

  # the hyphenated house number is CLOSED, and this is the pin on that: the
  # pair that was this section's exemplar of the loss now keys identically on
  # both sides. If a later version reopens it, this is the assertion that says
  # so rather than the count alone.
  i <- which(v$a_street == "70-11 150TH STREET" & v$b_street == "7011 150TH STREET")
  expect_length(i, 1L)
  expect_identical(c(v$a_street_key[i], v$b_street_key[i]),
                   c("7011 150TH ST", "7011 150TH ST"))
  expect_false(split[i])
  expect_identical(
    sum(split & (grepl("^[0-9]+-[0-9]", v$a_street) |
                 grepl("^[0-9]+-[0-9]", v$b_street))), 0L)

  # and the one pair 0.1.8 introduced, which is the same rule run backwards: a
  # hyphen is deleted where a space in that position is kept, so a letter-
  # suffixed house number no longer agrees with its spaced spelling.
  j <- which(v$a_street == "875-A ISLAND DRIVE SUITE 103" &
             v$b_street == "875 A ISLAND DRIVE SUITE 103")
  expect_length(j, 1L)
  expect_identical(c(v$a_street_key[j], v$b_street_key[j]),
                   c("875A ISLAND DR", "875 A ISLAND DR"))
  expect_true(spacing[j])

  # (c) the keys differ by more than spacing: 22 pairs, almost all of them a
  # suite fused to the street word, which `\\b` in .np_unit_pat cannot split,
  # so it survives inside street_key on one side only. Reported upstream as
  # npnormalize#7 §5 and recorded there as intended behaviour -- so if this
  # count falls, upstream changed its mind and dev/PLACES-SYNC.md §6 should say
  # so.
  expect_identical(sum(rest & !spacing), 22L)
  j <- which(v$a_street == "4550 WEST 77TH STREETSUITE 200")
  expect_length(j, 1L)
  expect_true((rest & !spacing)[j])
  expect_match(v$a_street_key[j], "STREETSUITE")
})
