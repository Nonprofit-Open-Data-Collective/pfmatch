# Stage 4 recovery passes

Appended after
[`pf_staged_passes()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_staged_passes.md).
Every pass here runs only on the residual the earlier stages could not
resolve, so the cost is bounded by how few queries are left rather than
by the size of the reference.

## Usage

``` r
pf_recovery_passes(state = TRUE, max_ref_freq = 5000, min_pair_idf = 8)
```

## Arguments

- state:

  Block these passes on state as well. `TRUE` keeps them cheap; `FALSE`
  is the recall-maximising setting for a small residual.

- max_ref_freq, min_pair_idf:

  Token pruning for the acronym pass.

## Value

A list of pass specifications.

## On the YES bar

Acronym and prefix matches are structurally weaker evidence than a
full-name match — an acronym is a lossy encoding and many organizations
share one. They are expected to land mostly in MAYBE unless the address
corroborates, which is the correct outcome: npmatch's acronym-aware
overlap in
[`npmatch::np_compare()`](https://nonprofit-open-data-collective.github.io/npmatch/reference/np_compare.html)
only fires when the address is confirmed, and caps such matches below
YES otherwise.
