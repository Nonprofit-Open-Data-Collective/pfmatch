# Staged cascade: state-blocked bulk, then an unblocked residual sweep

The production shape for the full file.
[`pf_default_passes()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_default_passes.md)
blocks nothing geographically, which is the right instrument for
*measuring* geographic mismatch but is unaffordable at 12.5M grants: its
cross-state token pass compares against all 1.9M BMF records and
accounts for 96% of the runtime.

## Usage

``` r
pf_staged_passes(
  sweep = c("lean", "full", "none"),
  concat = TRUE,
  max_ref_freq_state = 25000,
  min_pair_idf_state = 8,
  max_ref_freq_any = 5000,
  min_pair_idf_any = 8
)
```

## Arguments

- sweep:

  How much of the unblocked residual sweep to run (see above).

- concat:

  Include the adjacent-token compound pass `B2`, which recovers
  de-spacing differences (`STEP FORWARD` vs `STEPFORWARD`). Measured
  cost on 5,000 grants: 223,151 candidates — 46% of the whole lean
  cascade — for 48 YES matches. Keep it when recall matters more than
  runtime; drop it for a fast first pass over the full file, since most
  of what it finds degrades to MAYBE rather than disappearing.

- max_ref_freq_state, min_pair_idf_state:

  Token pruning inside a state.

- max_ref_freq_any, min_pair_idf_any:

  Token pruning for the unblocked sweep, tighter because the pool is the
  whole BMF.

## Value

A list of pass specifications for
[`npmatch::np_cascade()`](https://nonprofit-open-data-collective.github.io/npmatch/reference/np_cascade.html).

## Details

This cascade splits into three stages, tightest first. Because
[`npmatch::np_cascade()`](https://nonprofit-open-data-collective.github.io/npmatch/reference/np_cascade.html)
prunes only queries that reached **YES**, everything unresolved —
including every MAYBE — falls through to the next stage, so blocking
early costs recall only for records the later stages also miss.

## Stage A — state-blocked exact (very cheap)

Exact name against exact ZIP5, then against state, then the name/DBA
cross-products within state. ZIP5 implies state, so the first pass needs
no separate state key.

## Stage B — state-blocked token (moderate)

Shared distinctive name token within state, then the same with
adjacent-token compounds. This is where the bulk of the fuzzy work
happens, against ~1/15th of the reference rather than all of it.

## Stage C — unblocked residual sweep (expensive, small N)

Only the queries still unresolved reach here. This is what makes the
state block safe: it recovers the cases state blocking cannot see — a
990-PF state field that is simply wrong (six of the ten cross-state YES
matches in the benchmark had matching city *and* ZIP but a wrong state
code), a national headquarters address in the BMF against a local
grantee address, a lockbox, and every record whose state is missing
entirely (a blocked pass drops those, since `.np_bykey()` treats an
incomplete key as invalid).

## Choosing `sweep`

Measured on 5,000 grants, the unblocked **token** sweep (`C3`) generated
686,380 candidate pairs — 59% of the entire run — and produced **zero**
additional YES matches; its only product is MAYBE candidates for
adjudication. The four YES matches stage C did contribute all came from
the cheap exact pass `C1`, and three of those four are the known
cross-state false positives (`UNBOUND` MO-\>KS,
`FIRST PRESBYTERIAN CHURCH` IA-\>NC,
`PATTERSON VOLUNTEER FIRE DEPARTMENT` LA-\>NC) — common names matched in
another state with no address corroboration.

The cross-state cases that are *genuine* — a 990-PF state field simply
typed wrong, with city and ZIP both correct — never needed an unblocked
sweep at all: pass `A1` blocks on name + ZIP5 and deliberately carries
**no state key**, so it catches them at a fraction of the cost.

- `"lean"` (default) — stages A and B plus the cheap exact cross-state
  passes. Same YES set, roughly half the candidates.

- `"full"` — adds the unblocked token sweep. Use when maximising the
  adjudication queue matters more than runtime.

- `"none"` — state-blocked only. Fastest; gives up the state-typo
  recovery that `A1` cannot reach (a wrong state *and* a wrong ZIP).
