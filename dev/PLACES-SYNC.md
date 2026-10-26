# Places: staying in step with npmatch's address classes and matchdb's place tables

**Status: plan, 2026-10-26. Nothing here is built, and nothing is broken yet.**

Two upstream changes land on the same ground pfmatch's triangulation stands on:

* **npmatch PR #18, merged 2026-10-26** — "Normalizer: fold special letters,
  parse the suite, classify shared addresses". Moves
  `np_normalize_signature()` to **`v1-77a3842ce517e353`**, parses the suite into
  `street_unit_id`, adds `np_addr_freq()` and an `addr_class`, gives
  `.np_hier_score()` a unit term, and annotates every candidate pair for the
  reviewer. (PR #19 was folded into it.)
* **matchdb `dev/PLACES.md`, 2026-10-26** — a proposal to precompute place
  crowding, class and evidence per address, published per bundle as
  `addr_freq.parquet` plus a `place` / `place_layer` / `place_unit` sidecar.

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

The installed npmatch is **pre-PR**:

| | installed here | after PR #18 |
|---|---|---|
| `np_normalize_signature()` | `v1-6dcb298522cc5118` | `v1-77a3842ce517e353` |
| `np_addr_freq()`, `np_addr_class()` | absent | present |
| `street_unit_id` | absent | present |
| `geo_weights` has a `unit` term | no | yes, `0.97` |

So every claim pfmatch currently makes about npmatch is true *of the build on
this machine* and stops being true the moment someone runs
`remotes::install_github(...npmatch)`. That is the whole risk: not a gradual
drift but a step change on one `install` call, touching the reference cache,
the fixture, two dev notes and three commit messages at once.

Nothing needs doing until that install. Everything below is what to do when it
happens, and §2 is worth reading before it does.

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

**One subtlety that must not be glossed.** npmatch computes `addr_class` over
the **reference** frame (the BMF). pfmatch's triangulation groups live on the
**query** side (grant rows). These are different measurements of the same
street: the BMF knows who *files* from it, the grant file knows who a foundation
*paid* there. Both are wanted and neither substitutes for the other —
`np_addr_freq()` over the grant corpus classifies the triangulation group, while
the BMF-side class is evidence about the anchor. Do not join one and call it the
other.

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

1. **Stamp the reference bundle.** Add the signature to
   `pf_build_reference()`'s output and refuse a mismatch on load, reusing
   `.pf_check_stamp()`. *Check:* a bundle built under the current normalizer
   loads; the same bundle with the attribute tampered is refused.
   **Do this before reinstalling npmatch.**
2. **Reinstall npmatch and rebuild the reference.** *Check:*
   `np_normalize_signature()` reads `v1-77a3842ce517e353`; the rebuilt
   `REF-augmented.rds` loads; `PF_SET=1k` is re-measured and the change recorded
   — expect movement, since `street_key` changes on 1.78% of rows.
3. **Retire `pf_parse_unit()`.** Follow `dev/UNIT-UPSTREAM-SYNC.md` §4: diff the
   upstream parser against `pf_variants`' 5,410 recorded verdicts and the
   queue's 121 conflicts first, then delete `R/unit.R`, keeping
   `test-unit.R` pointed at the new entry points. Align the evidence vocabulary
   to npmatch's (`geo_unit`, `addr_shared`, `addr_units`, `addr_unit_shared`,
   `addr_note`) rather than keeping pfmatch's four values beside them.
   *Check:* every verdict that changes is traced to one of the designator
   decisions, `NO` and `OFC` among them.
4. **Adopt `street_key` as the triangulation group key.** This is the change
   worth the most. pfmatch's key differs from npmatch's `place_key` in three
   ways, the same three matchdb's note lists for its own `ein_key`: a raw
   `gsub("[^A-Z0-9]", "", toupper(ADDR_L1))` instead of `street_key`, a `|`
   separator instead of a space, and a regex PO-box test instead of
   `is_po_box`. Measured cost of the first alone: 528,862 of 2,326,459 address
   keys (22.7%) are redundant spellings, and 58,815 addresses never reach the
   two-rendering threshold because their spellings never meet. PR #18 makes this
   better still — `street_key` now also strips the suite, so grouping by
   `street_key` and discriminating by `street_unit_id` is the clean split
   pfmatch's hand-rolled version was groping toward. *Check:* the group count
   moves as measured; `np_addr_key()` output equals pfmatch's key for addresses
   where nothing should change.
5. **Classify the groups with `np_addr_freq()` over the grant corpus.** Replace
   `flag_shared` and the `n_names < 25` filter with `addr_class`, keeping the
   raw counts in the queue beside it. *Check:* the classes land where §2
   predicts — fiscal sponsors as `shared`, chapter networks as `federated`,
   the suite-conflict cases as `building`.
6. **Restrict the silver labels by class.** `cluster` yields labels;
   `building` only where the suite agrees; `shared` and `federated` are
   reported, not labelled. *Check:* re-measure what fraction of
   `PF-TRUTH-V2-TRIANGULATED.csv` survives, and say so in the artifact's note.
   This will shrink the set, and that is the point.
7. **Consume matchdb's `addr_freq` when it ships.** pfmatch builds its own
   reference rather than reading matchdb bundles, so it will not get
   `r$addr_freq` for free. Decide then whether pfmatch reads matchdb bundles or
   keeps computing `np_addr_freq()` itself. *Check:* if both are available, they
   agree over the same population.

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
  `np_addr_key()` and `np_addr_class()` with its thresholds. pfmatch needs both
  for exactly the reason matchdb does: its triangulation key *should be*
  `np_addr_key()` output, and its group classes should come from npmatch's rule
  rather than a third copy of it. Three implementations of one address key is
  the state this note exists to prevent.
* **Report the grant-side use case.** npmatch's `addr_class` is documented over
  a reference frame. pfmatch wants it over a query corpus, where "records" are
  grant rows written by third parties rather than filings by occupants —
  `top_name_share` and `unit_coverage` may not behave the same way. Worth
  saying before the thresholds are fixed.
* **Confirm the saturation result.** `9d87e3d` reached the same conclusion about
  the geo `max()` ladder from the triangulation corpus that npmatch reached from
  304,274 labelled pairs. Two independent routes to one answer is worth
  recording in npmatch's note.

---

## 7. Tripwires

* `tests/testthat/test-variants.R` pins every recorded key to
  `np_normalize_signature()` and **skips** with a rebuild instruction when it
  moves. A skip there means npmatch changed under us.
* `tests/testthat/test-unit.R` asserts `pf_unit_evidence()` reproduces
  `pf_variants$unit_evidence` and caps `conflict` at 2% of pairs.
* `.pf_check_stamp()` refuses a checkpoint whose stamped normalizer differs.
* **Missing, and §4.1 adds it:** nothing guards the cached reference bundle.
  Until that exists, treat `REF-augmented.rds` as unsafe across any npmatch
  upgrade.
