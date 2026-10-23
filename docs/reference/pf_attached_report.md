# Report on returns that do not itemize their grants

One row per (filer, tax year), because the unit of the problem is the
*return*: a filer that writes "see attached" usually does it for the
whole year, and the actionable object is the return, not the row.

## Usage

``` r
pf_attached_report(grants, verbose = TRUE)
```

## Arguments

- grants:

  A prepared frame from
  [`pf_prepare_grants()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_prepare_grants.md),
  carrying the raw `FILEREIN`, `FILERNAME1`, `TAXYEAR`, `SIGOCPYAMOUN`
  and `URL` columns.

- verbose:

  Print a summary.

## Value

A data frame, one row per non-itemizing return:

- `filer_ein`, `filer_name`, `taxyear`:

  who and when

- `n_placeholder_rows`, `placeholder_amount`:

  the un-itemized rows and their dollars

- `n_itemized_rows`, `itemized_amount`:

  what the same return *did* itemize — a return can do both

- `pct_dollars_hidden`:

  share of the return's grant dollars that are not itemized. 100% means
  the whole year is a single pointer row

- `placeholder_text`:

  the exact wording used, which varies by filer

- `url`:

  the e-file XML for the return
