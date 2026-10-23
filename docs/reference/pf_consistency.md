# Consistency across renderings of one organisation

A ground-truth-free quality metric. One organisation is written many
ways across grants; grouping those renderings by **address** is
independent of the name comparator, so within a group every rendering
should receive the same EIN whatever that EIN turns out to be.
Disagreement inside a group is a defect regardless of which member is
right.

## Usage

``` r
pf_consistency(run, groups = NULL, min_size = 2L)
```

## Arguments

- run:

  A run result, as for
  [`pf_evaluate()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_evaluate.md).

- groups:

  `(grant_id, group_id)` from `dev/build-triangulation-sample.R`, or a
  path to it.

- min_size:

  Smallest group to score. Default 2.

## Value

A list of `summary` and `detail` (per group), class `pf_consistency`.

## Details

That independence from ground truth is the point. The anchor-based
labels in `PF-TRUTH-TRIANGULATED.csv` measured only ~50-60% precise,
because a shared street address also covers fiscal sponsors
(`MULTIPLIERORG` and the Natural Resources Defense Council), individual
payees at an organisation's address (`EDUCATIONAL GRANT - <person>`),
and cases where the anchoring YES is itself wrong
(`Homes for our Troops`). None of that damages a disagreement count:
those groups are noisy in every configuration, so comparing
configurations on the same groups still isolates the change.

It is necessary, not sufficient. A configuration that answers every
rendering identically and wrongly scores perfectly here, so read it
alongside
[`pf_evaluate()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_evaluate.md),
never instead of it.
