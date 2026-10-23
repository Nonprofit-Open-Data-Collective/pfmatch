# Read the alias table, one row per (EIN, name)

Collapses the `(ein, name, city, state, zip5)` grain to `(ein, name)`,
keeping the best-corroborated address for each pairing, and drops names
that are ambiguous across EINs — a name used for two different
organizations cannot identify one of them.

## Usage

``` r
pf_schedi_alias(
  db = file.path(pf_schedi_dir(), "schedi_grants.duckdb"),
  min_filers = 2L,
  drop_ambiguous = TRUE
)
```

## Arguments

- db:

  Path to the DuckDB file.

- min_filers:

  Minimum distinct grantmakers. `1` admits everything (86% precision),
  `2` is the sensible floor (95%), `5` is auto-accept grade (98%).

- drop_ambiguous:

  Drop names that map to more than one EIN.

## Value

A `data.table`, one row per `(ein, name_norm)`.
