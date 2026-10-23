# Collapse grant rows to distinct recipient identities

The main scale lever for the full grant file. Grants repeat heavily —
the same foundation funds the same charity every year, and thousands of
foundations fund the same large charities — so matching distinct
*recipient identities* rather than grant rows removes work without
removing recall.

## Details

It also buys recall outright. Because a cluster is one organization by
construction, a match found for any member **propagates to every
member**: a truncated, misspelled, or acronymic variant inherits the EIN
resolved for an easier variant sitting in the same cluster. See
[`pf_propagate_matches()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_propagate_matches.md).

## Two levels

- `"exact"`:

  group by the normalized key `(name_key, street_key, zip5)`. A hash
  group-by; linear and safe.

- `"fuzzy"`:

  additionally cluster the *surviving distinct keys* — a much smaller
  set — within a geographic block, joining names whose Jaro-Winkler
  similarity clears `threshold`. Absorbs `ST JUDES` /
  `ST JUDE CHILDRENS RESEARCH HOSP`.

## Guarding against over-merging

Two different organizations can share an address
(`FIRST PRESBYTERIAN CHURCH` and `FIRST PRESBYTERIAN FOUNDATION` at one
Boca Raton ZIP). Fuzzy clustering therefore requires high name
similarity **and** applies npmatch's hard veto predicates — conflicting
embedded numbers, ordinals, or directions — so `LOCAL 32` never merges
with `LOCAL 45`, nor `FIRST` with `SECOND`. Inspect the result with
[`pf_dedup_report()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_dedup_report.md)
before trusting it.
