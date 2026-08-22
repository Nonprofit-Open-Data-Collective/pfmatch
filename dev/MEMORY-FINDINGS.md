# Where the 33 GB goes, and what can be done about it

Measured 2026-08-22. Instruments: `dev/probe-memory-steps.R`,
`dev/probe-thread-memory.R`, `dev/probe-shard-rss.R`. Logs: `MEMORY-STEPS.log`,
`THREAD-MEMORY.log`, `SHARD-RSS-NOB2.log`.

`dev/SHARD-AND-COLLAPSE-FINDINGS.md` established that a shard peaks at ~37 GB,
flat in batch size, capping this machine at one concurrent shard. It did not say
which step spends it. This does.

**The headline: the cascade peaks at 31 GB and returns 0.06 GB.** Nothing that
large is being *kept*. The fixed cost is transient allocation, which is a far
better problem to have than a large resident structure — but it is inside
`np_cascade()`, not in anything pfmatch controls.

---

## 1. The breakdown

Augmented reference, 500 queries. Per-step figures are R's own high-water mark
with `gc(reset = TRUE)` before each step, so they attribute rather than
accumulate; the cumulative column is the OS working set.

| step | seconds | step peak | cumulative | what it is |
|---|---:|---:|---:|---|
| 1. `readRDS(bundle)` | 69 | 3.50 GB | 3.53 GB | reference 2.96 + index 0.95 + freq 0.27 + idf 0.03 |
| 2. `pf_add_recovery_keys(reference)` | 179 | **5.94 GB** | 6.08 GB | stage-4 acronym/prefix keys over 3.88M rows |
| 3. query prep (`np_query` + normalize) | 0.1 | 3.63 GB | 6.08 GB | negligible at any batch size |
| 4. **the 11-pass cascade** | 436 | **31.07 GB** | **31.72 GB** | ← the whole problem |

**Resident after setup is ~6 GB. Peak is ~32 GB. The 26 GB in between is churn
inside one function call.**

500 queries is representative because peak working set moved only 0.6 GB between
2,000 and 8,000 identities — the cost is fixed, so a small query set exhibits all
of it and the probe costs minutes rather than hours.

## 2. It is not any single pass, and the passes are not additive

Each pass run alone, same reference, same queries:

| pass | seconds | peak | candidates |
|---|---:|---:|---:|
| A1-name-zip5 | 27 | 6.99 GB | 5,610 |
| A2-name-state | 13 | 7.06 GB | 11,083 |
| A3-name-dba | 6 | 6.81 GB | 69 |
| A4-dba-name | 13 | 6.92 GB | 2 |
| A5-dba-dba | 1 | 4.04 GB | *failed alone* |
| B1-token-state | 89 | 8.17 GB | 63,635 |
| **B2-token-concat** | **172** | 8.63 GB | **129,555** |
| C1-name-any | 7 | 7.95 GB | 13,890 |
| C2-dba-any | 4 | 7.84 GB | 329 |
| **D1-acronym** | 112 | **8.75 GB** | 33,356 |
| D2-prefix | 15 | 8.04 GB | 387 |
| **all 11 together** | **436** | **31.07 GB** | **77,664 in the union** |

Two things follow.

**No pass is expensive on its own.** The worst is D1-acronym at 8.75 GB, of which
~6 GB is the resident reference that every pass sees. The marginal cost of the
worst pass is under 3 GB.

**But eleven passes cost 31 GB, not 9.** The peak is 3.5x the worst single pass
while the *result* — the deduplicated union — is 77,664 pairs occupying 0.06 GB.
Candidates across passes overlap 3.32x (257,916 emitted, 77,664 distinct), so the
union is not the problem either. **The cascade is accumulating per-pass
intermediates and not releasing them between passes.**

