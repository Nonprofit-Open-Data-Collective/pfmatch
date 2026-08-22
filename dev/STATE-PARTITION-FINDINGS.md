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
