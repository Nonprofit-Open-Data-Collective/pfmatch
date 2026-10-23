# BASELINE-2026-10

Frozen 2026-10-23. Supersedes `BASELINE-2026-08`, which remains in place
unchanged as the historical record.

`manifest.csv` and `environment.txt` are generated. This file is written by hand
and carries the provenance reasoning that is not derivable from the artifacts.

## Why a new baseline rather than a re-freeze

`BASELINE-2026-08` was built on the GT-derived 1k samples. Those are truncated
at the recent end — measured on the 100k samples, 2024 is under-represented
roughly tenfold (0.9% of rows against 9.1% in the e-file rebuild) and 2025 is
absent entirely. The NCCS e-file rebuild (`R/efilepf.R`) exists to fix exactly
that, recovering 17,560,767 grant rows against GT's 12,559,051.

So the old baseline's clear rate could not be compared to anything measured on
the current population, which is why `dev/bench-efilepf.R` had to carry the note
that a difference against it "is not a regression". A baseline nobody can
compare against is worse than none.

Two further incomparabilities, both visible in the two `environment.txt` files:

| | 2026-08 | 2026-10 |
|---|---|---|
| population | GT 1k samples | e-file `ef1k` samples |
| R | 4.4.2 | 4.5.3 |
| normalizer signature | `v1-421e1e2a6afb024e` | `v1-b42811fe6601afe6` |

The normalizer signature moved with the npmatch release, independently of this
re-freeze, which is the other reason the old baseline had already gone stale.

A baseline is a historical record. `dev/build-baseline.R` now **refuses** to
write into a directory that already holds a `manifest.csv` unless
`PF_BASE_FORCE=1`, so the next freeze supersedes rather than overwrites.

## The arms

| arm | reference | identities | YES | MAYBE | NO | clear rate |
|---|---|---:|---:|---:|---:|---:|
| active | `REF-active.rds`, 1,924,822 rows | 4,780 | 2,726 | 1,003 | 1,051 | **57.0%** |
| augmented | `REF-augmented.rds`, 3,880,431 rows | 4,842 | 3,051 | 1,057 | 734 | **63.0%** |

Both arms run `pf_staged_passes("lean", concat = TRUE)` plus
`pf_recovery_passes(state = TRUE)` — 11 passes — with `recover = TRUE`.

**Cross-check.** The augmented arm's 63.0% reproduces arm A of
`dev/bench-jw-ab.R` exactly (3,051 YES on 4,843 identities there against 4,842
here, a 1-row difference in scope handling). Two independently written scripts
agreeing on the same population is the only external validation this figure has.

## What this baseline does NOT establish

* **It is a clear rate, not an accuracy.** Nothing here is adjudicated. The
  cascade's gains were measured at ~90% precision (`dev/CASCADE-STRATEGY.md`),
  and no equivalent figure exists for these arms.
* **The denominator is contested.** Roughly 37% of the NO residual are
  individual payees that arguably do not belong in it at all
  (`dev/NO-RESIDUAL-AUDIT.md`), which would lift both arms by about 3 points.
  The flags that should catch them miss about a quarter.
* **Timings in `dev/BASELINE-2026-10.log` are unusable.** An unrelated
  15-worker job held the machine throughout the build, which
  `dev/BENCHMARK-NOTES.md` forbids for timing. The 603.7 s and 1798.5 s figures
  are recorded only to show the arms ran, not as measurements.

## Two comparator knobs are OFF in this baseline

`npmatch` now exposes `config$jw_p` and `config$substring_p`, both defaulting to
`NULL`, which reproduces historical behaviour exactly. This baseline was built
with both unset, so it is the *current* behaviour and the correct reference point
for evaluating either change:

* `jw_p = 0.1` (true Jaro-Winkler) measured +1.5 points of YES but demotes 138
  current YES and produced wrong auto-accepts in the adjudicated sample — see
  `dev/JARO-NOT-JAROWINKLER.md`.
* `substring_p = 0.90` measured +77 NO→MAYBE with auto-accepts untouched — see
  `dev/FUZZY-KEY-DESIGN.md`.

Neither is adopted. Adopting either requires a new baseline, not an edit to this
one.
