# Recover a recipient name typed into the street field

Some rows carry the organization name in `SIGOCPYRFAAL1` with the name
fields blank (`Society of Jesus NY Province`, `St Ignatius School`), or
a placeholder such as `x` in the name field. Detected by the street
value looking nothing like a street: no leading house number, no PO box,
and no USPS street-type token.

## Usage

``` r
pf_recover_name_from_street(grants, verbose = TRUE)
```

## Arguments

- grants:

  A prepared frame from
  [`pf_prepare_grants()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_prepare_grants.md).

- verbose:

  Report how many rows were repaired.

## Value

`grants` with `recip_name` filled from `recip_street` where applicable,
and a logical `name_from_street` column recording it.

## Details

Measured on 55,000 grants this fires on ~6 rows, so it is a correctness
guard rather than a recall lever — but the alternative is matching on a
name that is known to be wrong.
