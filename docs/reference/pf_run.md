# Run the whole pipeline

[`pf_prepare()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_prepare.md)
-\>
[`pf_reference()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_reference.md)
-\>
[`pf_link()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_link.md)
-\>
[`pf_report()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_report.md).

## Usage

``` r
pf_run(
  grants,
  bmf,
  pattern = "grants.*[.]csv$",
  dedup = c("fuzzy", "exact", "none"),
  ref_cache = "data-dev/BMF-REFERENCE-BUNDLE.rds",
  dir = "data-dev/batches",
  batch_size = 25000L,
  dyads = NULL,
  report = TRUE,
  verbose = TRUE,
  ...
)
```

## Arguments

- grants, pattern, dedup:

  Passed to
  [`pf_prepare()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_prepare.md).

- bmf, ref_cache:

  Passed to
  [`pf_reference()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_reference.md).

- dir, batch_size, dyads:

  Passed to
  [`pf_link()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_link.md).
  `dyads` may be a table or a path to a cached one.

- report:

  Print the outcome tables when done.

- verbose:

  Print progress.

- ...:

  Further arguments to
  [`pf_link()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_link.md).

## Value

A list of class `pf_run` with `grants`, `recipients`, `status`, and
`timing`. The reference bundle is deliberately **not** returned — it is
~1.3 GB and is on disk at `ref_cache`.
