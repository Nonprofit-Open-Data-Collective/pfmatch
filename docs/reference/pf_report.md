<div id="main" class="col-md-9" role="main">

# Report on a grant-recipient match run

<div class="ref-description section level2">

Turns a `pf_match_grants()` result into the four-way outcome every grant
lands in, and crosstabs it against the standardized recipient type.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_status_levels()

pf_report(x, file = NULL)
```

</div>

</div>

<div class="section level2">

## Arguments

-   x:

    A `pf_match`.

-   file:

    Optional path; when given, the outcome frame and crosstab are also
    written as CSVs next to it.

</div>

<div class="section level2">

## Value

`pf_status_levels()`: the outcome levels in report order.

Invisibly, a list of the report tables.

</div>

<div class="section level2">

## Outcome levels

-   `YES` — one candidate cleared the auto-accept threshold with a clear
    lead

-   `MAYBE` — candidates surfaced but need adjudication (below
    threshold, a near-tie with the runner-up, or a soft veto)

-   `NO` — no candidate surfaced, or the best one scored below the
    review floor

-   `OOS` — out of sample: the recipient is not the kind of entity the
    BMF contains (a natural person, a government unit, a foreign
    organization), so there is nothing to find and the grant is not
    counted as a miss

</div>

</div>
