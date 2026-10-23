# Build the EIN -\> self-description table

Joins the Form 990 Part III wide table (see `dev/build-990-text-wide.R`)
to the BMF's classification text, one row per EIN. Where an EIN filed
more than one return for the year — 8,571 of 544,917 do, from amendments
and short periods — the latest tax period wins, then the longest text.

## Usage

``` r
pf_build_org_text(wide, bmf = NULL, ntee = NULL, cache = NULL)
```

## Arguments

- wide:

  Path to `F9-P03-TEXT-WIDE-*.rds`/`.csv`, or the table itself.

- bmf:

  The processed BMF (path or data frame), for the NTEE and activity
  text. Optional: omit for 990-text-only.

- ntee:

  Output of
  [`pf_ntee_text()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_ntee_text.md).
  Optional.

- cache:

  Path to cache the result as `.rds`. `NULL` to skip.

## Value

A `data.table` keyed by `ein` with `ntee_text`, `activity_text`,
`mission`, `prog_all`, `all_text`, `has_mission`, `has_program`,
`n_programs`, plus a `token_idf` attribute computed over the mission
corpus.
