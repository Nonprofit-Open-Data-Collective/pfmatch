# Partitioning the reference by state

Measured 2026-08-22. `dev/probe-state-partition.R`, `dev/probe-pass-spike.R`,
`dev/probe-acc-growth.R`. Logs: `STATE-PARTITION.log`, `PASS-SPIKE.log`.

**The lever works: 6.6x less memory and 4.4x less time.** It is also *not*
answer-preserving as measured here, for a reason that is fixable and specific.

---

## 1. The result

Held constant: 500 CA identities, the seven state-blocked passes. Varied: the
reference the cascade sees.

| | full reference | CA slice |
|---|---:|---:|
| reference rows | 3,880,431 | 410,127 (10.6%) |
| **cascade peak** | 22.53 GB | **3.43 GB** |
| **process peak** | 23.40 GB | **5.01 GB** |
| seconds | 325 | **75** |
| candidate pairs | 111,254 | 128,731 |
| YES / MAYBE / NO | 328 / 80 / 88 | 332 / 69 / 94 |

Memory tracks reference size, which is the thing four earlier experiments failed
to move. For comparison, none of these changed the peak at all: thread count
(1/4/14 → 31.2 GB each), `rm()` + `gc(full=TRUE)` between passes (31.23 GB, and
43% slower), stripping the reclin2 source-frame attributes (31.23 GB), and the
`(name, state, zip5)` row collapse (−10.5%).

## 2. Why it works, when nothing else did

`dev/probe-pass-spike.R` traced each pass's own high-water mark inside a real
cascade. The peak rises with pass **order**, not pass **work**:

| pass | candidates | peak |
|---|---:|---:|
| A1-name-zip5 | 5,688 | 7.34 GB |
| A2-name-state | 10,953 | 8.11 GB |
| A3-name-dba | 89 | 10.79 GB |
| **A4-dba-name** | **4** | **14.80 GB** |
| B1-token-state | 52,064 | 18.05 GB |
| B2-token-concat | 71,105 | 21.51 GB |
| D1-acronym | 23,956 | **31.23 GB** |

A pass producing **four candidate pairs** peaked at 14.8 GB. Whatever the cost
is, it is paid per pass and scales with the reference, not with the candidates.
Slicing the reference is therefore the only one of the levers tried that
addresses it — and it is why the CA slice at 10.6% of the rows lands at roughly
15% of the memory.

*(A false lead worth recording: each pass's frame reports 5.93 GB of `reclin2`
attributes — `y` is the whole reference — and the accumulator appears to grow
5.93 → 11.87 → 17.79 → 23.72 GB over four passes. Stripping them changed the
peak by nothing, because `object.size()` counts shared structure once per
reference: every pass points at the same `y`. The apparent growth was a
measurement artifact.)*

## 3. Which passes can be sliced

| pass | scope | sliceable |
|---|---|---|
| A1-name-zip5 | name_key + zip5 | **yes** — ZIP5 determines state |
| A2-name-state | name_key + state | yes |
| A3-name-dba, A4-dba-name, A5-dba-dba | \*_key + state | yes |
| B1-token-state, B2-token-concat | token, `by = state` | yes |
| D1-acronym | token, `by = state` | yes |
| D2-prefix | name_pre + zip5 | **yes** — ZIP5 determines state |
| **C1-name-any** | name == name, ANY state | **no** |
| **C2-dba-any** | name == dba, ANY state | **no** |

**Nine of eleven passes are state-local**, and the two that are not are the
cheapest in the cascade — 6,284 and 176 candidates against B2's 71,105. So the
expensive work is exactly the work that partitions.

The ZIP5 claim for A1 and D2 should be confirmed rather than assumed: it is true
that a ZIP5 lies in one state, but the *query* side may carry a ZIP5 whose state
disagrees with its recorded state, and those rows would change shards.

## 4. Why the answers differ, and how to make them not

The slice produced **more** candidate pairs than the full reference — 128,731
against 111,254 — which is the tell. `name_freq` and `token_idf` are computed
*from the reference*, and this probe rebuilt them on the slice. A token that is
common nationally can be rare within one state, so `max_ref_freq` and
`min_pair_idf` admit blocks they would otherwise gate out. The blocking changed,
so the answers changed.

**The fix is to keep the global tables.** Slice the reference rows and the
blocking index, but pass the `name_freq` and `token_idf` built on the *whole*
reference. Then every state-local pass sees identical gates and identical
candidates to the unsliced run, and equivalence is a property of the design
rather than a hope.

