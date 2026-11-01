<div id="main" class="col-md-9" role="main">

# The shared core of an organization name

<div class="ref-description section level2">

Strips legal suffixes and any arm marker, so that
`FRIENDS OF THE RACINE PUBLIC LIBRARY` and `RACINE PUBLIC LIBRARY`
reduce to the same string. Two candidates sharing a core are
*candidates* for being one body; geography decides it (see
`pf_cluster_arms()`).

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_arm_core(x)
```

</div>

</div>

<div class="section level2">

## Arguments

-   x:

    Character vector of organization names.

</div>

<div class="section level2">

## Value

Character vector of cores.

</div>

</div>
