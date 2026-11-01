<div id="main" class="col-md-9" role="main">

# Federated siblings from the BMF group exemption

<div class="ref-description section level2">

The other clustering case, and a genuinely different one: chapters under
a single group ruling — Lions Clubs, PTAs, BSA councils, Knights of
Columbus. Here `group_exemption_number` *is* the right key, provided the
`0000` sentinel is excluded. Siblings are not substitutes for one
another, so a cluster here is a warning that the candidate list holds
several interchangeable-looking chapters, not an invitation to collapse
them.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_group_siblings(bmf, eins = NULL)
```

</div>

</div>

<div class="section level2">

## Arguments

-   bmf:

    The processed BMF (path or data frame).

-   eins:

    Optional character vector of EINs to restrict to.

</div>

<div class="section level2">

## Value

A `data.table` of `ein`, `group_exemption_number`, `affiliation_code`
and `n_members`, for group numbers other than the `0000` sentinel.

</div>

</div>
