# Attach an external mission table

Joins mission text onto a frame by EIN. Supply any table with an EIN
column and a mission-text column — e.g. an e-file Form 990 Part III
extract. Where several filings exist per EIN the most recent tax year is
kept.

## Usage

``` r
pf_attach_missions(
  x,
  missions,
  ein_col = "ORG_EIN",
  mission_col = "F9_03_ORG_MISSION_PURPOSE",
  year_col = "TAX_YEAR",
  on = "ein",
  into = "mission"
)
```

## Arguments

- x:

  A data frame with an EIN column.

- missions:

  A data frame with EIN, mission text, and optionally a year.

- ein_col, mission_col, year_col:

  Column names in `missions`.

- on:

  The EIN column in `x`.

- into:

  Name of the mission column added to `x`.

## Value

`x` with the mission column added.
