<div id="main" class="col-md-9" role="main">

# Download the Schedule I extracts

<div class="ref-description section level2">

Downloads to a staging name and renames on success, so an interrupted
run never leaves a truncated file that a later run would treat as
complete.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_schedi_download(
  dir = pf_schedi_dir(),
  years = pf_schedi_years(),
  version = "efile_v2_2",
  overwrite = FALSE,
  verbose = TRUE
)
```

</div>

</div>

<div class="section level2">

## Arguments

-   dir:

    Destination directory. Defaults to `~/Documents/grants` —
    deliberately outside the package and outside any synced folder,
    because the raw set is \~3.5 GB.

-   years, version:

    Passed to `pf_schedi_url()`.

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
