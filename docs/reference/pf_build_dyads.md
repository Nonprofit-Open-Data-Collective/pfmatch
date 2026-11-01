<div id="main" class="col-md-9" role="main">

# Build the dyad table

<div class="ref-description section level2">

Reads the Schedule A and Schedule R dyad extracts, keeps rows where both
ends carry a usable EIN, symmetrises to one row per unordered pair, and
classifies each pair as `substitutable` or `related`.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_build_dyads(
  supported = pf_dyad_sources()$supported,
  related = pf_dyad_sources()$related,
  bmf = NULL,
  min_years = 1L,
  max_fanout = 3L,
  max_degree = 5L,
  cache = NULL,
  verbose = TRUE
)
```

</div>

</div>

<div class="section level2">

## Arguments

-   supported:

    Path to `dyad_supported_orgs.csv`, or the table itself. `NULL` to
    skip Schedule A.

-   related:

    Path to `dyad_related_exempt_orgs.csv`, or the table itself. `NULL`
    to skip Schedule R.

-   bmf:

    Processed BMF (path or data frame). Supplies the names used for the
    name-core test and the subsection codes used to veto
    cross-subsection substitution. Strongly recommended; without it the
    filed names are used and no subsection veto is applied.

-   min_years:

    Drop pairs disclosed in fewer than this many tax years. The default
    keeps everything; 2 removes 12% of pairs and is a reasonable setting
    if single-year disclosures look like data entry noise to you.

-   max_fanout:

    A Schedule A edge licenses substitution only if the supporter names
    at most this many organisations. Above it the filer is a grantmaking
    supporting organisation, not an arm.

-   max_degree:

    No EIN may end up with more than this many substitutable partners;
    edges touching one that does are demoted to `related`. This is what
    removes federated networks.

-   cache:

    Path to cache the result as `.rds`. `NULL` to skip.

-   verbose:

    Print progress.

</div>

<div class="section level2">

## Value

A keyed `data.table` with `ein_a < ein_b` and columns `dyad_id`,
`dyad_class`, `dyad_reason`, `src_a` (Schedule A seen), `src_r`
(Schedule R seen), `sched_a_dir` (`a_supports_b` / `b_supports_a` /
`NA`), `fan_out`, `n_years`, `first_year`, `last_year`, `same_state`,
`same_city`, `name_a`, `name_b`, `in_bmf`. Deliberately **not** given an
S3 class: it is a table people subset constantly, and a class would
hijack the print method of every subset. Use `pf_dyad_summary()`.

</div>

<div class="section level2">

## See also

<div class="dont-index">

`pf_dyad_collapse()`, `pf_dyad_annotate()`, `pf_cluster_arms()`

</div>

</div>

</div>
