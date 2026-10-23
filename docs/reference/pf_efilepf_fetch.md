# Fetch the 990-PF grants-paid extracts via panel990

Downloads the published ef2 tables for the requested years. Supersedes
[`pf_efilepf_download()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_efilepf_download.md),
which built the S3 URL from a release pinned inside this package.

## Usage

``` r
pf_efilepf_fetch(
  years = pf_efilepf_years(),
  dir = pf_efilepf_dir(),
  version = NULL,
  format = NULL,
  verbose = TRUE
)
```

## Arguments

- years:

  Tax years to fetch. Defaults to
  [`pf_efilepf_years()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_efilepf.md).

- dir:

  Destination directory. Defaults to
  [`pf_efilepf_dir()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_efilepf.md).

- version:

  Published release such as `"v3_1"`. `NULL` (default) takes panel990's
  current default, which is the point of delegating.

- format:

  `"parquet"` (panel990's default) or `"csv"`.

- verbose:

  Print progress.

## Value

Whatever
[`panel990::download_tables()`](https://rdrr.io/pkg/panel990/man/download_tables.html)
returns, invisibly: a frame describing what was fetched.
