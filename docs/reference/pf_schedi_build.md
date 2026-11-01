<div id="main" class="col-md-9" role="main">

# Load the extracts into DuckDB and reduce them to an alias table

<div class="ref-description section level2">

Three tables are created. `grants_raw` is the union of the yearly CSVs
(`union_by_name`, because the pre-2019 files predate the
`RecipientTable` column). `recip` is one normalized row per grant.
`alias` is the payload: one row per distinct
`(ein, name_norm, city, state, zip5)` with `n_obs` and `n_filers`.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_schedi_build(
  dir = pf_schedi_dir(),
  db = file.path(dir, "schedi_grants.duckdb"),
  rebuild = FALSE,
  threads = 4L
)
```

</div>

</div>

<div class="section level2">

## Arguments

-   dir:

    Directory holding the CSVs.

-   db:

    Path to the DuckDB file.

-   rebuild:

    Reload even if `grants_raw` already exists.

-   threads:

    DuckDB thread count.

</div>

<div class="section level2">

## Value

`db`, invisibly.

</div>

<div class="section level2">

## Details

`n_filers` is the trust signal and the reason this works — it counts
*independent* observations, so it separates a real alias from one
filer's typo. See the precision table in
[pf_schedi](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_schedi.md).

</div>

</div>
