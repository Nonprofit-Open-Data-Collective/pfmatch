<div id="main" class="col-md-9" role="main">

# Stage 3 — run the cascade and propagate to grant rows

<div class="ref-description section level2">

Wraps `pf_run_batches()` (which applies `pf_drop_self_matches()` per
batch) and then `pf_propagate_matches()`, so every grant row inherits
the result resolved for its identity cluster. Out-of-scope rows are
marked `OOS`.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

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

</div>

</div>

<div class="section level2">

## Arguments

-   prepared:

    Output of `pf_prepare()`.

-   ref:

    Output of `pf_reference()`.

-   dir:

    Checkpoint directory. Completed batches are skipped on re-run.

-   batch_size:

    Identities per checkpoint.

-   passes, config, method:

    Passed to `pf_run_batches()`.

-   dyads:

    Optional dyad table from `pf_build_dyads()`. When supplied, the
    substitutable pairs inside each candidate list are collapsed before
    selection, which is what removes ties a grant has with itself.
    `NULL` disables it. See
    [pf_dyads](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_dyads.md)
    and `dev/DYAD-FINDINGS.md`.

-   dyad_config:

    Settings for that collapse; see `pf_dyad_config()`.

-   resume:

    Reuse checkpoints in `dir` whose run stamp matches this call. A
    checkpoint written under different settings stops the run;
    `resume = FALSE` recomputes and overwrites. See `pf_run_batches()`,
    *Checkpoints are stamped*.

-   verbose:

    Print progress.

</div>

<div class="section level2">

## Value

A list of class `pf_linked` with identity-level `status`, row-level
`grants`, and `timing`.

</div>

</div>
