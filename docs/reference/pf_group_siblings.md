# Federated siblings from the BMF group exemption

The other clustering case, and a genuinely different one: chapters under
a single group ruling — Lions Clubs, PTAs, BSA councils, Knights of
Columbus. Here `group_exemption_number` *is* the right key, provided the
`0000` sentinel is excluded. Siblings are not substitutes for one
another, so a cluster here is a warning that the candidate list holds
several interchangeable-looking chapters, not an invitation to collapse
them.

## Usage

``` r
pf_group_siblings(bmf, eins = NULL)
```

## Arguments

- bmf:

  The processed BMF (path or data frame).

- eins:

  Optional character vector of EINs to restrict to.

## Value

A `data.table` of `ein`, `group_exemption_number`, `affiliation_code`
and `n_members`, for group numbers other than the `0000` sentinel.
