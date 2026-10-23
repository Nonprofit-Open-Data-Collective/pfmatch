# Report on a grant-recipient match run

Turns a
[`pf_match_grants()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_match_grants.md)
result into the four-way outcome every grant lands in, and crosstabs it
against the standardized recipient type.

## Usage

``` r
pf_status_levels()

pf_report(x, file = NULL)
```

## Arguments

- x:

  A `pf_match`.

- file:

  Optional path; when given, the outcome frame and crosstab are also
  written as CSVs next to it.

## Value

`pf_status_levels()`: the outcome levels in report order.

Invisibly, a list of the report tables.

## Outcome levels

- `YES` — one candidate cleared the auto-accept threshold with a clear
  lead

- `MAYBE` — candidates surfaced but need adjudication (below threshold,
  a near-tie with the runner-up, or a soft veto)

- `NO` — no candidate surfaced, or the best one scored below the review
  floor

- `OOS` — out of sample: the recipient is not the kind of entity the BMF
  contains (a natural person, a government unit, a foreign
  organization), so there is nothing to find and the grant is not
  counted as a miss
