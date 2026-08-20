# Should this be a fitted model rather than a decision tree?

For **ranking** — which of the five candidates is right — yes, and the evidence
says so. For **accepting** — is any of them right — no, and no feature fixes
that, because the constraint is labels, not features.

This memo separates those two decisions, gives the measured status of every
feature on the wish-list, and answers the NTEE-classifier question (it was
already built; it does not help).

---

## 1. Two decisions, not one

| decision | question | labels available | verdict |
|---|---|---|---|
| **RANK** | which candidate is correct? | ~28k unambiguous YES in the 50k run as silver labels, 156 adjudicated as gold | **fit a model** |
| **ACCEPT** | is any candidate correct? | 156 adjudicated, of which independent verification upheld ~5 of 12 checked | **cannot fit yet** |

The accept decision is where the project's value sits and where a learned score
would be most seductive. Three things block it:

1. **41% of hard cases resolve to NONE** (`dev/ENRICHMENT-FINDINGS.md`). A
   ranker always names a winner. Abstention has to be a first-class class, which
   means gold labels that include NONE — and silver YES labels contain none by
   construction.
2. **The gold labels are not reliable enough to calibrate against.** Twelve
   independently verified labels upheld five. A probability calibrated on those
   inherits their error.
3. **The dominant failure has no determinate answer.** Operating entity versus
   its own fundraising arm: two real EINs, and nothing in any public source
   records which one the cheque named.

So: fit a ranker, keep a rule for accept, and spend the labelling budget on
abstention rather than on features.

## 2. Feature status

Pair AUC = P(correct candidate scores above a distractor from the same grant).
0.5 is chance. Sources: `dev/PURPOSE-MATCH-FINDINGS.md` §4–5,
`dev/test-grantee-prior.R`.

| feature | pair AUC | fires on | status |
|---|---:|---:|---|
| `score` — name + geo, the current cascade | **0.861** | ~all | shipped |
| `text_len` — chars of mission + program text | 0.810 | 92% | measured; a size prior, biased against small grantees |
| `n_prog` — program services reported | 0.792 | 87% | measured |
| `has_mission` | 0.744 | 79% | measured |
| `has_program` / files a full 990 | 0.742 | 83% | measured |
| `cov_all` — IDF containment, purpose vs org text | 0.665 | 50% | measured; +2 grants in 28 |
| **`grantee_prior`** — distinct *other* foundations funding this EIN | **0.577** | **20%** | **new; 0.877 AUC and 76% top-1 conditional on firing** |
| `nb_major` — NTEE major group predicted from purpose text | 0.644 | 93% | measured; **degrades** the combination |
| `funder_repeat` — same foundation, another grant to this EIN | — | **0%** | untestable in this sample, see §4 |
| `is_arm` — candidate is a fundraising arm | **0.470** | ~all | **negative — do not demote arms globally** |
| `has_ntee` | 0.425 | 76% | measured; weakly predictive of being *wrong* |

### The grantee prior is worth adding, with the same caveat as everything else

Built only from unambiguous YES rows (exact name, ZIP agreement, score ≥ 0.95 —
14,748 rows, 11,020 distinct recipients), leave-one-out so a grant never feeds
its own prior:

* overall AUC **0.577** — unimpressive
* but it **separates the candidates on only 20% of grants**, and on those it
  scores **AUC 0.877, top-1 76%**

That is the same shape as every other content feature on this project: precise
when applicable, silent most of the time. 84% of recipient EINs are funded by
exactly one foundation in a 50k sample, so the prior is mostly zero. It belongs
inside the tie band, not in the main score.

### `is_arm` at 0.470 is a correction worth stating plainly

Across all 83 adjudicated grants, **correct** candidates are fundraising arms
27% of the time and **distractors** 21%. Being an arm is mildly *positive*
evidence, not negative.

That does not contradict `dev/AFFILIATION-FINDINGS.md` — it qualifies it. There
the operating entity won 9 of 15 *within a detected arm/operating pair*. Here
the population is all candidates. A blanket "demote anything ending in
FOUNDATION" would lose more than it gains.

