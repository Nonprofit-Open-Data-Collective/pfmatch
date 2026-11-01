<div id="main" class="col-md-9" role="main">

# Audit the standardization

<div class="ref-description section level2">

Frequency table of raw status strings by assigned type, most common
first. Use it to find spellings the cascade still misses before trusting
the scope split on a new extract.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_status_audit(x, detail = NULL, n = 50)
```

</div>

</div>

<div class="section level2">

## Arguments

-   x:

    Character vector of raw `SIGOCPYRFSTA` values.

-   detail:

    Optional `recipient_type_detail` to restrict to (e.g.
    `"unrecognized"`).

-   n:

    Maximum rows to return.

</div>

<div class="section level2">

## Value

A data frame of `status_norm`, `recipient_type`,
`recipient_type_detail`, and count.

</div>

</div>
