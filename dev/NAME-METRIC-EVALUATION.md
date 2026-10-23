# Does a different fuzzy-match algorithm fix the NO residual?

No. Tested 2026-10-22 against the cases pfmatch actually fails on. Scripts:
`dev/build-namesim-testset.R`, `dev/compare-name-metrics.R`,
`dev/namesim-diagnose.R`, `dev/namesim-worked-examples.R`.

## What production uses

Jaro-Winkler, in two places in `np_compare()`:

* `reclin2::cmp_jarowinkler(threshold = config$jw_threshold)` for the name and
  the fuzzy geo fields;
* `stringdist::stringsim(method = "jw", p = 0.1)` for the name/DBA/division
  cross-products, whose max becomes the effective name score.

Similarities below `jw_threshold` (**0.85**) are floored to 0. That floor is
applied explicitly in `np_compare()`, because reclin2's `threshold=` argument is
the Winkler prefix *boost*, not a cutoff — without the floor, unrelated strings
leak ~0.5 into every score.

There is already a token fallback, `.np_contain_overlap()`: acronym-aware,
containment-aware token overlap. It is gated on **address confirmation** (same
ZIP5, street number, or PO box) *and* ≥2 shared tokens *and* a shared token with
IDF ≥ 9, and `np_score()` caps a token-overlap-only match at MAYBE.

## How this was tested

The obvious experiment — score the true pairs under each metric and pick the
highest — is worthless, because it ranks metrics by looseness. Every case
therefore carries hard negatives drawn from its own candidate pool:

* the near-miss the production scorer actually chose (a wrong answer the
  current system already likes), and
* up to 40 same-state reference rows sharing the filed name's rarest token —
  i.e. exactly what a rare-token retrieval route would hand the comparator.

21 cases, 1,274 positives (all reference name variants for the adjudicated EIN),
442 negatives. Names normalised with the pipeline's own `name_key` pipeline, so
this measures metrics and not normalisation choices.

Reported per metric: `prec@1` (does the best correct name beat the best wrong
one), AUC within case, and at the 0.85 operating point `finds` (a correct name
clears it) and `admits` (a **wrong** name clears it).

## Result

| metric | prec@1 | AUC | finds | admits |
|---|---:|---:|---:|---:|
| qgram_cosine | 76% | 0.717 | 8/21 | 2/21 |
| qgram_jaccard | 76% | 0.688 | 6/21 | 2/21 |
| token_jaccard | 71% | 0.679 | 6/21 | 2/21 |
| lcs | 71% | 0.676 | 7/21 | 2/21 |
| **jw (production)** | 67% | 0.716 | 16/21 | 11/21 |
| lv | 67% | 0.627 | 7/21 | 2/21 |
| token_set | 62% | 0.684 | 20/21 | 18/21 |
| idf_cosine | 62% | 0.558 | 7/21 | 3/21 |
| max(jw, idf_contain) | 57% | 0.718 | 18/21 | 12/21 |
| monge_elkan | 57% | 0.718 | 17/21 | 14/21 |
| token_contain | 57% | 0.659 | 13/21 | 8/21 |
| idf_contain | 52% | 0.590 | 13/21 | 8/21 |

**Nothing beats Jaro-Winkler by a margin this test set can resolve.** The top
AUCs — 0.718, 0.718, 0.717, 0.716 — are a four-way tie that includes JW. On
prec@1, JW is 14/21 (95% CI 43–85%) against qgram_cosine's 16/21 (53–92%). Two
cases. At n = 21 the table ranks noise.

What *is* real is the shape: **changing the string metric moves along the
precision/recall curve, not off it.** `token_set` finds 20 of 21 and admits 18
of 21. `idf_contain` finds 13 and admits 8. JW finds 16 and admits 11. They are
all on the same curve, so a metric swap buys recall by spending precision at
roughly the going rate.

## Why the containment family loses

It looked like the obvious fix — the failure modes are containment, reordering
and acronyms, which are exactly what JW is bad at. On the worked examples
(`dev/namesim-worked-examples.R`) containment scores 1.00 where JW scores 0.76.

But this residual is full of **short filed names**, because truncation and
abbreviation are what made these cases hard in the first place — and containment
rewards a short name for being a subset of anything longer:

| filed (key) | correct, idf_contain | wrong, idf_contain |
|---|---|---|
| `GIRLS` (from GIRLS INC) | Girls Inc of Washington County — 1.00 | an org literally named `GIRLS` — 1.00 |
| `PLAYWORKS` | Playworks — 1.00 | `PLAYWORKS WASHINGTON DC` — 1.00 |
| `ANIMAL SHELTER` | Animal Shelter Inc — 1.00 | `STERLING` — 1.00 |
| `CROWN FINANCIAL MINISTRIES` | 0.79 | `THE CROWN FOUNDATION INC` — 1.00 |

JW's length penalty, which looks like the bug, is what keeps those out.

## The deeper reason: the name has run out of information

In 7 of 21 cases a **wrong** organisation has a name at least as good as the
right one under JW:

