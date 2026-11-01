<div id="main" class="col-md-9" role="main">

# Candidate-level adjudication frame

<div class="ref-description section level2">

One row per (grant, candidate EIN) for the requested grants, carrying
the comparison signals, the BMF context for the candidate, the BMF
context for the *filing foundation*, and the grant purpose. This is the
sheet a human or an LLM adjudicates from.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_candidate_frame(x, ids = NULL, k = 5, bmf_context = NULL)
```

</div>

</div>

<div class="section level2">

## Arguments

-   x:

    A `pf_match` from `pf_match_grants()`.

-   ids:

    Grant ids to include. Defaults to every MAYBE.

-   k:

    Maximum candidates per grant, by score.

-   bmf_context:

    A table from `pf_bmf_context()`.

</div>

<div class="section level2">

## Value

A data frame, one row per candidate, ordered by grant then rank.

</div>

</div>