Untested, and it is the first thing to measure next.

## 5. The sequencing constraint, which is easy to miss

`np_cascade()` is not a set of independent passes. It maintains `pending`, and
each pass runs **only on queries no earlier pass resolved to YES**. That is load
bearing, not an optimization: the final `np_select()` computes the runner-up
margin across *all* of a query's candidates, so giving a query candidates it
would not have received changes its margin and can move it between tiers.

For a partitioned design this means:

* A query belongs to one state, so **all of its state-local candidates come from
  one shard** — the union for that query is assembled from its own shard plus
  the cross-state job. No cross-shard communication is needed per query.
* The cross-state passes must see the **residual after** the state-local passes,
  which is one barrier: run all state shards, gather what is still pending, run
  C1/C2 once against the full reference, then select and tier over the combined
  union per query.
* Current pass order interleaves them (C1/C2 sit between B2 and D1). Moving all
  state-local passes ahead of the cross-state ones changes which queries are
  pending at C1/C2 and therefore can change answers. **Equivalence has to be
  re-established against `BASELINE-2026-08`, not assumed.**

## 6. What this would mean for the schedule

If the design in §4 holds and memory tracks reference size:

| slice | rows | projected peak | shards in 68 GB |
|---|---:|---:|---:|
| CA (largest) | 410,127 | ~5 GB (measured) | **11** |
| 90th percentile | 116,415 | ~1 GB | 60+ |
| median state | 21,255 | ~0.2 GB | 300+ |

The largest state is the constraint, and it alone fits 11 times over. Against
3,337,585 identities at 401 h single-stream, ten concurrent state shards is the
first thing measured on this project that would bring Phase 1 inside its 117 h
budget without giving up recall.

It is also the shape that ships to a cluster: **one job per state, no shared
state, no communication**, then a single small cross-state job and a combine
step. That is a much better fit for a scheduler than one 37 GB process.

## 7. Status

Nothing is adopted. What is measured is that the lever moves the number that
four other levers did not. What is *not* measured is whether it can be made
answer-preserving, and that is the gate — §4 first, then equivalence against the
frozen 1k benchmark, then a projection worth putting in the plan.

---

# Part 2 — the equivalence test

`dev/probe-state-equivalence.R`, `dev/probe-slice-shard.R`. Logs:
`STATE-EQUIVALENCE.log`, `REFIT-1K-GATE-BLOCKSTATS.log`.

**§4's proposed fix was aimed at the wrong table.** `name_freq` and `token_idf`
are consumed by `np_compare()` for *scoring*. The blocking gates read neither.
They read, in `npmatch/R/block.R`:

```
ref_df <- ref_index$df_concat / $df_base    -> max_ref_freq pruning, and IDF
n_ref  <- nrow(reference)                   -> idf = log(n_ref / ref_df)
```

Both are corpus statistics and both change under slicing. The index cannot
simply be reused either: `ref_index$base$row` holds **positions** into the
reference, so a slice needs its own. The design that follows is a **hybrid** —
slice-positional rows, whole-corpus statistics — plus one npmatch change so
`n_ref` comes from the index rather than the frame (`npmatch@110105b`; a no-op
for every existing caller, and the 1k gate confirms it at 24/24 identical).

## Results

Identical queries (500 CA), identical seven state-blocked passes.

| arm | pairs | vs full: in both | only full | only slice | tier agree | EIN agree |
|---|---:|---:|---:|---:|---:|---:|
| naive slice | 128,731 | 102,865 | 8,389 | 25,866 | 480/495 | 449/495 |
| **+ global stats** | 113,988 | **111,066** | **188** | **2,922** | **495/496** | 470/496 |
| full reference | 111,254 | — | — | — | — | — |

**Mismatched pairs fall from 34,255 to 3,110 — a 91% reduction — and tier
agreement reaches 99.8%.** The corpus-statistics half of the problem is closed.

**It is still not exact**, and the three residual causes are distinguishable:

1. **188 pairs the slice misses.** Queries were routed by `recip_state_raw`, but
   the cascade blocks on the *normalized* `state`. Where they disagree, a query
   lands in the wrong shard and its true matches sit in a slice it never sees.
   Route on the same field the blocker uses. Straightforwardly fixable.
2. **2,922 pairs the slice adds.** Most likely the `pending` interaction: a
   query resolved to YES early is withheld from later passes, so any difference
   in early tiering changes which queries reach B1/B2/D1 and therefore which
   candidates exist at all. Self-reinforcing, and it is why §5's sequencing
   constraint is not a footnote.
