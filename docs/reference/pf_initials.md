# Initialisms of a name at three levels of function-word elision

Initialisms of a name at three levels of function-word elision

## Usage

``` r
pf_initials(name_key)
```

## Arguments

- name_key:

  Character vector of normalized names.

## Value

A data frame with `acro_all`, `acro_core`, and `acro_content`. Values
shorter than three characters are `NA` — two-letter initialisms are far
too common to block on — and duplicates across the three tiers are
collapsed to `NA` so the index is not padded with repeats.
