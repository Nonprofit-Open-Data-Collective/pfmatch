# Break near-ties on grant purpose and filing presence

Recomputes the overall pick for grants where the top candidates are
within `tie_band` of each other, ordering the contenders by the
configured keys instead of by score. **Scores are not modified**, so the
YES / MAYBE / NO thresholds keep their meaning and the benchmark stays
comparable; only the choice among tied candidates changes.

## Usage

``` r
pf_purpose_tiebreak(x, org_text, config = pf_tiebreak_config())
```

## Arguments

- x:

  A `pf_match` from
  [`pf_match_grants()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_match_grants.md).

- org_text:

  Output of
  [`pf_build_org_text()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_build_org_text.md).

- config:

  Output of
  [`pf_tiebreak_config()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_tiebreak_config.md).

## Value

`x` with `result$overall_*` rewritten where the tiebreak fired, plus
`tiebreak_fired`, `tiebreak_key`, and `tiebreak_from_ein` columns
recording every change.

## Details

Features are computed lazily, for contending candidates only — a few
thousand pairs rather than the millions the cascade scored.

## What the keys are worth

On the 61 contested adjudicated grants, ordering by `cov_all` then
`has_mission` inside the band gains 3 and loses 0 (0.770 -\> 0.820) with
`tie_high = 0`, or gains 1 and loses 0 at `tie_high = 0.95`. On the 794
YES grants it changes nothing, because none of them are inside the band.
Note that npmatch's own `tiebreak = "name"` key is net 0 to −2 on this
data: it assumes the entity whose full name matches the query is the
right one, and in 990-PF grants the correct recipient is the
`FOUNDATION` arm 52.8% of the time, so the assumption is a coin flip
here.
