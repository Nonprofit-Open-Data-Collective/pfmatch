# Stage 3 — run the cascade and propagate to grant rows

Wraps
[`pf_run_batches()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_run_batches.md)
(which applies
[`pf_drop_self_matches()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_drop_self_matches.md)
per batch) and then
[`pf_propagate_matches()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_propagate_matches.md),
so every grant row inherits the result resolved for its identity
cluster. Out-of-scope rows are marked `OOS`.

## Usage

``` r
pf_link(
  prepared,
  ref,
  dir = "data-dev/batches",
  batch_size = 25000L,
  passes = NULL,
  config = npmatch::np_config(),
  method = "hier",
  dyads = NULL,
  dyad_config = pf_dyad_config(),
  resume = TRUE,
  verbose = TRUE
)
```

## Arguments

- prepared:

  Output of
  [`pf_prepare()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_prepare.md).

- ref:

  Output of
  [`pf_reference()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_reference.md).

- dir:

  Checkpoint directory. Completed batches are skipped on re-run.

- batch_size:

  Identities per checkpoint.

- passes, config, method:

  Passed to
  [`pf_run_batches()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_run_batches.md).

- dyads:

  Optional dyad table from
  [`pf_build_dyads()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_build_dyads.md).
  When supplied, the substitutable pairs inside each candidate list are
  collapsed before selection, which is what removes ties a grant has
  with itself. `NULL` disables it. See
  [pf_dyads](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_dyads.md)
  and `dev/DYAD-FINDINGS.md`.

- dyad_config:

  Settings for that collapse; see
  [`pf_dyad_config()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_dyad_config.md).

- resume:

  Reuse checkpoints in `dir` whose run stamp matches this call. A
  checkpoint written under different settings stops the run;
  `resume = FALSE` recomputes and overwrites. See
  [`pf_run_batches()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_run_batches.md),
  *Checkpoints are stamped*.

- verbose:

  Print progress.

## Value

A list of class `pf_linked` with identity-level `status`, row-level
`grants`, and `timing`.
