# Audit the standardization

Frequency table of raw status strings by assigned type, most common
first. Use it to find spellings the cascade still misses before trusting
the scope split on a new extract.

## Usage

``` r
pf_status_audit(x, detail = NULL, n = 50)
```

## Arguments

- x:

  Character vector of raw `SIGOCPYRFSTA` values.

- detail:

  Optional `recipient_type_detail` to restrict to (e.g.
  `"unrecognized"`).

- n:

  Maximum rows to return.

## Value

A data frame of `status_norm`, `recipient_type`,
`recipient_type_detail`, and count.
