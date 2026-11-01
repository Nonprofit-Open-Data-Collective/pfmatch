<div id="main" class="col-md-9" role="main">

# Initialisms of a name at three levels of function-word elision

<div class="ref-description section level2">

Initialisms of a name at three levels of function-word elision

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_initials(name_key)
```

</div>

</div>

<div class="section level2">

## Arguments

-   name_key:

    Character vector of normalized names.

</div>

<div class="section level2">

## Value

A data frame with `acro_all`, `acro_core`, and `acro_content`. Values
shorter than three characters are `NA` — two-letter initialisms are far
too common to block on — and duplicates across the three tiers are
collapsed to `NA` so the index is not padded with repeats.

</div>

</div>
