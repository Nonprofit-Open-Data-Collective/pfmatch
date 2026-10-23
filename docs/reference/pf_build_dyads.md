# Build the dyad table

Reads the Schedule A and Schedule R dyad extracts, keeps rows where both
ends carry a usable EIN, symmetrises to one row per unordered pair, and
classifies each pair as `substitutable` or `related`.

## Usage

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

## Arguments

- supported:

  Path to `dyad_supported_orgs.csv`, or the table itself. `NULL` to skip
  Schedule A.

- related:

  Path to `dyad_related_exempt_orgs.csv`, or the table itself. `NULL` to
  skip Schedule R.

- bmf:

  Processed BMF (path or data frame). Supplies the names used for the
  name-core test and the subsection codes used to veto cross-subsection
  substitution. Strongly recommended; without it the filed names are
  used and no subsection veto is applied.

- min_years:

  Drop pairs disclosed in fewer than this many tax years. The default
  keeps everything; 2 removes 12% of pairs and is a reasonable setting
  if single-year disclosures look like data entry noise to you.

- max_fanout:

  A Schedule A edge licenses substitution only if the supporter names at
  most this many organisations. Above it the filer is a grantmaking
  supporting organisation, not an arm.

- max_degree:

  No EIN may end up with more than this many substitutable partners;
  edges touching one that does are demoted to `related`. This is what
  removes federated networks.

- cache:

  Path to cache the result as `.rds`. `NULL` to skip.

- verbose:

  Print progress.

## Value

A keyed `data.table` with `ein_a < ein_b` and columns `dyad_id`,
`dyad_class`, `dyad_reason`, `src_a` (Schedule A seen), `src_r`
(Schedule R seen), `sched_a_dir` (`a_supports_b` / `b_supports_a` /
`NA`), `fan_out`, `n_years`, `first_year`, `last_year`, `same_state`,
`same_city`, `name_a`, `name_b`, `in_bmf`. Deliberately **not** given an
S3 class: it is a table people subset constantly, and a class would
hijack the print method of every subset. Use
[`pf_dyad_summary()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_dyad_summary.md).

## See also

[`pf_dyad_collapse()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_dyad_collapse.md),
[`pf_dyad_annotate()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_dyad_annotate.md),
[`pf_cluster_arms()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_cluster_arms.md)
