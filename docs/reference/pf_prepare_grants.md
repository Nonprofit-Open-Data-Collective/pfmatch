<div id="main" class="col-md-9" role="main">

# Prepare a raw 990-PF grants extract

<div class="ref-description section level2">

Prepare a raw 990-PF grants extract

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_prepare_grants(grants, id_prefix = "G")
```

</div>

</div>

<div class="section level2">

## Arguments

-   grants:

    A data frame of the raw GTDC 990-PF current-grants extract (columns
    `SIGOCPYRPNAM`, `SIGOCPYRBNBN1`, ..., `SIGOCPYRFSTA`).

-   id_prefix:

    Prefix for the generated `grant_id` when the input has none.

</div>

<div class="section level2">

## Value

A data frame with the original columns plus the prepared recipient name
/ address fields, the standardized recipient type, and the scope
decision (`in_scope`, `oos_reason`).

</div>

</div>
