<div id="main" class="col-md-9" role="main">

# Build the EIN-to-EIN affiliation link table

<div class="ref-description section level2">

Reads the Schedule A and Schedule R e-file tables and returns one row
per disclosed relationship. Both tables are available per tax year from
the NCCS e-file catalogue; 2022 is the development vintage.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_build_affiliation_links(sched_a = NULL, sched_r = NULL, cache = NULL)
```

</div>

</div>

<div class="section level2">

## Arguments

-   sched_a:

    Path to `SA-P01-T01-PUBLIC-CHARITY-STATUS-<year>.CSV`, or the table
    itself. `NULL` to skip.

-   sched_r:

    Path to `SR-P02-T01-ID-RLTD-TAX-EXEMPED-ORGS-<year>.CSV`, or the
    table itself. `NULL` to skip.

-   cache:

    Path to cache the result as `.rds`. `NULL` to skip.

</div>

<div class="section level2">

## Value

A `data.table` with `a`, `b`, `src` (`SCHED_A` / `SCHED_R`) and `rel`
(`a_supports_b` / `a_related_b`), plus an `undirected` attribute holding
the symmetrised form for lookup.

</div>

</div>
