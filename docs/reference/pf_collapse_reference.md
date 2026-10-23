# Collapse reference rows the matcher cannot tell apart

Rows sharing a normalized name, state and ZIP5 are indistinguishable to
every comparison the cascade makes. Keeping 6,710 of them buys nothing
and costs the blocking pass 6,710 candidates for every query that hits
the name.

## Usage

``` r
pf_collapse_reference(
  ref,
  by = c("name_key", "state", "zip5"),
  rebuild = TRUE,
  verbose = TRUE
)
```

## Arguments

- ref:

  A bundle from
  [`pf_build_reference()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_build_reference.md)
  or a normalized reference.

- by:

  Columns defining indistinguishability. The default is the set the
  cascade actually compares on.

- rebuild:

  Recompute `name_freq`, `token_idf` and `ref_index` from the collapsed
  reference. Leaving this `FALSE` keeps the *pre-collapse* name
  frequencies, which is a different system: `np_name_freq()` feeds the
  promotion gate, so a rebuild makes rare-after-collapse names newly
  eligible.

- verbose:

  Report what was collapsed.

## Value

The bundle with `reference` collapsed, plus `members` — one row per
merged EIN, carrying `rep_ein`, `ein` and `n_identical` — and
`collapse`, the summary statistics.

## Measured, and NOT adopted

`dev/PHASE3-LIBRARIES.md` §0 listed this as one of two changes to make
before the full run, on the strength of "reference −7%, cost driver
−8x". Both halves reproduce on the right artifact and the blocker's own
`name_key` (`dev/probe-ref-collapse.R`): **3,880,428 → 3,527,239 rows,
9.1% smaller, and `sum(block^2)` 4.49e8 → 5.66e7 — 7.9x.** The largest
`(name, state)` block falls from 7,379 rows to 1,208.

**It buys nothing.** Same rung, same queries, augmented against
collapsed (`dev/SHARD-RSS-COLLAPSED.log`): peak working set 36.82 →
32.95 GB (−10.5%, still one shard on 68 GB) and **366 s per 1,000 either
way — no speedup at all.** A 7.9x cut in the cost driver moved the cost
0%.

The proxy is what failed. `sum(block^2)` counts candidates on the
assumption that queries distribute like the reference. Grant recipients
do not: nobody makes grants to 6,710 PEO chapters, so the giant blocks
are almost never queried and shrinking them saves work nobody was doing.

## What it hides

152,825 groups hold more than one EIN, covering 506,014 — 13.0% of the
reference. Before the collapse that ambiguity was *visible*: tied
candidates drove the margin to zero and `np_tier()` held the grant in
MAYBE. Afterwards one row wins outright. On the 2,000-identity rung the
collapse moved **80 grants MAYBE → YES, and 88% of them are won by an
EIN standing for more than one** — median 2, max 5,363. That is a 5%
headline YES gain made entirely of converted abstentions, and it is why
this function returns `members` rather than quietly dropping the merged
EINs.

So: **do not use this in the production cascade.** It is kept because
the negative result rests on it and because `members` is a usable
same-name-same-place equivalence table in its own right — which is the
reference-side duplicate problem of `dev/CLUSTER-FINDINGS.md` §8, and a
better use for it than blocking.
