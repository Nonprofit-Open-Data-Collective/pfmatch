# Group a candidate list into operating/arm clusters

For each query, finds candidate pairs that share a name core, sit in the
same state, and split into one arm and one non-arm. Each such pair gets
a `joint_id`; the disclosure sources, when supplied, are attached as
evidence.

## Usage

``` r
pf_cluster_arms(
  cand,
  id = "id",
  ein = "ein",
  name = "name",
  state = "state",
  links = NULL,
  require_city = NULL
)
```

## Arguments

- cand:

  A candidate frame, one row per query/candidate pair, with columns
  named by `id`, `ein`, `name` and `state`.

- id, ein, name, state:

  Column names in `cand`.

- links:

  Optional output of
  [`pf_build_affiliation_links()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_build_affiliation_links.md).

- require_city:

  Optional column name; when given, the pair must also agree on it.
  Tighter, and disclosure rates are higher on the subset, but it drops
  arms that use a lockbox or a separate mailing address.

## Value

A `data.table`, one row per detected cluster, with `joint_id`, the two
EINs and names, their ranks in the candidate list, `evidence` (`SCHED_A`
/ `SCHED_R` / `NAME_GEO_ONLY`) and `direction`.

## Details

Roughly **13%** of MAYBE grants contain such a pair. Collapsing the pair
removes the runner-up from the tie band, which converts
`MAYBE-because-two-candidates-tie` into a single-body decision.

## See also

[`pf_arm_order()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_arm_order.md)
for choosing between the members.
