# Score a run against ground truth

Score a run against ground truth

## Usage

``` r
pf_evaluate(
  run,
  truth = NULL,
  population = NULL,
  min_confidence = c("medium", "high", "low")
)
```

## Arguments

- run:

  A run result: `pf_match_grants()$result` or a frame with an id column
  (`grant_id` or `.id`), a `tier`, and an EIN column (`ein`,
  `overall_ein` or `ein9`).

- truth:

  The ground-truth table, or a path to it. Defaults to
  `data-dev/PF-TRUTH.csv`.

- population:

  Optional fingerprint to enforce. When supplied and it disagrees with
  the truth table, this errors rather than scoring.

- min_confidence:

  Drop truth rows weaker than this. `"medium"` (the default) keeps web-
  and reference-based labels and the stratified inferences; `"high"`
  keeps only web-confirmed EINs.

## Value

An object of class `pf_eval`: a list of `summary` (one row) and `detail`
(per-case).

## What it can and cannot measure

Recall is measured against the truth rows that carry a `correct_ein`.
Precision on the YES mass is **not** measurable from a truth table built
out of cells the pipeline failed on — that needs a random stratified
sample. What *is* measurable without one is **false clears**: truth rows
asserting no organisation exists at all (an individual payee, a
government body, a payee with no exemption of its own) must never be
YES, so any that are are unambiguous false accepts.
