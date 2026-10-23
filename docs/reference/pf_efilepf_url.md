# URL for one year of the e-file 990-PF grants-paid extract

URL for one year of the e-file 990-PF grants-paid extract

## Usage

``` r
pf_efilepf_url(
  year,
  version = "efilepf_v3_1",
  table = pf_efilepf_table(),
  format = c("csv", "parquet")
)
```

## Arguments

- year:

  Tax year.

- version:

  NCCS extract version. **Use `efilepf_v3_1`** — see the version trap in
  [pf_efilepf](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_efilepf.md).

- table:

  Table stem; defaults to
  [`pf_efilepf_table()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_efilepf.md).

- format:

  `"csv"` or `"parquet"`. Both are published per year.

## Value

A single URL string.
