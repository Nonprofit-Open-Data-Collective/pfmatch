<div id="main" class="col-md-9" role="main">

# Schedule A Part I public-charity status flags

<div class="ref-description section level2">

The Part I checkbox is a status the filer declares about itself, which
makes it stronger evidence than anything inferred from a name. Two boxes
matter here:

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_schedule_a_status(sched_a_p1)
```

</div>

</div>

<div class="section level2">

## Arguments

-   sched_a\_p1:

    Path to `SA-P01-T00-PUBLIC-CHARITY-STATUS-<year>.CSV`, or the table
    itself.

</div>

<div class="section level2">

## Value

A `data.table` keyed by `ein` with logical `govt_college`,
`support_org`, `med_research`, `hospital`, `pub_support`, plus
`hospital_name` where line 4 named one.

</div>

<div class="section level2">

## Details

-   Line 5 (`govt_college`):

    170(b)(1)(A)(iv) - "operated for the benefit of a college or
    university owned or operated by a governmental unit". This is the
    state university foundation, and it identifies the population where
    no affiliation disclosure can ever exist, because the parent is a
    government agency rather than a related nonprofit. 2,105 EINs
    nationally in 2022; of the MAYBE-tier arms that tick it, 92% could
    not be linked to a parent by Schedule A, Schedule R or the BMF.

-   Line 12 (`support_org`):

    509(a)(3). The box whose accompanying table feeds
    `pf_build_affiliation_links()`.

Line 4 (`med_research`) is included for completeness and is close to
useless for this purpose: it covers medical *research* organizations
operated in conjunction with a hospital, only 384 filers nationally, and
none of the 927 arm pairs measured. Hospital arms tick line 12 or line 7
instead.

</div>

</div>
