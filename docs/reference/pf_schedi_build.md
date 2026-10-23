# Load the extracts into DuckDB and reduce them to an alias table

Three tables are created. `grants_raw` is the union of the yearly CSVs
(`union_by_name`, because the pre-2019 files predate the
`RecipientTable` column). `recip` is one normalized row per grant.
`alias` is the payload: one row per distinct
`(ein, name_norm, city, state, zip5)` with `n_obs` and `n_filers`.

## Usage

``` r
pf_schedi_build(
  dir = pf_schedi_dir(),
  db = file.path(dir, "schedi_grants.duckdb"),
  rebuild = FALSE,
  threads = 4L
)
```

## Arguments

- dir:

  Directory holding the CSVs.

- db:

  Path to the DuckDB file.

- rebuild:

  Reload even if `grants_raw` already exists.

- threads:

  DuckDB thread count.

## Value

`db`, invisibly.

## Details

`n_filers` is the trust signal and the reason this works — it counts
*independent* observations, so it separates a real alias from one
filer's typo. See the precision table in
[pf_schedi](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_schedi.md).
