# The normalizer lives in npnormalize

**2026-11-01.** The move is done, pfmatch depends on npnormalize directly, and
both of the things this note told a reader to do are now wrong. It is rewritten
rather than annotated a fourth time; the superseded layers are listed at the
bottom, because they were quoted into `dev/PLACES-SYNC.md` and into a commit
message, and a reader may meet them there first.

The plan and its history are in
[npnormalize's `dev/EXTRACTION.md`](https://github.com/Nonprofit-Open-Data-Collective/npnormalize/blob/main/dev/EXTRACTION.md).

## Where this stands

Read off this machine today with `packageVersion()`, `packageDescription()` and
`np_normalize_signature()` — not predicted, and not quoted from a plan:

| | value |
|---|---|
| npmatch | **0.1.1.9000**, and its `Imports` names `npnormalize (>= 0.1.3)` |
| npnormalize | **0.1.6** |
| matchdb | not installed |
| normalizer signature | `v1-d49b18cc81ab79fb`, the same value from both packages |

**There is no second copy of the normalizer any more.** `.np_addr_key`,
`.np_unit_id`, `.np_extract_unit`, `.np_street_key` and `.np_addr_class` exist
in npnormalize and *only* there: `npmatch:::.np_addr_key()` fails with
*"object '.np_addr_key' not found"*. npmatch keeps the matching machinery and
re-exports the normalizer's public surface, so every normalizer call pfmatch
makes through `npmatch::` now resolves into npnormalize. The S3 overwrite
warning that the previous version of this note treated as a cost was a symptom
of the duplicate install, and it is gone with it.

Checked re-exported, so none of pfmatch's call sites change: `np_normalize()`,
`np_normalize_signature()`, `np_name_freq()`, `np_token_idf()`, `np_cascade()`,
`np_compare()`, `np_tier()`, `np_select()`, `np_addr_freq()`.

**Twelve npnormalize exports are not reachable through npmatch**, up from the
five this note last recorded: `np_addr_key()`, `np_doc_freq()`,
`np_extract_unit()`, `np_has_box()`, `np_is_mail_only()`, `np_is_po_box()`,
`np_mail_freq()`, `np_mail_key()`, `np_pattern()`, `np_state_abb()`,
`np_tokenize()`, `np_unit_id()`. pfmatch wants two of them: `np_has_box()`,
which it now has, and `np_addr_key()` for `dev/PLACES-SYNC.md` §4 step 4.

### Seven scripts reached for internals that moved — repointed

Found while checking the above and fixed in the same breath. The
name-normalization internals went with the rest, so every `npmatch:::` call on
them was erroring:

| name | now in |
|---|---|
| `.np_basic_clean`, `.np_replace_tokens`, `.np_abbrev` | npnormalize only |
| `.np_strip_suffix`, `.np_strip_lead_the` | npnormalize only |
| `.np_unit_pat`, `.np_street_types` | npnormalize only |
| `.np_hier_score` | **still npmatch** — it is a scorer, not a normalizer |

`dev/build-namesim-testset.R`, `dev/compare-name-metrics.R`,
`dev/namesim-worked-examples.R`, `dev/probe-ref-truncation.R`,
`dev/scan-agreement-risk.R`, `dev/spellcheck-diagnose.R` and
`inst/probes/probe-ref-truncation.R` each rebuild a `name_key` out of the first
five. All 55 calls are now `npnormalize:::`, one prefix per call rather than a
blanket substitution: `dev/probe-variant-class-ab.R` keeps
`npmatch:::.np_hier_score`, which it hands to `assignInNamespace(..., ns =
"npmatch")`, and which is still npmatch's. Nothing under `R/` was affected —
the package itself uses no `:::`.

Checked rather than assumed: all eight scripts parse, and the repointed chain
reproduces `np_normalize()`'s own `name_key` exactly on an article strip, a
possessive, a `FOUNDATION` suffix and a kept `TR` —
`THE MULTIPLE MYELOMA RESEARCH FOUNDATION, INC.` to
`MULTIPLE MYELOMA RESEARCH`, `Saint Mary's Hospital Association` to
`SAINT MARYS HOSPITAL`.

**Why these are a `:::` at all, and a possible ask.** There is no public
single-vector name key: npnormalize exports `np_name_core()`,
`np_name_rules()`, `np_name_freq()` and `np_name_placeholder()`, but a
`name_key` can only be had by normalizing a frame. That is the same shape as
the `np_unit_id()` gate in npnormalize#7 — the exported surface serves the
matcher, and a consumer who wants one column has to go around. Worth asking for
`np_name_key()` beside `np_addr_key()`; until then these scripts are reaching
into a neighbour's internals and will break again on the next move.

## pfmatch Imports npnormalize directly, as of `99fdf70`

`99fdf70` ("pf_street_unit(): the box question is npnormalize's, not a local
regex", [pfmatch#17](https://github.com/Nonprofit-Open-Data-Collective/pfmatch/pull/17))
deleted `.PF_BOX_RE`, called `npnormalize::np_has_box(street)` in its place,
and added `npnormalize (>= 0.1.5)` to `Imports` beside `npmatch (>= 0.1.1)`.

That answers the "Optional, later" question this note used to leave open, and
answers it the other way: the direct dependency is declared. What made the case
was not the address key this note expected but the box flag — a function that
exists only in npnormalize, that npmatch does not re-export, and that was added
upstream for this consumer.

~~**Branch note.**~~ **Resolved 2026-11-02.** This note previously warned that
`99fdf70` was on `main` only, so the paragraph above described `main` rather
than the tree it was being read in. `main` has since been merged here
(`325a4e5`, which is also pfmatch#19 carrying this note into main), so
`DESCRIPTION` has the npnormalize line and `R/unit.R` calls `np_has_box()` on
every branch that matters.

## `np_addr_key()` takes a street key, not a street

Worth stating plainly, because the natural way to use it is the wrong one, and
`dev/PLACES-SYNC.md` §4 step 4 is the place that will reach for it. The
signature is `np_addr_key(street_keys, zip5)`; the body pastes the two together
and blanks the result for a PO-box or mail-only street. It normalizes nothing:

| input | `np_addr_key(input, "12210")` |
|---|---|
| `100 MAIN STREET` | `100 MAIN STREET 12210` |
| `100 MAIN ST` | `100 MAIN ST 12210` |

Feed it `street_key` from `np_normalize()` instead and the renderings collapse,
which is the whole point of the step:

| raw street | `street_key` | `np_addr_key(street_key, zip5)` |
|---|---|---|
| `100 MAIN STREET` | `100 MAIN ST` | `100 MAIN ST 12210` |
| `100 MAIN ST` | `100 MAIN ST` | `100 MAIN ST 12210` |
| `100 MAIN STREET SUITE 3` | `100 MAIN ST` | `100 MAIN ST 12210` |

So the unification pfmatch wants comes from `np_normalize()`, and
`np_addr_key()` only joins the key to the zip and applies the box rule. Handing
it a raw `ADDR_L1` reproduces exactly the defect step 4 exists to remove.

## What has not changed

* **pfmatch's normalizer calls keep working**, now five of them:
  `np_normalize()`, `np_normalize_signature()`, `np_name_freq()` and
  `np_token_idf()` through `npmatch::`, plus `np_normalize()` again inside
  `pf_street_unit()` to parse the secondary-unit line. The matching calls
  (`np_cascade()`, `np_compare()`, `np_score()`, `np_tier()`, `np_select()`,
  `np_config()`, `np_ref_index()` and the column maps) are npmatch's own.
* **The stamp checks keep working.** `pf_reference()` and the checks in
  `R/match.R` compare a stored reference's `normalize_signature` (a matchdb
  stamp, or a bundle's `normalizer`) with `np_normalize_signature()`. The
  comparison is the point, not the value — and the value *has* moved, twice.
* **The fallback is unaffected.** `pf_reference(source = "matchdb")` still
  falls back to pfmatch's own BMF reference when matchdb isn't installed or a
  tier was built under a different normalizer.
* **The unit parse is normalizer-dependent** where the old local parser was
  not, which is why `test-unit.R`'s fixture assertion is signature-gated.

## npnormalize#7 is closed, and two of its asks shipped

[npnormalize#7](https://github.com/Nonprofit-Open-Data-Collective/npnormalize/issues/7)
was pfmatch's report of five unit-extraction defects. Measured again on 0.1.6:

* **§1, the `BUILDING` split: fixed.** `BUILDING` is in `.np_unit_pat`, and
  both spellings now agree — `100 CAMPUS CENTER BUILDING 86E` and
  `100 CAMPUS CENTER BLDG 86E` both give `street_key` `100 CAMPUS CENTER`,
  `street_unit` `BLDG 86E`, `street_unit_id` `86E`.
* **§2, the ungated `np_unit_id()`: fixed, as asked.** It returns `NA` for
  everything that is not a unit — `PO BOX 1367`, `BOX 19960`, `114 HIGH ST`,
  `LAS VEGAS`, `C/O JOHN SMITH`, `NORTH TOWER`, `400891` — and `400` for
  `STE 400`. `np_extract_unit()` is exported too, so the gate is reachable
  without normalizing a frame. `pf_street_unit()` keeps the frame route
  anyway, deliberately: it makes pfmatch read the suite exactly as the matcher
  does.
* **§3, `street_unit_id` drops the designator: unchanged, and there was no
  ask.** `1 PLAZA FL 2` and `1 PLAZA STE 2` still both give `street_unit_id`
  `2`. Right for a 0.97 rung in a `max()` ladder, wrong for a flag a human
  reads, which is why `pf_unit_evidence()` compares the canonical
  `street_unit` with only the room-level designators folded.
* **§4, no flag for a box carried on line 2: answered by a new function.**
  `np_has_box()` (npnormalize 0.1.5, from its own #9 and #12) is TRUE for
  `211 EMMET STREET SOUTH PO BOX` and `4347 W NORTHWEST HWY STE 130 BOX` and
  FALSE for `BOX ELDER ST` — anchored, which the local regex was not.
  `99fdf70` adopted it.
* **§5, a suite fused to the street word: unchanged, and recorded as
  intended.** `4550 WEST 77TH STREETSUITE 200` still keys with the suite
  inside it.

## To reproduce results from before the move

Four readings so far, in order: `v1-6dcb298522cc5118` (what the fixtures were
originally built under), `v1-3e7b9f9d59bbb19e` (the first post-extraction
reading), `v1-533f186c123357cf` (npnormalize 0.1.5, which `cbcecd3` re-pinned
the fixtures to), and `v1-d49b18cc81ab79fb` — npnormalize 0.1.6, what is
installed — and what the fixtures pin **as of 2026-11-02**, rebuilt on 0.1.6 so
that `test-unit.R:182` and `test-variants.R:147` run again rather than skipping
(400 passing, 0 failures, 3 skips, all `{matchdb}`). The whole 0.1.6 rebuild
moved six cells: `PO DRAWER 2440` to `PO BOX 2440` on three pairs, with
`unit_evidence` identical across all 5,410 rows. `dev/UNIT-UPSTREAM-SYNC.md`
§4.3 has the detail. None of these signatures is a value to quote forward —
read it. The pre-move restore points, both at `v1-3e7b9f9d59bbb19e`:

```r
renv::install("Nonprofit-Open-Data-Collective/npmatch@v0.1.1")
renv::install("Nonprofit-Open-Data-Collective/matchdb@v0.1.1")
renv::snapshot()
```

## Superseded

Three layers of this note are dead. Listed so that a reader who finds them
quoted elsewhere does not act on them:

1. **"npmatch's normalizer is moving" (2026-10-28), in the future tense.** It
   has moved. The claim that the signature stays `v1-3e7b9f9d59bbb19e` was
   true of the build in front of it and was never a property of the move.
2. **"The installed build is pre-extraction" (2026-10-31).** True of npmatch
   0.1.1, false of the 0.1.1.9000 that is installed. The duplicate copy, and
   the S3 collision it caused, are gone.
3. **"Use `npmatch:::.np_addr_key()`, not the export" (2026-10-31).** The
   reasoning was that the export meant depending on a second copy of the whole
   normalizer. There is no second copy, and the function that recommendation
   pointed at does not exist any more. Use `npnormalize::np_addr_key()` — on a
   `street_key`, per the section above. The same reversal is written into
   `dev/PLACES-SYNC.md` §4 step 4 and §6, both corrected, and into the body of
   commit `5f528b3`, which cannot be edited: its correction 3 is the one to
   disregard. A parity test is still what makes the switch safe, so it is
   still the first thing to write.
