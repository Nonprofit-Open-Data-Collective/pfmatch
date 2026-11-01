<div id="main" class="col-md-9" role="main">

# Drop superseded and duplicate 990-PF filings, keeping every grant reported

<div class="ref-description section level2">

Deduplicates at the level of the **filing**, never the grant row, and
only within one reporting context — see the file header for why this
differs deliberately from `panel990::panel_deduplicate()`.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_efilepf_dedup(d, content_cols = pf_grant_content_cols(), verbose = TRUE)
```

</div>

</div>

<div class="section level2">

## Arguments

-   d:

    A grants-paid frame carrying the ef2 filing metadata: `EIN2`,
    `TAX_YEAR`, `OBJECTID`, and where available `RETURN_GROUP_X`,
    `RETURN_PARTIAL_X`, `RETURN_AMENDED_X`, `RETURN_TIME_STAMP`.

-   content_cols:

    Grant fields used to decide whether two filings report the same
    thing. Defaults to `pf_grant_content_cols()`.

-   verbose:

    Print the tally.

</div>

<div class="section level2">

## Value

`d` with superseded and duplicate filings removed, carrying two new
columns: `dedup_action` (`kept`, `kept_amended`, `kept_flagged`) and
`dedup_flag` — `TRUE` where several filings of one context disagree and
no amendment settles it, so **all** of them were kept. An attribute
`"pf_dedup"` holds the per-context audit table.

</div>

</div>