3. **26 identities agree on tier but report a different EIN.** Selection is
   first-row-wins — `.np_argmax_by()` orders then `!duplicated()`, and
   `.np_overall_summary()` takes `ix[1]` — so tied candidates resolve by
   *position*, and a slice orders its rows differently. `DETERMINISM-FINDINGS.md`
   already identified this as the mechanism that could make verdicts move without
   a code change; partitioning is what makes it bite. Exact equivalence needs a
   deterministic total order on candidates, EIN being the obvious key.

None of the three is a reason the approach cannot work. All three are reasons it
is not yet *proven* to work, and (3) is a latent ordering dependency worth fixing
on its own merits.

## What a shard actually costs

Measured in its own process, holding only the slice and the whole-corpus
statistics — never the full reference (`dev/probe-slice-shard.R`):

| | |
|---|---|
| slice | 410,127 rows (CA, the largest state) |
| resident before matching | 4.98 GB |
| **process peak** | **5.24 GB** |
| seconds (500 queries, 7 passes) | 227 |
| **concurrent shards in 68 GB** | **11** |

Against the 37 GB single shard this project has been stuck at, and against a
median state of 21,255 rows. The equivalence probe's in-process peaks (22.53 /
12.88 / 10.59 GB) are **not** shard sizes — all three arms ran in one process
with the full reference resident throughout, which is right for diffing answers
and useless for sizing.

## Status

The partition is now the leading candidate by a wide margin — it is the only
lever measured to move memory at all, and it moves it 7x. It is not adopted:
exact equivalence is the gate, three named causes stand between here and it, and
the cross-state passes (C1/C2) have not been run in a partitioned configuration
at all yet.

---

# Part 3 — causes 1 and 3

`dev/probe-state-equivalence2.R`. Logs: `STATE-EQUIVALENCE2.log`,
`REFIT-1K-GATE-TIEBREAK2.log`.

## Cause 1 was my misdiagnosis

I attributed the 188 missing pairs to routing queries on `recip_state_raw` while
the cascade blocks on the normalized `state`. Measured over all 74,673
identities:

| | |
|---|---:|
| agree | 73,901 |
| **disagree** | **2** |
| normalized state is NA | 770 |

**Two queries in 74,673.** Routing was already right, and re-routing on the
normalized field left the pair diff unchanged at 188 / 2,922. Worse for the
hypothesis: **all 188 only-in-full pairs have reference state = CA** — they are
rows the slice holds and still did not pair. So cause 1 as stated does not
exist, and the 188 belong with cause 2.

One real item survives: **770 identities have no normalized state** and would be
routed to no shard at all. A partitioned design needs an explicit
unassigned-state shard, or those identities are silently dropped.

## Cause 3 is real, and far larger than the partition made it look

Of the 25 identities where the slice and the full reference disagreed on the
reported EIN, **20 (80%) had identical scores** — decided purely by which row the
frame listed first.

That prompted running the deterministic tie-break against the *frozen benchmark*,
where the partition is not involved at all:

| | |
|---|---:|
| identities | 4,733 |
| **tier changed** | **0 (0.00%)** |
| **`overall_ein` changed** | **498 (10.52%)** |
| of those, scores identical | **498 (100%)** |

**One in ten reported EINs on the benchmark is currently decided by row order,
and no verdict depends on it.** `DETERMINISM-FINDINGS.md` showed the benchmark
reproduces bit-for-bit across processes and thread counts — true, and still true.
What it could not see is that 10.5% of those bits rest on the reference arriving
in the same order every time. Rebuild the BMF, re-sort it, or generate the same
pairs from a partition, and one EIN in ten changes.

The partition did not create this. It made a latent positional dependency
visible, and the 20-of-25 it exposed is a small sample of a 498-of-4,733
population.

### Why it is not adopted here

`npmatch@f14f1d9` (branch `deterministic-tiebreak`) implements it and **fails the
gate 12/24**, exactly as it must — changing 498 reported EINs is a behaviour
change. Adopting it means **re-freezing `BASELINE-2026-08`**, which gates
matchdb's phases as well as pfmatch's, so it is a cross-repo decision and not
one to slip in.

