<div id="main" class="col-md-9" role="main">

# Attach dyad context to a match result

<div class="ref-description section level2">

Adds `dyad_id`, `dyad_class` and `dyad_alt_ein` to every result row
whose chosen EIN has a disclosed partner among that grant's own
candidates. Makes no selection changes — use it when you want
funder-to-recipient rollups to be correct regardless of which member the
cascade picked, which is the use this data unambiguously supports.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_dyad_annotate(x, dyads, config = pf_dyad_config())
```

</div>

</div>

<div class="section level2">

## Arguments

-   x:

    A `pf_match` from `pf_match_grants()`.

-   dyads:

    Output of `pf_build_dyads()`.

-   config:

    Output of `pf_dyad_config()`.

</div>

<div class="section level2">

## Value

`x` with three columns added to `x$result`.

</div>

</div>
