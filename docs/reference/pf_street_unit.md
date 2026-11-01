<div id="main" class="col-md-9" role="main">

# Parse the secondary-unit line into a comparable unit

<div class="ref-description section level2">

Extracts the unit from a raw `PF_15_G_PAID_RECIP_ADDR_L2` value and
returns it in npmatch's canonical `street_unit` spelling — `"STE 400"`,
`"FL 2"`, `"# 206"` — or `""` where the line holds no unit.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_street_unit(x, street = NULL)
```

</div>

</div>

<div class="section level2">

## Arguments

-   x:

    Character vector of raw address line 2 values.

-   street:

    Optional street line, same length as `x`, used for the box-number
    rejection. A value carrying an explicit designator is still read as
    a unit.

</div>

<div class="section level2">

## Value

A character vector the length of `x`, holding npmatch's canonical
`street_unit` string or `""`.

</div>

<div class="section level2">

## Details

The parse itself is npmatch's: the value is passed to
`npmatch::np_normalize()` as a `unit` column and `street_unit` is read
back, so pfmatch compares units the same way the matcher does and a
normalizer change moves both together. Values are de-duplicated before
normalizing, since line 2 repeats heavily.

Two rejections are applied on top, because `ADDR_L2` is not a unit field
— street lines, city names, PO boxes and prose all appear in it. Both
apply only to a *bare* identifier, one carrying no designator; a value
with an explicit designator is always read as a unit.

-   **No digits.** `STREET`, `WAY` and `CONSERVANCY` are real values of
    this field, and npmatch's bare-identifier path reads each as a unit
    id. The digit requirement is pfmatch's, and it is why it belongs on
    the bare path only: `SUITE B` is a real suite with no digit in it.

-   **A box number at a box street.** At
    `211 EMMET STREET SOUTH PO BOX`, the `400891` on line 2 is a box,
    not a door. See `.PF_BOX_RE`.

</div>

<div class="section level2">

## See also

<div class="dont-index">

`pf_unit_evidence()`, and `dev/UNIT-UPSTREAM-SYNC.md` for the decisions
this delegation settles.

</div>

</div>

</div>
