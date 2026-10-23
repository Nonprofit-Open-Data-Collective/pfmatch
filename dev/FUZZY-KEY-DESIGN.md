# Spell correction, fuzzy blocking keys, and what each is good for

Measured 2026-10-22. Scripts: `dev/spellcheck-diagnose.R`,
`dev/namesim-worked-examples.R`. Follows from
`dev/NO-RESIDUAL-BLOCKING-REPLAY.csv`, which found 7 of 25 audited cases never
retrieved at all because token blocking requires an **exact** token match.

## Spell correction: mostly no, and for an instructive reason

The intuition is that cases fail on misspellings of common words —
`LIONS EYE DOUNDATION`, `BOROUGHS COMMUNITY CENTER`. Measuring it against the
reference vocabulary (397,592 distinct tokens) deflates it:

> Of 76 distinct content tokens across the audited filed names, **3** are absent
> from the reference vocabulary: `CTRP`, `HALOCHEN`, `VETFAM`.

`DOUNDATION` is **not** among them. It appears in the reference with df = 1 —
the BMF has the same typo. Neither is `BOROUGHS`, which is a real English word
and a real organisation name.

That is the whole lesson. **Retrieval is not failing because a token is
unknown; it is failing because a known, correctly-spelled token does not appear
in the right row.** A spell checker asks "is this word wrong?", and for these
cases the answer is almost always no. It is the wrong question.

The right question is "what else is near this word?", which needs no judgement
about correctness and no dictionary.

### If correction were used anyway, it must be additive

The data makes the case better than the principle does. Four of 73 known tokens
sit next to a neighbour at edit distance 1 that is more than 20x commoner:

| token | df | would be pulled toward | df |
|---|---:|---|---:|
| `UCAP` | 3 | `CAP` | 737 |
| `SCHL` | 67 | `SCH` | 3,195 |
| `FRIDGE` | 22 | `BRIDGE` | 4,725 |
| `DOUNDATION` | 1 | `FOUNDATION` | 39,733 |

Only the last is a real typo. `UCAP` is the acronym the D1 pass needs to find
Urban Collaborative Accelerated Program; `FRIDGE` is correct (We Care / Feed the
Fridge); `SCHL` is a deliberate abbreviation. **Replacement would be actively
harmful in three of four cases.** Adding a second key keeps both paths open.

A second, independent argument: neither unseen token with any neighbour had a
*unique* one — `CTRP` sits at distance 1 from `CORP`, `CTRL`, `CARP` and `CTRS`.
"Correct it" is not even well defined. Emitting all neighbours as extra keys is,
because the comparator still has to choose and Jaro-Winkler is good at that
(`dev/NAME-METRIC-EVALUATION.md`).

## Fuzzy keys: yes, and it takes two families, not one

The two obvious mechanisms cover **disjoint** failures:

| filed → correct | edit distance | delete-1 index | soundex |
|---|---:|---|---|
| `DOUNDATION` → `FOUNDATION` | 1 | yes | **no** — D533 ≠ F533 |
| `HACHESSED` → `HACHESED` | 1 | yes | yes — H223 |
| `BOROUGHS` → `BURROUGHS` | **2** | **no** | yes — B620 |
| `NUYGEN` → `NGUYEN` | **2** | **no** | yes — N250 |
| `THTR` → `THEATER` | 3 | no | no |

Soundex keys on the first letter, so any first-letter typo defeats it — exactly
the common-word case. An edit-distance index defeats on distance 2. Together
they reach four of five. `THTR → THEATER` is a consonant-skeleton abbreviation
rather than a typo and belongs to the acronym path, which already handles it:
D1-acronym was the only pass that retrieved `NW CHILDREN'S THTR SCHL`.

So a single fuzzy mechanism is not enough, and the choice between them is not a
trade-off — it is an and.

### Why this cannot cost precision

Extra blocking keys only generate **candidates**. Nothing is accepted that
`np_compare()` does not score and `np_tier()` does not clear. The risk is
entirely compute, not correctness — which is the opposite of the risk profile
of changing the comparator or lowering a threshold.

### Cost is the real constraint

Soundex has roughly 8,900 reachable codes, so 397,592 reference tokens average
~45 per bucket against ~1 for an exact token. That is a large fan-out, and
`dev/BENCHMARK-NOTES.md` already records that unblocked token sweeps are where
this cascade goes quadratic (the C3 pass yields zero YES for its cost).

Therefore fuzzy keys belong in a **stage-D recovery pass**, which runs only on
the residual the earlier stages could not resolve, never in B1 where they would
multiply every query. Gate them further:

* fire only on query tokens whose reference df is low (a fuzzy variant of
  `FOUNDATION` is pure cost);
* keep `min_pair_idf`, so a fuzzy match on a common token cannot justify a pair
  on its own;
* cap neighbours per token.

## What it takes to build

The insertion point already exists and the pattern is proven. `.np_tokenize()`
emits `base` and `concat` token lists; `np_ref_index()` caches both with
document frequencies; `np_block()` selects between them on `concat_adjacent`.
The de-spacing bigrams are precisely a synthetic-extra-token mechanism already
in production, so fuzzy keys slot in beside them.

| change | file | approx |
|---|---|---:|
| `.np_delete1()` / `.np_phonetic_key()` helpers | `npmatch/R/block.R` | 15 |
| emit `fuzzy` alongside `base` / `concat` | `.np_tokenize()` | 15 |
| index + document frequency for it | `np_ref_index()` | 10 |
| `fuzzy_tokens =` argument and selection | `np_block()` | 20 |
| `D3-fuzzy` pass | `pfmatch/R/recover.R` | 5 |

~65 lines plus tests. The work that actually matters is not the code but the
measurement: candidate blow-up per pass, and whether the recovered rows survive
scoring. Note from the replay that **18 of 25 audited cases were already
retrieved and lost downstream**, so fuzzy keys address the smaller half of the
problem. The composite score is the bigger lever.

## Order of work

1. Fix the composite score — 18 of 25, a good name with a matching city landing
   near 0.60 under a 0.65 floor.
2. ZIP-vs-state fallback in blocking — one line of logic, one case in 100.
3. `D3-fuzzy` with both key families, measured for blow-up.
4. Align the acronym key on both sides so D1 reaches `CASA OF NJ`.
5. Do **not** add spell correction as a normalisation step.
