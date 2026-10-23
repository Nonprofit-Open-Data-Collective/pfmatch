# Default locations of the linkid dyad extracts

The `dyad_` extracts carry `ego_ein` and `alter_ein` already normalised.
The `efile_` variants of the same tables mirror the raw e-file column
names and **do not carry the filer EIN at all** — only `OBJECTID` — so
they cannot be used here without a separate object-id to EIN index.
Always use `dyad_`.

## Usage

``` r
pf_dyad_sources(dir = "~/Documents/grants/linkid/out/full")
```

## Arguments

- dir:

  Directory holding linkid's `out/full` output.

## Value

A named list of two file paths.
