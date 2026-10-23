# Stage 2 — the BMF reference bundle

Wraps
[`pf_build_reference()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_build_reference.md)
with an on-disk cache and adds the stage-4 recovery keys
([`pf_add_recovery_keys()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_add_recovery_keys.md)),
so the bundle handed to the cascade is complete. This is preprocessing
and is excluded from match timings.

## Usage

``` r
pf_reference(
  bmf,
  cache = "data-dev/BMF-REFERENCE-BUNDLE.rds",
  active_col = NULL,
  recovery = TRUE,
  verbose = TRUE
)
```

## Arguments

- bmf:

  Processed BMF: a path or a data frame.

- cache:

  Path to cache the bundle (`.rds`). `NULL` disables caching.

- active_col:

  Optional BMF-active flag column.

- recovery:

  Add acronym / prefix blocking keys to the reference.

- verbose:

  Print progress.

## Value

The reference bundle list from
[`pf_build_reference()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_build_reference.md).
