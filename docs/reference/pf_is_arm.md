# Is this name a fundraising or support arm?

Detects the arm by name shape alone: a trailing support marker
(`FOUNDATION`, `ENDOWMENT`, `AUXILIARY`, `ALUMNI ASSOCIATION`, ...) or a
leading one (`FRIENDS OF`). Checked against Schedule A, the shape is
right 271 times in 276 — the five exceptions are bodies legally named
`... FOUNDATION` that are themselves the operating entity and are
supported by a differently-named arm.

## Usage

``` r
pf_is_arm(x)
```

## Arguments

- x:

  Character vector of organization names.

## Value

Logical vector.

## See also

[`pf_arm_core()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_arm_core.md),
[`pf_cluster_arms()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_cluster_arms.md)
