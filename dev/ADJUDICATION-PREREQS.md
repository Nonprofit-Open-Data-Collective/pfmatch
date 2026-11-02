# What has to be measured before the adjudication pipeline is built

Written 2026-11-02. Reconciles the three notes that stage adjudication, and
lists the measurements that have to exist before the design is *knowable* rather
than chosen. **This note contains no new measurement.** Every figure in it is
cited to the file that produced it; where a figure is contested, the contest is
cited too.

The question it answers: someone sitting down to implement adjudication finds
three overlapping plans, two of them numbered differently, and a routing
recommendation resting on 27 cases. Which order, and what has to be known first.

## 1. The three notes, and how they relate

| note | scope | what it is |
|---|---|---|
| `dev/ADJUDICATION-PLAN.md` §7 | MAYBE only | eight steps, revised 2026-08-20 |
| `dev/DEVELOPMENT-PLAN.md` Phase 4 | MAYBE only | five steps, the spine |
| `dev/DEVELOPMENT-PLAN.md` Phase 4b | **MAYBE and NO** | layer routing, added 2026-11-01 |

§7 and Phase 4 are the same spine at different revisions. Phase 4 is newer and
better in two specific ways, and worse in one.

**Better:** it scales the labelling round from 200 cases to ~1,000, and it moves
independent calibration *before* the queue and the production batch. §7 ran the
batch at step 6 and calibrated at step 7, which is the wrong way round — the
queue is built out of what calibration tells you, so calibrating afterwards
prices a queue whose composition you have not yet justified.

**Worse:** Phase 4 silently drops three §7 items. They are not superseded or
argued against anywhere; they are simply absent from the newer list.

| §7 step | Phase 4 | in the package? |
|---|---|---|
| 1 label 200, confirm ≥97% precision | superseded by Phase 4 step 2 | done — **72%**, so no auto-accept |
| 2 enrich the candidate packet | step 1 | **yes** — `pf_bmf_context()`, `pf_attach_missions()` |
| **3 `pf_adjudicate_auto()`** — `best_guess` + `confidence`, for tiering the queue and never for skipping review | **dropped** | no |
| **4 the two structural review-priority flags** | **dropped** | no |
| 5 dollar-sorted review queue | step 4, "re-derive at full scale" | no |
| 6 LLM batch on the enriched packet | step 5, MAYBE-only, Batch API | `dev/` only |
| 7 verify a stratified subsample independently | step 3 — **moved earlier** | `dev/` only |
| **8 entity-vs-fundraising-arm policy** | **dropped** | not decided |

Phase 4 also adds what §7 does not have: the arm-pair stratum pulled forward
(~100 labelled pairs settle an ordering policy currently resting on 15 cases,
against 196 reported EINs and 446 promotions of difference on a 50k sample), the
tier-filter economics, the Batch API rate-limit argument, and an exit criterion.

**Phase 4b is not a third step list.** It is orthogonal: which of four layers
goes in front of which tier. It is also the only one of the three that addresses
the **NO** tier — §7 is titled for MAYBE and Phase 4 scopes itself to MAYBE
explicitly. Anyone reading §7 or Phase 4 alone will build half a system.

So the merged picture is: **one spine, three orphaned items, one routing model.**

## 2. What Phase 4b already settles, and on what

Phase 4b recommends layer 1 everywhere for MAYBE with the cheap arm's own
`low`-confidence 18% escalated to layer 2; layer 3 with the cheap model for NO;
and layer 0 first for both. The reasoning is sound and the non-obvious part —
escalate *without* search — is the best-evidenced claim in the three notes: the
ablation decomposes the two-arm gap into **+7.4 points of model and +3.7 of
search**, the search step is one case in 27 (McNemar exact p = 1.000), the
no-search arm cleared **more** (49/68 against 47/68), and search's measurable
effect was on confidence (high 51% → 73%) rather than correctness.

What it rests on is thinner than what it concludes:

* the MAYBE recommendation is **26/27**;
* the NO recommendation is **33.0% against 36.3%** on 91 cases, with the same
  EIN named 31 times out of 31;
* the two were measured on **different packets**, so the two tiers' layer
  accuracies are not comparable with each other;
* layer 0's interaction with layers 1–3 is measured at **3 of 33** web-established
  EINs reached, 2 agreeing, **1 contradicting**.

None of that is wrong. It is a recommendation that cannot currently come out
wrong, which is the shape `dev/METRIC-SHAPES.md` exists to catch.

## 3. The finding: these are not twelve experiments

