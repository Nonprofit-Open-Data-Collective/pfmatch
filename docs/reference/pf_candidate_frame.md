# Candidate-level adjudication frame

One row per (grant, candidate EIN) for the requested grants, carrying
the comparison signals, the BMF context for the candidate, the BMF
context for the *filing foundation*, and the grant purpose. This is the
sheet a human or an LLM adjudicates from.

## Usage

``` r
pf_candidate_frame(x, ids = NULL, k = 5, bmf_context = NULL)
```

## Arguments

- x:

  A `pf_match` from
  [`pf_match_grants()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_match_grants.md).

- ids:

  Grant ids to include. Defaults to every MAYBE.

- k:

  Maximum candidates per grant, by score.

- bmf_context:

  A table from
  [`pf_bmf_context()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_bmf_context.md).

## Value

A data frame, one row per candidate, ordered by grant then rank.
