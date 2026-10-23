# The distinct recipient frame to actually match

One row per `recipient_uid`, choosing the **most complete**
representative of each cluster (longest name, then most address fields
populated) so the match runs against the best available spelling rather
than an arbitrary one.

## Usage

``` r
pf_recipients(grants)
```

## Arguments

- grants:

  Output of
  [`pf_dedup()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_dedup.md).

## Value

A data frame with one row per identity, carrying `recipient_uid` as the
match key.
