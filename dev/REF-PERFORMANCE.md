# Cascade cost: there is no blocker, and how I convinced myself there was one

Investigated 2026-08-21 while benchmarking the dyad module. **Conclusion: every
reference and pass combination measured is comfortably within the Phase 1
budget.** The augmented unified reference costs 1.77x the monthly BMF for 2.02x
the rows — sublinear, which is the good case.

The rest of this memo is the record of four wrong explanations, kept because the
mistake was methodological and worth not repeating.

## The measurement

1,000 identities, all 14 threads, idle machine, same queries throughout
(`dev/bench-cascade-clean.R`, `dev/CASCADE-COST-CLEAN.log`):

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

Each was a plausible reading of a number produced under uncontrolled conditions:

| claim | test | verdict |
|---|---|---|
| the augmented reference is ~166x slower | compared an 11-pass run to a 9-pass benchmark | **wrong** — different pass sets |
| the recovery passes cost ~44x | 9 vs 11 passes, same bundle | **wrong** — 1.1x |
| `REF-active.rds` lacks a blocking index | inspected all three bundles | **wrong** — all carry `ref_index`, `name_freq`, `token_idf` |
| a fixed per-call cost that small batches multiply | fitted time against query count | **wrong** — fixed component 15 s, R² 0.999 |

The actual variable was **`setDTthreads()`, differing between the diagnostic
scripts themselves**:

| threads | s per 1,000, same reference and passes |
|---:|---:|
| 6 | 1,335 |
| 14 | 192 |

Some early runs were also competing with an unrelated R process for cores. So
the "catastrophic slowdown" was a property of the harness, not the reference.

**The methodological error, which is the point:** thread count and background
load varied between runs while the results were treated as comparable, and the
explanation was sought *in the code* four times rather than *in the measurement
setup* once. A slow number should prompt "how did I measure this?" before "what
is wrong with the software?".

## The reusable reference index is worth ~14x

Measured while verifying the npmatch reinstall
(`dev/verify-npmatch-install.R`). Same queries, same reference, same passes,
with and without the precomputed `ref_index` / `name_freq` / `token_idf` handed
to `np_cascade()`:

| | s per 1,000 |
|---|---:|
| with the precomputed index | ~128 |
| **without** (bundle stripped) | **~1,790** |

Results are **identical** either way — 110 YES / 43 MAYBE / 34 NO — so this is
purely an optimisation, not a behaviour change.

This is the single largest performance factor found in the investigation, and it
is what npmatch commit `e68353d` ("Add batched matching and a reusable reference
token index") introduced. It also raises the stakes on the install problem: an
npmatch that cannot accept those arguments does not merely error, it forfeits
14x.

## Rebuilding the reference: where the time goes, and why IDF is not the lever

From `dev/probe-refbuild-cost.R` / `dev/REFBUILD-COST.log`, on the 1,924,822-row
monthly BMF:

| component | seconds | share of rebuild |
|---|---:|---:|
| `np_normalize` | 269.7 | **66%** |
| `np_ref_index` | 87.8 | 22% |
| `np_name_freq` | 27.5 | 7% |
| `np_token_idf` | 22.8 | **5.6%** |
| **total recompute** | **407.8** | |
| `readRDS` of the cached bundle | 50.7 | — |

`dev/probe-idf-atomize.R` shows token IDF *can* be precomputed per cell and
recombined for an arbitrary subset in **0.03 s instead of 41 s — a 1,371x
speedup, verified identical on 191,181 tokens.** But IDF is only 5.6% of a
rebuild, so the whole optimisation saves at most ~23 s of ~408 s. **Normalization
is the lever, not IDF**, and caching beats both: `readRDS` is 50.7 s against
407.8 s to recompute.

That is a clean negative result and belongs in the record: the fast thing was
made 1,371x faster and it did not matter.

**Caveat on the source.** `probe-refbuild-cost.R` errors before printing its own
summary (`object 'n1' not found`), so the shares above are computed by hand from
the four timings it did print. Those timings are sound; the summary arithmetic
in the script is not verified. The cause is unclear — possibly the shell wrapper
it was invoked through rather than the script itself — and it was not re-run,
since a rebuild is ~7 minutes and the numbers that matter already printed.

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
  mid-Stage-3 is a run in progress, not a crash, and was misread as one.
* **`npmatch` reinstalled 2026-08-21 and verified.** The installed copy now
  accepts `name_freq` / `token_idf` / `ref_index`, `pf_match_grants()` runs
  against it under plain `library(npmatch)`, and the dyad collapse plus
  `pf_status()` work end to end. `dev/VERIFY-NPMATCH.log`.

  **Both copies reported version `0.0.0.9000`** before and after, so the version
  string could not distinguish them. Check
  `names(formals(npmatch::np_cascade))` instead. Worth bumping npmatch's dev
  version whenever its API changes.
* **`pfmatch` installed 2026-08-21** from the `dyads-cascade-cost` branch. It
  was not installed at all before that, so `library(pfmatch)` — which every
  Phase 1 script calls — failed outright.

## A warning about this working tree

This repository lives inside Dropbox. During this session, edits to this file
and to `dev/DEVELOPMENT-PLAN.md` were silently reverted on disk between being
written and being committed, so commit `eeaf405` captured superseded text whose
conclusions contradicted its own commit message. Corrected in the following
commit.

**Verify file contents after writing, and before committing, in this repo.**
`git diff` against what you believe you wrote is the cheap check.
