# Build the rebuilt grant file from the downloaded extracts

Reads one year at a time and appends, so peak memory is one year (~2M
rows) rather than the whole 17.5M-row table.

## Usage

``` r
pf_efilepf_build(
  dir = pf_efilepf_dir(),
  out,
  years = pf_efilepf_years(),
  schema = c("v2", "gtdc"),
  dedup = NULL,
  verbose = TRUE
)
```

## Arguments

- dir:

  Directory holding the downloaded CSVs.

- out:

  Output CSV path.

- years:

  Years to include.

- schema:

  `"v2"` for the published concordance990 names and full metadata,
  `"gtdc"` for the legacy v1 names.

- dedup:

  Drop superseded and duplicate filings with
  [`pf_efilepf_dedup()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_efilepf_dedup.md).
  Requires `schema = "v2"`, since the legacy schema discards the flags
  the rule needs.

- verbose:

  Print progress.

## Value

A one-row-per-year `data.frame` of counts, invisibly.

## Details

Two e-file columns are carried through in addition to the GTDC schema,
because they are free here and the GTDC file had no equivalent:
`OBJECTID`, which identifies the source return, and `efile_year`, the
extract the row came from (distinct from `TAXYEAR` when a return is
filed late or amended).

## Schema

`schema = "v2"` (the default) keeps the ef2 columns **as published**,
with their concordance990 v2 names (`PF_15_G_PAID_*`) and the full
filing metadata. `schema = "gtdc"` reproduces the legacy behaviour:
rename to the v1 GTDC names via
[`pf_efilepf_map()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_efilepf_map.md)
and keep only those columns.

The legacy path exists to reproduce artifacts built before the
migration. It is a **downgrade**: the published files already carry the
current names, and renaming them to v1 also discarded ten standardized
columns. Two of those matter beyond tidiness — `TABLE_ID`, the
within-filing row counter that makes `OBJECTID + TABLE_ID` a unique row
key, and `RETURN_AMENDED_X` / `RETURN_PARTIAL_X`, without which
superseded filings cannot be identified. Dropping `TABLE_ID` is why a
content hash once had to be invented for a key the data already
published.
