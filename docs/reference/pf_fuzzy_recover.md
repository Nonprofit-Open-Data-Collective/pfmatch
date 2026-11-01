<div id="main" class="col-md-9" role="main">

# Retry the unresolved residual with fuzzy candidates

<div class="ref-description section level2">

Generates fuzzy pairs for every identity the cascade did not clear,
scores them through `npmatch::np_compare()` and `npmatch::np_score()`,
unions them with the pairs the cascade already retained, and re-runs
selection and tiering over that union.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_fuzzy_recover(
  m,
  ref,
  cutoff = 0.9,
  top_k = 5L,
  block = c("zip5", "city_state"),
  skip_personal = TRUE,
  max_pool = 20000L,
  verbose = TRUE
)
```

</div>

</div>

<div class="section level2">

## Arguments

-   m:

    A `pf_match` object from `pf_match_grants()`, with its `pairs`
    attribute intact.

-   ref:

    The same reference bundle the match was run against.

-   cutoff, top_k, block, skip_personal, max_pool:

    Passed to `pf_fuzzy_candidates()`.

-   verbose:

    Report the residual size, pairs added and tier movement.

</div>

<div class="section level2">

## Value

A list with `result` (the re-tiered frame), `before` and `after` tier
tables, `moved` (the identities whose tier changed, with their fuzzy
similarity), and `n` (counts).

</div>

<div class="section level2">

## Why the union, and not the fuzzy pairs alone

Selecting over the fuzzy pairs by themselves would let a fuzzy row win
an identity that an exact pass had already beaten on the same identity –
26 of the 33 recoverable NO cases *did* have candidates, scored and
rejected, so this is the common case rather than an edge one.
`npmatch::np_cascade()` makes its own final decision over the deduped
union of every pass, and this reproduces that: the fuzzy pairs are one
more pass's worth of rows, competing on the same footing.

A consequence worth stating, because it is the regression question: an
identity that already cleared YES is not in the residual, no pair is
added to it, and its selection is therefore bit-identical. The function
asserts that rather than trusting it.

</div>

<div class="section level2">

## What it is NOT limited to

The residual is every identity that has not cleared YES, which on the
production run is 845 NO *and* 1,044 MAYBE. "NO" is a tier assigned
after scoring, so it cannot be blocked on; and `npmatch::np_cascade()`
drops an identity from `pending` only when a pass clears it to YES,
which is the same rule. So this changes the MAYBE tier too – it adds
rows to the adjudication queue and can change which row a MAYBE identity
is holding. That is where a regression has to look; the YES set is
protected by construction.

</div>

<div class="section level2">

## See also

<div class="dont-index">

`pf_fuzzy_candidates()`, `pf_recover_from_dictionary()`

</div>

</div>

</div>
