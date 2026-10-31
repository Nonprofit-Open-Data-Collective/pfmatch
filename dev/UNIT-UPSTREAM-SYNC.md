# Secondary-unit handling: retire the local copy when npmatch lands its own

> **DONE, 2026-10-31 — the local parser is retired.** `pf_parse_unit()` is
> gone. `pf_street_unit()` hands line 2 to `npmatch::np_normalize()` and reads
> `street_unit` back; `pf_unit_evidence()` keeps pfmatch's comparison and its
> four-value vocabulary. The measured effect is in §4 below: 22 of the 5,410
> recorded pairs change verdict, the conflict rate is unchanged at 0.17%, and
> every change traces to a §3 decision. What is **not** done is the fixture and
> queue rebuild (§4.3–§4.4), because both need a triangulation run under the
> current normalizer rather than a rebuild from the old run's output, and the
> matcher question (§4.5), which is still open.
>
> **§1 is a description of the pre-PR npmatch** and two of its three facts are
> false upstream (the hierarchical scorer gained `unit = 0.97`; a unit-bearing
> profile is no longer auto-selected at all). It is kept as the record of why
> the local code existed. Read `dev/PLACES-SYNC.md` alongside this — it covers
> the whole merge, including the address classes that came with it, and carries
> the ordered plan. Note in particular that the normalizer signature must be
> **read** from the commit being built, never quoted.

**Original trigger: npmatch and matchdb are integrating unit parsing/
normalization and promotion of the unit to the adjudication stage. When those
merge, come back here.** pfmatch has its own implementation, written because
npmatch did not have one at the time, and two implementations of the same thing
will drift.

By the rule in `dev/NPMATCH-PROMOTION-PLAN.md` — *generic machinery, anything
whose correctness does not depend on the query file being 990-PF Part XIV,
belongs in npmatch* — the local copy was always a stopgap. USPS secondary-unit
parsing would be equally correct applied to SAM or USASpending. It goes.

---

## 1. Why pfmatch grew its own

**This section describes npmatch as it was before PR #18 and as it still is on
this machine, where the installed build is `v1-6dcb298522cc5118`. Upstream, the
second and third bullets no longer hold.** They are kept because they are why
the local code exists and because the coverage figure in the third is still the
number to re-measure before letting the unit into scoring.

Three facts, measured on the 50,000-case triangulation run (population
`cb3c78ff0f1a9546`, 91,817 identities). All three were reasons the *upstream*
version had to change, not just reasons we wrote a local one:

* **`np_normalize()` maps the unit but does not usefully parse it.** `unit` is
  in `pf_map_grants()` and `np_query()` carries it, but `street_unit` comes
  back `NA` for most rows that do hold a unit. Of 20 hand-checked pairs with
  unit text on both sides, one produced a `street_unit`. Worse, the designator
  often ends up stranded on the street: `street_key` values like
  `1385 S COLORADO BLVD STE` and `6300 E STATE UNIVERSITY DR SUITE`, with the
  number sitting in `ADDR_L2`.
* **`.np_hier_score()` has no unit term at all.** The hierarchical scorer is
  `0.6 * name + 0.4 * max(geo ladder)` and the ladder is zip9 / street / zip5 /
  pobox / zip3 / city / state. Under the method pfmatch runs
  (`method = "hier"`, `R/batch.R:73`) the unit is never compared.
* **The weighted path's unit profile cannot be selected.**
  `np_config()$weights$street_unit_full` does weight the unit (0.06), but
  `np_detect_geo(query, min_coverage = 0.5)` only picks a profile whose every
  field clears 50% coverage, and unit coverage here is **3.84%**. So
  `street_full` is chosen and the unit weight never applies.

So pfmatch intervened at the only layer that was free: the **adjudication
queue**, which a human reads. Nothing in the matcher was touched.

---

## 2. What is here now

**As of 2026-10-31**, `R/unit.R` holds `pf_street_unit()` (the two local
rejections on top of npmatch's parse) and `pf_unit_evidence()` (the
comparison), and `tests/testthat/test-unit.R` holds 12 blocks. The table below
describes the state **before** the retirement and is what §4's diff was taken
against.

