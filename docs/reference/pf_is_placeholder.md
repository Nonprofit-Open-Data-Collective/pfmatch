<div id="main" class="col-md-9" role="main">

# Flag grant rows whose recipient is a pointer to an attachment

<div class="ref-description section level2">

Flag grant rows whose recipient is a pointer to an attachment

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_is_placeholder(grants, name_col = "recip_name")
```

</div>

</div>

<div class="section level2">

## Arguments

-   grants:

    A prepared frame from `pf_prepare_grants()`.

-   name_col:

    Column holding the recipient name.

</div>

<div class="section level2">

## Value

A logical vector.

</div>

</div>
