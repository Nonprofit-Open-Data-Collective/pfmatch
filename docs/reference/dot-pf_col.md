<div id="main" class="col-md-9" role="main">

# Read a grant column by either schema name

<div class="ref-description section level2">

Accepts a concordance990 v2 name or the legacy v1/GTDC name and returns
whichever the frame carries, so a reader works against both the
published ef2 files and artifacts built before the migration.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
.pf_col(g, name, default = NA_character_)
```

</div>

</div>

<div class="section level2">

## Arguments

-   g:

    A grant frame.

-   name:

    Column name in either schema.

-   default:

    Value when the column is absent in both schemas.

</div>

<div class="section level2">

## Value

A character vector, `nrow(g)` long.

</div>

<div class="section level2">

## Details

Returns `default` (recycled) when neither name is present. That is
deliberate for genuinely optional fields — 2025 has no
`PF_15_G_PAID_RECIP_STAT`, for instance — but it does mean a typo reads
as all-missing rather than erroring, so `.pf_require_cols()` guards the
columns a caller cannot proceed without.

</div>

</div>
