<div id="main" class="col-md-9" role="main">

# NTEE codes rendered as text

<div class="ref-description section level2">

The bundled NTEE lookup used by `pf_build_org_text()`, built from the
two NCCS description files by `data-raw/make-nteev2.R`.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
nteev2
```

</div>

</div>

<div class="section level2">

## Format

A list of three `data.table`s:

-   `by_v2`:

    1,082 rows, one per NTEEv2 code: `key` (e.g. `ART-A00-AA`) and `ref`
    (labels + category description + keywords, as one string). Several
    legacy codes collapse onto one NTEEv2 code — `B80`, `B8040`, and
    `B8043` are all `EDU-B80-RG` — and only some carry keywords, so the
    builder keeps the richest description per key rather than the first.

-   `by_legacy`:

    505 rows: `key` (legacy code, e.g. `A23`) and `ref`.

-   `codes`:

    the code table itself — `NTEE2`, `ntee`, `level1`, `level4`,
    `cat_name`.

</div>

<div class="section level2">

## Source

NCCS NTEEv2 description files.

</div>

</div>
