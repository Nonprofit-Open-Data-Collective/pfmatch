# BASELINE-2026-10C

Frozen 2026-10-31. Supersedes `BASELINE-2026-10B`, which remains in place
unchanged as the historical record.

`manifest.csv` and `environment.txt` are generated. This file is written by hand
and carries the provenance reasoning that is not derivable from the artifacts.

## Why a new baseline

`BASELINE-2026-10B` was gated on `np_normalize_signature()`, and the normalizer
moved: npmatch PR #18 parsed the suite, folded non-decomposable Latin letters
and reclassified shared addresses. 10B was measured under
`v1-b42811fe6601afe6`; the installed normalizer is now
`v1-3e7b9f9d59bbb19e` (npmatch 0.1.1, `76964a0`). Both reference bundles were
rebuilt under it — `dev/REF-REBUILD.log` for the augmented one — so 10B's own
gate no longer certifies and this supersedes rather than restates.

Only the normalizer and the two references moved. **Same population** —
`efv2_1k`, 4,903 grants, population id `0b5126ef02f2a8b0` — same 11 passes
(`pf_staged_passes("lean", concat = TRUE)` plus
`pf_recovery_passes(state = TRUE)`), same configuration, `recover = TRUE`, both
comparator knobs still off. Every difference below is attributable to the
normalizer and nothing else.

## The arms

| arm | reference | identities | YES | MAYBE | NO | clear rate |
|---|---|---:|---:|---:|---:|---:|
| active | `REF-active.rds`, 1,924,822 rows | 4,687 | 2,667 | 986 | 1,034 | **56.90%** |
| augmented | `REF-augmented.rds`, 3,880,431 rows | 4,748 | 2,979 | 1,044 | 725 | **62.74%** |

The clear rate is **YES over identities**. YES+MAYBE is 77.94% active and
84.73% augmented, and is not a clear rate: there is no safe automatic
acceptance of the MAYBE tier (`dev/ADJUDICATION-PLAN.md`).

### Against the baseline it supersedes

| arm | 10B | 10C | Δ clear | Δ YES | Δ MAYBE | Δ NO |
|---|---:|---:|---:|---:|---:|---:|
| active | 56.86% | 56.90% | **+0.04** | +2 | −1 | −1 |
| augmented | 62.81% | 62.74% | **−0.07** | −3 | +3 | 0 |

**The normalizer change does not move this benchmark.** Four grant identities
changed tier across both arms, in opposite directions, on a sample of 4,748.
Identity counts are *identical* in both arms, so the query-side collapse did
not shift at all — `pf_dedup()` keys on `name_full`, and the 0.066% of
reference `name_key` values that moved never reached it.

That was not the expectation going in. The rebuild fixed a real defect — the
old unit pattern read `RM` inside `FARM` as a room designator and truncated
the street, so 5,134 reference rows were keyed to their own truncation and
could not match on street — and a lift seemed likely. It did not arrive, and
the arithmetic says why: 5,134 rows is 0.13% of a 3.88M-row reference, so the
chance that any of 4,748 benchmark identities needed one of those particular
farm roads is small. The fix is still right; it is simply not visible at this
sample size. Measuring it needs a population drawn to contain the affected
addresses, not this one.

## Timings are NOT usable in this baseline

685.6 s active and 1,624.2 s augmented, against 497.9 s and 1,319.0 s in 10B.
Do not read that as a regression. Both runs happened while Dropbox was syncing
roughly 4.5 GB of freshly written reference bundles out of the repository
folder, on the same disk the run was reading from. 10B's timings were taken on
an otherwise idle machine. `dev/BENCHMARK-NOTES.md` sets the conditions for a
timing claim and neither of these runs meets them.

## What this baseline does NOT establish

Unchanged from 10B, and worth repeating rather than cross-referencing:

* **It is a clear rate, not an accuracy.** Nothing here is adjudicated.
* **Precision on the YES mass is still unmeasured.** Every row of
  `PF-TRUTH-V2.csv` came from a cell the pipeline itself produced, so it
  measures recovery of known-hard cases, not precision over the 62.74%. That
  needs a fresh stratified random sample and adjudication, and no such sample
  exists.
* **The denominator is still contested.** Roughly 37% of the NO residual are
  individual payees that arguably do not belong in it
  (`dev/NO-RESIDUAL-AUDIT.md`), which would lift both arms by about 3 points.

## Two things this baseline does not cover

* **`REF-unified.rds` was not rebuilt.** Its md5 in `manifest.csv`
  (`9d486da3…`) is the same as 10B's, so it is still on the old normalizer.
  Nothing in these two arms reads it, but an arm that does is outside this
  baseline. `REF-augmented-collapsed.rds` is in the same position.
* **The augmented reference was rebuilt with `active_col = NULL`**, where
  `dev/run-bmf-comparison.R` specifies `active_col = "bmf_source"` for that
  arm. Measured impact: none. The old bundle's `active` column was logical and
  **FALSE on all 3,880,431 rows**; the rebuilt one is NA throughout; no
  function in npmatch reads the column at all, and the single pfmatch consumer
  (`pf_collapse_reference()`, which these arms do not call) tests
  `active %in% TRUE`, which is FALSE for both. Recorded because the artifact no
  longer matches its documented recipe, not because the figures are affected.

## Reproducing

```sh
PFMATCH_DIR=. PF_BASE_DIR=BASELINE-2026-10C \
  PF_BASE_GRANTS='^efv2_1k_grants_.*\.csv$' \
  PF_BASE=bench-active     Rscript dev/build-baseline.R
PFMATCH_DIR=. PF_BASE_DIR=BASELINE-2026-10C \
  PF_BASE_GRANTS='^efv2_1k_grants_.*\.csv$' \
  PF_BASE=bench-augmented  Rscript dev/build-baseline.R
PFMATCH_DIR=. PF_BASE_DIR=BASELINE-2026-10C \
  PF_BASE=manifest         Rscript dev/build-baseline.R
```

The references first, if they are not current — `pf_check_reference()` will
refuse a bundle from a different normalizer and warn on an unstamped one:

```r
pf_reference("../npmatch/data-raw/bmf_2026_01_processed.csv",
             cache = "data-dev/REF-active.rds", active_col = NULL)
pf_reference("data-dev/BMF-AUGMENTED-unified-fixed.csv",
             cache = "data-dev/REF-augmented.rds", active_col = "bmf_source")
```
