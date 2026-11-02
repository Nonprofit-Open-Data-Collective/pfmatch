# Places: staying in step with npmatch's address classes and matchdb's place tables

**Status: plan, revised 2026-10-26 (second pass). Nothing here is built in
pfmatch, and nothing is broken yet. Upstream, both sides have now shipped.**

Two upstream changes land on the same ground pfmatch's triangulation stands on:

* **npmatch PR #18, merged** — "Normalizer: fold special letters, parse the
  suite, classify shared addresses". Parses the suite into `street_unit_id`,
  adds `np_addr_freq()` and an `addr_class`, gives `.np_hier_score()` a unit
  term, annotates every candidate pair for the reviewer, and moves the
  normalizer signature. (PR #19 folded in; PR #20 is a correction, see below.)
* **matchdb PR #17 (`fix/bmf-reingest`), commits `935f846` and `07c7856`** —
  `dev/PLACES.md` has gone from *proposal* to **built and fixture-tested**:
  `md_place_key()`, `md_unit_id()`, `md_addr_freq()` and `md_build_places()`
  are exported, every bundle ships `addr_freq.parquet`, and `md_reference()`
  returns `addr_freq` and `places`. Full-database checks are still pending.

## Do not quote a normalizer signature. Read it.

The first pass of this note named `v1-77a3842ce517e353` as the value to expect.
**That value never existed on npmatch `main`.** It was measured on PR #18's
feature branch; PR #17 landed a one-line `.np_replace_tokens()` change in
between, which moved the signature, and on the merge commit `de52bb9` the value
was `v1-3e7b9f9d59bbb19e` instead.

npmatch PR #20 exists to strike that literal from its own `NEWS.md`, for a
reason worth quoting: *a published signature that never existed is worse than no
signature at all, because that is exactly the value downstream callers stamp
cached artifacts with.* pfmatch is one of those downstream callers, and this
note carried the bad value for a day — which is precisely the drift it was
written to prevent.

`NEWS.md` on main now says it plainly: **read the value with
`np_normalize_signature()` on the commit you are building from, rather than
from any value quoted anywhere.** So no literal target signature appears below.
The only literal kept is the one pfmatch's own artifacts were *built under*,
`v1-6dcb298522cc5118`, because that is a record of this machine's state rather
than a prediction about upstream.

**The short version.** pfmatch invented crude versions of all of this —
`flag_shared`, an `n_names < 25` filter, `pf_parse_unit()`, a hand-rolled
address key — because none of it existed upstream when the triangulation set
was built. All four are now superseded by measured implementations. The job is
to delete pfmatch's versions in the right order, and to notice that one of
npmatch's new labels contradicts the premise the whole triangulation design
rests on.

See also `dev/UNIT-UPSTREAM-SYNC.md`, whose trigger has now fired: the suite
half of this landed in the same PR.

---

## 1. Where pfmatch actually stands today

**The install has happened.** The first pass of this note was written against a
pre-PR npmatch and said "nothing needs doing until that install"; npmatch was
reinstalled on this machine during the same session. The step change is no
longer hypothetical:

| | pfmatch artifacts were built under | installed now |
|---|---|---|
| normalizer signature | `v1-6dcb298522cc5118` | `v1-3e7b9f9d59bbb19e` — moved again since, to `v1-d49b18cc81ab79fb`; see the 2026-11-01 block below |
| `np_addr_freq()` | absent | present, **exported** — and `np_cascade()` calls it itself, so pfmatch already has it (see step 5a) |
| `np_addr_key()`, `np_unit_id()` | absent | present, **exported** from `npnormalize` and **not** re-exported by npmatch. The `npmatch:::.np_addr_key()` / `.np_unit_id()` this row used to offer as a byte-identical alternative **no longer exist** — see the 2026-11-01 block below and step 4 |
| `np_addr_class()` | absent | present, **not exported** — internal, and now only in npnormalize |
| `street_unit_id` | absent | present |
| `geo_weights` has a `unit` term | no | yes, `0.97`, and it fires — measured 0.988 vs 0.980 on a suite conflict |
| `np_compare(addr_freq = )` | absent | present — but reachable only *through* `np_cascade()`, which has no `addr_freq =` of its own (step 5a) |

~~**The installed npmatch has not had its normalizer extracted.**~~ **Dead,
2026-11-01 — it described npmatch 0.1.1 and the installed build is now
0.1.1.9000.** The paragraph said npmatch carried its own full copy of the
normalizer, that npnormalize was installed beside it as an independent
duplicate, and that `npmatch:::.np_addr_key()` was therefore available and
byte-identical. None of that holds any more:

* **npmatch 0.1.1.9000 `Imports: npnormalize (>= 0.1.3)`.** The extraction
  happened. `.np_addr_key`, `.np_unit_id`, `.np_extract_unit`, `.np_street_key`
  and `.np_addr_class` live in npnormalize and *only* there —
  `npmatch:::.np_addr_key()` fails with *"object '.np_addr_key' not found"*.
  There is no duplicate copy and no S3 collision.
* **The signature is `v1-d49b18cc81ab79fb`**, identical from both packages, and
  npnormalize is at **0.1.6**. Everything the table above records as a *gap*
  between the fixtures and the install is still a gap, and wider.
* **pfmatch now `Imports: npnormalize (>= 0.1.5)` directly** on `main`, as of
  `99fdf70` (pfmatch#17), which calls `npnormalize::np_has_box()` in place of
  `.PF_BOX_RE`. That commit is not on this branch.

The consequence for the plan below is a reversal, written out at step 4 and in
§6: the exported `npnormalize::np_addr_key()` is the route, and the `:::` it
was told to prefer is gone. `dev/NPNORMALIZE.md` carries the full current
reading.

Both values above are records of this machine, read with
`np_normalize_signature()`, not predictions — see the warning above about
quoting a signature.

### What that broke, and what caught it

* **The signature tripwire fired as designed.** `test-variants.R`'s pinned test
  now skips with *"normalizer moved (fixture `v1-6dcb298522cc5118`, installed
  `v1-3e7b9f9d59bbb19e`); rebuild with `data-raw/make-pf-variants.R`"*. That is
  the mechanism working: a silent key change announced itself without anyone
  checking.
* **Two tests failed that should not have.** "street normalization reconciles
  what the raw text does not" and "its complement" were written as invariants
  but selected their rows using the fixture's *recorded* `street_key_equal`,
  which pinned them to the old normalizer without saying so. Fixed: the
  invariants are now asserted on literal strings, and fixture-column
  comparisons live only under the signature gate.
* **`REF-augmented.rds` is now stale**, built 2026-08-21 under the old
  normalizer. It is also unstamped, so until §4.1 landed nothing would have
  said so. It now warns.

### One deliberate loss worth recording

npmatch's new `.np_unit_pat` requires a word boundary, which means a suite
*fused* to the street word is no longer split:

```
4550 WEST 77TH STREETSUITE 200  ->  street_key "4550 W 77TH STREETSUITE 200", no unit
4550 West 77th Street Suite 200 ->  street_key "4550 W 77TH ST",  unit id "200"
```

pfmatch measured 9 pairs that the old permissive pattern reconciled this way.
npmatch measured the same pattern firing falsely on 27,954 rows (11.3% of all
extractions) — `SHERMAN WAY` yielding room `AN WAY` — and masking the real unit
on 3,636 of them. The trade is obviously right, and
`test-variants.R` now asserts the fused form stays unsplit so nobody "fixes" it
back. Separated forms all still reconcile, including `# 5`.

---

## 2. `addr_class` contradicts the triangulation premise

This is the substantive item; the rest is plumbing.

pfmatch's triangulation rests on a premise stated in its own commit history:
*triangulation works because a shared STREET means a shared organisation.*
npmatch's new taxonomy says that is true at one class of address and false at
two others:

| npmatch `addr_class` | what it is | does a shared street mean a shared org? |
|---|---|---|
| `cluster` (2–9 records) | an org with its foundation, auxiliary or PTO | **yes** — the premise holds here |
| `building` (≥10 records, ≥2 suites, coverage ≥0.5) | a multi-tenant office building | **no** — the suite separates tenants |
| `shared` (≥10 records, names spread) | a fiscal sponsor, registered agent or accountant | **no** — the address says nothing |
| `federated` (≥10 records, top name share ≥0.5) | a national office its chapters file from | **no** — the chapter number separates them |

Over the BMF: 134,212 `cluster`, 1,910 `building`, 1,319 `shared`, 1,188
`federated`.

pfmatch already approximates this, badly and without naming it:

* the universe filter drops addresses with `n_names >= 25` as "fiscal sponsors,
  DAF custodians and bank trust departments" — a crude `shared` detector with an
  arbitrary cut;
* `flag_shared := n_names_at_addr >= 4L` in the adjudication queue — a crude
  crowding signal that cannot tell `shared` from `federated` from `building`,
  which is exactly the distinction npmatch added because they *want opposite
  treatment*;
* the PO-box exclusion, `!grepl("^P?O?BOX|^POST", street)`, is a regex over a
  stripped string rather than npmatch's `is_po_box`.

And the empirical result from `pf_variants` lines up with the taxonomy: of the
different-name YES/MAYBE pairs, 38% share a distinctive token (the `cluster`
shape — `LAHEY CLINIC` / `LAHEY CLINIC FOUNDATION`) and 62% share none (the
`shared` and `federated` shapes). The 726 pairs where the candidate outscores
its anchor are concentrated in the same place.

**Consequence for the silver labels.** `PF-TRUTH-V2-TRIANGULATED.csv` writes the
anchor's EIN onto every other rendering at the address, at `confidence = "low"`.
That assumption is defensible at a `cluster` and wrong at a `shared` address. So
`addr_class` is not merely a better `flag_shared` — it is a filter on which
groups should produce labels at all. Recommended once the class is available:
emit labels for `cluster`, and for `building` only where the suite agrees;
report `shared` and `federated` separately rather than labelling them.

**Three populations, not two, and they are not interchangeable.** "How crowded
is this address" now has three answers, each counting something different:

| who | counts | caveat |
|---|---|---|
| `npmatch::np_addr_freq()` | **reference rows** | a compiled tier has one row per EIN per name and address, so record counts are inflated relative to EINs |
| `matchdb` `place` / `place_layer` | **EINs, per layer**, over each layer's own *current* addresses; historical spells feed churn instead | matchdb's own note says its figures "will differ by design" from npmatch's; `place_layer` can select the BMF layers to compare |
| pfmatch's triangulation | **grant-row renderings**, query side | written by third parties — a foundation naming a grantee's address, not an occupant filing from it |

The BMF knows who *files* from a street; the grant file knows who a foundation
*paid* there; matchdb knows who has *occupied* it over time. pfmatch wants its
own count to classify the triangulation group, and the BMF-side class as
evidence about the anchor. Do not join one and call it the other, and do not
expect pfmatch's numbers to reproduce npmatch's published BMF figures.

A caution that follows: `top_name_share` and `unit_coverage` were calibrated on
filings by occupants. On grant rows, where a third party wrote the address, they
may not behave the same way. Measure before adopting npmatch's thresholds
wholesale on the query side.

---

## 3. What breaks on the day npmatch is reinstalled

Ordered by how quietly it fails.

### 3a. ~~`REF-augmented.rds` is not signature-stamped~~ — **done, and the gate fired for real on 2026-11-02**

`pf_build_reference()` returns a plain
`list(reference, name_freq, token_idf, ref_index, ...)`. The reference is
normalized by `np_normalize()` at build time, and `name_freq`, `token_idf` and
`ref_index` are all derived from those keys. **Nothing records which normalizer
produced them.** The cached bundle here is 2.8 GB, built 2026-08-21.

After the signature change the query is normalized at run time with the new
rules while the cached reference still holds the old keys, so the two stop
meeting — npmatch measured `street_key` changing on 34,280 BMF rows (1.78%).
A match run would simply find fewer candidates and report a lower rate, with
nothing saying why.

Checkpoints are safe: `.pf_run_stamp()` includes
`npmatch::np_normalize_signature()` and `.pf_check_stamp()` refuses a mismatch.
A *fresh* run against a stale reference sails straight through. Close that gap
the same way — stamp the bundle, refuse a mismatch — before reinstalling.

> **It was closed, and 2026-11-02 is the first time it earned its keep.** The
> bundle is stamped and `pf_check_reference()` refuses a mismatch, so the
> §4.2 triangulation re-run stopped ten minutes in — after drawing its 36,366
> groups and preparing 91,104 identities, before a single batch was matched:
>
> ```
> reference: REF-augmented.rds, 3,880,431 rows
> Error: this reference bundle was built by a different normalizer.
>   bundle:    v1-3e7b9f9d59bbb19e
>   installed: v1-d49b18cc81ab79fb
> ```
>
> Exactly the failure this section was written to prevent, caught at the cost
> of ten minutes instead of a five-hour run whose keys came from two
> normalizers at once.
>
> **The consequence for the plan, which §4.2 does not state:** after a
> normalizer move, rebuilding the reference is a *prerequisite* for any match
> run, not a parallel errand. `pf_reference()` returns an existing cache
> untouched rather than rebuilding it, so the stale bundle has to be moved
> aside first; `dev/REF-REBUILD.log` records the 2026-10-26 rebuild at 23.4
> minutes and 2.83 GB, and keeps the outgoing bundle under a filename carrying
> its normalizer. The chain is: rebuild the reference, re-run the
> triangulation, then §4.3's fixture and §4.4's queue.

### 3b. `pf_parse_unit()` is superseded, and is wrong on two designators

> **Resolved 2026-10-31** — the function is deleted; see §4 step 3 below and
> `dev/UNIT-UPSTREAM-SYNC.md` §4. Kept here as the record of the defect.

npmatch's `.np_unit_designators` was built from BMF volume and it **excludes
two designators pfmatch includes**, for measured reasons:

* **`NO`** — "it is North far more often than Number". `R/unit.R` lists it.
* **`OFC`** — the USPS C2 designators match street names in this corpus
  (PIERCE ST, KEYSER AVE, SIDEHILL RD). `R/unit.R` lists `OFC` and `OFFICE`.

npmatch also found its old pattern false on 27,954 rows (11.3% of extractions)
by matching inside ordinary words — `SHERMAN WAY` giving room `AN WAY`,
`CHESTER` giving `STER` — and in 3,636 of those the false match *masked the real
unit*. pfmatch's pattern uses word boundaries and so avoids the worst of it, but
it was never scanned against a corpus the way npmatch's was. Two known
false-positive sources is enough: treat `pf_parse_unit()` as defective today,
not merely as a stopgap.

Where the two agree: separators dropped from the identifier (`T-700` → `T700`),
compared exactly, the postfix floor form handled, and line 2 read when the
street line names no suite.

### 3c. Three dev notes and commit messages go stale

* `dev/UNIT-UPSTREAM-SYNC.md` §1 says `.np_hier_score()` has no unit term and
  that the unit-bearing profile is gated at 50% coverage. After PR #18 both are
  false: `geo_weights` gains `unit = 0.97`, and a unit-bearing profile is no
  longer auto-selected *at all* (the profiles are a weighted sum in which an
  unrecorded suite is a silent penalty, so it needs an explicit `profile =`).
* Commit `9d87e3d` says the same about the unit term.
* `vignettes/name-and-address-variants.Rmd` renders the geo ladder from
  `np_config()$geo_weights`, so the table self-updates — but the prose around
  it names the terms and will need the `unit` rung added.

Worth noting in pfmatch's favour: npmatch independently confirmed the
saturation analysis from `9d87e3d`. Zeroing the street credit at crowded
addresses changed **not one decision** across 304,274 labelled pairs, "because
the geo terms combine with `max()` and the top rungs sit 0.05 apart" — the same
mechanism, measured on a labelled set rather than inferred from one corpus.

### 3d. The fixture and queue need rebuilding

`pf_variants` carries `normalizer = v1-6dcb298522cc5118` and 5,410 pairs of
recorded keys and unit verdicts. `test-variants.R` will skip with a rebuild
instruction; `test-unit.R` will fail outright, which is what it is for.

---

## 4. Plan

Each step ends with a check. Do not batch them; the signature change makes any
regression hard to attribute if several things move at once.

1. ~~**Stamp the reference bundle.**~~ **Done.** `pf_build_reference()` now
   returns a `normalizer` element, and `pf_check_reference()` enforces it from
   `pf_match_grants()` and `pf_run_batches()` (both take `check_reference=`).
   Severity is deliberately split: a bundle stamped with a *different*
   signature is known wrong and stops; an *unstamped* one is merely unknown,
   and since a reference is 2.8 GB and hours to rebuild it warns instead of
   blocking a run that is probably fine. Checkpoints stop in both cases because
   recomputing one is cheap. 14 assertions in
   `tests/testthat/test-reference-stamp.R`.
2. ~~**Rebuild the reference.**~~ **Done**, 23.4 min from
   `BMF-AUGMENTED-unified-fixed.csv`; full record in `dev/REF-REBUILD.log`.
   3,880,431 rows unchanged, 38 columns (was 35, gaining `name_core`,
   `name_placeholder`, `street_unit_id`), stamped and passing
   `pf_check_reference()`. The previous bundle is kept as
   `REF-augmented-v1-6dcb298522cc5118.rds`, its normalizer in the filename
   since it carries no stamp.

   It was not a cosmetic bump. `street_key` moved on 55,740 rows (1.436%,
   matching npmatch's 1.78% on their smaller BMF), and in **5,134** of them the
   old key was a strict *prefix* of the new one — the old pattern read `RM`
   inside `FARM` as a room designator and cut the street there, so
   `20 GILSLAND FARM RD` was keyed `20 GILSLAND FA`. Every farm road in the
   reference was keyed to its own truncation and could not match on street.
   `name_key` moved on 2,565 rows (990 abbreviations now expand: `FDN` to
   `FOUNDATION`, `MGMT` to `MANAGEMENT`, `HOSP` to `HOSPITAL`). And 413,417
   rows (10.65%) now carry a parsed `street_unit_id` across 19,878 distinct
   ids, which is what feeds the `building` class and the suite credit.

   Two consequences recorded rather than resolved: every measurement taken
   against the old bundle — `BASELINE-2026-10B`, the triangulation run — is now
   on a different footing and a rerun will not reproduce it; and matchdb's
   Phase 2 gate target has moved with it, so its comparison needs the new
   bundle rather than the kept one. `REF-active.rds`, `REF-unified.rds` and
   `REF-augmented-collapsed.rds` are all still on the old normalizer and
   unstamped.
3. ~~**Retire `pf_parse_unit()`.**~~ **Done**, 2026-10-31. `pf_street_unit()`
   hands line 2 to `npmatch::np_normalize()` and reads `street_unit` back;
   `pf_parse_unit()` and its three designator tables are deleted, `NO` and
   `OFC` with them. The diff against `pf_variants`' 5,410 recorded verdicts
   moved **22 pairs (0.41%)** with the conflict rate unchanged at 0.17%, and
   every one is traced in `dev/UNIT-UPSTREAM-SYNC.md` §4.1 — including three
   false `agree`s that were box numbers at a `CAMPUS BOX` street, and two real
   suites the local parser's global digit requirement had been throwing away.

   Two departures from the instruction as written. **The vocabulary is kept,
   not replaced:** `geo_unit` is `0`/`1`/`NA` and cannot express `one_sided`
   against `absent`, which is the distinction a reviewer needs, so
   `pf_unit_evidence()`'s four values stay and its docs state the mapping. The
   crowding half — `addr_shared`, `addr_units`, `addr_unit_shared`,
   `addr_note` — is *not* reimplemented here and should come from
   `np_compare()`; that is step 5a. **The comparison stays local:** npmatch
   compares `street_unit_id` alone, which collapses `FL 2` into `STE 2`.
   That is right for a 0.97 rung in a `max()` ladder and wrong for a flag a
   human reads, so pfmatch folds only the room-level designators.

   The fixture and queue rebuilds that §4.3–§4.4 call for are **not** done, and
   are blocked rather than skipped: `TRI-V2-MATCH.rds` predates the normalizer
   move, so rebuilding from it would stamp the fixture with a signature it was
   not matched under. The affected test is signature-gated and skips.
4. **Adopt `place_key` as the triangulation group key.** The change worth the
   most. pfmatch's key differs from npmatch's in three ways — the same three
   matchdb's note lists for its own `ein_key`: a raw
   `gsub("[^A-Z0-9]", "", toupper(ADDR_L1))` instead of `street_key`, a `|`
   separator instead of a space, and a regex PO-box test instead of
   `is_po_box`. npmatch's rule, as matchdb's port records it, is
   `paste(street_key, zip5)`, empty for a PO box, with the box pattern
   `^(P ?O ?BOX|P ?O ?B|BOX|P ?O) ?#? ?[0-9]+`.

   Measured cost of the first divergence alone: 528,862 of 2,326,459 address
   keys (22.7%) are redundant spellings, and 58,815 addresses never reach the
   two-rendering threshold because their spellings never meet. PR #18 improves
   it again — `street_key` now also strips the suite — so grouping by
   `place_key` and discriminating by `street_unit_id` is the clean split
   pfmatch's hand-rolled version was groping toward.

   **Measured 2026-11-02 under `v1-d49b18cc81ab79fb` (npnormalize 0.1.6), and
   the switch is not only a merge.** The parity test is written —
   `tests/testthat/test-addr-key.R` — and it says this step costs something the
   22.7% figure above does not show. Over all 5,410 shipped pairs, each of
   which sits at one hand-rolled key by construction,
   `np_addr_key(street_key, zip5)` **splits 92**. Two of these three rows moved
   the same day under 0.1.8 — see the update below the table; the table is kept
   as the 0.1.6 record because the BMF figures further down were measured
   against it:

   | pairs | why | verdict |
   |---:|---|---|
   | 11 | one side is a box or mail-only (`PO BOX 2440`, `GENERAL DELIVERY`), which `np_addr_key()` blanks and the local `^P?O?BOX|^POST` regex let through | npmatch is right; these should never have grouped |
   | 59 | the keys differ **only in spacing**: the hand-rolled `gsub("[^A-Z0-9]", "")` deleted every separator, so `70-11 150TH STREET` agreed with `7011 150TH STREET`; `street_key` keeps a space where the hyphen was (`70 11 150TH ST` against `7011 150TH ST`) | **a loss**, and Queens files both spellings |
   | 22 | the keys differ by more than spacing — almost all a suite fused to the street word (`4550 WEST 77TH STREETSUITE 200`), which `.np_unit_pat`'s word boundary cannot split, so it survives inside `street_key` on one side only | npnormalize#7 §5, recorded upstream as intended |

   **Measured over the whole BMF, 2026-11-02 under npnormalize 0.1.6 — and the
   answer is: adopt `street_key`, accept the 59, do not invent a third key.**
   *Re-measured over the same reference under 0.1.8 the same day; the three
   paragraphs after the table are superseded, and the replacement is below
   them. The conclusion holds and the reason for it does not.*
   `dev/measure-addr-key-spellings.R`, logged in `dev/ADDR-KEY-SPELLINGS.log`,
   put all three spellings over `REF-augmented.rds`'s 3,880,431 rows with
   `street_key` recomputed under npnormalize 0.1.6, because that file's
   recorded column is stale (6 rows in a 50,000 sample, all of them the
   `BUILDING` extraction or `PO DRAWER` → `PO BOX`).

   *Corrected later the same day:* this paragraph first said the file was
   *unstamped*, repeating §3a's old heading. It is **stamped**, at
   `v1-3e7b9f9d59bbb19e`, and stale — which is why `pf_check_reference()` was
   able to stop the §4.2 re-run cold. See the note under §3a. The recompute
   was the right thing to do and for the right reason; only the word was
   wrong.

   | spelling | rows keyed | groups | rows per group |
   |---|---:|---:|---:|
   | K1 hand-rolled, `gsub("[^A-Z0-9]", "")` + `\|` + zip5 | 2,627,588 | 2,110,592 | 1.245 |
   | K2 `np_addr_key(street_key, zip5)` | 2,628,491 | 1,941,116 | 1.354 |
   | K3 `np_addr_key(gsub(" ", "", street_key), zip5)` | 2,628,961 | 1,939,261 | 1.356 |

   Both box rules drop about the same third of the file: 1,252,843 rows for K1
   (32.29%) against 1,251,940 for K2 (32.26%).

   **K2 is the win the 22.7% figure promised, and the splitting is a corpus
   artefact.** It merges 87,790 K1 groups (4.53%) and cuts the group count by
   169,476 — 8.0% fewer groups over the same rows. It splits just 1,612 of
   2,109,207 K1 groups, **0.08%**. The 92 splits in `pf_variants` are 1.7% of
   that corpus because the corpus is *selected* for addresses with multiple
   renderings; across the BMF the same behaviour is two orders of magnitude
   rarer.

   **K3 does not pay for itself.** It adds 2,278 merges, 0.12% of groups, and
   972 of them — **42.67%** — join rows whose parsed `street_num` disagrees.
   The examples are mixed in a way no reviewer could sort at that volume:
   `110 04 ATLANTIC AVE` with `11004 ATLANTIC AVE` and `57C HOWARD RD` with
   `57 C HOWARD RD` are right, while `4780 1 55 N` with `47801 55 N` is simply
   wrong. A rule that fires on 0.12% of groups and is unreviewable in half of
   those is a bad trade for 59 pairs.

   **And K3 is aimed at the wrong target anyway.** Of its 2,278 merges only
   **410** involve a hyphenated spelling meeting an unhyphenated one — the case
   the 59 are made of. The other 1,864 are unrelated spacing noise, which is
   where the wrong merges live. So the 59 want a fix one layer down, not a
   third key: see the new `street_num` ask in §6.

   **RE-MEASURED under npnormalize 0.1.8, same script, same reference, logged
   in `dev/ADDR-KEY-SPELLINGS-20261102.log`. The local case against K3 is now
   WEAKER, not stronger, and the rejection no longer rests on it.**

   | | 0.1.6 | 0.1.8 |
   |---|---:|---:|
   | K1 keyed / groups | 2,627,588 / 2,110,592 | *identical* |
   | K2 groups | 1,941,116 | 1,940,724 |
   | K3 groups | 1,939,261 | 1,939,261 |
   | K1 → K2 splits | 1,612 (0.08%) | 1,482 (0.07%) |
   | K2 groups merging >1 K1 | 87,790 (4.53%) | 87,928 (4.54%) |
   | K3 merges over K2 | 2,278 (0.12%) | **1,886 (0.10%)** |
   | …of those, `street_num` disagrees | 972 (**42.67%**) | 322 (**17.07%**) |

   Two internal checks before reading it. K1 is hand-rolled and
   normalizer-independent, and its row is byte-identical across the two runs —
   the control. K3 strips every space, so it cannot see whether a hyphen became
   a space or nothing, and its group count is identical for that reason; a K3
   row that had moved would have meant the run was measuring something else.

   **The number that matters is the last one, and it cuts against this note's
   own argument.** K3 was rejected here because 42.67% of the merges it added
   joined rows whose house number disagreed — unreviewable at that volume. Under
   0.1.8 that is **17.07%**, because the join has already absorbed the
   hyphenated cases that made up most of the bad merges: 2,278 → 1,886 merges
   and 972 → 322 suspect. 1,886 merges at 17% suspect is a materially better
   trade than 2,278 at 43%, so *our* evidence against K3 has weakened.

   **The rejection stands anyway, on evidence this file cannot produce.**
   Upstream measured the *narrow* variant — a space allowed only where the join
   wants a hyphen — over 22,026,817 rows: splits fall to 334 and merges rise to
   10,232, but 92,797 further strings move and they are street names, 17,614 of
   them a house number followed by a bare numeric or single-letter street name
   that no rule can distinguish. That is the argument to cite. The 42.67% line
   is superseded and should not be quoted again — including from npnormalize's
   code comment, which quotes this repo's 0.1.6 log for it. npnormalize#20
   refreshes that comment to 1,886 / 322 / 17.07%, cites
   `dev/ADDR-KEY-SPELLINGS-20261102.log`, and states in the same place that the
   better trade does **not** carry the rejection on its own. Until #20 merges,
   the released comment is the stale one.

   The parity test pins all four counts from the pair corpus, and this log
   pins the BMF figures, so a move in either shows up.

   **It showed up, 2026-11-02 — and the ask in §6 has been answered upstream,
   partly granted and partly refused with better evidence than we had.**
   npnormalize moved `v1-d49b18cc81ab79fb` (0.1.6) →
   `v1-5e901add4a04a5d6` (0.1.8), the four pinned tests stopped abstaining, and
   three of the counts above moved: **92 splits → 82, and the 59 → 49**. The 11
   and the 22 are unchanged. Every closed pair is the hyphenated house number:
   `70-11 150TH STREET` and `7011 150TH STREET` both key to `7011 150TH ST`,
   and all 24 digits-hyphen-digits pairs in `pf_variants` now agree where 10 of
   them split before.

   *Attribution, corrected the same day.* This block first credited both
   changes to 0.1.8. Read off the installed `NEWS.md`: the house-number join is
   **#16 in 0.1.7**, the eleven further spellings of `FOUNDATION` are **#17 in
   0.1.7**, and **0.1.8 is only the compass-letter carve-out** below. The
   signature this session saw in between, `v1-59c6e84c5f38e9f5`, was 0.1.7 —
   which is why four tests abstained twice in one day under two different
   installed normalizers. From a consumer's side 0.1.4–0.1.7 arrive as one
   signature move, and the release notes are the only place the pieces are
   separable.

   **The granted part.** §6's `street_num` ask said the 59 wanted a fix one
   layer down rather than a third key spelling, and K3 was rejected here
   because only 410 of its 2,278 merges touched the hyphenated case. 0.1.7 made
   that fix, and upstream then measured it over matchdb's **22,026,817-row**
   address table rather than our 3.88M: the join **merges 7,583 EIN-level
   address groups and splits 1,496**. That 1,496 is the join *isolated*, by
   re-deriving with and without the house-number join, and is the figure to
   cite for what the rule itself does. Two other counts are in circulation and
   are not interchangeable with it: **1,499** is the 0.1.3 → 0.1.8 diff,
   carrying four releases, and **1,490** was an artifact of a narrower
   candidate set that missed 127 strings and six groups, now withdrawn.

   **Cite the split verdict in its weaker form, which is the supported one.**
   `NEWS.md` says every one of those splits is "a single address filed two
   ways, with 0 of them two different streets". Asked what that rested on, the
   author's answer was neither a reading of the addresses nor a check on
   `street_num`: it is separator-insensitive string identity, in two tiers —
   505 groups whose raw strings are identical once every non-alphanumeric is
   removed, 994 whose 0.1.8 `street_key`s are identical once spaces are
   removed, 0 neither. That classification was run over the **1,499** diff set,
   not the isolated 1,496. Same characters in a different arrangement does not
   establish one building, and a re-run for the shape where it cannot — a bare
   number or letter plus a street type and nothing else — found **20 of the
   1,499** are that shape (`1049 - 38 Street` against `1049 38 ST STE 400`,
   `436-15 ST` against `436 15 Street`). So: **0 differ in anything beyond
   separators, and for 20 of them that does not settle which street.**

   *Status of the upstream text, 2026-11-02:* the stronger wording is corrected
   in **[npnormalize#20](https://github.com/Nonprofit-Open-Data-Collective/npnormalize/pull/20)**
   — open, mergeable, blocked on five R-CMD-check platforms, branch
   `fix/weaken-split-claim`, 11 files. `main` still carries "none of them two
   different streets", so cite #20 rather than the released note, and cite it
   as open rather than landed. Verified here against the PR's own diff, not
   from the description: `NEWS.md`, `R/normalize.R`, `README.md`, the pkgdown
   docs and `tests/testthat/test-address.R` (+23).

   **The refused part, and it is the half we should stop asking for.** The
   *narrow* version of K3 — allow a space only where the join wants a hyphen,
   i.e. the leading house number alone, which is strictly safer than a blanket
   space strip — was measured over the same table under the same compass
   exclusion. It looks good in aggregate and is wrong in the particular: splits
   fall to 334 and merges rise to 10,232, but it moves **92,797 further
   strings, and those strings are street names** — `5001 11 MILE RD` →
   `500111 MILE RD` (11 Mile Road, Michigan), `712 H STREET NE` → `712H ST NE`
   (H Street NE, DC), `17398 M 86` → `17398M86` (M-86, a state highway),
   `1801 C ST` → `1801C ST`. **17,614** of them are a house number followed by
   a bare numeric or single-letter street name, which is the shape no rule can
   tell from a hyphenated house number: `101 B FOREST DR` is house 101B and
   `101 B ST` is house 101 on B Street, and nothing in either string says
   which.

   **So: do not revisit K3, blunt or narrow, and withdraw the §6 ask.** The
   residual 49 here are spacing in the *filed* text — `2200 S W 10TH` against
   `2200 SW 10TH`, `1147CENTRALAVE` against `1147 CENTRAL AVE`, `C/O` against
   `CO` — and **47 of the 49 contain no hyphen anywhere**, so no separator rule
   upstream can reach them by construction.

   **And the 22M-row result is silent about those 47, necessarily.** Only the
   hyphen join moved those keys, so a pair with no hyphen in either spelling
   was never in the 1,496: **0** of the split groups are hyphen-free. Nothing
   in that measurement bears on 47 of our 49, and this note should not borrow
   its authority for them.

   **Do not take `NEWS.md`'s `street_num` remedy at face value: measured here,
   it does not work for the case it is offered for.** The note says a consumer
   that would rather have the merges "can key on the house number itself —
   `street_num` is now the whole number on both spellings." Probed against the
   installed 0.1.8 in this repo:

   | street | `street_key` | `street_num` |
   |---|---|---|
   | `70-11 150TH STREET` | `7011 150TH ST` | `7011` |
   | `70 11 150TH STREET` | `70 11 150TH ST` | `70` |
   | `1049 - 38 STREET` | `104938 ST` | `104938` |
   | `1049 38 STREET` | `1049 38 ST` | `1049` |
   | `875-A ISLAND DRIVE` | `875A ISLAND DR` | `875A` |
   | `875 A ISLAND DRIVE` | `875 A ISLAND DR` | `875` |

   `street_num` carries the whole house number on the **hyphenated** spelling
   only; on the spaced spelling it carries the leading token, so it *disagrees
   across every split the remedy is meant to close* — the author confirms it
   disagrees in all ~1,500 by construction. Keying on `street_num` reproduces
   the split rather than closing it. It does merge the hyphenated spelling with
   the closed-up one, which `street_key` already merges, so it buys nothing we
   do not have. **Nothing here should be built on that remedy without
   measuring it first.**

   The remedy is **removed** upstream in npnormalize#20, with this probe in its
   place, and the asymmetry is pinned there as a test — `street_num is the
   whole number on the hyphenated spelling only (#16)`, asserting
   `c("7011", "70", "875A", "875")` and that the compass pair agrees on
   `street_key` as well, so `street_num` buys nothing even there. Read off that
   PR's diff. Until it merges, the released `NEWS.md` still offers the remedy,
   which is the version a reader of the installed package sees.

   **One pair went the other way, and it is the same rule read backwards.**
   `875-A ISLAND DRIVE` now keys to `875A ISLAND DR` while the same address
   filed as `875 A ISLAND DRIVE` keeps its space. Net 11 merged, 1 split. Both
   exemplars are pinned in the parity test, so the next upstream move is
   readable in the same terms rather than as a count that changed.

   *Corrected the same day, and the rule is narrower than the sentence above
   first said.* It read "a hyphen is now deleted where a space in that position
   is kept", as a blanket rule. Probed against the installed 0.1.8: the hyphen
   is deleted before digits (`70-11` → `7011`) and before a lone **non-compass**
   letter (`875-A` → `875A`, `57-C` → `57C`, `1801-C` → `1801C`), but before a
   lone **compass** letter it still becomes a space (`1002-E SENECA ST` →
   `1002 E SENECA ST`, `100-N 6TH ST` → `100 N 6TH ST`) — which is what keeps
   it agreeing with the spaced spelling of the same door instead of inventing
   the house number `1002E`. The carve-out moves nothing in this corpus: it
   holds **0** digits-hyphen-compass pairs and 4 digits-hyphen-letter pairs, 1
   of which splits, so no count above changes. Recorded because the rule is
   what a reader carries away from this block, and the count is not.

   The 49 that remain contain **no hyphen at all in 47 of them**, which is the
   substantive reason a separator rule upstream cannot reach them and K3's
   space-blindness is the only thing that would — at the price measured below.

   The BMF figures in the K1/K2/K3 table above are **not** re-measured and
   still carry npnormalize 0.1.6. They are the reason to adopt K2, which has
   not changed; but the 0.08% split rate and the 410 hyphenated merges are
   0.1.6 quantities, and the hyphen rule is exactly what moved. Re-running
   `dev/measure-addr-key-spellings.R` under 0.1.8 would make the K3 rejection
   current as well as correct. Not done.

   **Call npmatch's function; do not port it.** matchdb ported only because it
   needs SQL macros, and even then it pins the port with a parity test against
   `.np_addr_key()` on 4,000 random rows covering every PO-box spelling.
   pfmatch already `Imports: npmatch`, so it has no such excuse. Three
   implementations of one address key is the state this note exists to prevent.
   *Check:* the group count moves as measured, and the key is byte-identical to
   npmatch's on addresses where nothing should change.

   ~~**Revised 2026-10-31, and it reverses which route to take.**~~
   **Reversed back, 2026-11-01, and this time the route it recommended is
   gone.** That revision said to use `npmatch:::.np_addr_key()` rather than the
   export, because the installed npmatch did not import npnormalize and the
   export therefore meant a second copy of the whole normalizer. The installed
   npmatch is now 0.1.1.9000 and *does* import npnormalize (>= 0.1.3): there is
   one copy, it is npnormalize's, and `npmatch:::.np_addr_key()` fails with
   *"object '.np_addr_key' not found"*. pfmatch also already
   `Imports: npnormalize (>= 0.1.5)` on `main` for `np_has_box()`, so the
   dependency this step would have had to justify is already declared.

   **So: `npnormalize::np_addr_key()`, and mind what it takes.** Its signature
   is `np_addr_key(street_keys, zip5)` and its body pastes the two together and
   blanks the result for a PO-box or mail-only street. It normalizes nothing.
   Handed a raw `ADDR_L1` it returns `100 MAIN STREET 12210` against
   `100 MAIN ST 12210` — the very split this step exists to remove. Handed
   `street_key` from `np_normalize()`, all three of `100 MAIN STREET`,
   `100 MAIN ST` and `100 MAIN STREET SUITE 3` collapse to
   `100 MAIN ST 12210`. Normalize first, then key. The parity test is still
   what makes the switch safe, so it is still the first thing to write.

   Measured cost of the current hand-rolled key, beyond the 22.7% above: it
   keys on raw `ADDR_L1` with `gsub("[^A-Z0-9]", "")`, so it never gets USPS
   suffix contraction and splits renderings npmatch unifies —
   `100 MAIN STREET` → `100MAINSTREET|12210` against `100 MAIN ST` →
   `100MAINST|12210`, where the npmatch route gives `100 MAIN ST 12210` for
   both. Its PO-box test (`^P?O?BOX|^POST`) is also weaker than npmatch's.

   *One attribution corrected, 2026-11-01:* that unification is
   `np_normalize()`'s doing, not `np_addr_key()`'s. The earlier wording here —
   and in commit `5f528b3` — credited `.np_addr_key()` with the USPS suffix
   contraction, which it has never done; it joins an already-normalized
   `street_key` to the zip. The measured conclusion is unchanged, only the
   mechanism: what the hand-rolled key skips is `street_key`.
5. **Classify the groups with `np_addr_freq()` over the grant corpus.** Replace
   `flag_shared` and the `n_names < 25` filter with `addr_class`, keeping the
   raw counts in the queue beside it. Note the §2 caution on thresholds
   calibrated against filings rather than grant rows. *Check:* the classes land
   where §2 predicts — fiscal sponsors as `shared`, chapter networks as
   `federated`, the suite-conflict cases as `building`.
5a. ~~**Carry `addr_freq` on the reference and pass it to the comparer.**~~
   **Mostly moot, and the rest is not implementable as written. Rewritten
   2026-10-31 after reading `np_cascade()`'s body.**

   The original step said `pf_build_reference()` should gain an `addr_freq`
   element and `pf_match_grants()` should "pass it through". It cannot:
   **`np_cascade()` has no `addr_freq` parameter.** What it does instead is
   compute the statistic itself, once, before the pass loop:

   ```r
   addr_freq <- np_addr_freq(r$street_key, r$zip5, r$street_unit_id, r$name_key)
   ```

   and hand it to `np_compare()` on every pass. Note what is *missing* beside
   it: `name_freq`, `token_idf` and `ref_index` each sit behind an
   `if (is.null(...))` guard and each has a parameter, so a caller can supply
   them. `addr_freq` has neither.

   So pfmatch has had the whole address-frequency layer since the npmatch
   install, for free, without writing a line. Verified by running a cascade
   through `pf_default_passes()` on a synthetic multi-unit building: the pairs
   come back carrying `geo_unit`, `addr_shared`, `addr_units`,
   `addr_unit_shared`, `addr_unit_coverage` and `addr_note`, with
   `addr_units = 6` for a six-suite address. Nothing to adopt.

   **What is actually left is a cost, not a capability.** Because the statistic
   is recomputed per `np_cascade()` call and `pf_run_batches()` calls it once
   per batch, the whole-reference `np_addr_freq()` runs once for every batch —
   on the order of 40 times over a 1M-identity run against a 1.9M-row
   reference, for a value that cannot change between batches. The fix is
   upstream, not here (see §6): an `addr_freq =` parameter with the same
   `is.null()` guard its three siblings already have. Until then
   `pf_build_reference()` gaining an `addr_freq` element would have nowhere to
   send it.

   The same gap closes off tuning: `share_min` and `unit_coverage_min` take
   `np_addr_freq()`'s defaults (10L and 0.5) and are not reachable through the
   cascade either, which is exactly the §2 caution about thresholds calibrated
   on filings rather than grant rows. That caution is now a blocked item, not a
   choice pfmatch is making.
6. **Restrict the silver labels by class.** `cluster` yields labels;
   `building` only where the suite agrees; `shared` and `federated` are
   reported, not labelled. *Check:* re-measure what fraction of
   `PF-TRUTH-V2-TRIANGULATED.csv` survives, and say so in the artifact's note.
   This will shrink the set, and that is the point.
7. **Decide whether pfmatch reads matchdb bundles.** It already ships:
   `md_reference()` returns `addr_freq` (class `np_addr_freq`) and `places`,
   and every bundle carries `addr_freq.parquet` over its own rows. pfmatch
   builds its own reference from a BMF CSV via `pf_build_reference()`, so it
   gets none of it for free — step 5a is the alternative, computing the same
   object locally. The richer half is only available by reading bundles:
   matchdb's `place_flags` (`flag_care_of`, `flag_bank_trust`, `flag_cmra`,
   `flag_group_confirmed`, `flag_agent_churn`, `flag_military_or_gd`), the
   occupancy history behind `churn`, and `building_id` from rooftop geocodes
   are signals npmatch cannot reach at run time and pfmatch cannot compute at
   all. Those name exactly the addresses whose triangulation groups are
   spurious — the "fiscal sponsors, DAF custodians and bank trust departments"
   the `n_names < 25` filter is a blunt stand-in for. *Check:* if both routes
   are available, they agree over the same population.

   Precedent worth following: matchdb now forms a `co_tenant` cluster **only**
   at a plain `cluster` place without the care-of, mailbox-store, bank-trust or
   churn flags. That is the same move step 6 proposes for pfmatch's silver
   labels, made by the package that owns the evidence.

Steps 1–3 are maintenance and should happen together with the reinstall. Steps
4–6 are a redesign of the triangulation set and want their own measurement
pass; 7 waits on matchdb.

---

## 5. The slice footgun applies here too

matchdb's note calls out that `np_addr_freq()` counts over "whatever frame is
passed, so a state partition or a shard silently under-counts every shared
address". pfmatch runs `pf_run_batches(batch_size = 25000L)` — the **query** is
sliced, four batches on the last run. Reference-side counts are safe, because
the whole reference goes to every batch. Query-side counts are not: if the
triangulation group counts were ever computed inside the batch loop, every
group would be under-counted and every class wrong. Compute them once over the
whole grant corpus, as `build-group-index.R` already does, and pass them in.

---

## 6. What to feed back upstream

* ~~**Second matchdb's ask**~~ (`PLACES.md` §8.2) that npmatch export
  `np_addr_key()`, `np_unit_id()` and `np_addr_class()` with its thresholds.
  **Partly granted.** With the normalizer's move into npnormalize (0.1.1), that
  package exports `np_addr_key()` and `np_unit_id()` alongside
  `np_addr_freq()`. Still internal: `.np_addr_class()` and `.np_extract_unit()`.
  So step 4 can call `npnormalize::np_addr_key()` rather than a port or a
  `:::`; step 5 still cannot reach the class rule.
  ~~**Qualified 2026-10-31:** only once pfmatch is on an npmatch that imports
  npnormalize.~~ **The qualification is void, 2026-11-01.** npmatch 0.1.1.9000
  imports npnormalize (>= 0.1.3), so there is no second copy to depend on and
  `npmatch:::.np_addr_key()` no longer exists. `np_extract_unit()` has since
  been exported as well, which was the second half of the ask below; of the
  three functions matchdb asked for, only the class rule
  (`npnormalize:::.np_addr_class`) is still internal, so step 5 still cannot
  reach it.
* ~~**Ask for `.np_extract_unit()`, or for a documented unit entry point.**~~
  ~~**Report the spelled-out `BUILDING` gap.**~~ **Both filed 2026-10-31 as
  [npnormalize#7](https://github.com/Nonprofit-Open-Data-Collective/npnormalize/issues/7)**,
  with the `street_unit_id` comparison point below and two further items. Kept
  here in summary because the asks are pfmatch's and the issue may be closed
  with only some of them taken.

  **Closed, with both asks taken — measured on npnormalize 0.1.6, 2026-11-01.**
  `BUILDING` is in `.np_unit_pat`, so the two spellings below now agree:
  `100 CAMPUS CENTER BUILDING 86E` and `100 CAMPUS CENTER BLDG 86E` both give
  `street_key` `100 CAMPUS CENTER` with unit `BLDG 86E` and id `86E`.
  `np_unit_id()` is gated: `NA` for `PO BOX 1367`, `BOX 19960`,
  `114 HIGH ST`, `LAS VEGAS`, `C/O JOHN SMITH`, `NORTH TOWER` and `400891`,
  `400` for `STE 400`. `np_extract_unit()` is exported. The box flag asked for
  in §4 of the issue arrived as `np_has_box()` in 0.1.5 and `99fdf70` adopted
  it, deleting `.PF_BOX_RE`. The two items below are kept as the record of what
  was reported; neither describes the installed normalizer any longer.

  * The exported `np_unit_id()` takes an *already extracted* unit and only
    strips the designator, so on a raw `ADDR_L2` it returns nonsense with no
    signal: `BOX1367` for `PO BOX 1367`, `114HIGHST` for `114 HIGH ST`,
    `VEGAS` for `LAS VEGAS`, `OJOHNSMITH` for `C/O JOHN SMITH`. (This note
    previously said `1367` for the first; that was wrong, and the real answer
    is worse.) The gate that makes the field usable is `.np_unit_pat` inside
    `.np_extract_unit()`, which is internal. `pf_street_unit()` therefore goes
    the long way round, handing a one-column frame to `np_normalize()` just to
    read `street_unit` back out. That works, is deliberately the public path,
    and has the real advantage that pfmatch reads the suite exactly as the
    matcher does — so we intend to keep it either way.
  * `.np_unit_pat` carries `BLDG` but not `BUILDING`, while carrying
    `APARTMENT`, `SUITE`, `FLOOR`, `SPACE`, `ROOM` and `NUMBER` beside their
    abbreviations. **The mechanism, found on re-reading `np_normalize()`:**
    `.np_extract_unit()` runs at body line 25 and `.np_street_key()` only at
    line 27, so extraction reads the *raw* street while the
    `BUILDING -> BLDG` contraction in `.np_street_types` happens afterwards —
    the unit pattern never sees the spelling it knows. The cost is not one
    lost value but a split: `100 CAMPUS CENTER BUILDING 86E` keys to
    `100 CAMPUS CENTER BLDG 86E` with **no** unit, while
    `100 CAMPUS CENTER BLDG 86E` keys to `100 CAMPUS CENTER` with unit
    `BLDG 86E`. Two renderings of one address disagree on both outputs and
    will not block together.
* **Ask for `addr_freq =` on `np_cascade()`.** `np_compare()` takes it;
  `np_cascade()` does not, and computes it internally with no `is.null()`
  guard — unlike `name_freq`, `token_idf` and `ref_index`, which all have a
  parameter *and* a guard. A batched caller therefore recomputes a
  whole-reference statistic once per batch (≈40 times over a 1M-identity run)
  for a value that cannot change, and cannot reach `share_min` /
  `unit_coverage_min` at all. The asymmetry with its three siblings looks like
  an oversight rather than a decision. See step 5a.
* ~~**Report the hyphenated house number: a space is inserted inside it, and
  `street_num` keeps only the part before the hyphen.**~~ **Filed 2026-11-02 as
  [npnormalize#16](https://github.com/Nonprofit-Open-Data-Collective/npnormalize/issues/16).**
  Measured over `REF-augmented.rds`: **6,459 of 3,880,431 rows (0.166%)** carry
  one, and they are not a curiosity — Queens (`77-06 BROADWAY`), Hawaii
  (`91-400 KOMOHANA`, `41-1347 KALANIANAOLE HWY`, `73-4460 QUEEN KAAHUMANU
  HWY`) and Chicago ranges (`5830-5832 W LAWRENCE AVE`) all write addresses
  this way. Kept here in summary because the ask is pfmatch's and the issue may
  be closed with only part of it taken. **Three** consequences, not the two this
  note first listed — writing the issue turned up the third:

  * `street_key` becomes `77 06 BROADWAY`, which does not block with the same
    address filed `7706 BROADWAY`. That is what the 59 splits in step 4 are
    made of, and 410 such twin groups exist across the BMF.
  * `street_num` is `77` for `77-06 BROADWAY` and `73` for
    `73-4460 QUEEN KAAHUMANU HWY` — a house number truncated at the hyphen,
    which anything keying or comparing on `street_num` inherits.
  * `street_name` absorbs the remainder: `06 BROADWAY` for `77-06 BROADWAY`,
    `4460 QUEEN KAAHUMANU HWY` for the Kona address, `11 150TH` for
    `70-11 150TH STREET`. The street *name* is wrong, not merely truncated,
    so anything comparing `street_name` is affected as well as the key. The
    hyphen survives nowhere in the frame — no `street_key` or `street_num`
    contains one.

  **Ask:** treat a hyphenated house number as one token — either strip the
  hyphen (`7706`) or keep it (`77-06`), consistently, and let `street_num`
  carry the whole thing while `street_name` starts at the real name. Stripping
  is the choice that serves the filings, since it makes the two spellings one
  key, which is the same reasoning as the USPS suffix contraction already
  applied. pfmatch is not patching this locally; the measurement says a local
  space-blind key costs more than it recovers (step 4), so the fix belongs
  upstream or nowhere.
* **Ask for `np_name_key()`, beside `np_addr_key()`.** There is no public
  single-vector name key: `np_name_core()`, `np_name_rules()`, `np_name_freq()`
  and `np_name_placeholder()` are exported, but a `name_key` can only be had by
  normalizing a frame. Seven pfmatch scripts therefore chained
  `.np_basic_clean`, `.np_replace_tokens`, `.np_abbrev`, `.np_strip_suffix` and
  `.np_strip_lead_the` through `:::`, and all seven broke when those moved to
  npnormalize — repointed 2026-11-01, and verified to reproduce
  `np_normalize()`'s `name_key` exactly. Same shape as the `np_unit_id()` gate
  in npnormalize#7: the exported surface serves the matcher, and a consumer who
  wants one column goes around it.
* **Report the grant-side use case.** npmatch's `addr_class` is documented over
  a reference frame. pfmatch wants it over a query corpus, where "records" are
  grant rows written by third parties rather than filings by occupants —
  `top_name_share` and `unit_coverage` may not behave the same way. Worth
  saying before the thresholds are fixed.
* **Confirm the saturation result.** `9d87e3d` reached the same conclusion about
  the geo `max()` ladder from the triangulation corpus that npmatch reached from
  304,274 labelled pairs. Two independent routes to one answer is worth
  recording in npmatch's note.
* **Report the two bad designators as a found defect, not a preference.**
  `R/unit.R` listed `NO` and `OFC`, which npmatch's BMF scan excludes for
  measured reasons. pfmatch found them independently by shipping them and is
  evidence the exclusions are right, which is worth saying while the designator
  table is still new. (The local table is now deleted; the finding stands.)
* **Report that `street_unit_id` is the wrong thing to compare for a reviewer
  flag.** `np_compare()` compares `street_unit_id`, which drops the designator,
  so `FL 2` and `STE 2` score as the same door. At 0.97 in a `max()` ladder
  that is cheap — the credit is simply given. Surfaced to a human as
  "the suites agree" it is a false reassurance nobody re-checks, which is why
  `pf_unit_evidence()` compares the canonical `street_unit` with only the
  room-level designators folded. Worth upstream knowing that the annotation and
  the score may want different comparisons.

---

## 7. Tripwires

* `tests/testthat/test-variants.R` pins every recorded key to
  `np_normalize_signature()` and **skips** with a rebuild instruction when it
  moves. A skip there means npmatch changed under us.
* `tests/testthat/test-unit.R` caps `conflict` at 2% of pairs ungated, and
  asserts `pf_unit_evidence()` reproduces `pf_variants$unit_evidence` under the
  fixture's own normalizer — signature-gated since the parse became npmatch's,
  so it skips while the fixture is stale.
* `.pf_check_stamp()` refuses a checkpoint whose stamped normalizer differs.
* `pf_check_reference()` stops on a reference bundle from a different
  normalizer and warns on an unstamped one (§4.1). ~~`REF-augmented.rds` is
  currently in the warning case~~ — **it is in the stopping case, 2026-11-02:
  stamped `v1-3e7b9f9d59bbb19e` against an installed `v1-d49b18cc81ab79fb`, so
  it does not warn, it halts the run.** That is the tripwire paying for itself;
  see the note under §3a for the transcript.
* **Still missing:** nothing tells you that *matchdb* or *npmatch* moved. Both
  tripwires above fire only on a local reinstall. Checking
  `gh pr list --repo Nonprofit-Open-Data-Collective/npmatch` and matchdb's
  `dev/PLACES.md` status line is still a manual step, and the first pass of
  this note went stale within a day for exactly that reason.
