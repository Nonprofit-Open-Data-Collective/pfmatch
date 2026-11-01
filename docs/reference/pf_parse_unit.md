<div id="main" class="col-md-9" role="main">

# Parse the secondary-unit line into a comparable identifier

<div class="ref-description section level2">

Extracts the unit from a raw `PF_15_G_PAID_RECIP_ADDR_L2` value and
returns it as `type` plus `id`, or `""` for both when the line does not
hold a unit.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_parse_unit(x, street = NULL)
```

</div>

</div>

<div class="section level2">

## Arguments

-   x:

    Character vector of raw address line 2 values.

-   street:

    Optional street line, same length as `x`. When it names a PO box, a
    *bare* identifier in `x` is rejected: at a box address the digits on
    line 2 are a box or account number, not a door.
    `211 EMMET STREET SOUTH PO BOX` with `400891` on line 2 is the case.
    A value carrying an explicit designator is still read as a unit.

</div>

<div class="section level2">

## Value

A data frame with `type` and `id`, one row per input.

</div>

<div class="section level2">

## Details

A line is rejected when it is a PO box, when it looks like a street
address (a leading house number followed by a street-type word), or when
it carries no digits at all — `STREET`, `LAS VEGAS` and `114 HIGH ST`
are all real values of this field.

`type` separates room-level designators (`STE`, `UNIT`, `APT`, `RM`, …,
normalized to `STE`) from level-level ones (`FL`, `BLDG`, `TOWER`, …),
so that `FL 2` is not read as the same place as `STE 2`. A bare
identifier with no designator — `206`, `A-304` — gets type `""`, and
compares equal to a room-level unit with the same `id`, since a filer
writing `Suite 206` and one writing `206` at the same street mean the
same door.

</div>

<div class="section level2">

## See also

<div class="dont-index">

`pf_unit_evidence()`

</div>

</div>

</div>