The change is also honest about what it buys: ties resolve to the lowest `.ein`,
which is arbitrary. It replaces an *unstable* arbitrary rule with a *stable* one,
which is all a tie-break can do when the scorer cannot separate the candidates.
The principled answers for the cases that deserve one live elsewhere — the dyad
collapse for disclosed substitutable pairs, matchdb's `group_id` for group
subordinates, and reference-side duplicate resolution for one body under two BMF
rows.

### What it says about the project

498 identities where the top candidates score *identically* is a measurement of
how often the cascade cannot separate candidates at all. It is a larger and more
concrete statement of the same fact as `CLUSTER-FINDINGS.md` §8 (15.9% of the
MAYBE tie band is one body under two BMF rows) and matchdb's finding that a group
cluster in the close set never co-occurs with YES. Three independent routes to
the same conclusion: **the residual ambiguity is structural, not a scoring
deficiency**, and no amount of threshold tuning addresses it.

## Part 4 — cause 2 is concentrated, and it is per-query

`dev/STATE-EQUIVALENCE3.log`.

| | pairs | over identities | top 5 hold |
|---|---:|---:|---:|
| only in full | 188 | **4** | 100% |
| only in slice | 2,922 | 70 | 28% |
| **queries affected at all** | — | **73 of 496 (14.7%)** | — |

**Not systematic.** A blocking difference would touch every query with the
affected tokens; this touches 73, and the only-in-full side collapses to four
identities, one of which (`SOLUTIONS FOR CHANGE INC`) holds 158 of the 188.

The affected names are of one kind:

```
ST MARK'S-IN-THE-VALLEY EPISCOPAL CHURCH    176 slice-only
ST JOHNS'S EPISCOPAL CHURCH                 176
Santa Clara Korean American Senior Citiz    165
ST MARTIN OF TOURS SCHOOL                   157
ST JAMES ARMENIAN APOSTOLIC CHURCH          155
SOLUTIONS FOR CHANGE INC                    158 full-only
```

High-frequency institutional tokens — `ST`, `CHURCH`, `EPISCOPAL` — i.e. queries
sitting exactly on the blocking gates, which is where a small difference in how
far a query travels through the cascade shows up as hundreds of candidates.

This is consistent with the `pending` interaction (§5): each pass runs only on
queries no earlier pass resolved, so a query that stays pending one pass longer
picks up a whole extra block of B2/D1 candidates. **Consistent with, not proven
— the mechanism has not been traced to a specific pass.** That is the next
measurement, and it is a `trace_memory`-style per-pass diff rather than another
whole-cascade run.

What it does establish: the residual is a **per-query** effect on 14.7% of
queries, not a systematic blocking divergence, and tier agreement is already
495/496. So the two-phase design (state-local passes, barrier, cross-state, one
combined select) remains sound in principle; what is unproven is whether it
reproduces the unpartitioned answer exactly, and 25 of the 26 remaining
disagreements are ties (Part 3) whose resolution depends on a decision that has
not been made.

---

# Part 5 — shipped: the partitioned run reproduces the baseline exactly

`R/partition.R`, `dev/probe-partition-validate.R`,
`dev/PARTITION-VALIDATE6.log`. Validated against **BASELINE-2026-08 revision 2**,
five 1k grant files, active reference.

| | baseline | partitioned |
|---|---:|---:|
| identities | 4,733 | **4,733** |
| YES / MAYBE / NO | 2821 / 1006 / 906 | **2821 / 1006 / 906** |
| same tier | — | **4,733 (100.00%)** |
| same EIN | — | 4,726 (99.85%) |
| regressions | — | **0** |
| identities lost / added | — | **0 / 0** |

**Every identity lands in the same tier.** The bar was "no tier regressions";
the result is exact tier equality, over 50 shards, with only 7 reported EINs
differing among ties.

## Three defects found by validating, each invisible without the frozen baseline

**1. Skipping the stateless shard.** "A query with no state cannot match a
state-blocked pass" is false — the block key is built from the field as it
stands, so a stateless query joins reference rows that are also stateless. One
identity (`HILLENGALE HHH` → `HIS HELPING HANDS`, via D1-acronym) vanished from
the output.

**2. One index per token column, not one per shard.** `np_block()` validates a
supplied `ref_index` by comparing `token_col`, and a mismatch is **not an
error** — it silently rebuilds the index inline from the reference it was handed.
On a shard that is the slice, so the whole-corpus graft never applied to
`D1-acronym`, which blocks on `name_acro`. Both sides of the lost pair sat in TN;
the pass simply gated on Tennessee acronym frequencies.

