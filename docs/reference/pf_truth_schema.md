# Ground-truth table columns

The schema `data-dev/PF-TRUTH.csv` is written in by `dev/build-truth.R`.

## Usage

``` r
pf_truth_schema()
```

## Value

A character vector of required column names.

## Details

A row records the *correct answer for a grant*, never a judgement about
some run's pick. That distinction is the whole reason this table exists:
a label saying "the pipeline's choice was right" cannot score a
different configuration, because a different configuration chooses
differently.
