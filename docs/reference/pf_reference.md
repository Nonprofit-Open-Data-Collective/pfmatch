<div id="main" class="col-md-9" role="main">

# Stage 2 — the reference bundle

<div class="ref-description section level2">

Returns the reference the cascade matches against, with the stage-4
recovery keys (`pf_add_recovery_keys()`) added, so the bundle is
complete. This is preprocessing and is excluded from match timings.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_reference(
  bmf = NULL,
  cache = "data-dev/BMF-REFERENCE-BUNDLE.rds",
  active_col = NULL,
  recovery = TRUE,
  verbose = TRUE,
  source = c("auto", "matchdb", "local"),
  tier = getOption("pfmatch.matchdb_tier", "active-observed")
)
```

</div>

</div>

<div class="section level2">

## Arguments

-   bmf:

    Processed BMF: a path or a data frame. Needed only for the local
    bundle, and only when `cache` does not exist.

-   cache:

    Path to cache the local bundle (`.rds`). `NULL` disables caching.

-   active_col:

    Optional BMF-active flag column (local bundle only).

-   recovery:

    Add acronym / prefix blocking keys to the reference.

-   verbose:

    Print progress.

-   source:

    `"auto"`, `"matchdb"` or `"local"`; see above.

-   tier:

    The matchdb tier. Defaults to
    `getOption("pfmatch.matchdb_tier", "active-observed")`.

</div>

<div class="section level2">

## Value

A reference bundle: `reference`, `name_freq`, `token_idf`, `ref_index`,
and `source` (`"matchdb"` or `"local"`). A matchdb bundle also carries
`clusters` and its publication `stamp`.

</div>

<div class="section level2">

## Where the reference comes from

-   `source = "matchdb"`:

    A published matchdb reference,
    `matchdb::md_reference(tier, fetch = "missing")`: downloaded once
    from the public NCCS copy, checked against its md5s and against the
    installed npmatch normalizer, and cached under matchdb's data root.
    Nothing is built locally.

-   `source = "local"`:

    The bundle built here from `bmf` by `pf_build_reference()`, cached
    at `cache`.

-   `source = "auto"` (the default):

    A `bmf` given is a request for that file, so it is honoured: the
    local bundle, exactly as before. Without one, matchdb when the
    package is installed and the tier loads; otherwise, with a message
    saying why, the local bundle at `cache`. A matchdb bundle built by a
    different npmatch normalizer is refused by `md_reference()`, so a
    normalizer update falls back here until the tier is republished.

`tier = "active-observed"` is the default because it wins on both axes
at once: the `bmf_active` layer with legal, DBA and observed name
variants, 2.89M rows, it matched the 1k benchmark in 11.5 min against
23.2 for the augmented BMF pfmatch built for itself, and cleared 62.0%
against 61.2% (`dev/BENCH-MD-REFERENCE.log`, YES over the 4,868 in-scope
identities — the same denominator for every arm, since each arm finds
pairs for a different number of them; measured 2026-10-23 under
normalizer `v1-6dcb298522cc5118`, so treat the comparison rather than
the level as the claim and re-run if the installed normalizer has
moved). `"unified-observed"` is the closer correspondence to the
augmented bundle — it adds the inactive tranche, so every BMF release
rather than the current one — but that is 1.76M more rows for two and a
half times the match time and +0.49 point. Ask for it when the question
is grantees that no longer exist, not for the clear rate. The "Choosing
a matching dictionary" vignette has the comparison;
`matchdb::md_reference()` lists the tiers.

</div>

</div>
