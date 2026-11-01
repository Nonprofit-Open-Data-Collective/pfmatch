<div id="main" class="col-md-9" role="main">

# Add acronym and prefix recovery columns to a normalized frame

<div class="ref-description section level2">

Adds three blocking columns:

-   `name_acro`:

    `name_key` with the record's initials appended as extra synthetic
    tokens. Blocking on this column lets a query that *is* an acronym
    (`NJOP`) or merely *contains* one (`PVCC EDUCATIONAL FOUNDATION`)
    find the spelled-out reference record. Initials are rare, so they
    carry high IDF and justify a pair on their own — while the IDF
    machinery still prunes the common ones.

-   `name_pre`:

    the first `prefix_len` characters of `name_key`, for the truncation
    pass.

-   `name_is_acro`:

    `TRUE` when the whole name is a single short all-letter token, i.e.
    the query is itself an acronym.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_add_recovery_keys(d, prefix_len = 18L, only_truncated = NULL)
```

</div>

</div>

<div class="section level2">

## Arguments

-   d:

    A normalized frame from `npmatch::np_normalize()`.

-   prefix_len:

    Characters to keep for the truncation prefix key.

-   only_truncated:

    Optional logical vector, one per row. When supplied, `name_pre` is
    `NA` wherever it is `FALSE`, so the prefix pass never fires on a
    name that was not cut off.

</div>

<div class="section level2">

## Value

`d` with the three columns added.

</div>

<div class="section level2">

## Details

Apply to **both** sides. On the reference it supplies the initials to
match against; on the query it supplies the prefix and the acronym flag.

</div>

<div class="section level2">

## Restricting the prefix key

On the reference side every record gets a `name_pre`. On the **query**
side it should be set only for names that are actually truncated — pass
`only_truncated`. Without that restriction the pass fires on every long
name and an 18-character prefix is far too blunt a key:
`AMERICAN ASSOCIATION OF PRO-LIFE OBSTETRICIANS` and
`AMERICAN ASSOCIATION OF ZOO KEEPERS` share one, and that exact false
positive appeared in testing.

</div>

</div>
