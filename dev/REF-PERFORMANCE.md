# The augmented unified reference is ~166x slower, and Phase 1 cannot run on it

Found 2026-08-21 while benchmarking the dyad module, which is why it is recorded
separately: it has nothing to do with dyads and blocks the full-file run whether
or not they ship.

## The measurement

| reference | rows | seconds per 1,000 |
|---|---:|---:|
| `bmf_2026_01_processed.csv` (monthly BMF) | 1,924,822 | **33.5** (grants) |
| `BMF-AUGMENTED-bmf_unified_geocoded_2026-08-20.csv` | 3,891,187 | **5,558** (identities) |

From `dev/BENCH-DYAD-1K.log`: 978 identities, cascade 5,436 s wall, one core
saturated throughout. The two figures are not perfectly comparable — grants
versus deduplicated identities, and identities are the harder unit — but the
collapse ratio on this sample is 1.02x, so the comparison stands at roughly
**two orders of magnitude**.

The reference is 2.02x larger. The slowdown is ~166x. It is superlinear, so it
is not "the reference doubled".

## Where it goes

Candidate counts per pass, 978 identities:

| pass | candidates | resolved |
|---|---:|---:|
| A1-name-zip5 | 781 | 307 |
| A2-name-state | 8,056 | 79 |
| A3-name-dba | 174 | 16 |
| **B1-token-state** | **56,442** | 65 |
| **B2-token-concat** | **121,738** | **5** |
| C1-name-any | 10,360 | 0 |
| **D1-acronym** | **30,276** | **1** |
| D2-prefix | 11 | 0 |

127,206 scored pairs over 978 identities — **130 candidates per identity**.

The three token/acronym passes generate **208,456 of the 227,838 candidates and
resolve 71 queries between them.** B2-token-concat alone costs 121,738
candidates for **5** resolutions. On the 50k monthly-BMF run the same passes
were expensive but proportionate (B1: 2.1M candidates, 4,144 resolutions).

The likely mechanism is the 193,063 Schedule I alias rows: an alias is a short,
common name variant, so it enlarges token blocks disproportionately and adds
rows that are near-duplicates of BMF rows already present. That is a hypothesis
consistent with the counts above, **not something measured yet** — the
attribution test is to run the same benchmark against the unaugmented unified
BMF (3,687,435 rows, no aliases) and see whether the cost tracks row count or
alias count.

## Why it matters

Phase 1 is 12,559,051 grants, budgeted at 117 hours single-threaded against the
monthly BMF and made tractable by dedup plus ~12 parallel shards. At 5,558 s per
1,000 identities that budget becomes tens of thousands of hours. **The full-file
run is not executable against this reference**, and no amount of sharding fixes
a 166x constant.

Phase 0b credits the augmented reference with +2.2 points of recall. That gain
is real and measured, but it has never been priced against its runtime, and on
this evidence the price is prohibitive.

## What to do, in order

1. **Attribute the cost.** Same benchmark, three references: monthly BMF,
   unaugmented unified BMF, augmented unified. This separates "more rows" from
   "alias rows" and takes one run each. `dev/run-bmf-comparison.R` already has
   the three configs wired.
2. **Profile the token passes** against the augmented reference. If block sizes
   are the cause, the fix is a block-size cap or an IDF floor on the blocking
   token, not a smaller reference.
3. **Reconsider what the alias rows are for.** `dev/SCHEDI-ALIAS-FINDINGS.md`
   established that the alias justifies the match and enters as its own row. If
   alias rows only ever need to resolve through the *exact-name* passes (A1/A2),
   they could be excluded from token blocking entirely, which would remove them
   from B1/B2/D1 at no recall cost. This is the most promising lever and is
   untested.
4. **Only then re-benchmark Phase 1.**

## Incidental

`dev/BENCH-AUG.log` stops mid-Stage-3 with no error. That was read as a crash
and is not one — the run was still going. Any future benchmark against this
reference needs `verbose = TRUE` on `pf_link()` so per-batch progress is
visible, otherwise a very slow run is indistinguishable from a hung one.

The installed `npmatch` is also older than its source tree: `np_cascade()` there
does not accept `name_freq` / `token_idf` / `ref_index`, which
`pf_match_grants()` passes. Anything running from the installed package fails
immediately. Reinstall before Phase 1.
