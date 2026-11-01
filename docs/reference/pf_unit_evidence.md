<div id="main" class="col-md-9" role="main">

# Compare two unit lines as adjudication evidence

<div class="ref-description section level2">

Compare two unit lines as adjudication evidence

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_unit_evidence(a, b, street_a = NULL, street_b = NULL)
```

</div>

</div>

<div class="section level2">

## Arguments

-   a, b:

    Raw address line 2 values, the anchor's and the candidate's.

-   street_a, street_b:

    Optional street lines, passed through to `pf_street_unit()` so a box
    number is not read as a suite.

</div>

<div class="section level2">

## Value

A character vector, one per pair:

-   `conflict`:

    Both parse to a unit and they disagree. Two different doors at one
    street, so the two renderings are very likely different
    organizations and a triangulated label assigning them one EIN is
    probably wrong. This is the case worth a reviewer's attention.

-   `agree`:

    Both parse and match. **Do not read this as support for one
    organization.** Measured on the triangulation run it is close to
    worthless: `SUITE 100`, `SUITE 300` and `SUITE 400` are shared by
    unrelated tenants (`MIDDLE EAST CHILDRENS ALLIANCE` and
    `IRISH REPERTORY THEATER` both at Suite 100; `GLOBAL FUND FOR WOMEN`
    and `THAKKER CHARITABLE TRUST` both at Suite 400), a fiscal
    sponsor's suite is shared by everything it sponsors, and some values
    are not units at all — `15219` is a Pittsburgh ZIP code sitting on
    line 2. It is recorded for completeness, not as evidence.

-   `one_sided`:

    One parses, the other does not. Carries nothing — filers omit the
    line constantly, so silence is not disagreement.

-   `absent`:

    Neither parses.

Two units agree when their identifiers match **and** their designators
fall in the same class: the room-level designators are interchangeable
(`.PF_UNIT_ROOM`), everything else is not, so `UNIT 1200` is `STE 1200`
but `FL 2` is not `STE 2`. This is where pfmatch departs from npmatch,
which compares `street_unit_id` alone and so reads a floor as a suite.
Upstream the cost is a missing 0.97 rung in a `max()` ladder; here it
would be a false `agree`, which no reviewer ever looks at.

Against npmatch's own pair annotations: `conflict` and `agree` are
`geo_unit == 0` and `geo_unit == 1` under the stricter designator rule
above, and `one_sided` and `absent` are the two halves of
`geo_unit == NA` that `geo_unit` cannot tell apart. The crowding half of
the annotation — `addr_shared`, `addr_units`, `addr_unit_shared`,
`addr_note` — has no counterpart here and should be taken from
`np_compare()` rather than reinvented; see `dev/PLACES-SYNC.md` §4.5.

`conflict` fires on 0.47% of candidate pairs in the triangulation run —
69 of 14,790, of which 19 sit on a `MAYBE` candidate and so reach the
adjudication queue. It is a rare, sharp signal, not a routine one, and
it concentrates: one address (a fellowship program writing a sequential
counter into line 2, one per individual grantee) produced 31 of the 69.
A conflict is a prompt for a reviewer, never an automatic verdict. See
the "Name and address variants" vignette for the full rates.

</div>

<div class="section level2">

## See also

<div class="dont-index">

`pf_street_unit()`

</div>

</div>

</div>
