<div id="main" class="col-md-9" role="main">

# Build a dictionary of resolved grant renderings

<div class="ref-description section level2">

Turns matched grant rows into a reference the cascade can run against,
keyed on the **filer-written** name and address rather than the BMF's.
Use it with `pf_recover_from_dictionary()`.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_grant_dictionary(
  grants,
  keep = "YES",
  exclude = NULL,
  key_col = NULL,
  stats = "dictionary",
  verbose = TRUE
)
```

</div>

</div>

<div class="section level2">

## Arguments

-   grants:

    Matched grant rows: the prepared recipient columns (`recip_name`,
    `recip_street`, `recip_city`, `recip_state`, `recip_zip5`) plus a
    tier and an EIN. A list carrying `$grants` is accepted, so the
    output of a run can be passed straight in.

-   keep:

    Tiers to build from. `"YES"` only, by default: a dictionary seeded
    from MAYBE would propagate exactly the decisions in doubt.

-   exclude:

    Optional grant keys to leave out — pass the keys of the rows you
    intend to match, or the dictionary answers them with themselves.

-   key_col:

    Column holding the grant key, for `exclude`.

-   stats:

    `"dictionary"` (default) computes the name and token statistics over
    the dictionary itself; supply a reference bundle to borrow its
    `name_freq` and `token_idf` instead. The IDF of \~90k filer
    renderings is not the IDF of 3.88M BMF names, and which one is right
    is an open question — the argument exists so the two are never
    confounded silently.

-   verbose:

    Print what was built and what was dropped.

</div>

<div class="section level2">

## Value

A reference bundle — `reference`, `name_freq`, `token_idf`, `ref_index`,
`normalizer` — with attributes `n_eins`, `n_renderings`,
`ambiguous_dropped` and `built_from`.

</div>

<div class="section level2">

## Why the address is not optional

Keying on the name alone does not work, and the margin is not close.
Measured over 88,744 renderings: 727 of 63,310 bare name keys (1.15%)
carry more than one EIN, and the worst is `HABITAT FOR HUMANITY` with
**39**. `RONALD MCDONALD HOUSE` has 31, `BIG BROTHERS BIG SISTERS` 29.
Adding ZIP5 takes that to **0 of 66,425**. Any `(name_key, zip5)` that
still resolves to more than one EIN is dropped rather than guessed at,
and the count is reported in the `ambiguous_dropped` attribute.

</div>

<div class="section level2">

## See also

<div class="dont-index">

`pf_recover_from_dictionary()`

</div>

</div>

</div>
