# BASELINE-2026-08

The frozen reference point every matchdb phase gate is measured against
(`matchdb/dev/PROCESS.md` §4, Phase 0a). Produced 2026-08-21 from a single
pinned commit pair by `pfmatch/dev/build-baseline.R`.

**Artifacts are identified by md5 and row count, never by filename.** That is
not pedantry: three near-identically named augmented BMFs exist in `data-dev/`,
the reference bundles record which one built them nowhere, and Phase 0c
discovered the plan had been naming the wrong one. See *Provenance* below.

## Environment

| | |
|---|---|
| built | 2026-08-21 |
| R | 4.4.2, `x86_64-w64-mingw32` |
| pfmatch | `d02a458` |
| npmatch | `d658486` |
| normalizer signature | **`v1-421e1e2a6afb024e`** |

The signature is what makes the rest of this meaningful. Every derived column
below (`name_key`, `street_key`, `zip9`, …) was produced by that normalizer;
comparing against a candidate built with a different one produces differences
that look behavioural and are not, while hiding ones that are.
`matchdb/dev/verify/run-gate.R` refuses to run on a mismatch.

Package versions: `data.table` 1.17.0, `stringi` 1.8.7, `stringr` 1.6.0,
`reclin2` 0.6.0, `stringdist` 0.9.17, `duckdb` 1.2.0, `DBI` 1.2.3.

## Artifacts

| artifact | md5 | rows | gates |
|---|---|---:|---|
| `REF-active.rds` | `51954557f721bc282d1523884fa38ee2` | 1,924,822 | **Phase 1** — `md_compile(active-legal)` must reproduce this |
| `REF-unified.rds` | `9d486da3e5e29dcb6f8ad6324f1aa19b` | 3,687,435 | the unified layer without aliases (0c arm A) |
| `REF-augmented.rds` | `74eb9b4a6875b671f64d8aadd48a36d5` | 3,880,431 | **Phase 2** — `md_compile(*-observed)` must reproduce this |
| `BMF-AUGMENTED-unified-fixed.csv` | `dac8ff11b176beb31a7bc4da5d548caf` | 3,880,431 | the source `REF-augmented.rds` was built from |
| `benchmark-1k-active.rds` | `aec9fb37d8b486bb6d9b4930003db48e` | 4,733 | 1k verdicts, active reference |
| `benchmark-1k-augmented.rds` | `75d4cf833cd0df70d022883c6468ba5d` | 4,793 | 1k verdicts, augmented reference |

The four large artifacts live in `pfmatch/data-dev/`, which is gitignored — they
total ~11 GB and regenerate from public sources. The hashes are the tracked
part. The two benchmark outputs **are** tracked: 163 KB and 165 KB each, small
enough to version because the `pairs` attribute is stripped before saving (see
`../DETERMINISM-FINDINGS.md` — it is 194 MB of a 198 MB object).

## Benchmark verdicts

| reference | identities | YES | MAYBE | NO |
|---|---:|---:|---:|---:|
| active | 4,733 | 2821 | 1006 | 906 |
| augmented | 4,793 | 3015 | 1041 | 737 |

Both reproduce results already on record from independent runs — the active
figures match the three determinism runs and the 0c A/B's arm D, the augmented
match arm B. The freeze therefore records numbers confirmed by four separate
processes, not a single run.

**Identity counts differ by reference and that is expected.** The tiered frame
carries one row per identity that drew at least one candidate, and a larger
reference reaches more of them. Comparing tiered outputs across references
requires the union-align rule in `matchdb::md_compare_tiered()`, which marks an
absent identity `NONE` — distinct from a scored `NO`.

## Pinned column lists

`columns-reference-*.txt` and `columns-tiered-*.txt` hold the exact column sets
the comparison normal form must use. They are pinned here rather than resolved
from `npmatch::np_fields` at run time, because Phase 0c adds `variant_class` to
that constant — a live lookup would compare a baseline built without the column
against a candidate built with it and report a difference carrying no
information. `matchdb::md_normal_form()` requires the list as an argument and
refuses to default.

## Provenance: which augmented BMF

Three candidates exist, and the difference matters:

| file | rows |
|---|---:|
| `BMF-AUGMENTED-unified.csv` | 3,880,431 |
| `BMF-AUGMENTED-unified-fixed.csv` | 3,880,431 |
| `BMF-AUGMENTED-bmf_unified_geocoded_2026-08-20.csv` | 3,891,187 |

`REF-augmented.rds` holds 3,880,431 rows and aligns row-for-row with
`-unified-fixed.csv` at 100.0000% EIN agreement. It is **not** built from the
3,891,187-row geocoded CSV — which is the artifact behind `REF-PERFORMANCE.md`'s
published "+43 YES". Two consequences:

1. An earlier draft of the matchdb plan named `BMF-AUGMENTED-unified.csv` as the
   Phase 2 target. Wrong file. Corrected to this manifest's entry.
2. `REF-PERFORMANCE.md`'s figure was measured against a reference nothing here
   uses. Phase 2's target is 0c's measured delta (+199 YES / −67 MAYBE for the
   aliases), not the published number.

The first two rows are indistinguishable by row count; they are distinguished
here by md5. That is the case for hashing rather than naming.

## Rebuilding

```bash
PF_BASE=bench-active     Rscript dev/build-baseline.R
PF_BASE=bench-augmented  Rscript dev/build-baseline.R
PF_BASE=manifest         Rscript dev/build-baseline.R
```

Roughly 10 and 22 minutes for the two benchmarks, plus ~6 minutes of hashing.
The benchmark is deterministic and thread-independent
(`../DETERMINISM-FINDINGS.md`), so a rebuild on the same commit pair reproduces
these hashes exactly — that property is what lets this serve as a gate.
