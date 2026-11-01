<div id="main" class="col-md-9" role="main">

# Build the BMF reference once

<div class="ref-description section level2">

Normalization, the name-frequency table, the token-IDF table, and the
blocking index are all functions of the reference alone, so they are
computed once here and reused across every pass, batch, and experiment.
This is **preprocessing** and is excluded from the match timings
reported by `pf_match_grants()`.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_build_reference(bmf, active_col = NULL)
```

</div>

</div>

<div class="section level2">

## Arguments

-   bmf:

    The raw processed BMF data frame (or a path to its CSV).

-   active_col:

    Optional column flagging BMF-active EINs (for the unified BMF). Omit
    for the active-only file.

</div>

<div class="section level2">

## Value

A list with the normalized `reference`, `name_freq`, `token_idf`, and
`ref_index`, plus the elapsed seconds each stage took.

</div>

</div>
