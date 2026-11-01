<div id="main" class="col-md-9" role="main">

# Append Schedule I alias rows to the BMF

<div class="ref-description section level2">

Emits one extra reference row per `(ein, alias name)` that the BMF does
not already carry, copying every other field — NTEE, subsection,
foundation code, filing requirement — from that EIN's own BMF row, so
the augmented file is a drop-in for the plain one.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_bmf_augment(
  bmf,
  alias,
  address = c("alias", "bmf"),
  name_col = "org_name_join",
  display_col = "org_name_display",
  ein_col = "ein",
  verbose = TRUE
)
```

</div>

</div>

<div class="section level2">

## Arguments

-   bmf:

    The BMF: a path or a data frame. Works with either the active file
    or the unified (active + inactive) one — the unified file attaches
    8.4 points more of the alias table (64.8% of alias EINs vs 56.4%).

-   alias:

    Output of `pf_schedi_alias()`.

-   address:

    `"alias"` or `"bmf"`.

-   name_col, display_col, ein_col:

    BMF column names.

-   verbose:

    Print the difference report.

</div>

<div class="section level2">

## Value

The BMF with alias rows appended and three provenance columns:
`row_source` (`"bmf"` / `"schedi"`), `alias_n_filers`,
`alias_last_year`.

</div>

<div class="section level2">

## Details

Only the **name** varies by default. The alias address is used because
that is how grantmakers write it, which is the premise of the whole
source; pass `address = "bmf"` to keep the BMF's own address instead.

</div>

</div>
