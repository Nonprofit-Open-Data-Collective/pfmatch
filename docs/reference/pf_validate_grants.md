<div id="main" class="col-md-9" role="main">

# Validate a grant file

<div class="ref-description section level2">

Checks schema consistency, key uniqueness, deduplication status and
column coverage, and reports what it finds rather than guessing at a
repair.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_validate_grants(grants, strict = FALSE, verbose = TRUE)
```

</div>

</div>

<div class="section level2">

## Arguments

-   grants:

    A grant frame, or a path passed to `pf_read_grants()`.

-   strict:

    When `TRUE`, any FAIL raises an error instead of returning.

-   verbose:

    Print the report.

</div>

<div class="section level2">

## Value

A `data.frame` of checks, one row per check, with columns `check`,
`status` (`PASS` / `WARN` / `FAIL` / `INFO`) and `detail`, invisibly.

</div>

</div>
