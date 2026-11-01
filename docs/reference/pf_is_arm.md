<div id="main" class="col-md-9" role="main">

# Is this name a fundraising or support arm?

<div class="ref-description section level2">

Detects the arm by name shape alone: a trailing support marker
(`FOUNDATION`, `ENDOWMENT`, `AUXILIARY`, `ALUMNI ASSOCIATION`, ...) or a
leading one (`FRIENDS OF`). Checked against Schedule A, the shape is
right 271 times in 276 — the five exceptions are bodies legally named
`... FOUNDATION` that are themselves the operating entity and are
supported by a differently-named arm.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_is_arm(x)
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

Logical vector.

</div>

<div class="section level2">

## See also

<div class="dont-index">

`pf_arm_core()`, `pf_cluster_arms()`

</div>

</div>

</div>
