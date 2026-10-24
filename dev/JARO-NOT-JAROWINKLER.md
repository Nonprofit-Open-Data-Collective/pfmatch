# The name comparator is Jaro, not Jaro-Winkler

> **Population note, added 2026-10-23.** The figures below are measured on
> `ef1k` (population `d1c3db4c56a01709`), the undeduplicated v1 samples, which
> `BASELINE-2026-10B` supersedes. They were re-measured on the deduplicated v2
> population and the *conclusions hold* — every clear rate moves by about a
> fifth of a point and the ordering of the arms is unchanged. Quote
> `dev/BASELINE-2026-10B/MANIFEST.md` for current numbers, not this file.


Found 2026-10-22 while tracing why pairs with a matching address were scoring
0.360. Scripts: `dev/trace-geo-credit.R`, `data-dev/GEO-CREDIT-TRACE.csv`.

## What happens

`np_compare()` builds its comparators as

```r
reclin2::cmp_jarowinkler(threshold = jt)     # jt = config$jw_threshold = 0.85
```

and reclin2 implements that as

```r
cmp_jarowinkler <- function(threshold = 0.95) {
  function(x, y) {
    if (!missing(y)) 1 - stringdist(x, y, method = "jw")   # <- no p argument
    else (x > threshold) & !is.na(x)
  }
}
```

`stringdist(method = "jw")` defaults to **`p = 0`**, which is plain **Jaro** —
no Winkler prefix boost. The `threshold` argument is never reached on the
two-argument path, so it does nothing at all here.

Meanwhile the name/DBA/division cross-products a few lines later in the same
function use

```r
stringdist::stringsim(a, b, method = "jw", p = 0.1)          # real Jaro-Winkler
```

So **two different metrics are used for the same quantity inside one function**,
the same 0.85 floor is applied to both, and the primary name↔name path is the
weaker of the two. Whatever the right choice is, it cannot be both.

## Why it matters

The three cases that prompted the trace all sit in the gap between the two
metrics:

| pair | Jaro (p=0) | JW (p=0.1) |
|---|---:|---:|
| `PLAYWORKS` / `PLAYWORKS WASHINGTON DC` | 0.797 | 0.878 |
| `THISTLEBEND COTTAGE` / `THISTLEBEND MINISTRIES` | 0.791 | 0.875 |
| `SALVATION ARMY` / `SALVATION ARMY BIRMINGHAM AREA COMMAND` | 0.789 | 0.874 |

Under Jaro all three fall below the 0.85 floor and the name term is zeroed, so
only geo survives: `0.4 × 0.90 (zip5) = 0.360`, exactly the traced score. Under
Jaro-Winkler all three clear, and with the zip5 credit they reach
`0.6 × 0.878 + 0.4 × 0.90 = 0.887` — YES.

The prefix boost is precisely what a filed name that is a *prefix* of the legal
name needs, and that is the dominant shape in this data: a parent name extended
by a chapter, a city or a programme.

## Measured effect

On the 21-case name test set (`dev/NAME-METRIC-EVALUATION.md`), 1,274 positives
and 442 negatives:

```
mean positive similarity   Jaro 0.758 -> JW 0.833   (+0.075)
mean negative similarity   Jaro 0.639 -> JW 0.683   (+0.044)
```

The boost helps true pairs **more** than false ones, so it separates the
distributions rather than merely inflating them.

| configuration | prec@1 | finds | admits |
|---|---:|---:|---:|
| Jaro, floor 0.85 — **current** | 62% | 9/21 | 5/21 |
| JW p=0.1, floor 0.85 | 67% | 16/21 | 11/21 |
| JW p=0.1, floor 0.88 | 67% | 13/21 | 7/21 |
| JW p=0.1, floor 0.90 | 67% | 10/21 | 6/21 |
| Jaro, floor 0.78 — *relax the floor instead* | 62% | 14/21 | 9/21 |

This is the answer to "would relaxing the floor help": **no — relaxing the floor
moves along the curve and leaves prec@1 at 62%, while fixing the comparator
shifts the curve to 67%.** And once fixed, the floor should probably go *up*,
not down: JW at 0.88 finds 13 and admits 7, a better ratio than Jaro at 0.78
(14 and 9).

## Measured on the full cascade