| file | what |
|---|---|
| `R/unit.R` | `pf_parse_unit()`, `pf_unit_evidence()`, both exported |
| `tests/testthat/test-unit.R` | 9 test blocks, every input a value observed in the corpus |
| `dev/build-triangulation-v2.R` | computes `unit_evidence` / `flag_unit_conflict`, carries `anchor_unit` + `cand_unit` into the queue |
| `data-raw/make-pf-variants.R` | records `unit_evidence` per pair |
| `data/pf_variants.rda` | `unit_evidence` column; conflict 9, agree 27, one_sided 108, absent 5,266 |
| `vignettes/name-and-address-variants.Rmd` | the measured rates and the two cautions |

Queue as regenerated: 58,680 rows, `conflict` on **121** of them, 26 of those in
the zero-flag band. Commit `8facb11`.

---

## 3. The decisions to diff against upstream

This is the part worth reading before touching anything. Each line is a choice
that could reasonably have gone the other way, so check what npmatch/matchdb
decided rather than assuming agreement. Where they differ, **upstream wins
unless the pfmatch behaviour is listed in §5**.

**Designator handling**

* Room-level designators are interchangeable and collapse to `STE`: `STE`,
  `SUITE`, `UNIT`, `APT`, `APARTMENT`, `RM`, `ROOM`, `SPC`, `TRLR`, `LOT`,
  `OFFICE`, `OFC`, `NO`. So `UNIT 1200` == `STE 1200`.
* Level-level designators are kept separate and are **not** interchangeable
  with room-level: `FL`, `FLOOR` (→ `FL`), `BLDG`, `BUILDING` (→ `BLDG`),
  `TOWER`, `WING`. So `FL 2` != `STE 2`.
* A bare identifier with no designator is treated as **room-level**, so
  `206` == `Suite 206`. A filer writing just the number means the door.
* `#400` is handled separately: `#` has no word boundary, so the designator
  regex cannot see it.
* A floor is usually written identifier-first (`2ND FLOOR`, `2 FLOOR`), which
  needs its own pattern.

**Identifier handling**

* Internal separators are stripped: `T-700` → `T700`. Consequence worth
  checking against upstream: `STE 1150-291` != `STE 1150`, i.e. a
  sub-identifier reads as a different door. That was chosen deliberately —
  see §5.

**Rejections** — `ADDR_L2` is not a unit field. A value is rejected when it is

* a PO box (`PO BOX 1367`, `P O BOX 42`, `BOX 19960`),
* care-of text (`C/O JOHN SMITH`),
* a street line — leading house number plus a street-type word
  (`114 HIGH ST`, `1124 West Carson Street`, `312 SW 1ST AVE`),
* digitless prose (`STREET`, `LAS VEGAS`, `NORTH TOWER`),
* **or a bare identifier whose street line names a PO box** — at
  `211 EMMET STREET SOUTH PO BOX`, the `400891` on line 2 is a box number, not
  a door. This is why `pf_parse_unit()` takes an optional `street` argument;
  check whether the upstream signature can express it.

**Output vocabulary** — four values: `conflict`, `agree`, `one_sided`,
`absent`. If matchdb's adjudication layer defines its own evidence vocabulary,
align to it and translate here, rather than carrying two sets of names.

---

## 4. Retirement order when upstream lands

Do not batch these. **Steps 1 and 2 are done (2026-10-31); 3, 4 and 5 are
not**, and 3 and 4 are blocked on a measurement pass rather than on effort —
see below.

### 4.1 Compare, do not replace — DONE

Measured against `pf_variants$unit_evidence`, all 5,410 pairs, with
`npnormalize`/`npmatch` 0.1.1 installed (signature `v1-3e7b9f9d59bbb19e`). The
old implementation reproduces the recorded column exactly, so the diff below is
attributable to the replacement alone.

