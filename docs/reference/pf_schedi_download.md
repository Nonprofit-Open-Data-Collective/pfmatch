# Download the Schedule I extracts

Downloads to a staging name and renames on success, so an interrupted
run never leaves a truncated file that a later run would treat as
complete.

## Usage

``` r
pf_schedi_download(
  dir = pf_schedi_dir(),
  years = pf_schedi_years(),
  version = "efile_v2_2",
  overwrite = FALSE,
  verbose = TRUE
)
```

## Arguments

- dir:

  Destination directory. Defaults to `~/Documents/grants` — deliberately
  outside the package and outside any synced folder, because the raw set
  is ~3.5 GB.

- years, version:

  Passed to
  [`pf_schedi_url()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_schedi_url.md).

- overwrite:

  Re-download files that already exist.

- verbose:

  Print progress.

## Value

Character vector of local paths, invisibly.