**3. `pending` does not survive being split across calls.** Each `np_cascade()`
starts its own pending set at every query it is given. Grouping passes by token
column into separate calls therefore re-ran the later passes on queries an
earlier pass had already resolved, handing them candidates the monolithic cascade
withheld — the extra candidates became runner-ups and the margin brake demoted
them. **44 YES → MAYBE**, until the loop carried `pending` across the groups by
hand.

Defect 3 is the one worth remembering: it is the sequencing constraint this memo
named in §5 as load-bearing, and I still broke it, in a way that showed up only
as a tier count. The reason to validate against a frozen baseline rather than
against expectation is that all three of these produce plausible-looking output.

## Cost

Shard sizes on the active reference: 50 shards, largest CA at 199,286 rows,
median far smaller. Peak working set for the largest state slice against the
augmented reference is **5.24 GB** (`dev/probe-slice-shard.R`), so **11 shards
fit in 68 GB** where one did before.

The validation run executes all 50 shards **sequentially in one process**, which
is the wrong way to run it in production and the right way to test it: sequential
execution makes the comparison deterministic and the memory ceiling irrelevant.
Production runs one process per shard, which is what the memory measurement is
for — and it is also the shape that ships to a scheduler, since the shards share
no state and need no communication.

## Part 6 — the augmented reference does NOT reproduce, and that is the blocker

`dev/PARTITION-VALIDATE-AUG.log`. Same code, same bar, production reference.

| | active | **augmented** |
|---|---:|---:|
| identities | 4,733 / 4,733 | 4,793 / 4,794 |
| YES / MAYBE / NO (baseline) | 2821 / 1006 / 906 | 3015 / 1041 / 737 |
| YES / MAYBE / NO (partitioned) | **2821 / 1006 / 906** | 3010 / 1045 / 739 |
| same tier | **100.00%** | **98.75%** |
| **regressions** | **0** | **31** |
| gains | 0 | 29 |
| verdict | **PASSES** | **FAILS** |

Tier movement on the augmented reference is two-directional — 15 YES→MAYBE,
12 YES→NO, 15 MAYBE→YES, 6 NO→YES — so it is not a systematic loss of candidates
in one direction. It looks like sensitivity: 60 identities sitting close enough
to a boundary that a different candidate set moves them either way.

**This is the blocker, and it is the production configuration.** The active
reference is not what Phase 1 runs.

### Why this was worth measuring rather than extrapolating

The active result was exact, and the obvious inference — "so the augmented one
will be too" — is wrong. That is the **second** time in this work that carrying a
conclusion from the active reference to the augmented one has failed: the first
was the ≈139 s/1k throughput estimate in `REFIT-1K-FINDINGS.md` §4, falsified by
direct measurement. The augmented reference is not the active one scaled; it
carries 2.02x the rows, most of them Schedule I alias variants, and those are
precisely rows that create near-ties.

**Rule for this project: no conclusion crosses from the active reference to the
augmented one without being measured there.**

### Cost, measured on the production reference

| | |
|---|---:|
| partitioned, all 54 shards sequential in one process | 1,238 s / 4,793 = **258 s per 1,000** |
| monolithic, same reference and benchmark | 1,122 s / 4,793 = **234 s per 1,000** |
| partitioning overhead on total CPU | **+10%** |

The 9–10% overhead reproduces the active measurement, which is the reassuring
part: partitioning costs about a tenth more total work and makes that work
divisible.

Projected over 3,337,585 identities:

| | |
|---|---:|
| single stream | 239 h |
| 11 shards | **22 h** |
| budget | 117 h |

**Cost clears the budget with room.** What does not yet clear is equivalence.

### Where that leaves the stop rule

`DEVELOPMENT-PLAN.md`'s clause 1 asks for a configuration that clears the budget
*and* is gated against `BASELINE-2026-08`. Half of it holds: 22 h against 117 h.
The other half holds on the active reference and fails on the augmented one by 31
tier regressions out of 4,793.

The next measurement is not more engineering. It is to look at the 60 moved
identities and find out whether they share a mechanism — the shard boundary, the
alias rows, or the pass reordering — in the way Part 4's residual turned out to
concentrate on 73 queries. Until that is understood, partitioned Phase 1 would
ship 31 unexplained tier changes per 4,793 identities.

## Part 7 — diagnosed: one EIN, many reference rows, and a dedup that keeps the first

`dev/probe-mover-diagnosis.R`, `dev/MOVER-DIAGNOSIS.log`,
`data-dev/MOVERS-AUGMENTED.csv`.

