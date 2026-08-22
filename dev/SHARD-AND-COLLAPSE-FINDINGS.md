# One shard fits, and the reference collapse does not help

Measured 2026-08-22. Instruments: `dev/probe-shard-rss.R`,
`dev/probe-ref-collapse.R`, `dev/build-ref-collapsed.R`. Logs: `SHARD-RSS.log`,
`SHARD-RSS-2K-CLEAN.log`, `SHARD-RSS-COLLAPSED.log`, `REF-COLLAPSE.log`,
`REF-COLLAPSE-BUILD.log`.

Two results, one negative:

1. **A shard peaks at ~37 GB and that is flat in batch size, so this machine runs
   one shard, not twelve.** Every sharded cost figure on this project divides by a
   parallelism that is not available.
2. **The reference-row collapse reproduces its headline claim and buys nothing.**
   `sum(block²)` falls 7.9x; runtime falls 0% and memory 10.5%. The proxy was
   wrong about what it was proxying.

---

## 1. How much memory a shard actually needs

`pf_run_batches()` at the production config — augmented reference, 11 passes,
dyads wired — one batch, one process, peak **working set** read from
`PeakWorkingSet64` rather than `gc()`, because the number that decides whether
twelve processes fit is what the OS charged, not what R's allocator tracked.

| identities in the batch | s per 1,000 | peak working set |
|---:|---:|---:|
| 2,000 | 366 | **36.82 GB** |
| 8,000 | 433 | **37.41 GB** |

Four times the batch for 0.6 GB more memory. The reference bundle is 3.59 GB of
that; **the other ~33 GB is a fixed cost every shard process pays in full**,
regardless of how much work it is given.

| batch_size | predicted | shards in 68 GB |
|---:|---:|---:|
| 5,000 | 37.0 GB | **1** |
| 25,000 (the default) | 39.0 GB | **1** |
| 50,000 | 41.5 GB | **1** |

**The `/12 shards` and `/4 shards` columns in `dev/DEVELOPMENT-PLAN.md` Phase 1
and in `dev/REFIT-1K-FINDINGS.md` §4 are unavailable on this machine.** They
assume the per-process cost is the reference; it is not.

Batch size is not a lever in either direction: it barely moves memory, and larger
batches are *slower* per identity (§2), so there is no memory-for-speed trade to
make here.

### A defect in the first ladder, and the fix

The first rung built the 100k identity cache in its own process before loading
the reference. `PeakWorkingSet` is sticky, so that rung reported 38.42 GB against
the larger rung's 37.41 — a smaller batch using *more* memory, which has no
physical explanation and was the tell. Re-measured in a clean process: **36.82
GB**, and the ordering is now sane. `probe-shard-rss.R` refuses to build the
cache and measure in the same process (`PF_N=prep` builds it separately).

Worth stating because the harness was written *specifically* to avoid this — "one
process per rung" is in its header — and the cache build slipped through the rule
anyway.

## 2. Cost gets worse with batch size on the augmented reference

366 s/1k at 2,000 → 433 s/1k at 8,000, same reference, same machine.

That is the **opposite** of the active reference, where `REFIT-1K-FINDINGS.md` §4
measured 81 s/1k at 4,733 against 228 at 978 — 2.8x cheaper at the larger n.
Whatever amortizes on the active reference does not on the augmented one, and
something superlinear dominates instead.

**This falsifies the ≈139 s/1k estimate in `REFIT-1K-FINDINGS.md` §4**, which
carried the augmented/active ratio measured at n≈1,000 onto the active
reference's large-n figure. Two references with opposite scaling cannot be
related by a constant. The direct measurement replaces it.

## 3. Phase 1, recosted

At the measured 433 s/1k, single stream, 12,559,051 grants:

| dedup assumption | identities | single stream |
|---|---:|---:|
| 1.323x — **measured here**, on 100k | 9.49M | **1,142 h** |
| 1.8x — `SCALE-PLAN.md` extrapolation | 6.98M | 839 h |
| 3.72x — reported in `CODE-AUDIT.md` §6 from a full-file run whose output is not in `data-dev/` | 3.38M | **406 h** |

Against a **117 h** budget, on **one** shard. Even the most favourable dedup
figure is 3.5x over, and it is the one that most needs re-establishing.