**This is the strongest argument for the user's framing.** A hand-built decision
tree invites exactly this error: a rule that is right inside one subpopulation
gets applied globally because it reads as a sensible heuristic. A fitted model
with an interaction term — `is_arm × in_detected_pair` — gets it right
automatically, and would have flagged the main effect as near-zero.

## 3. The NTEE-12 classifier: already built, and it does not help

Not hard at all, and already done (`dev/eval-purpose-sim.R`). A multinomial
naive Bayes trained on 337,260 Form 990 mission statements labelled with the
filer's own BMF NTEE major group:

| input | top-1 over 25 labels |
|---|---:|
| full mission statement | 59.1% |
| first 3 content tokens | 48.7% |
| first 2 content tokens | 43.5% |
| majority class | 15.4% |

So text → sector is learnable, and truncating to grant-purpose length costs
about 15 points. But as a **candidate feature** it reaches only 0.644 AUC, and
adding it to the name score makes results **worse**:

| weight on `nb_major` | 0 | 0.05 | 0.10 | 0.20 | 0.40 |
|---|---:|---:|---:|---:|---:|
| top-1 (gold, 28 grants) | 22/28 | 22/28 | 22/28 | 20/28 | 17/28 |

The failure is not the classifier. It is that **the grant purpose describes the
beneficiary programme while the NTEE code describes the organisation's primary
activity**, and these routinely differ — a health funder's grant "for after-school
tutoring" to a hospital foundation is not a classification error. Compounding it,
NTEE is unusable on 33.5% of BMF rows and *more* often missing on large
organisations, which are exactly the ones that generate ambiguity.

Answering the question directly: it adds nothing over the existing text
similarity scores, and used as a re-ranking weight it subtracts.

There is one untested variant worth a cheap look: using the classifier as a
**veto** rather than a ranker — ruling out a candidate whose predicted sector is
flatly incompatible — which trades recall for precision and would be measured on
what it demotes, not on AUC.

## 4. The sampling design is blocking one feature outright

`funder_repeat` — "does this foundation give to this EIN in another grant or
year" — separated the candidates on **0 of 83** adjudicated grants. That is not a
result about the feature. It is a result about the sample:

| file | grants | filers | median grants per filer | filers with ≥2 |
|---|---:|---:|---:|---:|
| 50k dev sample | 50,000 | 26,361 | **1** | 35% |
| 100k file | 100,000 | 39,817 | **1** | 46% |

The dev samples are random *grants*, so a foundation's portfolio arrives
shredded. At full scale each filer contributes its entire Part XIV table, and
every portfolio feature — funder repeat, cross-year name consolidation, the
foundation's own grantee cluster — becomes available.

**Recommendation: switch the dev sample to all grants from a random sample of
filers.** Same row count, same cost, and it unlocks a whole feature family that
is currently invisible. It also makes the dedup measurements more honest, since
within-filer repetition is where most duplication lives.

## 5. What a fitted ranker would actually look like

* **Target**: pairwise, within-grant — correct candidate over each distractor.
  Not pointwise; the decision is comparative and the candidate sets vary in size.
* **Training data**: silver from unambiguous YES (~28k grants in the 50k run,
  ~14.7k after the strict filter), gold from the 156 adjudicated cases as a
  held-out evaluation set, never as training.
* **Model**: logistic regression on within-grant feature *differences*, or
  LambdaMART if non-linearity earns its keep. With ~10 features and this much
  silver data, regularised logistic is likely to match the tree and stays
  auditable — which matters, because every finding on this project has needed to
  be explained to a human.
* **Features**: the table in §2, plus `arm_pair_member` and its interaction with
  `is_arm`, plus `joint_id` membership from `R/affiliation.R`, plus the Schedule A
  line-5 flag as a hard override rather than a feature.
* **What it will not do**: decide NONE. Keep that as a separate calibrated
  abstention model, and do not build it until the labels exist.

### The honest cost

The ranker is perhaps two days' work and would improve the arm cases materially
(the cascade is at 27% there, so almost anything helps). It will not move the
headline YES rate much, because `score` is already at 0.861 AUC and the cascade
is decisive where it is confident.

The thing that would move the headline is **1,000 adjudicated cases with NONE as
a first-class label**, collected on the enriched packet with an evidence class
attached. That is the investment decision in front of the project; feature
engineering is a smaller, safer bet that does not substitute for it.
