# Secondary-unit handling: retire the local copy when npmatch lands its own

> **TRIGGER FIRED, 2026-10-26.** npmatch PR #18 is merged: the suite is parsed
> into `street_unit_id`, carried to review, and scored. matchdb has shipped its
> side too (PR #17). Read `dev/PLACES-SYNC.md` first; note in particular that
> the normalizer signature must be **read** from the commit being built, never
> quoted — npmatch PR #20 struck a literal from its own NEWS for that reason.
> This note's §3–§5 still
> apply and are what to diff against — but **§1 is now a description of the
> pre-PR npmatch**, and two of its three facts are false upstream (the
> hierarchical scorer gained `unit = 0.97`; a unit-bearing profile is no longer
> auto-selected at all). Two of pfmatch's designator decisions are also known
> wrong: npmatch excludes `NO` and `OFC`, measured, and `R/unit.R` includes
> both. Read `dev/PLACES-SYNC.md` first — it covers the whole merge, including
> the address classes that came with it, and carries the ordered plan.

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

Do not batch these.

1. **Compare, do not replace.** Run the upstream parser over the same inputs
   and diff against `pf_variants$unit_evidence` (5,410 pairs) and the queue's
   121 conflicts. Any pair that changes verdict is a decision in §3 that was
   settled differently — resolve it explicitly, do not average it away.
2. **Delete `R/unit.R`** and re-export or alias the upstream functions. Keep
   `tests/testthat/test-unit.R` pointed at the new entry points: the
   assertions are corpus-derived and are worth more than the implementation.
3. **Rebuild the fixture** with `data-raw/make-pf-variants.R`, which will
   refresh both `unit_evidence` and the `normalizer` attribute.
4. **Regenerate the queue** with `PF_TRI_REUSE_MATCH=1` — seconds, no rematch —
   and confirm the pre-existing columns stay byte-identical, as they did in
   `8facb11`.
5. **Revisit the matcher question**, which the local change deliberately did
   not touch. If npmatch starts parsing the unit reliably, the 3.84% coverage
   figure is the thing to re-measure: a `street_unit_full` profile gated at 50%
   stays unreachable, and `.np_hier_score()` still needs a unit term before any
   of it reaches the score. Decide whether the unit should score at all — with
   coverage this low the honest answer may remain no.

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
  `pf_variants$unit_evidence` exactly. It fails the moment either side moves.
  It also caps `conflict` at 2% of pairs — if a parser change starts reading
  junk as units, that is the alarm.
* `tests/testthat/test-variants.R` pins every recorded key to
  `np_normalize_signature()`, currently `v1-6dcb298522cc5118`. It **skips**
  with a rebuild instruction when the normalizer moves, so a skip in that file
  means npmatch changed under us.
* `pf_variants`' `normalizer` attribute records the same signature. Stale
  attribute, stale keys.
