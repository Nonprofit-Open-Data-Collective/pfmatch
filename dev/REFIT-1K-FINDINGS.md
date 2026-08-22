# The 1k refit run: what the cascade refinements did, and what they left broken

Run 2026-08-21 by `dev/probe-refit-1k.R`. Logs: `REFIT-1K.log` (profile arm),
`REFIT-1K-GATE.log` (baseline arm), `SHARD-MEMORY.log`.

**Why this run exists.** `BASELINE-2026-08` gates the cascade with `dyads = NULL`
— `build-baseline.R` calls `pf_match_grants()`, which has no `dyads` argument. The
last two code commits changed *only* the dyad path, and both were measured by
re-scoring a saved 50k pair set offline:

| commit | change |
|---|---|
| `0b28fd7` | `keep_soft_veto`, plus the `modifyList()` bug that discarded the reduced `pairs` attribute |
| `046a7b5` | default collapse policy `"operating"` → `"query"` |

Neither had run through the wired path — `pf_prepare` → `pf_link` →
`pf_run_batches` → `pf_dyad_collapse` → `pf_status` → `pf_propagate_matches` —
even once. **The frozen baseline cannot see a dyad regression by construction.**

17 checks: 8 pass, 4 fail, 5 reported without assertion.

---

## 1. The frozen baseline still reproduces, exactly

`PF_REFIT=gate`: five 1k files, no dyads, active reference, 11 passes.

| | |
|---|---|
| identities | 4,733 — matches the freeze |
| columns identical to `benchmark-1k-active.rds` | **24 / 24** |

HEAD is byte-identical to the pinned commit pair on the no-dyad path, as it should
be: nothing outside `R/dyads.R` and one benign `R/purpose.R` line has changed since
`d02a458`. The freeze is live and the gate works.

`testthat`: 78 assertions, 0 failures.

## 2. The three dyad refinements hold on the wired path

978 identities from `inputs/1k_grants_01.csv`, active reference, four collapse
configs applied to one scored match so the comparison isolates the policy.

| config | collapsed | YES | MAYBE | NO | MAYBE→YES |
|---|---:|---:|---:|---:|---:|
| baseline (no collapse) | — | 552 | 192 | 193 | — |
| **query / keepveto** (shipping) | 30 | 563 | 181 | 193 | **11** |
| operating / keepveto | 30 | 563 | 181 | 193 | 11 |
| query / **no** veto | 30 | 567 | 177 | 193 | 15 |
| top / keepveto | 30 | 560 | 184 | 193 | 8 |

* **Nothing is pushed into NO** — 0 demotions, and every tier change lands on a
  collapsed identity. The 50k and 1k dyad results replicate on a third sample.
