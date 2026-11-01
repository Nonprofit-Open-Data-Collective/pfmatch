<div id="main" class="col-md-9" role="main">

# Run the grant-recipient match

<div class="ref-description section level2">

Splits the prepared grants into in-scope and out-of-sample (see
`pf_oos_details()`), runs the cascade on the in-scope side only, and
reports the elapsed time of the match itself.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_match_grants(
  grants,
  ref,
  config = npmatch::np_config(),
  method = "hier",
  passes = pf_default_passes(),
  recover = FALSE,
  verbose = TRUE,
  check_reference = c("auto", "stop", "warn", "ignore")
)
```

</div>

</div>

<div class="section level2">

## Arguments

-   grants:

    A prepared frame from `pf_prepare_grants()`.

-   ref:

    A reference bundle from `pf_build_reference()`, or a normalized
    `np_reference`.

-   config:

    An `npmatch::np_config()`.

-   method:

    Scoring method passed to `npmatch::np_score()`.

-   passes:

    Blocking passes; defaults to `pf_default_passes()`.

-   recover:

    Add the stage-4 acronym and prefix blocking keys to both sides
    before matching. Required by `pf_recovery_passes()`; harmless
    otherwise, but it costs a pass over both frames, so it is `FALSE` by
    default.

-   verbose:

    Print the per-stage cascade report.

</div>

<div class="section level2">

## Value

A `pf_match` object: the `np_tiered` result plus the in-scope /
out-of-scope split, the per-stage table, and timings.

</div>

<div class="section level2">

## Details

The timing covers the cascade only — blocking, comparison, scoring,
veto, selection, tiering. Reading and normalizing the BMF, and preparing
the grant extract, are excluded (do them once via `pf_build_reference()`
/ `pf_prepare_grants()`).

</div>

</div>
