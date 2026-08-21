# Cascade cost: there is no blocker, and how I convinced myself there was one

Investigated 2026-08-21 while benchmarking the dyad module. **Conclusion: every
reference and pass combination measured is comfortably within the Phase 1
budget.** The augmented unified reference costs 1.77x the monthly BMF for 2.02x
the rows — sublinear, which is the good case.

The rest of this memo is the record of four wrong explanations, kept because the
mistake was methodological and worth not repeating.

## The measurement

1,000 identities, all 14 threads, idle machine, same queries throughout:

| reference | rows | passes | s per 1,000 | scored pairs | YES | MAYBE |
|---|---:|---|---:|---:|---:|---:|
| monthly BMF | 1,924,822 | 9 | **128** | 51,214 | 569 | 188 |
| monthly BMF | 1,924,822 | 11 | 149 | 52,210 | 569 | 193 |
| augmented unified | 3,891,187 | 9 | 226 | 127,018 | 612 | 198 |
| augmented unified | 3,891,187 | 11 | **279** | 128,983 | 612 | 201 |

Two ratios worth keeping:

* **recovery passes cost 1.16–1.23x**, and buy +5 MAYBE and 0 YES on this
  sample. Cheap, and on this evidence close to worthless — but cheap.
* **the augmented unified reference costs 1.77x for 2.02x the rows**, and buys
  +43 YES and +10 MAYBE over the monthly BMF on 1,000 identities. That is the
  +2.2 points of Phase 0b showing up, at a sublinear price.

## Phase 1 is executable

12,559,051 grants, **before** any dedup credit:

| reference | passes | total | on 12 shards |
|---|---|---:|---:|
| monthly | 9 | 445 h | **37 h** |
| monthly | 11 | 520 h | 43 h |
| augmented unified | 9 | 789 h | 66 h |
| augmented unified | 11 | 975 h | **81 h** |

The worst combination is 81 hours on 12 shards with no dedup at all. The plan
budgets 117 hours. Dedup on the full file has not been measured yet (Phase 1.2)
and only improves this. **Run the augmented unified reference with all passes.**

## Four wrong explanations, and the one real error

Each was a plausible reading of a number I had produced under uncontrolled
conditions:

| claim | test | verdict |
|---|---|---|
| the augmented reference is ~166x slower | compared 11-pass run to a 9-pass benchmark | **wrong** — different pass sets |
| the recovery passes cost ~44x | 9 vs 11 passes, same bundle | **wrong** — 1.1x |
| `REF-active.rds` lacks a blocking index | inspected all three bundles | **wrong** — all carry `ref_index`, `name_freq`, `token_idf` |
| a fixed per-call cost that small batches multiply | fitted time against query count | **wrong** — fixed component 15 s, R² 0.999 |

The actual variable was **`setDTthreads()`, differing between my own
diagnostic scripts**:

| threads | s per 1,000, same reference and passes |
|---:|---:|
| 6 | 1,335 |
| 14 | 192 |

Some early runs were also competing with an unrelated R process for cores. So
the "catastrophic slowdown" was a property of the harness, not the reference.

**The methodological error, which is the point:** I varied thread count and
background load between runs while treating the results as comparable, then
reached for an explanation *in the code* four times rather than *in the
measurement setup* once. A slow number should prompt "how did I measure this?"
before "what is wrong with the software?".

## The reusable reference index is worth ~14x

Measured while verifying the npmatch reinstall (`dev/verify-npmatch-install.R`).
Same queries, same reference, same passes, with and without the precomputed
`ref_index` / `name_freq` / `token_idf` handed to `np_cascade()`:

| | s per 1,000 |
|---|---:|
| with the precomputed index | ~128 |
| **without** (bundle stripped) | **~1,790** |

Results are **identical** either way — 110 YES / 43 MAYBE / 34 NO — so this is
purely an optimisation, not a behaviour change.

This is the single largest performance factor found in the whole investigation,
and it is exactly what npmatch commit `e68353d` ("Add batched matching and a
reusable reference token index") introduced. It also raises the stakes on the
install problem below: an npmatch that cannot accept those arguments does not
merely error, it forfeits 14x.

## Residual, not worth chasing

The 2026-08-19 50k run recorded 35 s per 1,000 against 128 s per 1,000 here for
the same reference and passes — 3.7x, unexplained. Candidates are batch size
(46,900 queries in 2 calls versus 1,000 in one, so better amortisation of
whatever is not strictly per-query) and machine conditions. It does not change
any decision: at either figure Phase 1 runs. Left open deliberately.

## Practical notes

* **Always `setDTthreads(0L)` in benchmarks**, and check for competing processes
  before timing anything. A 7x swing hides in this.
* **Pass `verbose = TRUE` to `pf_link()`** on a large reference. With it off, a
  slow run is indistinguishable from a hung one — `dev/BENCH-AUG.log` stopping
  mid-Stage-3 is a run in progress, not a crash, and I misread it as one.
* **`npmatch` reinstalled 2026-08-21 and verified.** The installed copy now
  accepts `name_freq` / `token_idf` / `ref_index`, `pf_match_grants()` runs
  against it under plain `library(npmatch)`, and the dyad collapse plus
  `pf_status()` work end to end. `dev/VERIFY-NPMATCH.log`.

  Note that **both copies reported version `0.0.0.9000`** before and after, so
  the version number could not distinguish them. Check
  `names(formals(npmatch::np_cascade))` instead.

* **`pfmatch` is not installed at all.** `library(pfmatch)` fails with "there is
  no package called 'pfmatch'". The Phase 1 scripts (`dev/full-0*.R`) call it,
  so they cannot run as written. Installing npmatch fixed half the problem.
