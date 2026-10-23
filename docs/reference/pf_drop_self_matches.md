# Never match a grant to the foundation that made it

A 990-PF grant row is a payment *from* the filing foundation, so the
filer's own EIN can never be the recipient. The MAYBE audit caught this
happening: `SIGMA GAMMA ASSOCATION` was matched to
`SIGMA GAMMA FOUNDATION`, which is the filer — a confident, well-scored,
structurally impossible answer. The correct recipient sat at rank 2.

## Usage

``` r
pf_drop_self_matches(x, verbose = TRUE)
```

## Arguments

- x:

  A `pf_match` result from
  [`pf_match_grants()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_match_grants.md).

- verbose:

  Report how many pairs were removed.

## Value

`x` with self-matched pairs dropped and selection/tiering recomputed, so
a query whose winner was its own filer falls back to its next-best
candidate instead of being lost.

## Details

This is a hard constraint rather than a scoring adjustment: no amount of
name or address agreement makes a self-match valid.
