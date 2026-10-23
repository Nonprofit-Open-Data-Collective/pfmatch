# Collapse substitutable candidates before selection

For every grant whose tie band holds two or more candidates joined by a
disclosed dyad, merges them into one and re-picks by `config$policy`
instead of by score. **Scores are not modified**, so the YES / MAYBE /
NO thresholds keep their meaning; what changes is which member of a
merged pair is reported and how many distinct bodies remain in
contention.

## Usage

``` r
pf_dyad_collapse(
  x,
  dyads,
  config = pf_dyad_config(),
  np_config = NULL,
  rescore = TRUE
)
```

## Arguments

- x:

  A `pf_match` from
  [`pf_match_grants()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_match_grants.md).

- dyads:

  Output of
  [`pf_build_dyads()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_build_dyads.md).

- config:

  Output of
  [`pf_dyad_config()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_dyad_config.md).

- np_config:

  The `npmatch` config used to re-select. Defaults to the one stored on
  `x`, falling back to
  [`npmatch::np_config()`](https://nonprofit-open-data-collective.github.io/npmatch/reference/np_config.html).

- rescore:

  Re-run selection and tiering on the reduced pair set. See *Collapse
  before selection*.

## Value

`x` with the selection recomputed, plus `dyad_collapsed`, `dyad_id`,
`dyad_class`, `dyad_alt_ein`, `dyad_from_ein`, `dyad_n_before` and
`dyad_n_after` recording every merge — including merges that left the
pick unchanged, which are the majority and are still the point.

`dyad_alt_ein` and `dyad_from_ein` are not the same column and the
difference matters. `dyad_from_ein` is the EIN that *was* reported and
only fills in when the collapse changed the pick; `dyad_alt_ein` is the
member merged away and fills in on every merge. A rollup keyed on the
reported EIN needs the second one.

## Details

Grouping is resolved **within one grant's candidate list only**. A dyad
between two candidates merges them; a dyad from a candidate to some
third EIN that is not a candidate here does nothing. That restriction is
what keeps this from becoming the 67,000-EIN transitive closure
described in
[pf_dyads](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_dyads.md).

## Collapse before selection, not after

With `rescore = TRUE` (the default) the losing members of each merged
group are **removed from the scored pair set and the selection is
re-run**. That is the whole point: `np_tier()` demotes a YES to MAYBE
whenever the margin to the runner-up is below `min_margin`, and when the
runner-up is the same body that demotion is spurious. Rewriting the pick
after the fact leaves the tier where it was and measures nothing.
`rescore = FALSE` keeps the old post-hoc behaviour for comparison.
