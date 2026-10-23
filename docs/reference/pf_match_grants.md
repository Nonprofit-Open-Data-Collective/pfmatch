# Run the grant-recipient match

Splits the prepared grants into in-scope and out-of-sample (see
[`pf_oos_details()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_oos_details.md)),
runs the cascade on the in-scope side only, and reports the elapsed time
of the match itself.

## Usage

``` r
pf_match_grants(
  grants,
  ref,
  config = npmatch::np_config(),
  method = "hier",
  passes = pf_default_passes(),
  recover = FALSE,
  verbose = TRUE
)
```

## Arguments

- grants:

  A prepared frame from
  [`pf_prepare_grants()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_prepare_grants.md).

- ref:

  A reference bundle from
  [`pf_build_reference()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_build_reference.md),
  or a normalized `np_reference`.

- config:

  An
  [`npmatch::np_config()`](https://nonprofit-open-data-collective.github.io/npmatch/reference/np_config.html).

- method:

  Scoring method passed to
  [`npmatch::np_score()`](https://nonprofit-open-data-collective.github.io/npmatch/reference/np_score.html).

- passes:

  Blocking passes; defaults to
  [`pf_default_passes()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_default_passes.md).

- recover:

  Add the stage-4 acronym and prefix blocking keys to both sides before
  matching. Required by
  [`pf_recovery_passes()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_recovery_passes.md);
  harmless otherwise, but it costs a pass over both frames, so it is
  `FALSE` by default.

- verbose:

  Print the per-stage cascade report.

## Value

A `pf_match` object: the `np_tiered` result plus the in-scope /
out-of-scope split, the per-stage table, and timings.

## Details

The timing covers the cascade only — blocking, comparison, scoring,
veto, selection, tiering. Reading and normalizing the BMF, and preparing
the grant extract, are excluded (do them once via
[`pf_build_reference()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_build_reference.md)
/
[`pf_prepare_grants()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_prepare_grants.md)).
