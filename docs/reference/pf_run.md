<div id="main" class="col-md-9" role="main">

# Run the whole pipeline

<div class="ref-description section level2">

`pf_prepare()` -> `pf_reference()` -> `pf_link()` -> `pf_report()`.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_run(
  grants,
  bmf = NULL,
  pattern = "grants.*[.]csv$",
  dedup = c("fuzzy", "exact", "none"),
  ref_cache = "data-dev/BMF-REFERENCE-BUNDLE.rds",
  dir = "data-dev/batches",
  batch_size = 25000L,
  dyads = NULL,
  report = TRUE,
  verbose = TRUE,
  ref_source = c("auto", "matchdb", "local"),
  tier = getOption("pfmatch.matchdb_tier", "active-observed"),
  ...
)
```

</div>

</div>

<div class="section level2">

## Arguments

-   grants, pattern, dedup:

    Passed to `pf_prepare()`.

-   bmf, ref_cache:

    Passed to `pf_reference()`. With no `bmf`, the reference is the
    matchdb tier, falling back to the bundle at `ref_cache`.

-   dir, batch_size, dyads:

    Passed to `pf_link()`. `dyads` may be a table or a path to a cached
    one.

-   report:

    Print the outcome tables when done.

-   verbose:

    Print progress.

-   ref_source, tier:

    Passed to `pf_reference()` as `source` and `tier`.

-   ...:

    Further arguments to `pf_link()`.

</div>

<div class="section level2">

## Value

A list of class `pf_run` with `grants`, `recipients`, `status`, and
`timing`. The reference bundle is deliberately **not** returned — it is
\~1.3 GB and is on disk (at `ref_cache`, or in matchdb's cache).

</div>

</div>
