# URL for one Schedule I extract

URL for one Schedule I extract

## Usage

``` r
pf_schedi_url(year, version = "efile_v2_2")
```

## Arguments

- year:

  Tax year.

- version:

  NCCS extract version. **Use `efile_v2_2`**: `efile_v2_1` has the same
  schema but roughly a tenth of the rows at identical bytes-per-row
  (641k vs 66k grants in 2024), i.e. it is a partial or superseded
  extract.