Eight of the twelve tests below are **cuts of one labelling round**, if that
round is designed for them: all four layers run over the *same* enriched cases,
with confidence and evidence class recorded per verdict.

Phase 4 step 2 and Phase 4b's routing question are therefore **one experiment,
not two**. Run as written — two phases, two packets — they produce another pair
of incomparable denominators, which is the defect class
`dev/PLAUSIBLE-WRONG-NUMBERS.md` catalogues and the specific failure
(a share over the wrong population) that `dev/assert-lib.R` was written to stop.

Design the round once, and the routing table stops being an extrapolation.

## 4. Tier 0 — nothing downstream is knowable without these

**T1. The labelled enriched set.** ~1,000 cases, stratified, `NONE` a
first-class verdict, an evidence class (`QUOTE` / `NTEE` / `INFER` / `NONE`) and
a quoted sentence on every verdict. Stratify to over-sample arm pairs and
restricted-gift purposes, and include the two flag populations (T8) and the
entity-vs-fundraising shapes (T7) so they come free.

*Why it is irreducible:* the 200-case round was run on the **unenriched** packet
(`dev/ADJUDICATION-PLAN.md` §1). Those labels do not transfer to a packet that
now carries NTEE text, mission and program descriptions, because the thing being
judged changed. Every test below is a cut of this one.

**T2. Independent verification of a stratified subsample**, reporting accuracy
per evidence class. Candidate-only review survived independent verification on
**~5 of 12** checks (§7 step 7), which is why both notes say no accuracy claim
ships without this step.

## 5. Tier 1 — free cuts of Tier 0, if the round is designed for them

**T3. Confidence monotonicity, per arm and per tier.** Gates both the dropped
`pf_adjudicate_auto()` and Phase 4b's MAYBE escalation rule, which is the
*only* part of the routing recommendation that depends on a model's self-report.

*Do not assume it:* `dev/adjudicate-15-no-arms.R:176` records that the MAYBE
search arm's confidence **rose as accuracy fell** — "worse than useless" — while
Opus on the NO tier was the inverse. Confidence calibration is arm- and
tier-specific, so it has to be measured for the exact arm that would ship.

**T4. Does the evidence class discriminate?** The design assumes
QUOTE > NTEE > INFER. Untested. If it holds, the evidence class is the
acceptance gate and confidence is redundant; if it does not, requiring it buys
prompt cost and an audit trail that does not predict correctness.

**T5. Layer accuracy per tier, on common cases.** Turns Phase 4b's table from an
extrapolation into a finding. Needs all layers on the same cases — see §3.

**T6. Layer 0 against layers 1–3: substitute or complement?** "They compose" is
structurally true; the *size* is unmeasured. At 3 of 33 reached with 1
contradiction, substitution and complementarity are indistinguishable, and the
contradiction is the costly outcome rather than a near miss: one of the two EINs
is wrong and the pipeline cannot say which.

**T7. The entity-vs-fundraising-arm inconsistency rate.** The dominant measured
failure is inconsistency on identical structure, so measure the rate — including
whether two reviewers, and a model against itself, agree — before writing §7
step 8's policy. A policy written against an unmeasured rate cannot be shown to
have improved anything.

**T8. Flag precision at usable n.** The two structural flags are **60% on n=15**
and **71% on n=7** (§7 step 4). Neither can carry a shipping decision, and both
are cheap to re-measure inside T1.

## 6. Tier 2 — independent of labelling, runnable now

**T9. Re-derive the dollar-coverage curve.** Phase 4 step 4 and §7 step 5 both
rest on "~740 reviews cover 70% of the recoverable unresolved dollars".
`dev/FIGURE-PROVENANCE.md` §6 finds that table does not reproduce — **489
against a published 738** at the 70% point, and 113/489/1,094/2,806 against
195/738/1,475/3,528 across the four rows — and that the note which would settle
it, `dev/GRANT-DOLLARS-FINDINGS.md`, is cited at `ADJUDICATION-PLAN.md:127` and
`PACKAGE-PLAN.md:375` and **has never existed in this repository**. Re-run with
§4's two stated exclusions applied and see whether 489 moves.

*Why it blocks:* the queue's whole premise is a dollar-coverage claim. The error
runs conservative rather than flattering, so the queue may be larger than it
needs to be — but the direction is an inference, not a measurement.

**T10. A Batch API pilot at ~10k cases.** Phase 4 step 5's feasibility rests on
100 cases at 6 concurrent workers extrapolated to 1.01M calls (~150 h on one
synchronous stream). That is a 10,000x extrapolation of a throughput figure, and
rate limits are the stated binding constraint rather than price.

