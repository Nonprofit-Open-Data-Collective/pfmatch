# Partition the reference by state, and run the cascade over the partition

A shard's peak memory tracks the size of the reference it holds, and
nothing else moved it — not thread count, not batch size, not collecting
between passes, not collapsing duplicate reference rows
(`dev/MEMORY-FINDINGS.md`). Slicing the reference is therefore the only
measured route to running more than one shard at a time: the largest
state slice peaks at **5.24 GB against 37 GB for the whole reference**,
so eleven fit in 68 GB where one did before
(`dev/STATE-PARTITION-FINDINGS.md`).

Queries must be routed on the **normalized** `state`, not on the raw
recorded one. The two disagree on only 2 of 74,673 identities, so this
is not where the recall goes — but 770 carry no normalized state at all,
and those match nothing under a state-blocked pass by construction. They
are routed to `"_NONE"` and reach the reference only through the
cross-state phase, which is exactly the set of passes that could ever
have matched them.

Phase 1 runs the state-local passes inside each shard. Phase 2 runs the
cross-state passes against the whole reference, on the queries no shard
resolved. The candidate sets are then unioned and **selected and tiered
once** — which is what `np_cascade()` does internally, and the reason a
query's runner-up margin is still computed across all of its candidates.

## Usage

``` r
pf_partition_reference(
  ref,
  states = NULL,
  min_rows = 5000L,
  token_cols = c("name_key", "name_acro"),
  verbose = TRUE
)

pf_route_queries(query, shards)

pf_run_partitioned(
  grants,
  part,
  ref,
  config = npmatch::np_config(),
  method = "hier",
  passes = c(pf_staged_passes("lean", concat = TRUE), pf_recovery_passes(state = TRUE)),
  verbose = TRUE
)
```

## Arguments

- ref:

  The unpartitioned bundle, for the cross-state phase.

- states:

  Which states to build. Defaults to every state present.

- min_rows:

  States with fewer rows than this are merged into a single `"_SMALL"`
  shard, so the territories do not each pay a process.

- verbose:

  Per-shard progress.

- query:

  A normalized `np_query`.

- shards:

  Names of the available shards.

- grants:

  A prepared frame from
  [`pf_prepare_grants()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_prepare_grants.md).

- part:

  A `pf_partition_reference()` result.

- config, method:

  Passed to the cascade.

- passes:

  Full pass list; split internally into state-local and cross-state.

## Value

A list of bundles, one per shard, each holding a sliced `reference` and
a hybrid `ref_index`. `name_freq` and `token_idf` are shared unchanged —
they are consumed by scoring, which must see the whole corpus.

A character vector of shard labels, one per query row.

A `pf_match`, the same class the monolithic path returns.

## Why nine of eleven passes partition

Seven passes block on `state` outright, and `A1-name-zip5` and
`D2-prefix` block on ZIP5, which determines state. A query can only
reach a reference row in its own state under any of them, so holding the
other 89% of the reference buys nothing. The two that genuinely cross
state lines — `C1-name-any` and `C2-dba-any` — are also the cheapest in
the cascade, 6,284 and 176 candidates against `B2-token-concat`'s
71,105.

## The two things that make a slice behave like the whole

**Corpus statistics.** `np_block()` gates tokens on document frequency
and IDF, both derived from the reference. Rebuilt on a slice they
describe California rather than the country, and a token common
nationally but rare in-state stops being gated — on the first attempt
that produced *more* candidate pairs from a tenth of the reference.
`pf_partition_reference()` therefore builds a **hybrid** index: rows
positional within the slice, because `ref_index$base$row` indexes the
frame it was built from, and `df_base`, `df_concat` and `n_reference`
taken from the whole corpus.

**Order of passes.** `np_cascade()` withholds queries that an earlier
pass resolved to YES, so a query's candidate set depends on how far it
travelled. Running the state-local passes first and the cross-state
passes on what remains changes what is pending when `C1`/`C2` run,
relative to the monolithic order where they sit between `B2` and `D1`.
That is a real difference and it is why `pf_run_partitioned()` is
validated on tier agreement rather than assumed identical.
