# Fingerprint a grant population

Labels are not portable between grant vintages: `grant_id` is
positional, so the same id denotes a different grant in each population.
Measured directly, ids join across the two vintages at 96-97% while
recipient names agree on **0%**. Scoring a run against truth from
another population therefore produces confident nonsense, and
[`pf_evaluate()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_evaluate.md)
refuses it.

## Usage

``` r
pf_population_id(grants)
```

## Arguments

- grants:

  A frame carrying `OBJECTID` (the e-file document id).

## Value

A 16-character fingerprint.