**T11. Precision on the YES mass.** `dev/BASELINE-2026-10C/MANIFEST.md` records
it as unmeasured. **This is the test that could reorder the phase**: adjudication
is justified by what MAYBE recovers, and if YES precision sits below assumption
then auditing YES outranks adjudicating MAYBE. It needs its own stratified
sample and cannot be read off the adjudication round.

**T12. Unit tests for the sheet builder.** `pf_adjudicate()`,
`pf_candidate_frame()` and `pf_bmf_context()` have **no test referencing them**
anywhere in `tests/`. In particular, Phase 4 step 1 requires enrichment on
*every* candidate, and nothing asserts it. Adding `pf_adjudicate_auto()` and two
flags on top of an untested sheet builder is how a figure goes wrong quietly:
the sheet is where every later number comes from.

## 7. What needs no further test

* **Auto-accepting MAYBE.** Settled at 72% precision (95% CI 65–78%) on 200
  fresh cases against a first estimate of 18/18. Closed.
* **Scoping production to the MAYBE tier.** $11,635 for every grant row,
  $3,092 for every identity, **$680** for MAYBE identities only — a 17x saving
  before any model or pricing decision (Phase 4 step 5).
* **Layer 0 first.** Structural: a pair it recovers is a pair layers 1–3 then
  get to see. Also the only layer whose bill does not scale with the corpus.
* **Escalating without search on MAYBE.** The ablation evidence in §2 above.

## 8. One correction this reconciliation inherits

Phase 4b flags it itself, and it matters for any NO-tier budget: a budget built
on `BASELINE-2026-10C`'s **725** NO under-counts the tier by 14%, because those
4,748 "identities" are the *result frame* and the 120 in-scope identities no
blocking pass produced a pair for are absent from it. **The tier is 845.** Those
120 are the hardest retrieval failures in the file, so a NO-tier layer costed on
725 is costed on the easier 86% of the tier.

## 9. What this note does not claim

It does not claim the Phase 4b recommendation is wrong — only that it is not yet
falsifiable, because every arm of it was measured on a denominator too small to
embarrass it. It does not claim the dropped §7 items should be built; T3 and T8
exist precisely to decide that, and the honest outcome of T8 may be that neither
flag ships. It does not re-measure anything: no figure here was computed for this
note, and §10 says where each came from. And it does not set the order *within*
Tier 1 — those are cuts of one run, so they have no order.

The one ordering claim it does make: **T1 and T2 precede everything, T9 to T12
can start today, and the rest are free if T1 is designed for them.**

## 10. Provenance

| figure | source |
|---|---|
| 72% on 200, 18/18 on the first sample | `dev/ADJUDICATION-PLAN.md` §1 |
| ~5 of 12 independent checks | `dev/ADJUDICATION-PLAN.md` §7 step 7 |
| flags 60% n=15, 71% n=7 | `dev/ADJUDICATION-PLAN.md` §7 step 4 |
| 196 EINs, 446 promotions, 15-case basis | `dev/DEVELOPMENT-PLAN.md` Phase 4 step 2 |
| $11,635 / $3,092 / $680; ~150 h | `dev/DEVELOPMENT-PLAN.md` Phase 4 step 5 |
| 26/27, 33.0% vs 36.3%, 31/31, layer costs | `dev/DEVELOPMENT-PLAN.md` Phase 4b |
| +7.4 / +3.7, p = 1.000, 49/68 vs 47/68, 51% → 73% | `dev/DEVELOPMENT-PLAN.md` Phase 4b |
| 3 of 33, 2 agree, 1 contradicts | `dev/DEVELOPMENT-PLAN.md` Phase 4b, layer 0 |
| NO tier is 845, not 725 | `dev/DEVELOPMENT-PLAN.md` Phase 4b |
| confidence rose as accuracy fell | `dev/adjudicate-15-no-arms.R:176` |
| 489 against 738; the four-row table | `dev/FIGURE-PROVENANCE.md` §6 |
| `GRANT-DOLLARS-FINDINGS.md` absent, cited twice | `ADJUDICATION-PLAN.md:127`, `PACKAGE-PLAN.md:375` |
| YES precision unmeasured | `dev/BASELINE-2026-10C/MANIFEST.md` |
| no tests reference the three sheet functions | `tests/`, by inspection |

See also `dev/PLAUSIBLE-WRONG-NUMBERS.md` for the defect class §3 refers to,
and `dev/METRIC-SHAPES.md` for the practice that a metric which cannot come out
wrong is not evidence.
