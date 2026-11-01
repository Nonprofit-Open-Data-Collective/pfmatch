<div id="main" class="col-md-9" role="main">

# Candidate pairs from a near-miss name inside a geographic block

<div class="ref-description section level2">

Jaro-Winkler similarity on `name_key` within an exact ZIP5 block,
falling back to city plus state where the ZIP5 block is empty. Blocking
first is what makes this affordable: the pools are small (median 477
reference rows on the NO sample, largest 2,940) and scoring one takes
microseconds, against the 223,151 candidates pass B2 generates on 5,000
grants.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_fuzzy_candidates(
  query,
  reference,
  cutoff = 0.9,
  top_k = 5L,
  block = c("zip5", "city_state"),
  personal = NULL,
  skip_personal = TRUE,
  max_pool = 20000L,
  verbose = TRUE
)
```

</div>

</div>

<div class="section level2">

## Arguments

-   query:

    A normalized query frame (from `npmatch::np_normalize()`) carrying
    `name_key`, `zip5`, `city` and `state`.

-   reference:

    A normalized reference frame with the same four columns.

-   cutoff:

    Minimum Jaro-Winkler similarity. Read the section above before
    lowering it.

-   top_k:

    Most candidates to emit per query row.

-   block:

    Which blocks to try, in order. `"city_state"` is a fallback for a
    query row whose ZIP5 matches no reference row (6 of 91 on the NO
    sample), not an additional pass: a row the ZIP5 block resolved is
    not retried.

-   personal:

    Optional logical vector, one per query row, from `looks_personal` on
    the prepared grants. Passed positionally, the same way
    `pf_add_recovery_keys()` takes `only_truncated`.

-   skip_personal:

    Drop query rows flagged `personal` before scoring.

-   max_pool:

    Refuse to score a block larger than this, and say so. A guard
    against a degenerate key – an all-blank ZIP5 column collapsing the
    whole reference into one block – not a tuning parameter.

-   verbose:

    Report pool sizes and how many pairs were emitted.

</div>

<div class="section level2">

## Value

An `np_blocks` frame of `.x` / `.y` indices, with a `sim` attribute
holding the similarity of each emitted pair.

</div>

<div class="section level2">

## On the cutoff

The default of 0.90 is set from measurement, not taste. Scoring all 91
cases of the NO sample against their own ZIP5 pools:

-   0.90 recovers 7 of the 33 identities the BMF does hold, and offers
    exactly one row across the 57 it does not – `SEE SCHEDULE ATTACHED`
    against `SEE SCHEDULE O`, which the placeholder filter below
    removes.

-   0.85 recovers 11 of the 33, four more, but the highest-scoring
    personal name sits at 0.848: `ALEXANDER SCHWEIG` against
    `ALEXANDER GRAHAM BELL ASSOCIATION`. A one-point margin on 38
    individuals is not a margin.

That near-collision is structural rather than bad luck. Jaro-Winkler's
prefix bonus is exactly what rewards a shared first name, so individuals
are the population this comparator is worst at excluding, and
`skip_personal` exists to keep them out of the pool rather than leaving
the cutoff to catch them.

</div>

<div class="section level2">

## See also

<div class="dont-index">

`pf_fuzzy_recover()`, `pf_staged_passes()`

</div>

</div>

</div>