*(A5-dba-dba errors when run in isolation. That is an artifact of this probe
driving one pass at a time, not a defect in the cascade — it runs fine as part of
the eleven. Noted so the table's gap is not mistaken for a finding.)*

## 3. Ruled out: thread count

data.table parallelises the blocking joins and allocates per-thread buffers, so
threads were the cheapest hypothesis, and safe to change —
`dev/DETERMINISM-FINDINGS.md` shows the cascade is bit-identical at 1 thread and
7.

| threads | cascade | peak | pairs |
|---:|---:|---:|---:|
| 1 | 420 s | **31.23 GB** | 77,664 |
| 4 | 363 s | **31.23 GB** | 77,664 |
| 14 | 436 s | 31.07 GB | 77,664 |

**Identical to two decimal places.** Threads are not the mechanism, and
`setDTthreads()` is not a shard-count lever.

Incidentally: 1 thread is within 4% of 14 on wall-clock too, so this cascade is
not thread-bound at this size either.

## 4. Ruled out: B2-token-concat

B2 is the largest single candidate producer, so it was the obvious suspect.
Same rung, same queries, production config, B2 off:

| | B2 on | B2 off |
|---|---:|---:|
| s per 1,000 | 366 | **197** (1.86x faster) |
| peak working set | 36.82 GB | **35.67 GB** |
| shards in 68 GB | 1 | **1** |
| YES (of 2,000) | 1,182 | 1,171 |

**B2 is ~47% of runtime and ~3% of memory.** Dropping it does not buy a single
shard. Its recall cost was already settled at 100k in `dev/SCALE-PLAN.md`
(−1.55% YES, ≈73,000 matches at full scale, "keep B2 on"); this adds that it is
not a memory lever, so the decision is purely the runtime/recall trade it always
was.

## 5. Ruled out: the reference-row collapse

`dev/SHARD-AND-COLLAPSE-FINDINGS.md` §4. 7.9x off the blocking cost driver for
**0% runtime and −10.5% memory**, while manufacturing an 80-grant MAYBE→YES gain
that is 88% converted abstention. Not adopted.

## 6. What is left, ranked

Four candidates remain, and the measurements above have already eliminated the
cheap ones. Everything here is unmeasured; the ranking is by expected value, not
evidence.

**1. Release between passes — the only lever aimed at the actual mechanism.**
The cascade holds 31 GB to produce 0.06 GB. If `np_cascade()` scored and reduced
each pass's candidates before starting the next, rather than accumulating raw
intermediates, peak should approach the worst single pass — **~9 GB, which is 6
shards on 68 GB**, a 6x parallelism gain that no other lever here can approach.
This is an **npmatch** change, and it is not cosmetic: it touches the order in
which passes, scoring and the union interact. Cross-repo, and it needs the 1k
benchmark as its gate, which is exactly what `BASELINE-2026-08` exists for.

**2. Slim the reference before the cascade.** The reference carries 35 columns at
2.96 GB; the comparisons use a handful. Every pass sees the whole frame. Dropping
unused columns is low-risk and cheap to test, but it attacks the ~6 GB resident
base, not the 26 GB of churn — so the ceiling on this is small.

**3. Partition the reference by state instead of the query by identity.** Most
passes already block on state, so a state-sliced reference is near-lossless for
them and gives each process a fraction of the reference *and* a fraction of the
candidate churn. The cross-state passes (`C1-name-any`, `C2-dba-any`, and the
xstate recovery paths) would need to run as a separate job against the whole
reference. This is a real architectural change and the only route to parallelism
that does not depend on npmatch, but it changes what a shard *is*, and the
"identical answers" claim would have to be re-established rather than assumed.

**4. A second machine.** No engineering risk, and at 406–1,142 h for one shard it
is the honest comparison the other three should be measured against.

## 7. What this does not change

One shard still fits, and Phase 1 is still 406–1,142 h single-stream depending on
the dedup ratio (§3 of `SHARD-AND-COLLAPSE-FINDINGS.md`). Turning B2 off halves
the runtime and buys no shards; nothing measured so far buys shards at all. The
first item in §6 is the only one that would, and it is in the other repository.
