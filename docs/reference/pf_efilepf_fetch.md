<div id="main" class="col-md-9" role="main">

# Fetch the 990-PF grants-paid extracts via panel990

<div class="ref-description section level2">

Downloads the published ef2 tables for the requested years. Supersedes
`pf_efilepf_download()`, which built the S3 URL from a release pinned
inside this package.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_efilepf_fetch(
  years = pf_efilepf_years(),
  dir = pf_efilepf_dir(),
  version = NULL,
  format = NULL,
  verbose = TRUE
)
```

</div>

</div>

<div class="section level2">

## Arguments

-   years:

    Tax years to fetch. Defaults to `pf_efilepf_years()`.

-   dir:

    Destination directory. Defaults to `pf_efilepf_dir()`.

-   version:

    Published release such as `"v3_1"`. `NULL` (default) takes
    panel990's current default, which is the point of delegating.

-   format:

    `"parquet"` (panel990's default) or `"csv"`.

-   verbose:

    Print progress.

</div>

<div class="section level2">

## Value

Whatever `panel990::download_tables()` returns, invisibly: a frame
describing what was fetched.

</div>

</div>
