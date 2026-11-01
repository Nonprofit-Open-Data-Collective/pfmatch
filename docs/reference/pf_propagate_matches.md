<div id="main" class="col-md-9" role="main">

# Propagate a match back from identities to grant rows

<div class="ref-description section level2">

Propagate a match back from identities to grant rows

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_propagate_matches(grants, status)
```

</div>

</div>

<div class="section level2">

## Arguments

-   grants:

    Output of `pf_dedup()`.

-   status:

    A `pf_status()` frame computed over `pf_recipients()`.

</div>

<div class="section level2">

## Value

`grants` with the identity-level outcome joined onto every row.

</div>

</div>
