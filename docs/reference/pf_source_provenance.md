<div id="main" class="col-md-9" role="main">

# The release pfmatch would read, as panel990 resolves it

<div class="ref-description section level2">

Recorded in run provenance so an artifact says which published release
and which concordance it was built against, rather than leaving it
implied.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_source_provenance()
```

</div>

</div>

<div class="section level2">

## Value

A named list: `efile_version`, `efile_root`, `efile_format`,
`concordance_version`, and `grants_table`. Entries are `NA` when the
relevant package is not installed.

</div>

</div>
