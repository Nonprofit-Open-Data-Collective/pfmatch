<div id="main" class="col-md-9" role="main">

# Standardize SIGOCPYRFSTA into recipient types

<div class="ref-description section level2">

Applies the rule cascade documented in
[pf_recipient_type](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_recipient_type.md).

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_standardize_status(x)
```

</div>

</div>

<div class="section level2">

## Arguments

-   x:

    Character vector of raw `SIGOCPYRFSTA` values.

</div>

<div class="section level2">

## Value

A data frame with one row per input value:

-   `recipient_type`:

    the five-level standard, as a factor with levels from
    `pf_type_levels()`

-   `recipient_type_detail`:

    the finer level that drives scope

-   `status_norm`:

    the normalized string the rules matched against

-   `status_rule`:

    index of the rule that fired; `NA` if none did

</div>

</div>
