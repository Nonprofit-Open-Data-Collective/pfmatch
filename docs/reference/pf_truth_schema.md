<div id="main" class="col-md-9" role="main">

# Ground-truth table columns

<div class="ref-description section level2">

The schema `data-dev/PF-TRUTH.csv` is written in by `dev/build-truth.R`.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_truth_schema()
```

</div>

</div>

<div class="section level2">

## Value

A character vector of required column names.

</div>

<div class="section level2">

## Details

A row records the *correct answer for a grant*, never a judgement about
some run's pick. That distinction is the whole reason this table exists:
a label saying "the pipeline's choice was right" cannot score a
different configuration, because a different configuration chooses
differently.

</div>

</div>
