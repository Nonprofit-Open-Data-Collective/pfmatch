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

## Skipping forward, failing backward ----------------------------------------
#
# A skip is the right answer in ONE direction only. Installed NEWER than the
# fixture means the fixture is stale and the keys legitimately moved: skip, and
# say to rebuild. Installed OLDER than the fixture means the environment is
# wrong -- somebody is running against a normalizer that predates the data in
# this package -- and that is a broken install, not a stale fixture.
#
# The distinction is load-bearing because nothing else catches it. DESCRIPTION's
# floor is the only automatic guard, and it is a FLOOR: it cannot notice a
# downgrade after installation. And it could not be relied on transitively
# either -- npmatch's released v0.1.1 does not import npnormalize at all, so
# `npmatch (>= 0.1.1)` constrains the normalizer not at all. Before this, a
# too-old install surfaced as four skips, which is indistinguishable from four
# passes in a summary line, and this session twice watched exactly that happen
# under a normalizer that had moved underneath it.
.npn_older <- function(live, built) {
  if (live == "unrecorded" || built == "unrecorded") return(FALSE)
  isTRUE(tryCatch(utils::compareVersion(live, built) < 0, error = function(e) FALSE))
}

skip_if_normalizer_moved <- function(v) {
  built <- attr(v, "normalizer")
  live  <- tryCatch(npmatch::np_normalize_signature(),
                    error = function(e) NA_character_)
  skip_if(is.na(built) || is.na(live))
  pk <- normalizer_versions(v)
  if (identical(built, live)) return(invisible(TRUE))

  if (.npn_older(pk[["live"]], pk[["built"]]))
    stop(sprintf(paste0(
      "installed npnormalize %s is OLDER than the %s this fixture was built",
      " against (%s vs %s).\n",
      "  This is a broken environment, not a stale fixture, so it fails rather",
      " than skipping.\n",
      "  DESCRIPTION requires npnormalize (>= %s); install at least that."),
      pk[["live"]], pk[["built"]], live, built, pk[["built"]]), call. = FALSE)

  skip(sprintf(paste("normalizer moved (fixture %s, npnormalize %s; installed %s,",
                     "npnormalize %s); rebuild with data-raw/make-pf-variants.R"),
               built, pk[["built"]], live, pk[["live"]]))
}
