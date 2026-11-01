<div id="main" class="col-md-9" role="main">

# URL for one year of the e-file 990-PF grants-paid extract

<div class="ref-description section level2">

URL for one year of the e-file 990-PF grants-paid extract

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_efilepf_url(
  year,
  version = "efilepf_v3_1",
  table = pf_efilepf_table(),
  format = c("csv", "parquet")
)
```

</div>

</div>

<div class="section level2">

## Arguments

-   year:

    Tax year.

-   version:

    NCCS extract version. **Use `efilepf_v3_1`** — see the version trap
    in
    [pf_efilepf](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_efilepf.md).

-   table:

    Table stem; defaults to `pf_efilepf_table()`.

-   format:

    `"csv"` or `"parquet"`. Both are published per year.

</div>

<div class="section level2">

## Value

A single URL string.

</div>

</div>
