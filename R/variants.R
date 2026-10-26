# ============================================================================
# Documentation for the bundled name/address variant corpus. Built by
# data-raw/make-pf-variants.R; see the vignette "Name and address variants".
# ============================================================================

#' Name and address variants that survive normalization
#'
#' 5,410 pairs of recipient renderings filed at the same street and ZIP, one of
#' which the cascade resolved (`YES`) and one of which it did not (`MAYBE`).
#' Drawn from the 50,000-case triangulation run over population
#' `cb3c78ff0f1a9546`, restricted to organization recipients.
#'
#' @section Why these pairs are the interesting ones:
#' Every pair here is a difference that **survived** normalization.
#' [np_normalize()][npmatch::np_normalize] already strips a leading `THE`,
#' rewrites `&` to `AND`, expands `FDN` to `FOUNDATION` and contracts USPS
#' street suffixes, and [pf_dedup()] then collapses renderings that share an
#' identity key. So nothing in this table differs only in a way the pipeline
#' already handles: these are the cases that reached the comparator and split.
#' That makes the table a regression corpus. Tighten the normalizer and
#' specific documented pairs should move; the pairs recorded as already closed
#' should stay closed.
#'
#' @section What it does not contain:
#' Ground truth. The triangulation verdicts are silver, `confidence = "low"`,
#' and unadjudicated — assigning the anchor's EIN to every other rendering at
#' the address is the assumption under test, not a fact. `expected_same_org` is
#' therefore `TRUE` on only 20 rows, where the two names are the same string
#' under a documented cosmetic transformation at an identical address, and `NA`
#' — never `FALSE` — on the other 5,390. A pair sharing no tokens may still be
#' one organization (`US OLYMPIC AND PARALYMPIC FOUNDATION` / `USOC`); a pair
#' sharing a distinctive token may still be two (`MARINE CORPS UNIVERSITY
#' FOUNDATION` / `MARINE CORP SCHOLARSHIP FUND`). `label_basis` records which
#' rows are waiting for a human.
#'
#' Pairs where either side is a person rather than an organization are
#' excluded, so the table carries no individual's name or home address.
#'
#' @format A data frame with 5,410 rows and 57 columns. `a_*` is the anchor —
#'   the best-scoring `YES` rendering at the address. `b_*` is the candidate
#'   that came back `MAYBE`.
#' \describe{
#'   \item{`pair_id`, `group_id`, `addr_key`}{Identifiers. `addr_key` is the
#'     uppercased-alphanumeric street plus ZIP5 that defines the group.}
#'   \item{`curated`}{`TRUE` for 155 exemplars, up to six per
#'     `name_class` x `addr_class` cell, chosen deterministically by anchor
#'     score. Use these for examples and tests; use the full table for
#'     regression.}
#'   \item{`a_name`, `b_name`}{The names as filed.}
#'   \item{`a_name_key`, `b_name_key`, `a_dba_key`, `b_dba_key`}{The normalized
#'     keys the cascade blocks on, from `np_normalize()`.}
#'   \item{`a_street`, `b_street`, `a_street_key`, `b_street_key`}{Street as
#'     filed, and as normalized.}
#'   \item{`a_unit`, `b_unit`, `a_city`, `b_city`, `a_state`, `b_state`,
#'     `a_zip`, `b_zip`, `a_zip5`, `b_zip5`}{The rest of the address, filed and
#'     derived.}
#'   \item{`a_ein`, `a_bmf`}{The anchor's matched EIN and the BMF name behind
#'     it. `b_ein` is the candidate's own EIN where it has one.}
#'   \item{`a_score`, `b_score`, `a_pass`, `b_pass`}{Score and winning pass for
#'     each side. `a_pass_rank` and `b_pass_rank` grade the pass: 6 for an
#'     exact name + ZIP5 hit down to 1 for an unblocked token sweep.}
#'   \item{`a_grants`, `b_grants`}{Grant rows behind each identity.}
#'   \item{`name_class`}{What separates the names: `identical normalized`,
#'     `spacing or punctuation`, `leading THE`, `corporate suffix`,
#'     `and vs ampersand`, `abbreviation`, `truncation`,
#'     `token added or dropped`, `typo`, `partial token overlap`, or
#'     `different name`. `and vs ampersand` is empty in this build:
#'     `np_normalize()` resolves `&` to `AND` upstream, so what survives is an
#'     ampersand that was *deleted* rather than spelled out, which lands in
#'     `spacing or punctuation`.}
#'   \item{`addr_class`}{What separates the addresses: `identical`,
#'     `zip4 differs`, `city differs`, `unit differs`, `street spelling`, or
#'     `state differs`.}
#'   \item{`name_lev`, `name_jaccard`, `shared_distinctive`,
#'     `is_initialism`}{Edit distance, token Jaccard, count of shared tokens
#'     that are not generic org words, and whether one name is an initialism of
#'     the other.}
#'   \item{`street_differs`, `unit_differs`, `city_differs`, `zip4_differs`,
#'     `state_differs`}{Whether the filed text differs, before normalizing.}
#'   \item{`name_key_equal`, `street_key_equal`, `zip5_equal`}{Whether the
#'     normalized keys agree. Pair `street_differs` with `street_key_equal` to
#'     see what the street normalizer is buying.}
#'   \item{`blocking_intact`}{`TRUE` when ZIP5 agrees and the state does not
#'     disagree, so every blocked pass could still fire. `FALSE` on 20 rows.}
#'   \item{`b_outscores_a`}{`TRUE` on 726 rows where the candidate's own match
#'     beat the anchor's, by score or by a stronger pass. On these the silver
#'     label is running against the system's own evidence and should be read
#'     before it is trusted.}
#'   \item{`n_names_at_addr`}{Distinct renderings at the address.}
#'   \item{`expected_same_org`, `label_basis`, `label_confidence`}{The label,
#'     and how it was arrived at. See "What it does not contain".}
#' }
#' @source The triangulation run in `dev/build-triangulation-v2.R`, over the
#'   deduplicated e-file corpus (`efilepf_v3_1`, 17,253,199 rows). The
#'   `normalizer` attribute records the `np_normalize_signature()` the keys were
#'   computed under; if it no longer matches, the keys are stale.
#' @seealso `vignette("name-and-address-variants", package = "pfmatch")`
"pf_variants"