**1.323x is the first dedup number measured on a sample where repetition is
possible** (the 1k files give 1.002x because random grants share no filers). It
is not the full-file number — that requires the full file — but it is real.

## 4. The reference collapse: claim verified, benefit absent

`dev/PHASE3-LIBRARIES.md` §0 listed "collapse identical `(name, state, zip5)`
reference rows — reference −7%, cost driver −8x" as one of two changes to make
*before* the full run. It was never built, and the claim had no committed log —
`dev/diagnose-ref-blowup.R` produced it, against the wrong augmented CSV (the one
`BASELINE-2026-08/MANIFEST.md` flags) and against an ad-hoc name key rather than
the `name_key` the blocker uses.

**Re-measured on the right artifact and the right key, the claim holds:**

| | before | after |
|---|---:|---:|
| reference rows | 3,880,428 | 3,527,239 (**−9.1%**) |
| `sum(block²)` on `(name, state)` | 4.49e8 | 5.66e7 (**7.9x**) |
| largest block | 7,379 | 1,208 |

The blocks are what the memo said they were: `PTA CALIFORNIA CONGRESS OF PARENTS
TEACHERS AND STUDENTS` at 7,379 rows in CA, `PEO SISTERHOOD INTERNATIONAL
CHAPTER` at 6,713 in IA, `DUCKS UNLIMITED` at 5,364 in TN.

**And it buys nothing.** Same rung, same 2,000 queries, augmented vs collapsed:

| | augmented | collapsed |
|---|---:|---:|
| peak working set | 36.82 GB | 32.95 GB (**−10.5%**) |
| s per 1,000 | 366 | **366** |
| shards in 68 GB | 1 | **1** |

A 7.9x cut in the cost driver moved the cost **0%** and the memory 10%.

### Why the proxy failed

`sum(block²)` counts candidates on the assumption that **queries distribute like
the reference**. Grant recipients do not. Nobody makes grants to 6,710 PEO
chapters or 5,364 Ducks Unlimited chapters — those blocks are enormous and almost
never queried, so shrinking them saves work nobody was doing. The cost is in the
blocks that grants actually hit, and those are small and numerous.

This is worth keeping as a general caution: **a reference-side cost proxy is only
valid weighted by query frequency**, and every block-size statistic on this
project is unweighted.

### The collapse also manufactures a YES gain

On the same rung it moved **80 grants MAYBE → YES** — a 5% headline improvement.
It is not recall:

| | |
|---|---:|
| MAYBE → YES | 80 |
| …won by an EIN standing for more than one EIN | **70 (88%)** |
| median EINs hidden behind those winners | 2 |
| max | **5,363** |

Before the collapse the ambiguity was visible — tied candidates drove the margin
to zero and `np_tier()` held the grant. Afterwards one row wins outright and the
grant is auto-accepted against an arbitrary member of a group of up to 5,363.
Also moving: 20 YES → MAYBE and 4 YES → NO, from the rebuilt `name_freq` shifting
the promotion gate.

**Verdict: do not use the collapse in the cascade.** Had it been adopted on the
strength of §0's claim — as the plan directed — it would have shipped a 5% YES
gain made entirely of converted abstentions, at no speed benefit, and the gain
would have looked like a win.

`pf_collapse_reference()` is kept: the negative result rests on it, and its
`members` table (506,014 EINs in 152,825 same-name-same-place groups) is a
ready-made equivalence table for the reference-side duplicate problem in
`dev/CLUSTER-FINDINGS.md` §8 — which `DEVELOPMENT-PLAN.md` Phase 3.6 calls larger
than everything the dyad table reaches. That is a better use for it than blocking.

## 5. What this leaves

The two levers that remain are the two the plan already had, and their value has
gone up because everything else got worse:

* **B2-token-concat.** 51% of the cascade at 50k, degrades with scale, and
  dropping it is measured at 2.18x faster for −1.55% of matches
  (`SCALE-PLAN.md` §"B2 gets worse with scale"). At 406–1,142 h that trade reads
  very differently than it did at 67 h. Still un-re-decided at 100k.
* **The full-file dedup ratio.** The single largest uncertainty in the table in
  §3 — a factor of 2.8 between the low and high assumptions — and the only way to
  settle it is to run it.

Neither is a substitute for the fact that **one shard fits**. Real parallelism
here needs either a second machine, or an attack on the ~33 GB fixed cost that
this round has now shown is *not* the identical-name blocks.
