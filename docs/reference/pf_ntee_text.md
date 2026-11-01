<div id="main" class="col-md-9" role="main">

# NTEE classification rendered as text

<div class="ref-description section level2">

A lookup from NTEE code to a bag of words describing that code: the
level 3-5 labels, the category name and description, and the keyword
list. Keyed twice — by the NTEEv2 three-part code (`ART-A00-AA`) and by
the legacy three-character code (`A23`) — because the BMF populates the
two unevenly. On the audit sample the NTEEv2 key resolves 38% of
candidates and the legacy key a further 51%, for 89% combined.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_ntee_text(x = NULL)
```

</div>

</div>

<div class="section level2">

## Arguments

-   x:

    Optional replacement lookup, in the shape of
    [nteev2](https://nonprofit-open-data-collective.github.io/pfmatch/reference/nteev2.md)
    — a list with `by_v2` and `by_legacy`, each a table of `key` and
    `ref`.

</div>

<div class="section level2">

## Value

A list with `by_v2` and `by_legacy` lookup tables.

</div>

<div class="section level2">

## Details

The table ships with the package as `nteev2` (1,082 codes, 84 KB); this
accessor exists so a caller can substitute a newer vintage without
editing code. Rebuild the bundled copy with `data-raw/make-nteev2.R`.

</div>

<div class="section level2">

## See also

<div class="dont-index">

[nteev2](https://nonprofit-open-data-collective.github.io/pfmatch/reference/nteev2.md)
for the bundled data.

</div>

</div>

</div>
