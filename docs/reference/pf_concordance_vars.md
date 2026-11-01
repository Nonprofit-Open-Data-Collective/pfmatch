<div id="main" class="col-md-9" role="main">

# The grants-paid variables, taken from concordance990

<div class="ref-description section level2">

Reads the variable names from the installed concordance rather than
hardcoding them, so a concordance rename surfaces here instead of
silently producing all-missing columns. Falls back to the names baked
into `pf_efilepf_map()` when concordance990 is not installed.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_concordance_vars(check = TRUE)
```

</div>

</div>

<div class="section level2">

## Arguments

-   check:

    When `TRUE` and concordance990 is installed, warn about any name
    pfmatch expects that the concordance no longer lists.

</div>

<div class="section level2">

## Value

A character vector of concordance990 v2 variable names.

</div>

</div>
