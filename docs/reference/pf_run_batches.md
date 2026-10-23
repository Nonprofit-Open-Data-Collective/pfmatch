# Run the cascade over a large grant file in checkpointed batches

Run the cascade over a large grant file in checkpointed batches

## Usage

``` r
pf_run_batches(
  grants,
  ref,
  dir = "data-dev/batches",
  batch_size = 25000L,
  passes = c(pf_staged_passes("lean"), pf_recovery_passes(state = TRUE)),
  config = npmatch::np_config(),
  method = "hier",
  recover = TRUE,
  self_guard = TRUE,
  dyads = NULL,
  dyad_config = pf_dyad_config(),
  resume = TRUE,
  verbose = TRUE
)
```

## Arguments

- grants:

  A prepared frame from
  [`pf_prepare_grants()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_prepare_grants.md),
  ideally already deduplicated by
  [`pf_dedup()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_dedup.md)
  and reduced with
  [`pf_recipients()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_recipients.md).

- ref:

  A reference bundle from
  [`pf_build_reference()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_build_reference.md).

- dir:

  Checkpoint directory. Created if absent.

- batch_size:

  Identities per batch. Smaller batches checkpoint more often and lose
  less on an interrupt; larger ones amortise per-batch overhead.

- passes, config, method, recover:

  Passed to
  [`pf_match_grants()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_match_grants.md).

- self_guard:

  Apply
  [`pf_drop_self_matches()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_drop_self_matches.md)
  to each batch.

- dyads:

  Optional dyad table from
  [`pf_build_dyads()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_build_dyads.md).
  When given,
  [`pf_dyad_collapse()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_dyad_collapse.md)
  runs on each batch before the status frame is built, and the status
  gains `dyad_collapsed`, `dyad_id`, `dyad_class`, `dyad_alt_ein` and
  `dyad_from_ein`. See *Where the collapse runs*.

- dyad_config:

  Settings for that collapse; see
  [`pf_dyad_config()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_dyad_config.md).

- resume:

  Reuse batches whose checkpoint file already exists **and whose run
  stamp matches this call**. A checkpoint written under different
  settings is an error, not a cache hit; see *Checkpoints are stamped*.

- verbose:

  Per-batch progress.

## Value

A data frame: the concatenated per-identity
[`pf_status()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_status.md)
frames, with a `batch` column. Timings are attached as
`attr(, "timing")`.

## Where the collapse runs

Between
[`pf_drop_self_matches()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_drop_self_matches.md)
and
[`pf_status()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_status.md),
because that is the only point at which the scored pairs still exist —
the status frame keeps just the winning candidate. Collapsing is
resolved **within one grant's candidate list only**, so a per-batch
collapse is identical to a whole-file one; batching cannot change the
answer.

## Checkpoints are stamped

Every checkpoint carries a `pf_stamp` attribute recording what produced
it: reference size and column set, the normalizer signature, the pass
table, the
[`npmatch::np_config()`](https://nonprofit-open-data-collective.github.io/npmatch/reference/np_config.html),
`method`, `recover`, `self_guard`, and the shape of `dyads` with its
`dyad_config`. On resume the stamp must match this call or
`pf_run_batches()` stops.

This guards a specific silent failure, measured in
`dev/REFIT-1K-FINDINGS.md` §3a: calling
[`pf_link()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_link.md)
twice on one directory, first with `policy = "query"` and then with
`policy = "operating"`, returned **identical EINs both times** — every
batch came off disk and the changed config was never applied. Nothing in
the output distinguishes that from a real run. A wasted recomputation
costs hours; an unnoticed stale one costs the result.

Checkpoints written before stamping existed carry no stamp and cannot be
verified, so they are refused for the same reason. To recompute and
overwrite, pass `resume = FALSE`; to start clean, delete `dir`.
