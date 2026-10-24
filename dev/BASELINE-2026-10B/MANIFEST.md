# BASELINE-2026-10B

Frozen 2026-10-23. Supersedes `BASELINE-2026-10`, frozen the same day, which
remains in place unchanged as the historical record.

`manifest.csv` and `environment.txt` are generated. This file is written by hand
and carries the provenance reasoning that is not derivable from the artifacts.

## Why a new baseline, fifteen hours after the last one

`BASELINE-2026-10` was frozen on `ef1k`, the e-file samples built with the v1
GTDC schema from an **undeduplicated** corpus. The ef2 source migration
(`e0e5b75`) changed what the package reads: concordance990 v2 names, the
published row key `OBJECTID + TABLE_ID`, and filing-level deduplication that
removes 307,568 of 17,560,767 grant rows. A clear rate measured over the old
population cannot be quoted for the new one, so this supersedes rather than
restates.

Only the population moved. Same references, same 11 passes, same configuration,
**same normalizer signature** `v1-b42811fe6601afe6` — so every difference below
is attributable to the population and nothing else. That is the whole point of
re-cutting rather than adjusting.

| | 2026-10 | 2026-10B |
|---|---|---|
| population | `ef1k`, v1 schema, undeduplicated | `efv2_1k`, v2 schema, deduplicated |
| population id | `d1c3db4c56a01709` | `0b5126ef02f2a8b0` |
| grant rows | 5,000 | 4,903 |
| row key | content hash (invented) | `OBJECTID \| TABLE_ID` (published) |
| truth table | `PF-TRUTH.csv`, 177 rows | `PF-TRUTH-V2.csv`, 172 rows |
| R | 4.5.3 | 4.5.3 |
| normalizer signature | `v1-b42811fe6601afe6` | `v1-b42811fe6601afe6` |

## The arms

| arm | reference | identities | YES | MAYBE | NO | clear rate |
|---|---|---:|---:|---:|---:|---:|
| active | `REF-active.rds`, 1,924,822 rows | 4,687 | 2,665 | 987 | 1,035 | **56.86%** |
| augmented | `REF-augmented.rds`, 3,880,431 rows | 4,748 | 2,982 | 1,041 | 725 | **62.81%** |

Both run `pf_staged_passes("lean", concat = TRUE)` plus
`pf_recovery_passes(state = TRUE)` — 11 passes — with `recover = TRUE`.

### Against the baseline it supersedes

| arm | 2026-10 | 2026-10B | Δ clear | Δ identities |
|---|---:|---:|---:|---:|
| active | 57.03% | 56.86% | **−0.17** | −93 |
| augmented | 63.01% | 62.81% | **−0.21** | −94 |

**The migration costs about a fifth of a point.** It is a correctness and
coverage change — the published row key, 2025, the deduplication — and not a
performance one. Nothing here argues for it on accuracy grounds.

The direction is the expected one rather than a regression. Deduplication
removes duplicate *copies* of grants that had already cleared, so the rows that
leave are slightly easier than average and the survivors are marginally harder.

The identity count falls by ~94 while the sample lost 97 grants, because
identities are grants collapsed on normalized name and address; the two do not
move in step.

**Cross-check.** The augmented arm's 62.81% here and the 62.77% that
`dev/evaluate-arms.R` reports for arm A are two independently written scripts
over two different augmented references (`REF-augmented.rds`, 3,880,431 rows;
`BMF-REF-AUG-2026-08-20.rds`, 3,891,187 rows) landing 0.04 points apart. That
agreement is the only external validation either figure has.

## The population is the lift, not a fresh draw

`efv2_1k` is `ef1k` carried onto the deduplicated corpus — the same grants,
4,903 of 5,000, with the other 97 removed as superseded filings. It was lifted
rather than re-cut because 177 hand adjudications are keyed to those grants, and
a fresh draw would have orphaned every one of them, leaving no way to separate a
change in the population from a change in the grants.

That choice has a cost, and it was measured rather than waved away: the sample
was drawn at random from the **undeduplicated** frame, so it over-weights filers
who amended, and pruning the superseded rows afterwards does not undo that. An
independent 5,000-grant draw from the deduplicated corpus
(`inputs/effresh_1k_grants_0*.csv`, seed 20261023), same arm and reference:

```
lifted  62.77%   (n = 4,749)
fresh   62.36%   (n = 4,873)
diff    -0.41 points,  95% CI +/- 1.93   -- within sampling error
```

So the lifted sample represents the deduplicated population and the figures
above stand on it.

## What this baseline does NOT establish

* **It is a clear rate, not an accuracy.** Nothing here is adjudicated.
* **Precision on the YES mass is still unmeasured**, on this population or any
  other. Every row of `PF-TRUTH-V2.csv` came from a cell the pipeline itself
  produced — the MAYBE tier, the cleared cell, the NO residual — so it measures
  *recovery of known-hard cases*, not precision over the 62.81%. That needs a
  fresh stratified random sample and adjudication, and no such sample exists.
* **The denominator is still contested.** Roughly 37% of the NO residual are
  individual payees that arguably do not belong in it
  (`dev/NO-RESIDUAL-AUDIT.md`), which would lift both arms by about 3 points.
  The flags that should catch them miss about a quarter.
* **Timings are usable here, unlike in 2026-10.** 497.9 s active and 1319.0 s
  augmented, measured on an otherwise idle machine. They are still not
  benchmarks: `dev/BENCHMARK-NOTES.md` sets the conditions for that.

## Two comparator knobs are OFF, as before

Both `config$jw_p` and `config$substring_p` are unset, which reproduces current
behaviour, so this is the correct reference point for evaluating either change.
Re-measured on this population (`data-dev/ARMS-VS-TRUTH-V2.csv`):

| arm | YES | Y+M | recall | false clears | ruled-out picks |
|---|---:|---:|---:|---:|---:|
| Jaro, no substring **[current]** | 62.77% | 84.65% | 23/87 | 0/58 | 14 |
| Jaro-Winkler | 64.27% | 88.73% | 32/87 | 1/58 | 9 |
| Jaro + substring | 62.75% | 86.25% | 23/87 | 0/58 | 14 |
| Jaro-Winkler + substring | 64.25% | 89.26% | 32/87 | 1/58 | 9 |

The recall **numerators are identical** to those measured on the v1 population
— 23 and 32. Only the denominator moved, 89 to 87, because two of the five
labels dropped with their superseded filings carried a correct EIN. So the
ordering of the arms survives the repopulation intact, and the conclusions in
`dev/JARO-NOT-JAROWINKLER.md` and `dev/FUZZY-KEY-DESIGN.md` — measured on a
population that no longer exists — still hold. Neither knob is adopted;
adopting either requires a new baseline, not an edit to this one.

## Reproducing

```sh
PF_BASE_DIR=BASELINE-2026-10B PF_BASE_GRANTS='^efv2_1k_grants_[0-9]+\.csv$' \
  PF_BASE=bench-active    Rscript dev/build-baseline.R
PF_BASE_DIR=BASELINE-2026-10B PF_BASE_GRANTS='^efv2_1k_grants_[0-9]+\.csv$' \
  PF_BASE=bench-augmented Rscript dev/build-baseline.R
PF_BASE_DIR=BASELINE-2026-10B PF_BASE=manifest Rscript dev/build-baseline.R
```

`build-baseline.R` refuses to write into a directory that already holds a
`manifest.csv` unless `PF_BASE_FORCE=1`, so the next freeze supersedes this one
rather than overwriting it.