| old → new | pairs | why |
|---|---:|---|
| `absent` → `one_sided` | 14 | one side's line 2 holds a whole street with the suite after it (`35 RESEARCH DR SUITE 100`), which the local parser rejected on its street-type rule; plus `PMB 136`, `PMB 612` and `NUMBER 180`, designators upstream has and pfmatch lacked. Carries nothing either way. |
| `absent` → `agree` | 2 | `SUITE B` — the local parser required a digit *globally*, so it threw away a real suite; and `68 JAY STREET SUITE 425` / `68 JAY ST SUITE 425`, the street-on-line-2 case above with a suite on both sides. Both are genuine recoveries. |
| `agree` → `absent` | 3 | bare digits at a street ending in `CAMPUS BOX` or `STE 130 BOX`. The local box test only knew `PO BOX`; `.PF_BOX_RE` now matches any `BOX`. These were box numbers read as doors — false `agree`s, the kind §5 cares about most. |
| `conflict` → `absent` | 1 | same rule, `184` / `150` at `4347 W NORTHWEST HWY STE 130 BOX`. |
| `one_sided` → `conflict` | 1 | `A-304` / `610-A`. The local bare-identifier patterns read the first and not the second; upstream reads both. §5-compliant. |
| `one_sided` → `absent` | 1 | `100 CAMPUS CENTER BUILDING 86E`. **An upstream gap:** `.np_unit_pat` has `BLDG` but not the spelled-out `BUILDING`, though it has `APARTMENT`, `SUITE` and `FLOOR`. Not patched locally — reported instead, see `dev/PLACES-SYNC.md` §6. |
| **total changed** | **22** | 0.41% of pairs |

`conflict` is 9 pairs before and 9 after — 0.17%, unchanged, well inside the 2%
cap the test asserts. `agree` falls 27 → 26 and `one_sided` rises 108 → 120.

Every §3 decision was re-settled explicitly rather than averaged away:

* **Room-level designators collapse** — kept, as a *comparison* rule rather
  than a parse rule. npmatch's canon keeps `STE`, `APT`, `UNIT`, `RM`, `SPC`,
  `TRLR`, `LOT` and `#` distinct and then compares `street_unit_id` alone,
  which collapses *everything* including `FL`. pfmatch folds the room-level set
  into one class and keeps the rest apart, so `UNIT 1200` is still `STE 1200`
  and `FL 2` is still not `STE 2`. Upstream's choice is right for a 0.97 rung
  in a `max()` ladder and wrong for a flag a human reads.
* **`NO` and `OFC` are gone.** This was the defect; it is fixed by deletion.
  `NO 5`, `OFC 200`, `OFFICE 200` and `OFC PIERCE ST` all parse to nothing now,
  and there is a test saying so.
* **Separators stripped, compared exactly** — unchanged, `T-700` → `T700`,
  and `STE 1150-291` still reads as a different door from `STE 1150`.
* **The postfix floor form** — unchanged, `2 FLOOR` → `FL 2`.
* **Rejections** — the PO-box, care-of, street-line and digitless cases are all
  still rejected, but by three different mechanisms now: `.np_unit_pat` handles
  most of them for free, and only two needed keeping locally (digitless bare
  values, and a bare identifier at a box street). Both are on the bare path
  only, which is what fixed `SUITE B`.
* **Output vocabulary** — pfmatch's four values are kept, because npmatch's
  `geo_unit` cannot express two of them: `one_sided` and `absent` are both
  `NA`. `pf_unit_evidence()`'s docs now state the mapping, and the crowding
  half of npmatch's annotation (`addr_shared`, `addr_units`,
  `addr_unit_shared`, `addr_note`) is deliberately *not* reimplemented here.

The queue's 121 conflicts were not re-diffed, because regenerating the queue
needs step 4 below.

### 4.2 Delete the local parser — DONE

`pf_parse_unit()` and its three designator tables are gone. `pf_street_unit()`
replaces it and returns npmatch's canonical `street_unit` string (`"STE 400"`,
`"FL 2"`, `"# 206"`) or `""`, not the old `type`/`id` data frame — the
designator is no longer dropped at parse time, since the comparison needs it.
De-duplicates before normalizing, since line 2 repeats heavily. It stops with a
named error if `np_normalize()` returns no `street_unit`, because a silent
`NULL` there would read as "no line holds a unit" and make every verdict
`absent` with nothing failing.

`test-unit.R` is pointed at the new entry points and grew from 9 blocks to 12:
the digitless-vs-bare split, the street-on-line-2 recovery, and the two
excluded designators each got one, and the box test gained the campus-box,
suite-box, `BOXWOOD LANE` and `BOXER ST` cases. The fixture-reproduction
assertion is now **signature-gated**, the same way `test-variants.R`'s pinned
block is, and currently skips.

### 4.3 Rebuild the fixture — NOT DONE, and not a rebuild

