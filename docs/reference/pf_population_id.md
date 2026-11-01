<div id="main" class="col-md-9" role="main">

# Fingerprint a grant population

<div class="ref-description section level2">

Labels are not portable between grant vintages: `grant_id` is
positional, so the same id denotes a different grant in each population.
Measured directly, ids join across the two vintages at 96-97% while
recipient names agree on **0%**. Scoring a run against truth from
another population therefore produces confident nonsense, and
`pf_evaluate()` refuses it.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_population_id(grants)
```

</div>

</div>

<div class="section level2">

## Arguments

-   grants:

    A frame carrying `OBJECTID` (the e-file document id).

</div>

<div class="section level2">

## Value

A 16-character fingerprint.

</div>

</div>
