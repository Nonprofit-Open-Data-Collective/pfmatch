# Dyad collapse settings

Dyad collapse settings

## Usage

``` r
pf_dyad_config(
  tie_band = 0.05,
  max_band = 25L,
  use = "substitutable",
  policy = c("query", "operating", "arm", "top"),
  keep_soft_veto = TRUE
)
```

## Arguments

- tie_band:

  Candidates within this much of the top score are in contention.
  Matches npmatch's `np_config()$tie_band`.

- max_band:

  Cap on how many candidates per grant enter the collapse, by score.
  This is a hard requirement, not a tuning knob: pairing is quadratic,
  and a token-blocked query can put **thousands** of equal-scoring
  candidates inside the band — one grant with 2,000 of them is two
  million comparisons, which is what hung the first run of
  `dev/test-dyad-cascade.R`. Nothing below the top handful can affect
  the selection anyway. Counts of what the cap drops are reported by
  [`pf_dyad_collapse()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_dyad_collapse.md).

- use:

  Which dyad classes may be collapsed. The default is `"substitutable"`
  only; `c("substitutable", "related")` is available for measurement but
  see
  [pf_dyads](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_dyads.md)
  for why it should not be shipped.

- keep_soft_veto:

  Carry a soft veto from a merged-away member onto the surviving
  representative, so the grant stays in review. A soft veto is npmatch's
  "do not auto-accept this" signal, and `affiliate_suffix` is the
  operating-arm problem in veto form — it fires on exactly the
  `X FOUNDATION` candidate when the grant says `X`. Without this,
  dropping the arm drops the veto with it. Measured on the 50k run: **71
  of 700 promotions** came from that path, every one of them a case
  where the cascade ranked the arm first and the policy overrode both
  the score and the veto. `FALSE` restores the older behaviour and
  recovers those 71 auto-accepts, at the cost of resting them on a rule
  validated at 60% on 15 cases.

## Value

A list.

## Why the policies differ

On the 50k run, `operating` promotes 629 MAYBE grants to YES, `top` 388
and `arm` 253 — and `top` cannot lose on score, since it keeps the
highest-scoring member by construction. The gap is the **soft veto**. Of
the 241 grants where `operating` and `top` land on different tiers,
`top` keeps an arm in **240**, `operating` in **none**, and the query
carries a support marker in **none**. That is exactly the
`affiliate_suffix` trigger — candidate ends in a support token, query
does not — so `top` inherits a veto that `operating` escapes. The
policies are not trading accuracy for score; one of them is standing on
a veto.
