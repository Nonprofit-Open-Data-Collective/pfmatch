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

> **2026-10-31: that is the future tense, and this note read as though it were
> the present.** The installed build is npmatch **0.1.1**, which is
> *pre-extraction*: its `Imports` does not list npnormalize and it carries its
> own full copy of the normalizer, including its own `.np_addr_key`,
> `.np_unit_id`, `.np_addr_class` and `.np_extract_unit` — all byte-identical
> to npnormalize's. npnormalize 0.1.1 is installed *beside* it as an
> independent duplicate, not as its dependency, which is why attaching
> npnormalize prints *"Registered S3 methods overwritten by 'npnormalize':
> `print.np_addr_freq`, `print.np_signature`"* (and the reverse when npmatch is
> attached second).
>
> So every normalizer call pfmatch makes today resolves to **npmatch's own
> code, not a re-export**. Nothing is broken by this — both copies produce the
> same signature and the same output — but the distinction matters for the
> "Optional, later" section below, and the claim "npmatch re-exports all four"
> is true of 0.1.1.9000 and not of what is installed.

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
useful on a raw `ADDR_L2` (it strips a designator, it does not gate the field),
but `np_addr_key()` is exactly what `dev/PLACES-SYNC.md` §4 step 4 needs for
the triangulation group key.

**2026-10-31, three corrections to the paragraph above.**

1. **Five exports are not re-exported, not two.** The full set npmatch 0.1.1
   leaves unreachable is `np_addr_key()`, `np_unit_id()`, `np_tokenize()`,
   `np_doc_freq()` and `np_state_abb()`. pfmatch wants only the first; the
   other three have no call site here and are listed so the next reader does
   not re-derive the set.
2. **The `np_unit_id()` example was wrong.** It returns `BOX1367` for
   `PO BOX 1367`, not `1367` — it strips the leading `PO` as the designator and
   then removes non-alphanumerics from what is left. The point stands and is
   worse than stated: `114 HIGH ST` comes back as `114HIGHST`, `LAS VEGAS` as
   `VEGAS`, `C/O JOHN SMITH` as `OJOHNSMITH`. Filed upstream as
   [npnormalize#7](https://github.com/Nonprofit-Open-Data-Collective/npnormalize/issues/7)
   together with a `BUILDING` gap in `.np_unit_pat`.
3. **The recommendation reverses on the installed build.** Importing
   npnormalize to reach the exported `np_addr_key()` would declare a dependency
   on a *second, independent copy of the whole normalizer* (see the note at the
   top) and bring the S3 collision with it. `npmatch:::.np_addr_key()` is
   byte-identical and is the same lineage as the `street_key` it consumes, so on
   npmatch 0.1.1 the `:::` with a parity test is the better route, not the
   fallback. Switch to the exported function once pfmatch is on an npmatch that
   actually imports npnormalize (0.2.0). Either way the parity test is what
   makes the switch safe, so write it first.

## To reproduce results from before the move

Pin the two restore points, both with signature `v1-3e7b9f9d59bbb19e`:

```r
renv::install("Nonprofit-Open-Data-Collective/npmatch@v0.1.1")
renv::install("Nonprofit-Open-Data-Collective/matchdb@v0.1.1")
renv::snapshot()
```
