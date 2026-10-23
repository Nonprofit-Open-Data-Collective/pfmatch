# Deduplicate grant recipients

Deduplicate grant recipients

## Usage

``` r
pf_dedup(
  grants,
  method = c("exact", "fuzzy"),
  threshold = 0.92,
  max_block = 2000L,
  verbose = TRUE
)
```

## Arguments

- grants:

  A prepared frame from
  [`pf_prepare_grants()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_prepare_grants.md).

- method:

  `"exact"` or `"fuzzy"` (fuzzy implies exact first).

- threshold:

  Jaro-Winkler similarity required to join two names in the same
  geographic block. Default 0.92.

- max_block:

  Blocks larger than this are compared exactly only, not fuzzily — a
  guard against a quadratic blow-up on a huge shared ZIP.

- verbose:

  Print the collapse ratio.

## Value

`grants` with two columns added: `recipient_uid` (the identity a match
is computed for) and `recipient_n` (how many grant rows share it).