`dev/bench-jw-ab.R`, 5,000 grant rows against the augmented unified reference,
same passes as `dev/bench-efilepf.R`. npmatch now exposes `config$jw_p`
(`NULL` = today's split behaviour, a number = one `p` on both paths).

```
                   YES    YES+MAYBE
Jaro (current)   63.0%        84.8%
Jaro-Winkler     64.5%        88.8%
change           +1.5         +4.1
```

Tier movement (rows Jaro, columns Jaro-Winkler):

| | YES | MAYBE | NO |
|---|---:|---:|---:|
| **YES** | 2912 | **138** | 1 |
| **MAYBE** | 137 | 916 | 1 |
| **NO** | **77** | **122** | 539 |

NO falls from 738 to 541. Identity churn is negligible: of the 2,912 rows YES
under both, **2** changed EIN. So this is a tiering change, not a reshuffle of
which organisation gets picked.

On the 25 hand-adjudicated NO-residual cases, the number surfaced as YES or
MAYBE **with the correct EIN** goes from **0 to 7**. Under Jaro nine of those
already had the correct top pick and not one was offered for review.

### It is not free

**138 current YES demote to MAYBE.** Raising every name similarity also raises
the runner-up, so `min_margin = 0.05` now fails on pairs that previously cleared
it. Net YES is +75 (214 promotions against 139 demotions). Those 138 are
auto-accepted today and would become review work.

**Some new YES are wrong.** Within the adjudicated 25, `BEIT HALOCHEN USA` goes
NO → **YES on the wrong EIN** (under Jaro its top pick was correct), and
`WGBH Public TV` goes NO → YES also wrong, against 4 newly-correct YES.
`MUSCULAR DYSTROPHY` loses a correct top pick. That is roughly 67% precision on
new YES in a sample of six — tiny, and biased toward current failures, but it
is evidence the promotion is not clean.

### Settled against ground truth — and it reverses the above

`dev/evaluate-arms.R` scores all four arms against `data-dev/PF-TRUTH.csv`
(177 labels, 89 with a known correct EIN, 59 asserting no organisation exists at
all, 40 carrying an EIN adjudication ruled out).

| arm | recall YES | recall Y+M | false clears | ruled-out EINs picked |
|---|---:|---:|---:|---:|
| Jaro (current) | 23/89 **26%** | 36/89 **40%** | 0/59 | **15** |
| Jaro-Winkler | 32/89 **36%** | 49/89 **55%** | 1/59 | **10** |
| Jaro + substring | 23/89 26% | 43/89 48% | 0/59 | 15 |
| both | 32/89 **36%** | 52/89 **58%** | 1/59 | **10** |

**Jaro-Winkler is better on the negative checks, not worse.** It picks 10
explicitly-ruled-out EINs against Jaro's 15, and costs **one** false clear out
of 59 known-impossible cases. The caution recorded above — that Jaro-Winkler
"carries all the risk" — came from eyeballing 2 apparent wrong YES in a 25-case
sample drawn from current failures. It does not survive measurement against 59
known-impossible cases and 40 negative constraints.

Recall rises substantially: 23 → 32 correct-and-cleared, 36 → 49 surfaced.

**The 138 demotions do not appear as damage.** A demoted correct answer would
leave `recall YES` while remaining in `recall Y+M`; both rose. That is
reassuring and **not** conclusive, because the truth table is built from cells
the pipeline failed on and so under-samples cases that were already YES —
precisely the population demotions would hurt. Still open.

**Recommendation: adopt both** (`jw_p = 0.1`, `substring_p = 0.90`), which is
best on every measured axis. Substring credit changes `recall YES` not at all
and lifts `recall Y+M` by 7, exactly as a review-only path should.

Do not read 26-36% as pipeline accuracy. These 89 cases were selected for being
hard. It means "of known-hard cases, this arm recovers 36%". Precision on the
3,051 YES mass remains unmeasured; the false-clear check is real but narrow.

## Do not just change it

Every threshold in the system was tuned against the behaviour the pipeline
actually had, which is Jaro. Switching to Jaro-Winkler raises *every* name
similarity by ~0.04–0.08, which will push a large number of currently-NO pairs
into MAYBE and some MAYBE into YES across all 4,869 identities. The 21-case test
set cannot predict that.

Required before changing it:

1. Re-run the full 1k benchmark under both settings and compare clear rate
   **and** the adjudicated-precision cells, not just the clear rate.
2. Re-tune `jw_threshold`, `thresholds$yes` and `thresholds$maybe` jointly —
   they are not independent of the comparator.
3. Re-freeze `dev/BASELINE-2026-08/`, since this changes the normalizer-adjacent
   behaviour the baseline is gated on.
4. Decide deliberately whether Jaro or Jaro-Winkler is wanted, and make the
   name↔name and name↔DBA paths agree either way. The present state — two
   metrics, one floor — is not a defensible choice in either direction.

## Note on the earlier "pooling" diagnosis

An earlier reading of the trace concluded that name credit and geo credit were
never earned by the same row, and that evidence needed pooling across rows of
an EIN. The full trace refutes that: rows carrying **both** do exist and do
score well.

```
SALVATION ARMY BIRMINGHAM AREA C  BIRMINGHAM AL  name 0.95  z5=1  score 0.780
JUVENILE DIABETES RESEARCH FOUND  ATLANTA GA     name 0.95  z5=1  score 0.780
```

Both reach 0.780 — the YES threshold, capped there because the match came
through `token_overlap`, which `np_score()` deliberately holds below YES. So
the evidence is not split; the right rows score fine when they are scored. The
open question is why the production run recorded 0.6017 and 0.6107 for these
identities instead, which points at which *row* blocking retrieved rather than
at the scorer. `dev/NO-RESIDUAL-BLOCKING-REPLAY.csv` only checked EIN-level
retrieval, not row-level, so that remains unmeasured.
