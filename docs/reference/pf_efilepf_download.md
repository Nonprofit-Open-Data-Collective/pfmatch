# Download the e-file 990-PF grants-paid extracts

Downloads to a staging name and renames on success, so an interrupted
run never leaves a truncated file that a later run would treat as
complete — the same discipline
[`pf_schedi_download()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_schedi_download.md)
uses.

## Usage

``` r
pf_efilepf_download(
  dir = pf_efilepf_dir(),
  years = pf_efilepf_years(),
  version = "efilepf_v3_1",
  table = pf_efilepf_table(),
  overwrite = FALSE,
  verbose = TRUE
)
```

## Arguments

- dir:

  Destination directory. Defaults to `~/Documents/grants/efilepf`,
  deliberately outside the package and outside any synced folder: the
  full set is several GB.

- years, version, table:

  Passed to
  [`pf_efilepf_url()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_efilepf_url.md).

- overwrite:

  Re-download files that already exist.

- verbose:

  Print progress.

## Value

Character vector of local paths, invisibly.
