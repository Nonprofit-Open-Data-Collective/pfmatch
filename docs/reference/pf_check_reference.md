<div id="main" class="col-md-9" role="main">

# Refuse a reference bundle built by a different normalizer

<div class="ref-description section level2">

Checkpoints have carried a normalizer stamp since `.pf_run_stamp()`, but
a *fresh* run against a stale `REF-augmented.rds` had nothing to catch
it. This closes that gap, on the same principle: recomputing wastes
time, reusing a mismatched key produces a result that looks correct and
is not.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_check_reference(ref, action = c("auto", "stop", "warn", "ignore"))
```

</div>

</div>

<div class="section level2">

## Arguments

-   ref:

    A bundle from `pf_build_reference()`, a matchdb tier from
    `pf_reference()`, or a bare reference frame.

-   action:

    `"auto"` (default: stop on a mismatch, warn on a missing stamp), or
    force `"stop"`, `"warn"` or `"ignore"`.

</div>

<div class="section level2">

## Value

`ref`, invisibly.

</div>

<div class="section level2">

## Details

Two cases, deliberately different in severity. A bundle stamped with a
*different* signature is known wrong, so `"auto"` stops. A bundle with
*no* stamp is merely unknown — it predates stamping and may well be
current — and a reference is 2.8 GB and hours to rebuild from the BMF,
so `"auto"` warns rather than blocking a run that is probably fine.
Checkpoints stop in both cases because recomputing one is cheap; this is
the same principle applied to a much more expensive artifact.

The signature is read from either place a reference records it:
`normalizer` on a bundle from `pf_build_reference()`, or
`stamp$normalize_signature` on a matchdb tier fetched by
`pf_reference()`. Reading only the first would report a stamped matchdb
tier as unstamped and downgrade a real mismatch to a warning — and a
warning nobody can act on is worse than no check.

</div>

</div>
