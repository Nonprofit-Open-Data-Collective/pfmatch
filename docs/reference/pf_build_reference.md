# Build the BMF reference once

Normalization, the name-frequency table, the token-IDF table, and the
blocking index are all functions of the reference alone, so they are
computed once here and reused across every pass, batch, and experiment.
This is **preprocessing** and is excluded from the match timings
reported by
[`pf_match_grants()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_match_grants.md).

## Usage

``` r
pf_build_reference(bmf, active_col = NULL)
```

## Arguments

- bmf:

  The raw processed BMF data frame (or a path to its CSV).

- active_col:

  Optional column flagging BMF-active EINs (for the unified BMF). Omit
  for the active-only file.

## Value

A list with the normalized `reference`, `name_freq`, `token_idf`, and
`ref_index`, plus the elapsed seconds each stage took.
