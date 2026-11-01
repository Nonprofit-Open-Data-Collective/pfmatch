<div id="main" class="col-md-9" role="main">

# Stage 4 — build the adjudication sheet

<div class="ref-description section level2">

Wraps `pf_bmf_context()`, `pf_candidate_frame()`, and optionally
`pf_purpose_tiebreak()`. Produces the sheet a human or an LLM reviews.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_adjudicate(
  x,
  bmf,
  ids = NULL,
  k = 5,
  tiebreak = FALSE,
  org_text = NULL,
  verbose = TRUE
)
```

</div>

</div>

<div class="section level2">

## Arguments

-   x:

    A `pf_match` (from `pf_match_grants()`) or a `pf_linked` batch run.

-   bmf:

    Processed BMF, for candidate and foundation context.

-   ids:

    Grant ids to include. Defaults to every MAYBE.

-   k:

    Candidates per grant.

-   tiebreak:

    `FALSE`, `TRUE` for defaults, or a `pf_tiebreak_config()`.

-   org_text:

    Output of `pf_build_org_text()`; required when `tiebreak` is not
    `FALSE`.

-   verbose:

    Print progress.

</div>

<div class="section level2">

## Value

A candidate-level data frame, one row per (grant, candidate).

</div>

<div class="section level2">

## Details

The tiebreak is **off by default**. It gains 1 grant and loses 0 of the
6 changes we can check against adjudicated truth, out of 75 it makes on
a 5,000-grant run — real in direction, unestablished in magnitude. See
`dev/PURPOSE-MATCH-FINDINGS.md` §10 before switching it on.

</div>

</div>