`data-raw/make-pf-variants.R` reads `data-dev/TRI-V2-MATCH.rds`, which was
produced 2026-10-25 under the **old** normalizer. Running it now would stamp
the fixture `v1-3e7b9f9d59bbb19e` while its keys came from a
`v1-6dcb298522cc5118` match run — a fixture claiming a normalizer it was not
built under, which is precisely the drift `dev/PLACES-SYNC.md` was written to
prevent. So this waits on a triangulation re-run under the current normalizer,
which `dev/PLACES-SYNC.md` §4.2 already records as a separate measurement pass.
Until then the gated test skips with the rebuild instruction, and the 22 changes
in §4.1 are what the rebuild should reproduce.

### 4.4 Regenerate the queue — NOT DONE

Same blocker: `PF_TRI_REUSE_MATCH=1` reuses the old-normalizer match.

### 4.5 Revisit the matcher question — OPEN

Upstream has moved under this. `geo_weights` now carries `unit = 0.97`,
`np_compare()` emits `geo_unit` and the three crowding counts, and a
unit-bearing profile is no longer auto-selected at all, so the 50%-coverage
gate is no longer the obstacle — an explicit `profile =` is the mechanism. The
reference rebuild put `street_unit_id` on 413,417 BMF rows (10.65%). The
figure to re-measure is query-side coverage, last seen at 3.84%. Decide whether
the unit should score at all; with coverage that low the honest answer may
remain no.

---

## 5. What any implementation has to keep

Measured here, so a cleaner upstream implementation does not get to discard
them without re-measuring:

* **`agree` is not evidence of one organization.** Generic suites are shared by
  unrelated tenants — `MIDDLE EAST CHILDRENS ALLIANCE` and `IRISH REPERTORY
  THEATER` both at Suite 100, `GLOBAL FUND FOR WOMEN` and `THAKKER CHARITABLE
  TRUST` both at Suite 400 — a fiscal sponsor's suite is shared by everything
  it sponsors, and some values are not units at all (`15219` is a Pittsburgh
  ZIP code on line 2). If upstream treats agreement as positive evidence, that
  is a disagreement to raise, not to adopt.
* **A false `agree` is worse than a false `conflict`.** A conflict gets looked
  at; an agreement never does. Bias the ambiguous cases toward `conflict`.
  This is why `T-700` and `T-205` must not collapse to `T`, and why
  `STE 1150-291` reads as different from `STE 1150`.
* **`conflict` concentrates and must stay reviewable.** One address produced 31
  of 69 conflicts in the pair measurement: a fellowship program writing
  `291 BROADWAY STE 1901`, `STE 1902`, … one per individual grantee, using
  line 2 as a record counter. No parser fixes that. The flag is a prompt for a
  reviewer, never an automatic verdict, and the queue must keep carrying both
  sides' **raw** line 2 beside it.
* **Do not fold it into `n_flags`.** That counter measures reasons to doubt a
  case and drives review order. A unit conflict is near-decisive where it
  fires; averaging it in would bury it and redefine the zero-flag "cleanest
  slice". It has its own column and sorts to the top of its flag band.

---

## 6. Tripwires

Things that will tell you the two have drifted, without anyone checking:

* `tests/testthat/test-unit.R` asserts `pf_unit_evidence()` reproduces
  `pf_variants$unit_evidence` exactly, **under the fixture's own normalizer**;
  since the parse is npmatch's now, that assertion is signature-gated and
  skips when the normalizer has moved, the same way `test-variants.R`'s pinned
  block does. A skip there means the fixture is stale, not that nothing is
  checked: the conflict cap (2% of pairs) and every behavioural assertion run
  ungated, so a parser change that starts reading junk as units still fails.
* `pf_street_unit()` stops with a named error if `np_normalize()` returns no
  `street_unit` column — the npmatch-too-old case, which would otherwise read
  as "no line 2 holds a unit".
* `tests/testthat/test-variants.R` pins every recorded key to
  `np_normalize_signature()`, currently `v1-6dcb298522cc5118`. It **skips**
  with a rebuild instruction when the normalizer moves, so a skip in that file
  means npmatch changed under us.
* `pf_variants`' `normalizer` attribute records the same signature. Stale
  attribute, stale keys.
