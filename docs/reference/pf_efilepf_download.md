<div id="main" class="col-md-9" role="main">

# Download the e-file 990-PF grants-paid extracts

<div class="ref-description section level2">

Downloads to a staging name and renames on success, so an interrupted
run never leaves a truncated file that a later run would treat as
complete — the same discipline `pf_schedi_download()` uses.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

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

</div>

</div>

<div class="section level2">

## Arguments

-   dir:

    Destination directory. Defaults to `~/Documents/grants/efilepf`,
    deliberately outside the package and outside any synced folder: the
    full set is several GB.

-   years, version, table:

    Passed to `pf_efilepf_url()`.

-   overwrite:

    Re-download files that already exist.

-   verbose:

    Print progress.

</div>

<div class="section level2">

## Value

Character vector of local paths, invisibly.

</div>

</div>
