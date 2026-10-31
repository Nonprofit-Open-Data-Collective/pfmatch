# The normalizer is moving to npnormalize

**2026-10-28.** A pointer note. The plan and its current status are in
[npnormalize's `dev/EXTRACTION.md`](https://github.com/Nonprofit-Open-Data-Collective/npnormalize/blob/main/dev/EXTRACTION.md).

## What is happening

npmatch's normalizer is moving, unchanged, into a new package,
[npnormalize](https://github.com/Nonprofit-Open-Data-Collective/npnormalize).
It covers:
* the rule tables;
* `np_normalize()` and `np_name_core()`;
* the name and token statistics;
* `np_normalize_signature()`.

npmatch then imports it and re-exports the public functions
([npmatch#22](https://github.com/Nonprofit-Open-Data-Collective/npmatch/pull/22),
npmatch 0.1.1.9000; the next release is 0.2.0), and matchdb follows. Every
function name and body moves unedited, so the normalizer signature stays
`v1-3e7b9f9d59bbb19e`.

## What it means for pfmatch: nothing has to change

* **pfmatch's normalizer calls keep working.** It calls four normalizer
  functions through `npmatch::`: `np_normalize()`, `np_normalize_signature()`,
  `np_name_freq()` and `np_token_idf()`. npmatch re-exports all four. Its
  matching calls (`np_cascade()`, `np_compare()`, `np_score()`, `np_tier()`,
  `np_select()`, `np_config()`, `np_ref_index()` and the column maps) stay in
  npmatch.
* **The stamp checks keep working.** `pf_reference()` and the checks in
  `R/match.R` compare a stored reference's `normalize_signature` (a matchdb
  stamp, or a bundle's `normalizer`) with `np_normalize_signature()`. The value
  doesn't move, and matchdb keeps the `normalize_signature` field; it will add
  `npnormalize_version` beside it.
* **The fallback is unaffected.** `pf_reference(source = "matchdb")` still falls
  back to pfmatch's own BMF reference when matchdb isn't installed or a tier
  was built under a different normalizer.
* **Checked:** pfmatch's 112 tests pass, with no edits, against npmatch#22
  installed in a scratch library.

**2026-10-31, one function added to the list.** `pf_street_unit()` (which
replaced `pf_parse_unit()`) calls `np_normalize()` to parse the secondary-unit
line, so that is a fifth normalizer call — through `npmatch::`, which
re-exports it, so nothing above changes. Noted because the unit parse is now
normalizer-dependent where the old local parser was not: `test-unit.R`'s
fixture assertion is signature-gated for that reason.

## Optional, later

pfmatch could call `npnormalize::` directly for normalization and import
npnormalize. It wouldn't drop its npmatch dependency, since it still matches
with npmatch, so there is little gain. I'd leave it.

One thing would change the calculation: npnormalize exports `np_unit_id()` and
`np_addr_key()`, which npmatch does **not** re-export. `np_unit_id()` is not
useful on a raw `ADDR_L2` (it strips a designator, it does not gate the field —
it returns `1367` for `PO BOX 1367`), but `np_addr_key()` is exactly what
`dev/PLACES-SYNC.md` §4 step 4 needs for the triangulation group key. If that
step goes ahead, importing npnormalize is the clean way to reach it, and the
alternative is `npmatch:::.np_addr_key()` with a parity test.

## To reproduce results from before the move

Pin the two restore points, both with signature `v1-3e7b9f9d59bbb19e`:

```r
renv::install("Nonprofit-Open-Data-Collective/npmatch@v0.1.1")
renv::install("Nonprofit-Open-Data-Collective/matchdb@v0.1.1")
renv::snapshot()
```
