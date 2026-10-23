# Read a grant column by either schema name

Accepts a concordance990 v2 name or the legacy v1/GTDC name and returns
whichever the frame carries, so a reader works against both the
published ef2 files and artifacts built before the migration.

## Usage

``` r
.pf_col(g, name, default = NA_character_)
```

## Arguments

- g:

  A grant frame.

- name:

  Column name in either schema.

- default:

  Value when the column is absent in both schemas.

## Value

A character vector, `nrow(g)` long.

## Details

Returns `default` (recycled) when neither name is present. That is
deliberate for genuinely optional fields — 2025 has no
`PF_15_G_PAID_RECIP_STAT`, for instance — but it does mean a typo reads
as all-missing rather than erroring, so
[`.pf_require_cols()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/dot-pf_require_cols.md)
guards the columns a caller cannot proceed without.
