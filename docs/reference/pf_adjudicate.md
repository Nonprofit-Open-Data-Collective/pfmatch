# Stage 4 — build the adjudication sheet

Wraps
[`pf_bmf_context()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_bmf_context.md),
[`pf_candidate_frame()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_candidate_frame.md),
and optionally
[`pf_purpose_tiebreak()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_purpose_tiebreak.md).
Produces the sheet a human or an LLM reviews.

## Usage

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

## Arguments

- x:

  A `pf_match` (from
  [`pf_match_grants()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_match_grants.md))
  or a `pf_linked` batch run.

- bmf:

  Processed BMF, for candidate and foundation context.

- ids:

  Grant ids to include. Defaults to every MAYBE.

- k:

  Candidates per grant.

- tiebreak:

  `FALSE`, `TRUE` for defaults, or a
  [`pf_tiebreak_config()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_tiebreak_config.md).

- org_text:

  Output of
  [`pf_build_org_text()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_build_org_text.md);
  required when `tiebreak` is not `FALSE`.

- verbose:

  Print progress.

## Value

A candidate-level data frame, one row per (grant, candidate).

## Details

The tiebreak is **off by default**. It gains 1 grant and loses 0 of the
6 changes we can check against adjudicated truth, out of 75 it makes on
a 5,000-grant run — real in direction, unestablished in magnitude. See
`dev/PURPOSE-MATCH-FINDINGS.md` §10 before switching it on.
