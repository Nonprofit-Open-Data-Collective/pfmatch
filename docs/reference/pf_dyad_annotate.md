# Attach dyad context to a match result

Adds `dyad_id`, `dyad_class` and `dyad_alt_ein` to every result row
whose chosen EIN has a disclosed partner among that grant's own
candidates. Makes no selection changes — use it when you want
funder-to-recipient rollups to be correct regardless of which member the
cascade picked, which is the use this data unambiguously supports.

## Usage

``` r
pf_dyad_annotate(x, dyads, config = pf_dyad_config())
```

## Arguments

- x:

  A `pf_match` from
  [`pf_match_grants()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_match_grants.md).

- dyads:

  Output of
  [`pf_build_dyads()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_build_dyads.md).

- config:

  Output of
  [`pf_dyad_config()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_dyad_config.md).

## Value

`x` with three columns added to `x$result`.
