# The shared core of an organization name

Strips legal suffixes and any arm marker, so that
`FRIENDS OF THE RACINE PUBLIC LIBRARY` and `RACINE PUBLIC LIBRARY`
reduce to the same string. Two candidates sharing a core are
*candidates* for being one body; geography decides it (see
[`pf_cluster_arms()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_cluster_arms.md)).

## Usage

``` r
pf_arm_core(x)
```

## Arguments

- x:

  Character vector of organization names.

## Value

Character vector of cores.
