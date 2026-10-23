# The release pfmatch would read, as panel990 resolves it

Recorded in run provenance so an artifact says which published release
and which concordance it was built against, rather than leaving it
implied.

## Usage

``` r
pf_source_provenance()
```

## Value

A named list: `efile_version`, `efile_root`, `efile_format`,
`concordance_version`, and `grants_table`. Entries are `NA` when the
relevant package is not installed.
