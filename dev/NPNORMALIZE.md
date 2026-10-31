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

## Optional, later

pfmatch could call `npnormalize::` directly for normalization and import
npnormalize. It wouldn't drop its npmatch dependency, since it still matches
with npmatch, so there is little gain. I'd leave it.

## To reproduce results from before the move

Pin the two restore points, both with signature `v1-3e7b9f9d59bbb19e`:

```r
renv::install("Nonprofit-Open-Data-Collective/npmatch@v0.1.1")
renv::install("Nonprofit-Open-Data-Collective/matchdb@v0.1.1")
renv::snapshot()
```