**None of the five hypotheses was the cause.** The answer is a property of the
augmented reference that the active reference does not have at all:

| | REF-active | REF-augmented |
|---|---:|---:|
| reference rows | 1,924,822 | 3,880,431 |
| distinct EINs | 1,924,822 | 3,687,435 |
| **EINs with more than one row** | **0 (0.00%)** | **127,499 (3.46%)** |
| EINs whose rows span >1 state | **0** | **7,489 (0.20%)** |
| rows on those EINs | 0 | 27,107 (0.70%) |
| **max states for a single EIN** | **1** | **45** |

**The active reference is exactly one row per EIN.** Partitioning by state is
trivially lossless there — every EIN lives in exactly one shard, and that is the
whole reason it scored 100.00%. It was never evidence that the design was sound;
it was evidence that the active reference cannot exhibit the defect.

### The mechanism

Candidate pairs are keyed `(.id, .ein)` and the union is deduplicated with
`!duplicated(...)`, which **keeps the first occurrence** — in `np_cascade()`,
deliberately, "keep tightest pass". When an EIN carries several reference rows,
those rows score *differently*, so "which row represents this EIN" is decided by
whichever pass reached it first. Change the order in which passes run — which is
exactly what partitioning does — and a different row survives, under the same
EIN, with a different score.

That is why the movers show the same EIN present on both sides at different
scores:

| identity | baseline | partitioned |
|---|---|---|
| `HORSE OF CT` → 22-2611615 | 0.780, MAYBE | **0.22**, NO |
| `INTERNATIONAL FOLK ART MARKET` → 35-2285824 | 0.914, YES | **0.760**, MAYBE |
| `THE SALVATION ARMY` → 13-2923701 | 0.380, NO | 0.380, but a **better row wins at 0.902**, YES |

EIN 13-2923701 has **eight** reference rows — `SALVATION ARMY WORLD SERVICE
OFFICE` in VA, `MADISON INDIANA CITADEL` in IN, `ALASKA DIVISON` in AK,
`HOLLISTER CORPS` in CA, `PORT ANGELES` in WA. One EIN, five states, five shards.

### Why the diagnostic hypotheses looked partly right

They were downstream symptoms, and worth recording so they are not re-tested:

* **H1 boundary** — movers sit nearer the margin brake (median |margin − 0.05|
  0.112 vs 0.570; 12% within 0.02 vs 2%). True, and a consequence: swapping the
  row that represents an EIN changes the score, and grants near a boundary are
  the ones a score change can move.
* **H4 pass** — 58 of 60 movers were won by a *token* pass (B1 48, B2 6, D1 4)
  against 1 for all four exact-key passes combined. Also a consequence: token
  passes are where an EIN's several rows are reachable by different routes.
* **H5 alias** — 80% of movers' baseline picks sit on a multi-row EIN against
  51% of non-movers. This was the closest to the mark, and understated it,
  because the proxy counted multi-row EINs rather than multi-*state* ones.
* **H2 ties** and **H3 shard** — no signal.

Movers carry a median of **46 candidates against 4** for everything else, which
is the same population as always: high-fanout national names — `PLANNED
PARENTHOOD`, `THE SALVATION ARMY`, `PROTESTANT EPISCOPAL CHURCH`, `TEMPLE
ISRAEL`. 0.20% of EINs, but they are the EINs grants actually go to, which is how
0.20% of the reference becomes 1.25% of identities.

### The fix, and why it is not free

**Deduplicate `(.id, .ein)` by highest score rather than by first occurrence.**
That makes the pair set independent of pass order, and it is the same defect —
and the same remedy — as the selection tie-break already adopted in revision 2:
an EIN-level answer must not rest on row-level ordering.

It is **not** partition-specific. The monolithic cascade has it too: which row
represents a multi-row EIN today depends on pass order, and nothing records that
choice. So the fix is another npmatch behaviour change against
`BASELINE-2026-08`, and it will move some verdicts, which means another
re-freeze under the stop rule's override clause.

Two things should be measured before adopting it, in this order:

1. **How many identities does highest-score dedup move in the *monolithic* run?**
   If it is small the change is cheap; if it is large it is a genuine question
   about whether "tightest pass" was ever the right rule.
2. **Does the partition then reproduce the monolith on the augmented reference?**
   The mechanism says it should. Nothing here has demonstrated it.

Until then the partition is validated **only against a reference with one row per
EIN**, which is not the production one.
