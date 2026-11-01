<div id="main" class="col-md-9" role="main">

# Default locations of the linkid dyad extracts

<div class="ref-description section level2">

The `dyad_` extracts carry `ego_ein` and `alter_ein` already normalised.
The `efile_` variants of the same tables mirror the raw e-file column
names and **do not carry the filer EIN at all** — only `OBJECTID` — so
they cannot be used here without a separate object-id to EIN index.
Always use `dyad_`.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_dyad_sources(dir = "~/Documents/grants/linkid/out/full")
```

</div>

</div>

<div class="section level2">

## Arguments

-   dir:

    Directory holding linkid's `out/full` output.

</div>

<div class="section level2">

## Value

A named list of two file paths.

</div>

</div>
