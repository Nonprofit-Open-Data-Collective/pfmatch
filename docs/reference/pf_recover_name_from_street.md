<div id="main" class="col-md-9" role="main">

# Recover a recipient name typed into the street field

<div class="ref-description section level2">

Some rows carry the organization name in `SIGOCPYRFAAL1` with the name
fields blank (`Society of Jesus NY Province`, `St Ignatius School`), or
a placeholder such as `x` in the name field. Detected by the street
value looking nothing like a street: no leading house number, no PO box,
and no USPS street-type token.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_recover_name_from_street(grants, verbose = TRUE)
```

</div>

</div>

<div class="section level2">

## Arguments

-   grants:

    A prepared frame from `pf_prepare_grants()`.

-   verbose:

    Report how many rows were repaired.

</div>

<div class="section level2">

## Value

`grants` with `recip_name` filled from `recip_street` where applicable,
and a logical `name_from_street` column recording it.

</div>

<div class="section level2">

## Details

Measured on 55,000 grants this fires on \~6 rows, so it is a correctness
guard rather than a recall lever — but the alternative is matching on a
name that is known to be wrong.

</div>

</div>
