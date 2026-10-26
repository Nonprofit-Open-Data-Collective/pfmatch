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
| normalizer signature | `v1-6dcb298522cc5118` | `v1-3e7b9f9d59bbb19e` |
| `np_addr_freq()` | absent | present, **exported** |
| `np_addr_key()`, `np_unit_id()`, `np_addr_class()` | absent | present, **not exported** |
| `street_unit_id` | absent | present |
| `geo_weights` has a `unit` term | no | yes, `0.97` |
| `np_compare(addr_freq = )` | absent | present |

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

### 3a. `REF-augmented.rds` is not signature-stamped — fix this first

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

### 3b. `pf_parse_unit()` is superseded, and is wrong on two designators

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
3. **Retire `pf_parse_unit()`.** Follow `dev/UNIT-UPSTREAM-SYNC.md` §4: diff the
   upstream parser against `pf_variants`' 5,410 recorded verdicts and the
   queue's 121 conflicts first, then delete `R/unit.R`, keeping
   `test-unit.R` pointed at the new entry points. Align the evidence vocabulary
   to npmatch's (`geo_unit`, `addr_shared`, `addr_units`, `addr_unit_shared`,
   `addr_note`) rather than keeping pfmatch's four values beside them.
   *Check:* every verdict that changes is traced to one of the designator
   decisions, `NO` and `OFC` among them.
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

   **Call npmatch's function; do not port it.** matchdb ported only because it
   needs SQL macros, and even then it pins the port with a parity test against
   `.np_addr_key()` on 4,000 random rows covering every PO-box spelling.
   pfmatch already `Imports: npmatch`, so it has no such excuse: use
   `np_addr_key()` once exported, or `npmatch:::.np_addr_key()` with the same
   parity test until then. Three implementations of one address key is the
   state this note exists to prevent. *Check:* the group count moves as
   measured, and the key is byte-identical to npmatch's on addresses where
   nothing should change.
5. **Classify the groups with `np_addr_freq()` over the grant corpus.** Replace
   `flag_shared` and the `n_names < 25` filter with `addr_class`, keeping the
   raw counts in the queue beside it. Note the §2 caution on thresholds
   calibrated against filings rather than grant rows. *Check:* the classes land
   where §2 predicts — fiscal sponsors as `shared`, chapter networks as
   `federated`, the suite-conflict cases as `building`.
5a. **Carry `addr_freq` on the reference and pass it to the comparer.** This is
   now a specified interface rather than a guess. `np_compare()` takes
   `addr_freq =` (verified on `origin/main`), and `np_addr_freq()` is the one
   place function npmatch exports. So `pf_build_reference()` should gain an
   `addr_freq` element computed over **exactly** the reference rows it returns —
   which is what `md_addr_freq()` does for a matchdb bundle and what
   `md_publish()` ships as `addr_freq.parquet` — and `pf_match_grants()` should
   pass it through. Reference-side counts are safe from the slice footgun in
   pfmatch because the whole reference goes to every batch (see §5). *Check:*
   `np_addr_freq()` recomputed over the bundle's reference equals the stored
   element exactly, the same round-trip check matchdb runs.
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

* **Second matchdb's ask** (`PLACES.md` §8.2) that npmatch export
  `np_addr_key()`, `np_unit_id()` and `np_addr_class()` with its thresholds.
  Confirmed still outstanding: `np_addr_freq` is the only one of the four in
  npmatch's `NAMESPACE` on main. pfmatch needs them for exactly the reason
  matchdb does — its triangulation key *should be* `np_addr_key()` output, and
  its group classes should come from npmatch's rule rather than a third copy of
  it. matchdb has already paid for a port and a parity harness; a second
  consumer asking for the same export is the argument for making it.
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
  `R/unit.R` lists `NO` and `OFC`, which npmatch's BMF scan excludes for
  measured reasons. pfmatch found them independently by shipping them and is
  evidence the exclusions are right, which is worth saying while the designator
  table is still new.

---

## 7. Tripwires

* `tests/testthat/test-variants.R` pins every recorded key to
  `np_normalize_signature()` and **skips** with a rebuild instruction when it
  moves. A skip there means npmatch changed under us.
* `tests/testthat/test-unit.R` asserts `pf_unit_evidence()` reproduces
  `pf_variants$unit_evidence` and caps `conflict` at 2% of pairs.
* `.pf_check_stamp()` refuses a checkpoint whose stamped normalizer differs.
* `pf_check_reference()` stops on a reference bundle from a different
  normalizer and warns on an unstamped one (§4.1). `REF-augmented.rds` is
  currently in the warning case and will stay there until it is rebuilt.
* **Still missing:** nothing tells you that *matchdb* or *npmatch* moved. Both
  tripwires above fire only on a local reinstall. Checking
  `gh pr list --repo Nonprofit-Open-Data-Collective/npmatch` and matchdb's
  `dev/PLACES.md` status line is still a manual step, and the first pass of
  this note went stale within a day for exactly that reason.
