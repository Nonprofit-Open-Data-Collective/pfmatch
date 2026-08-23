# BASELINE-2026-08

The frozen reference point every matchdb phase gate is measured against
(`matchdb/dev/PROCESS.md` §4, Phase 0a). Produced from a single pinned commit
pair by `pfmatch/dev/build-baseline.R`.

**Artifacts are identified by md5 and row count, never by filename.** That is
not pedantry: three near-identically named augmented BMFs exist in `data-dev/`,
the reference bundles record which one built them nowhere, and Phase 0c
discovered the plan had been naming the wrong one. See *Provenance* below.

> ## Revision 2 — re-frozen 2026-08-22
>
> **Only the two benchmark outputs changed. Every reference artifact keeps its
> hash, and the normalizer signature is unchanged**, so no derived column moved.
>
> The cause is a single deliberate behaviour change: `npmatch@f14f1d9` breaks
> selection ties on `.ein` instead of on row position. Measured against
> revision 1 (`../REFIT-1K-GATE-TIEBREAK2.log`):
>
> | | |
> |---|---:|
> | identities | 4,733 |
> | **tier changed** | **0 (0.00%)** |
> | `overall_ein` changed | **498 (10.52%)** |
> | of those, the two candidates scored *identically* | **498 (100%)** |
>
> Tier counts are unchanged in both arms — active 2821 / 1006 / 906 and
> augmented 3015 / 1041 / 737, exactly as in revision 1. **No verdict moved.
> What moved is which of several tied EINs is reported.**
>
> Why it was worth a re-freeze: one reported EIN in ten was being decided by the
> order rows happened to arrive in. `../DETERMINISM-FINDINGS.md` established that
> the benchmark reproduces bit-for-bit across processes and thread counts, which
> is true and remains true — what it could not see is that 10.5% of those bits
> rested on the reference arriving in the same order every time. Rebuild the BMF,
> re-sort it, or generate the same pairs from a partitioned reference, and one
> EIN in ten changed. That was discovered by state partitioning, which made a
> latent positional dependency visible without creating it
> (`../STATE-PARTITION-FINDINGS.md` Part 3).
>
> The new rule — lowest `.ein` wins a tie — is arbitrary, deliberately. It
> replaces an *unstable* arbitrary rule with a *stable* one, which is all a
> tie-break can honestly do when the scorer cannot separate the candidates. The
> principled answers for the cases that deserve one live elsewhere: the dyad
> collapse for disclosed substitutable pairs, matchdb's `group_id` for group
> subordinates, and reference-side duplicate resolution for one body under two
> BMF rows.
>
> `npmatch@f14f1d9` also carries `110105b`, which takes the IDF corpus size from
> the blocking index rather than the reference frame. That one is a **no-op** for
> every caller whose index was built from its own reference, and it gated clean
> at 24/24 before this re-freeze (`../REFIT-1K-GATE-BLOCKSTATS.log`). It exists
> so a partitioned reference can carry whole-corpus statistics.
>
> **Revision 1 is recoverable** from git at `pfmatch@45ca500` and earlier: md5
> `aec9fb37d8b486bb6d9b4930003db48e` (active) and
> `75d4cf833cd0df70d022883c6468ba5d` (augmented), against npmatch `d658486`.

## Environment

| | |
|---|---|
| built | 2026-08-22 |
| R | 4.4.2, `x86_64-w64-mingw32` |
| pfmatch | `1c657f8` |
| npmatch | **`f14f1d9`** |
| normalizer signature | **`v1-421e1e2a6afb024e`** (unchanged) |

The signature is what makes the rest of this meaningful. Every derived column
below (`name_key`, `street_key`, `zip9`, …) was produced by that normalizer;
comparing against a candidate built with a different one produces differences
that look behavioural and are not, while hiding ones that are.
`matchdb/dev/verify/run-gate.R` refuses to run on a mismatch. **It did not change
in this revision** — which is precisely why the reference hashes did not either.

Package versions: `data.table` 1.17.0, `stringi` 1.8.7, `stringr` 1.6.0,
`reclin2` 0.6.0, `stringdist` 0.9.17, `duckdb` 1.2.0, `DBI` 1.2.3.

## Artifacts

| artifact | md5 | rows | gates |
|---|---|---:|---|
| `REF-active.rds` | `51954557f721bc282d1523884fa38ee2` | 1,924,822 | **Phase 1** — `md_compile(active-legal)` must reproduce this |
| `REF-unified.rds` | `9d486da3e5e29dcb6f8ad6324f1aa19b` | 3,687,435 | the unified layer without aliases (0c arm A) |
| `REF-augmented.rds` | `74eb9b4a6875b671f64d8aadd48a36d5` | 3,880,431 | **Phase 2** — `md_compile(*-observed)` must reproduce this |
| `BMF-AUGMENTED-unified-fixed.csv` | `dac8ff11b176beb31a7bc4da5d548caf` | 3,880,431 | the source `REF-augmented.rds` was built from |
| `benchmark-1k-active.rds` | **`a8b8f0a94fff15f51c28eef11bec31f9`** | 4,733 | 1k verdicts, active reference |
| `benchmark-1k-augmented.rds` | **`373b247414c2279d422e070b66ae1abc`** | 4,793 | 1k verdicts, augmented reference |

The four large artifacts live in `pfmatch/data-dev/`, which is gitignored — they
total ~11 GB and regenerate from public sources. The hashes are the tracked part.
The two benchmark outputs **are** tracked: ~165 KB each, small enough to version
because the `pairs` attribute is stripped before saving (see
`../DETERMINISM-FINDINGS.md` — it is 194 MB of a 198 MB object).

## Benchmark verdicts

| reference | identities | YES | MAYBE | NO |
|---|---:|---:|---:|---:|
| active | 4,733 | 2821 | 1006 | 906 |
| augmented | 4,793 | 3015 | 1041 | 737 |

**Unchanged from revision 1**, which is the point: the re-freeze moved reported
EINs among ties and no verdicts. Revision 1's figures were themselves confirmed
by four independent processes (three determinism runs, the 0c A/B's arms B and
D); this revision reproduces their tier counts exactly.

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

Roughly 7 and 19 minutes for the two benchmarks, plus ~3 minutes of hashing.
`build-baseline.R` uses `library(npmatch)`, **not** `devtools::load_all()`, so
the installed npmatch must be at the pinned commit before rebuilding or the
freeze records code that is not the code named above.

The benchmark is deterministic and thread-independent
(`../DETERMINISM-FINDINGS.md`), and as of this revision it is also independent of
reference row order — so a rebuild on the same commit pair reproduces these
hashes exactly. That property is what lets this serve as a gate.