| filed | correct | wrong |
|---|---|---|
| PLAYWORKS | `PLAYWORKS` 1.00 | `PLAYWORKS INC` **1.00** |
| CROSSROADS THE RIDE | `CROSSROADS` 0.91 | `CROSSROADS SHELTER` **0.91** |
| WGBH Public TV | `WGBH` 0.86 | `WGBH MUSIC` **0.87** |
| EASTER SEAL SOCIETY OF DEL-MAR | `EASTER SEALS` 0.88 | `EASTER SEAL SOCIETY OF WESTERN PENN` **0.91** |
| GIRLS INC | `GIRLS INC OF WASHINGTON COUNTY` 0.83 | `GIRLS` **1.00** |

These are sibling-organisation collisions — a chapter, an affiliate, a
same-named unrelated charity. No string metric can resolve them, because the
string genuinely does not contain the answer. The discriminating evidence is
geography, parent/child structure, and corroboration. That is why the metric
sweep has no winner: it is asking the string to carry information it does not
have.

## Acronyms need a targeted rule, not a term in the max

The sweep's acronym test scored 0 everywhere — a bug in the test, not a result:
it only fired when one side reduced to a single token, and `CASA OF NJ`
tokenises to CASA + NJ. Repaired to scan k-token windows, it fires on exactly
the two acronym cases (`UCAP SCHOOL` → Urban Collaborative Accelerated Program,
`CASA OF NJ` → Court Appointed Special Advocates of New Jersey) and on one wrong
name. Folded into the score as `max(jw, acronym)` it is **net negative**:
prec@1 67% → 62%, finds 16 → 17, admits 11 → 12.

Acronym evidence is strong but needs gating on something else (geography, IDF of
the expansion) rather than being allowed to set the score on its own. pfmatch
already has the right instinct here: the D1-acronym pass puts acronyms in
*blocking*, where they generate a candidate that still has to be confirmed.

## Where the cases are actually lost

Replaying the production passes over the 25 adjudicated EINs
(`dev/replay-no-residual-blocking.R`, `dev/NO-RESIDUAL-BLOCKING-REPLAY.csv`)
splits the residual in two:

```
A1-A5 exact         0 pairs
B1-token-state  1,118 pairs   correct EIN retrieved for 15 of 25
B2-token-concat 1,216 pairs                              15 of 25
C1-name-any        46 pairs                               4 of 25
C2-dba-any         10 pairs                               0 of 25
D1-acronym      1,054 pairs                              15 of 25
D2-prefix           6 pairs                               2 of 25
                           retrieved by some pass:       18 of 25
                           never retrieved:               7 of 25
```

**18 of 25 were retrieved and still lost downstream.** The correct row reached
the comparator; JW scored the correct name ≥0.85 in 16 of 21; and the case still
ended NO. These are scoring failures — either a sibling scored as well (above),
or a good name score was diluted against weak geo corroboration into the ~0.60
composites seen throughout `dev/NO-RESIDUAL-AUDIT.md`, under the 0.65 MAYBE
floor. No comparator change helps, because the comparator was already right.

**7 of 25 were never retrieved**, and for those no comparator could have helped
at all. The mechanism is that token blocking requires an **exact** token match:

* `BOROUGHS COMMUNITY CENTER` → **1** candidate in the whole reference. The
  single-letter typo (`BOROUGHS` / `BURROUGHS`) means it shares no token with
  the correct row, so the row is unreachable however good the comparator is.
* `EASTER SEAL SOCIETY OF DEL-MAR` is filed in the wrong state (ZIP 19720 is
  Delaware, the record says PA), so every state-keyed pass looks in the wrong
  place.
* `CASA OF NJ` is not recovered even by D1, because `pf_initials()` builds the
  reference acronym over the whole content string (`CASANJ`-style) while the
  query token is `CASA`, and blocking needs them equal.

D1-acronym is the strongest single pass here — 15 of 25, and the only pass that
finds `UCAP SCHOOL` and `NW CHILDREN'S THTR SCHL`. It was initially reported as
crashing; that was an error in the replay harness, which did not call
`pf_add_recovery_keys()` to build `name_acro` / `name_pre`. The pass is sound.

## What this means for the fix

1. **Do not replace the comparator.** No tested metric separates from JW, and
   18 of 25 cases had the right row in hand anyway.
2. **The retrieval fix is fuzzy keys, not a fuzzy comparator.** Exact-token
   blocking cannot reach a typo'd rare token. A phonetic or q-gram key
   (double-metaphone, or 3-gram shingles on the rarest token) as an *additional*
   blocking pass would reach `BURROUGHS` from `BOROUGHS` — and because it only
   generates candidates, JW still has to confirm them, so it cannot by itself
   cost precision.
3. **Make blocking fall back to ZIP when the filed state contradicts it.** One
   case in 100 in the audit, and it is free.
4. **The scoring fix is the composite, not the name term.** Work out why a
   ≥0.85 name with a matching city lands at 0.60 — that is 18 of these 25 and it
   is the single largest lever found anywhere in this analysis.
5. **Align the acronym key on both sides** so D1 can reach `CASA OF NJ`.