* **The reduced pair set survives** (`0b28fd7`'s `modifyList` fix): 51,215 →
  51,181 pairs. Before the fix this attribute was silently reverted, and
  `pf_candidate_frame()` builds review sheets from it.
* **`keep_soft_veto` binds and costs 4 promotions here.** Exposure with the guard
  on: 0. With it off: 4 grants promoted MAYBE→YES where the baseline pick carried
  a soft veto *and* the reported EIN changed — the exact path `0b28fd7` closed,
  reproduced at 1k on 30 collapses.
* **The `query` policy fires twice and both are arm-named grants** — `PHOENIX
  CHILDREN'S HOSPITAL FOUNDATION` and `BOCA RATON REGIONAL HEALTH FOUNDATION`,
  0 switches on grants that do not name an arm. Tier differences vs `operating`:
  **0**. The policy moves the reported EIN and nothing else, as designed.

  Worth noting: in both switches the *BMF name* of the two EINs is identical to
  26 characters. These are reference-side duplicates as much as arm pairs —
  `dev/CLUSTER-FINDINGS.md` §8's problem showing up inside the dyad path.

## 3. Two defects the run found — **both fixed, and the fix re-measured**

Fixed the same day. `PF_REF=active Rscript dev/probe-refit-1k.R` re-run against
the fixed source (`REFIT-1K-POSTFIX.log`) returns **11 pass, 0 fail** against the
first run's 8 pass, 4 fail — the two remaining first-run failures were the cost
checks, which §4 shows were never regressions. Suite: 107 assertions, 0 failures,
including 22 new ones in `tests/testthat/test-batch.R`.

| | before | after |
|---|---|---|
| `status carries the documented dyad columns` | MISSING `dyad_alt_ein`, `dyad_class` | **all four** |
| `config change is refused, not silently ignored` | identical EINs from cache | **stops with a stamp mismatch** |
| `resume = FALSE recomputes under the new config` | — | 2 EINs differ, the two `query` switches |

That last row is the confirmation that matters: under `resume = FALSE` the
operating policy actually ran and moved exactly the two EINs §2 says it should.
Before the fix that recomputation never happened and the difference was zero.

### 3a. `pf_link()` silently returns a stale answer when the dyad config changes

**Reproduced.** Running `pf_link()` twice on the same checkpoint directory, the
second time with `policy = "operating"` instead of `"query"`, returns **EINs
identical to the first run**. The changed config was ignored; every batch came off
disk.

`R/batch.R:47` documents this — *"Changing `dyads` or `dyad_config` invalidates the
checkpoints in `dir`, which `resume` will otherwise happily reuse"* — but nothing
enforces it, and `resume = TRUE` is the default on both `pf_run_batches()` and
`pf_link()`. On a 1k run a wasted re-run costs five minutes. On the Phase 1 run it
costs a shard's worth of hours, or worse: a config change believed applied that was
not, in output nothing distinguishes from the real thing.

**Fixed.** Every checkpoint now carries a `pf_stamp` attribute — reference row
count and column set, normalizer signature, pass table, `np_config()`, `method`,
`recover`, `self_guard`, and the shape of `dyads` with its `dyad_config` — and
`pf_run_batches()` stops rather than resume across a mismatch, naming the setting
that differs. An unstamped checkpoint is refused for the same reason: it cannot
be shown to belong to this run.

The reference is summarised rather than hashed, deliberately. It is 2–4 GB
resident and hashing it per run would cost more than the batches the stamp
protects; row count plus column set plus normalizer signature catches every
change that can actually occur, and the case it cannot see — same shape, same
normalizer, different values — requires a rebuild that moves the row count. The
stamp costs 180 KB per checkpoint, which is per *batch*, not per identity:
~90 MB across the full run at `batch_size = 25,000`.

`resume` was also added to `pf_link()`, which did not have it. The guard's advice
is "pass `resume = FALSE`", and that has to be true of the wrapper people
actually call.

### 3b. The documented status contract is wrong

`R/batch.R:38` promises the status frame gains `dyad_collapsed`, `dyad_id`,
`dyad_alt_ein` and `dyad_class`. `.pf_attach_dyad_cols()` attaches
`dyad_collapsed`, `dyad_id` and **`dyad_from_ein`**. `dyad_alt_ein` and
`dyad_class` come from `pf_dyad_annotate()`, which the batch path never calls.

The doc named the more useful columns, so the code was brought up to it rather
than the doc down: `pf_dyad_collapse()` now emits `dyad_class` and
`dyad_alt_ein`, and `.pf_attach_dyad_cols()` carries all four through.

The distinction is load-bearing and worth stating. `dyad_from_ein` is the EIN
that *was* reported, and it fills in **only when the collapse changed the pick**;
`dyad_alt_ein` is the member merged away, and it fills in on **every** merge. On
this sample the pick changed on 2 of 30 merges, so `dyad_from_ein` alone loses
93% of them — and a rollup keyed on the reported EIN needs all 30.

## 4. Cost: the per-1,000 figure is a function of batch size, and the plan's is pessimistic

| run | n | reference | s per 1,000 |
|---|---:|---|---:|
| this run | 978 | active | **228** |
| `DEVELOPMENT-PLAN` Phase 1 table | 1,000 | active | 149 |
| determinism runs | 4,733 | active | 95–113 |
| **this run, gate arm** | **4,733** | **active** | **81** |
| this run | 978 | augmented | **392** |
| `DEVELOPMENT-PLAN` Phase 1 table | 1,000 | augmented | 279 |

The same code, same reference, same day: **81 s/1k at 4,733 identities and 228 s/1k
at 978 — 2.8x.** The cascade pays a fixed per-call cost over the whole reference
(key construction, index alignment, per-pass setup) that amortizes over the query
set. Every published per-1,000 figure on this project was measured at n ≈ 1,000 and
therefore **overstates production cost, where `batch_size = 25,000`.**

This does not reopen `dev/REF-PERFORMANCE.md` — that memo's subject was thread
count, and its conclusion stands. It adds a second amortization axis that no
measurement has controlled for.

> **SUPERSEDED 2026-08-22 — the table below is wrong in both directions.**
> `dev/SHARD-AND-COLLAPSE-FINDINGS.md` measured the augmented reference directly
> instead of extrapolating: **366 s/1k at 2,000 identities and 433 at 8,000** —
> it gets *slower* at larger n, where the active reference gets 2.8x faster. Two
> references with opposite scaling cannot be related by a constant ratio, which
> is exactly what the 139 s/1k figure below does. And the shard rows assume a
> parallelism that does not exist: a shard peaks at ~37 GB flat in batch size, so
> **one** fits in 68 GB, not four or eight. Recosted single-stream at 433 s/1k:
> 406 h at the best dedup figure on record, 1,142 h at the 1.323x measured on
> 100k. Retained below as written, because the reasoning that produced it is the
> point of §5's warning.

Carrying the augmented/active ratio measured at n = 978 (1.72x) onto the gate's
81 s/1k gives ≈ **139 s/1k for the augmented reference at production batch size**:

| | no dedup | at 1.8x dedup |
|---|---:|---:|
| 12,559,051 grants, augmented, 11 passes | 485 h | **269 h** |
| on 4 concurrent shards | 121 h | **67 h** |
| on 8 concurrent shards | 61 h | **34 h** |

Against a 117 h budget, four shards clear it and eight clear it comfortably —
*if* four to eight shards fit in memory, which is §5.

**Recall is unchanged and the augmented reference's gain replicates:** 552 → 595
YES on 978 identities, **+43 YES per 1,000**, the same figure
`dev/REF-PERFORMANCE.md` published — this time on `REF-augmented.rds` itself
rather than the geocoded CSV `BASELINE-2026-08/MANIFEST.md` flagged as the wrong
artifact. It costs 2.5x the candidate pairs (51,215 → 126,881) for 2.02x the rows.

## 5. Memory, not cores, sets the shard count — **and the answer is one**

> **ANSWERED 2026-08-22**, and the section's premise was right while its guess at
> the mechanism was wrong. A shard peaks at **~37 GB, flat in batch size** —
> 36.82 GB at 2,000 identities against 37.41 at 8,000 — so **one shard fits in
> 68 GB**, at `batch_size = 25,000` or any other. The ~33 GB above the bundle is
> a *fixed* cost, not the batch-proportional one this section assumed, so
> shrinking batches does not buy shards. `dev/SHARD-AND-COLLAPSE-FINDINGS.md` §1.


`dev/SHARD-MEMORY.log`. One process per shard means one resident reference per
shard:

| bundle | disk | resident | of which `reference` |
|---|---:|---:|---:|
| `REF-active.rds` | 1.43 GB | 2.28 GB | 1.60 GB |
| `REF-augmented.rds` | 2.84 GB | **4.21 GB** | 2.96 GB |

The bundle is the small part. Peak R memory **inside one process** during the 1k
profile was **14.1 GB on active and 26.5 GB cumulative on augmented** — the
blocking joins, not the reference, dominate. At 978 identities.

`pf_run_batches()` defaults to `batch_size = 25,000`: **25x this run's query set,
and nothing has measured the working set there.** The Phase 1 plan's "up to ~12x on
24 cores" is a core count, not a memory budget. On 68 GB, 12 augmented shards need
50 GB of references before a single join allocates.

**This is the one blocking unknown for Phase 1, and it is a two-hour measurement:**
one shard, augmented reference, `batch_size = 25,000`, peak RSS recorded. Do it
before committing a schedule.

## 6. Incidental

* **Dedup on this sample is 1.002x** — 1,000 rows, 978 identities. Consistent with
  `dev/FUNDER-PROFILE-FINDINGS.md` §3: random grants means one grant per filer, so
  nothing repeats. The full-file ratio is still unmeasured and it is the single
  number the Phase 1 schedule most depends on.
* **Checkpoint footprint is negligible**: 0.4 MB per 978 identities → ~5 GB across
  12.56M grants. Not a constraint.
* **A saved `pf_match` is 40 MB at 1k active, 97 MB at 1k augmented**, almost all
  of it the `pairs` attribute. `dev/DETERMINISM-FINDINGS.md`'s advice — strip it
  unless the pairs are the point — applies with more force on the augmented
  reference, where pairs grow 2.5x.
* The reference-row collapse recommended in `dev/PHASE3-LIBRARIES.md` §0
  (identical `(name, state, zip5)` rows; "reference −7%, cost driver −8x") was
  **built and rejected on 2026-08-22** — the claim reproduces and buys 0% runtime.
  `dev/SHARD-AND-COLLAPSE-FINDINGS.md` §4.
