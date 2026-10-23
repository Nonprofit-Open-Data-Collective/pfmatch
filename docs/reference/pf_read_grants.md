# Read and prepare the sample grant CSVs

Read and prepare the sample grant CSVs

## Usage

``` r
pf_read_grants(
  path = "inputs",
  pattern = "grants.*\\.csv$",
  allow_mixed = FALSE
)
```

## Arguments

- path:

  Directory or vector of CSV paths.

- pattern:

  File pattern when `path` is a directory. The default matches the
  `*_grants*.csv` benchmark files and so will pull in **every** size
  variant sitting in the folder — pass an explicit pattern or file
  vector to pick one set.

- allow_mixed:

  Set `TRUE` to suppress the vintage check described below. Only do this
  when the mixture is genuinely wanted.

## Value

The prepared frame, with `source_file` recording provenance.

## Vintage check

Grant extracts from different sources do not share a schema, and
silently concatenating them produces a population that is neither. The
two vintages in this project are distinguished by `OBJECTID`: the NCCS
e-file rebuild carries it, the older GT-derived extracts do not. Reading
both at once also double-counts, because the two sources were sampled
from overlapping filings.

The default `pattern` matched 15 files across both vintages in `inputs/`
— 422,806 rows where either population alone is a fraction of that — so
this function now stops when the matched files disagree on `OBJECTID`,
naming the files on each side. The check is on the column, not on
filenames, so it keeps working whatever the samples are called.
