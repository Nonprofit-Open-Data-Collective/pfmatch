## The normalizer gate, shared by test-variants.R and test-unit.R ------------
#
# Both files pin a block of assertions to the normalizer the fixture was built
# under, because an intentional improvement SHOULD move keys and a stale
# fixture must not be read as a regression. The gate is an exact comparison of
# np_normalize_signature() against the fixture's recorded `normalizer`.
#
# A signature is opaque on purpose, which makes a bare mismatch message hard to
# act on: it says THAT the two differ, never which is newer or by how much.
# That cost is not theoretical -- npnormalize published 0.1.3
# (v1-592912060053c4c3), 0.1.4 (v1-1179714ce1e9d31f) and 0.1.5
# (v1-533f186c123357cf) inside one week, and a fixture rebuilt against the
# middle one was found to be stale again only by someone checking by hand. So
# the message names the npnormalize VERSION on each side as well, which is the
# part a reader can compare at a glance and look up in NEWS.md.
#
# `normalizer_pkg` is recorded by data-raw/make-pf-variants.R. Fixtures built
# before it existed have no such attribute; the message then says "unrecorded"
# rather than failing, so an old fixture still produces a usable skip.

normalizer_versions <- function(v) {
  a <- attr(v, "normalizer_pkg")
  built <- if (is.null(a) || is.na(a["npnormalize"])) "unrecorded" else
             unname(a["npnormalize"])
  live  <- tryCatch(as.character(utils::packageVersion("npnormalize")),
                    error = function(e) "unrecorded")
  c(built = built, live = live)
}

skip_if_normalizer_moved <- function(v) {
  built <- attr(v, "normalizer")
  live  <- tryCatch(npmatch::np_normalize_signature(),
                    error = function(e) NA_character_)
  skip_if(is.na(built) || is.na(live))
  pk <- normalizer_versions(v)
  skip_if_not(
    identical(built, live),
    sprintf(paste("normalizer moved (fixture %s, npnormalize %s; installed %s,",
                  "npnormalize %s); rebuild with data-raw/make-pf-variants.R"),
            built, pk[["built"]], live, pk[["live"]]))
}
