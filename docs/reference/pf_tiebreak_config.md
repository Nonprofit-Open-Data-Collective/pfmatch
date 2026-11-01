<div id="main" class="col-md-9" role="main">

# Tiebreak settings

<div class="ref-description section level2">

Tiebreak settings

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_tiebreak_config(
  tie_band = 0.05,
  tie_high = 0.95,
  keys = c("cov_all", "has_mission")
)
```

</div>

</div>

<div class="section level2">

## Arguments

-   tie_band:

    Candidates within this much of the top score are in contention.
    Matches npmatch's `np_config()$tie_band`.

-   tie_high:

    Only tiebreak when the top score is at least this. npmatch defaults
    to 0.95; setting it to 0 widens the tiebreak to every near-tie,
    which on the audit sample raises the gain from +1 to +3 of 61 grants
    but is a change to selection behaviour that 61 grants cannot
    justify.

-   keys:

    Ordered tiebreak keys, applied in sequence until one separates the
    contenders. `cov_all` is the purpose comparison; `has_mission` is
    whether the candidate files a Form 990 with a mission statement at
    all.

</div>

<div class="section level2">

## Value

A list.

</div>

</div>
