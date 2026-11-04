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
are cheap to re-measure inside T1 — *once there is a run to measure them on*.
Both compare the pick to the runner-up, so both need the `pairs` the production
run does not serialize; §6b.5(c) has the populations, the floor they miss, and
the one-line unblocker.

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

## 6a. What is built, 2026-11-02 — and what the normalizer work did not unblock

**It did not unblock T1, and nothing in code can.** The day's work on the
normalizer (npnormalize 0.1.6 → 0.1.8, the fixture rebuild, the address-key
re-measurement) made the measurement *base* trustworthy: four fixture tests
that had been silently abstaining now run, and the published address-key
figures were re-pinned under the installed signature. None of that produces a
labelled case. T1 is a data-collection round, T2 is a second one, and T3–T5 and
T8 are cuts of T1 — so the four decisions that were blocked before are blocked
now, on the same thing.

It arguably made two of the Tier 2 tests *more* work, and the note should say
so rather than let a reader assume otherwise. T9 and T11 both read off
`BASELINE-2026-10C`, which was measured under an older normalizer than the one
installed; matchdb's published tiers were rebuilt under `v1-5e901add4a04a5d6`
on 2026-11-02. Neither figure is wrong, but both are now cross-signature, which
is exactly the comparison `pf_check_reference()` exists to stop.

**What was built instead is the arithmetic those tests will need**, so that when
the labels arrive each one is a function call rather than a fresh analysis:

* **T12 — done.** `tests/testthat/test-adjudicate-sheet.R` (PR #42), 36
  assertions over `pf_adjudicate()`, `pf_candidate_frame()` and
  `pf_bmf_context()`, including Phase 4 step 1's requirement that enrichment
  reaches *every* candidate and not only the pick. It also caught a crash:
  `pf_candidate_frame()` failed with "replacement has 0 rows" on any BMF
  context lacking `org_addr_state`.
* **The verdict seam — done.** `pf_verdict_cols()`, `pf_read_verdicts()`,
  `pf_apply_verdicts()` (PR #42). `pf_apply_verdicts()` accepts nothing, which
  is §7's settled finding rather than a limitation.
* **The queue — done.** `pf_review_queue()` (PR #42), which refuses to price a
  deduped match from its own rows, because `pf_recipients()` keeps one
  representative row per identity and carries no dollar total.
* **The grading harness — done.** `R/grade.R`: `pf_grade_verdicts()`,
  `pf_grade_by()`, `pf_grade_layers()`, `pf_wilson()`, with 60 assertions.
  It takes **one** labelled round and returns the cuts, which is §3's finding
  expressed as an interface:
  - `pf_grade_by(g, "confidence")` is **T3**, and reports monotonicity as
    decreasing / increasing / neither rather than assuming it — an increasing
    result is the finding that forbids using confidence as a gate.
  - `pf_grade_by(g, "evidence_class")` is **T4**, with a `separated` attribute
    that only claims discrimination when the intervals are disjoint.
  - `pf_grade_layers()` is **T5/T6**, and **stops** unless every layer covers
    the same cases, naming what is missing from which layer. That refusal is
    §3 enforced: two packets give two denominators, and a function that
    quietly intersected would make that failure look like a working comparison.
  - `pf_grade_by(g, <flag>)` is **T8**, where `min_n` marks a cell unusable
    below 20 and the Wilson interval does the rest: 60% on n=15 is
    [36%, 80%], which is the width the note needs visible.
  - `pf_wilson()` is exported because `dev/adjudicate-03-score.R`,
    `-06-calib-score.R` and `-12-no-score.R` each defined their own.

**What the harness deliberately does not compute.** Precision on the YES mass
(T11) is not derivable from a truth table assembled out of cells the pipeline
failed on, and `pf_grade_verdicts()` says so rather than reporting a number.
T9's re-derivation and T10's pilot are measurements, not functions, and remain
undone.

**The one thing the harness changes about T1's design.** Every cut above reads
a column, so the round has to *record* it: `confidence` and `evidence_class` on
every verdict, the layer identity, the flag populations, and one case set shared
by all layers. Running T1 without those is what makes T3–T8 unanswerable, and
the function signatures are now the checklist.

## 6b. The round, designed — 2026-11-02

Measured from the two MAYBE-tier rounds already on disk
(`data-dev/ADJ-CAL-SCORED.rds` + `ADJ-CAL-TRUTH.rds`, 200 cases, three arms;
`ADJ-EXP-*`, 100 cases, two arms) rather than assumed. These are the
**unenriched** packet, so the accuracy *levels* do not transfer (§4) — the
**distributions and the directions** are what the design needs, and they do.

### 6b.1 Three findings that change what the round can and cannot ask

**(a) Confidence is monotone, in 5 of 5 arms, steeply — and T3's premise is
not supported by any data in this repository.** Accuracy by self-reported
confidence, scoreable cases, Wilson 95%:

| round / arm | high | medium | low |
|---|---|---|---|
| CAL light | 100% (n=98) | 81% (n=74) | **25%** (n=28) |
| CAL deep | 100% (n=136) | 87% (n=54) | 60% (n=10) |
| CAL search | 98% (n=166) | 64% (n=28) | **17%** (n=6) |
| EXP light | 92% (n=13) | 33% (n=12) | 14% (n=7) |
| EXP deep | 64% (n=25) | 25% (n=4) | 0% (n=3) |

In CAL light the three intervals are **disjoint** ([96,100], [71,88],
[13,43]). T3 above says "do not assume it" and cites
`dev/adjudicate-15-no-arms.R:176` for the MAYBE search arm's confidence having
*risen as accuracy fell*. That line is **prose in a NO-tier script**, not a
measurement in it, and the MAYBE search arm on disk is the steepest monotone
one of the five. Nothing here argues the sentence was never true of something;
it argues that it is unsupported for the MAYBE tier, and that **this note, the
roxygen for `pf_grade_by()` and `pf_verdict_levels()` all relayed it as
established fact.** Corrected in all three.

*Consequence:* the policy worth testing is **not** blanket auto-acceptance
(settled, 72%, §7) but **acceptance gated on high confidence**, which the prior
rounds put at 98–100% over 49–83% of cases. That is the round's primary
question, and it was being treated as an open design space rather than a
hypothesis with four supporting arms.

**(b) T4 cannot be answered as `QUOTE > NTEE > INFER`. The NTEE rung is
empty by construction.** Evidence class assigned, per arm: CAL light
QUOTE 65 / NTEE **16** / INFER 87; CAL deep 102 / **2** / 95; CAL search
98 / **1** / 95. Scaled to a 1,000-case round the NTEE cell holds ~5–80 cases
depending on arm, and at n=10 a Wilson interval is ~60 points wide. Reaching
300 NTEE verdicts in the search arm would take ~30,000 cases.

What *is* answerable is **QUOTE vs INFER**, and it is already arm-dependent:
95% vs 66% in CAL light (**disjoint**, so discrimination is real there), 96% vs
93% in CAL deep (not separable), 95% vs 85% in CAL search (marginal). So the
evidence class discriminates *on the weak arm* and not on the strong one, which
is the opposite of how an acceptance gate would be used.

*Consequence:* either drop NTEE from the schema, or **force** it — ask the
reviewer for the best class *and* whether NTEE alone would have sufficed,
turning an unbalanced free cut into a designed comparison. Do not plan a
three-way ordering.

**(c) The reviewer-assigned cells cannot be stratified in advance.** §3 says
eight tests are "free cuts of one labelling round". True for the cuts keyed on
*case* features (tier, arm pair, purpose, flags, shapes); **false for
`confidence` and `evidence_class`**, which the reviewer assigns during review.
No sampling design controls them, which is why (a) and (b) are distribution
problems rather than sample-size problems.

### 6b.2 What size buys what, computed with `pf_wilson()`

| | n=25 | n=50 | n=100 | n=150 | n=300 | n=500 |
|---|---|---|---|---|---|---|
| CI width at p=.72 | 33pt | 24pt | 17pt | 14pt | 10pt | 8pt |
| CI width at p=.95 | 19pt | 12pt | 9pt | 7pt | 5pt | 4pt |

Separating two cells (disjoint intervals, against a 0.80 reference) needs
**n ≥ 75** for a 25-point gap, **100** for 20, **150** for 15, **300** for 10.

So: a high-confidence precision claim of "≥ 95%, lower bound ≥ 90%" needs
**~150 high-confidence verdicts per arm**. At the observed 49–83% high share,
that is **250–300 cases per arm**.

### 6b.3 The design

**One round, one case set, all arms — because §3's incomparable-denominator
failure is the one this must not reproduce.** `pf_grade_layers()` now refuses a
comparison whose arms cover different cases, so the design is enforced in code.

* **Frame:** in-scope MAYBE identities from one match run, population
  fingerprinted with [pf_population_id()]. **Use the 845-identity NO tier, not
  725** (§8) if the NO tier is included.
* **Size:** 1,000 — 250–300 per arm over 4 arms, which §6b.2 says is what the
  primary question costs. Not a round number chosen first.
* **Stage it.** Stage 1 of ~400 reads the realized confidence and class
  distribution; stage 2 of ~600 tops up thin cells. Without this, (a) and (b)
  are discovered after the budget is spent.
* **Strata, all on case features so they are controllable:**
  tier · arm pair (`pass`) · restricted-gift purpose ([pf_purpose()]) ·
  margin band (`overall_margin`, `n_close`) · dollar band.
* **Oversample deliberately, because these do not arrive by chance:**
  the two T8 flags (NTEE support code on the pick with a non-support runner-up;
  the `X FOUNDATION` / `X` shape — [pf_is_arm()] and [pf_arm_core()] detect the
  second on pick vs runner-up) to **≥100 each**, and the T7
  entity-vs-fundraising shapes, which are the same population as the second
  flag.
* **Record per verdict:** [pf_verdict_cols()], plus arm, stratum, reviewer
  identity (T7 needs two reviewers and a model against itself), and the stage.
* **T2:** re-review a stratified subsample independently, reporting accuracy
  per evidence class. ~5 of 12 checks survived last time (§4), so this is a
  gate, not a formality.

### 6b.4 Status

Built and merged: the grading harness (§6a), which makes every cut above a
function call. Designed here. **Stage 1 is drawn** — §6b.5 — and **dealt to
five named labelers** — §6b.6 — and **labelled** — §6b.7. All 400 cases
carry truth. What stage 1 still lacks is the hand-labelled slice that would
turn its agreement figures into accuracy (§6b.7e).

### 6b.5 Drawn, 2026-11-02 — and what the real frame changed

`dev/ADJ-ROUND-STAGE1-20261102.log` is the full record; this is what it changes
about the design above. Stage 1 is
`data-dev/ADJ-ROUND-STAGE1.csv`: **400 cases** of the 24,107-identity MAYBE
tier of `data-dev/TRI-V2-MATCH.rds`, population **`cb3c78ff0f1a9546`**, seed
`20261102`, redrawable with `dev/draw-round-stage1.R`. $66.7M of grant dollars,
median identity $6,010.

**(a) §6b.3's strata over-partition the frame, at every scale.** The full
`tier · pass · purpose · margin · dollar` cross gives 141 cells on a
1,006-case frame and **206 on the production frame**, of which 120 would
receive less than one case at n=400. A larger frame makes it worse, not better,
because more passes exist to cross against. Stage 1 stratifies on
**`tier · pass · purpose`** — 20 cells, 16 non-empty — and the margin and
dollar bands are **recorded on every case** rather than stratified on, which is
what reading a realized distribution and topping up stage 2 actually needs.

**(b) The frame is not a `pf_match`, and the one that is cannot be
fingerprinted.** The production run is serialized as `list(status, grants)`
with no `pairs`; the only two pair-complete runs on disk carry the archived GT
schema, have no `OBJECTID`, and so draw labels that §8's 0% id agreement says
could never be re-attached. `pf_round_sample()` therefore takes a status frame
as a first-class input and **requires** the fingerprint, `require_population =
FALSE` being reserved for a dry run whose labels are thrown away.

**(c) T8's floor of 100 is right and currently unreachable.** Measured on the
1,006-case dry-run frame, `flag_arm_shape` holds **156** cases and
`flag_ntee_support` **60** — against §6b.3's floor of 100, which
`pf_round_sample()` refuses, correctly: at n=60, p=.60 the Wilson interval is
0.47–0.71. Both flags compare the **pick to the runner-up** and nothing else in
the design does, so both need a pair-complete run. **The unblocker is one
serialization** — re-save the production cascade keeping `$result` and its
`pairs` — not a change to the design. Until then T8 is stage 2's.

**(d) Stage 1 is not sized to compare passes, and two passes cannot be
compared at any size.** Proportional allocation gives `B1-token-state` 219 of
the 400 and the next pass 50, against §6b.2's 250–300 per arm. That is right
for the tier estimate and for reading the confidence and class distribution —
§6b.1c's purpose for staging — and the per-arm comparison belongs to stage 2,
with floors set from what stage 1 shows. Separately, the MAYBE tier holds
**11** `A4-dba-name` identities and **3** `D2-prefix` identities in total: no
round size buys a per-pass claim for either.

### 6b.6 Dealt, and re-dealt — 2026-11-03

`dev/ADJ-ROUND-STAGE1-DEAL-20261103.log` dealt the 400 cases to eight
labelers; `dev/ADJ-ROUND-STAGE1-REDEAL-20261103.log` re-dealt them to five.
The **draw did not change** — same 400 cases, same population
`cb3c78ff0f1a9546`, same `frame_id` `89a2a597ed0ea128`, same normalizer
`v1-5e901add4a04a5d6`. What changed is how many labelers work it and how the
blinded overlap reaches them.

**(a) The first deal could not answer the question the overlap exists for.**
k=8 at overlap 0.10 put **7, 15, 11, 10, 12, 10, 9 and 6** overlap cases on
the eight labelers, against an expectation of 10 and against
`pf_labeler_agreement()`'s `min_n` of 20. Every per-labeler cell would have
come back `usable = FALSE`, leaving only the pooled rate — n=40, ±11 points —
which is exactly where a single bad labeler is invisible. The per-labeler
figure is the one `R/shards.R`'s own header says the overlap is *for*, so the
round would have spent 440 labels and not bought it.

**(b) That was chance, not sample size.** The *primary* deal was already
round-robin within stratum and landed within one case of even. The overlap was
not dealt at all: the cases were a uniform sample of the frame and each second
shard a uniform draw from the other seven. Balanced in expectation, not
balanced. `pf_truth_shards()` now deals both halves — each shard gives up its
own share of the overlap cases, and the second copies travel on a rotation of
*lags* rather than a coin flip — so every shard gives and receives the same
number, exactly when `k` divides the overlap.

**(c) The round is now k=5 at overlap 0.15,** and the balance is exact rather
than approximate: 92 cases per labeler, 460 label-rows for 400 cases,
**24 overlap cases on every one of the five**, and all ten labeler pairs
represented at six cases each — so the agreement figure is about the round and
not about one pair. The cost of the change is **60 extra labels**, 15% on top
of the 400.

*What 24 buys, stated so nobody reads more into it later:* it clears `min_n`,
so the per-labeler cut exists. It detects a **gross** outlier — a labeler at
0.40 against a pool at 0.85 separates at this n — and not a subtle one.
§6b.2's table puts separating a 25-point degradation at n ≥ 75, which would
need 600 overlap rows on a 400-case round: no stage-1 deal buys it at five
labelers. `by_labeler` is a screen, not a quality claim.

**(d) Five labelers, all models — so the accuracy slice is still missing, and
deliberately so.** `TRUTH-LABELING-PROTOCOL.md` §6 step 4 is unchanged: until
a hand-labelled slice is scored against the labelers with
`pf_grade_verdicts()`, this round reports **agreement**, and the truth set has
an unknown error rate. Choosing five model shards defers that step rather than
removing it.

**(e) Two defects the redeal exposed, both now fixed and tested.**
`pf_write_shards()` wrote k=5 over the k=8 directory, overwrote shards 1–5 and
left `shard-06` through `shard-08` in it — files indistinguishable from work to
hand out, whose rows `pf_read_truth()` refuses only *after* a labeler has done
them. It now removes them and reports the removal. Separately, `sample(x)` on
a length-one `x` permutes `seq_len(x)` rather than `x`, and the first balanced
draft recycled one case into three shards because of it.

**(f) The roster, and the check that was documented but absent.** The five
labelers are `claude-fable-5-1/truth-01` through `-05` — five instances of one
truth-producing procedure, **not** of either graded arm's model. The arms this
round grades are `claude-haiku-5-5` (light) and `claude-opus-5-5` (deep);
truth on `claude-opus-5-5` would grade the deep arm partly against its own
model, and the shared blind spots of one model are invisible to an overlap
between two instances of it. Cost does not argue the other way: the deep arm
measured $0.033–$0.066/case (`dev/ADJ-EXP-DEEP-RUN.log`,
`dev/ADJ-CAL-DEEP-RUN.log`), so 460 label-rows is tens of dollars on either
model.

*So say what this roster measures and what it does not.* Five instances of one
procedure means `pf_labeler_agreement()` reports **run-to-run stability** — a
drifted prompt, a truncated session, a bad day. It is not a cross-model second
opinion. It is still not accuracy, by the same §6 step 4 that (d) names.

Naming the roster was verified to be a **re-stamp and not a redeal**: dealing
with and without `labelers` under seed `20261103` gives an identical
`(grant_id, shard, overlap, primary)` assignment.

And it exposed a third defect, the worst of the three because it was a claim
rather than an omission: `pf_truth_shards(labelers = )`'s roxygen has said
since it was written that *"`pf_read_truth()` enforces the `labeler` stamp
against it"*, and **that check was never in `pf_read_truth()`**. A shard
returned under the wrong name — the wrong labeler's work, or one labeler's
file reaching another — read in clean, and every per-labeler figure built on
it would have named the wrong producer. The check now exists, refuses with the
shard, the name that arrived and the name dealt, and leaves an unrostered key
reporting what arrived rather than refusing it. Three tests, including the
two-labelers-swapped-files case the overlap check cannot see, because both
files are complete and internally consistent and merely attributed to each
other.

The superseded k=8 deal is kept at
`data-dev/round-stage1-k8-superseded/` — not as a round in progress, but
because its key is now the only record of (a): the overlap is dealt rather
than sampled, so `seed 20261103, k 8, overlap 0.10` no longer reproduces it.

### 6b.7 Labelled — 2026-11-03. Stage 1 has truth, and it moves a closed number

`dev/ROUND-STAGE1-READOUT-20261103.log` is the record;
`dev/read-round-stage1.R` reproduces it. All 400 cases carry truth: shard 1
from `claude-fable-5-1` on every case, shards 2–5 from the high-only gate of
§6b.8. 460 label-rows, 446 of them `basis = web`, 60 overlap cases.

**(a) The blinded overlap is readable, and that is the redeal paying for
itself.** 56/60 = **93.3% [84.1, 97.4]** effective, and — the point of §6b.6 —
**every labeler has 24 overlap cases, so every per-labeler cell is usable**:
91.7%, 87.5%, 95.8%, 95.8%, 95.8%. Under the k=8 deal all eight cells would
have been `usable = FALSE`.

It is also **not one comparison**, and is not reported as one. Shard 1 is
all-fable and shards 2–5 are a two-model pipeline, so the 60 cases decompose:

| the two rows came from | n | agree | |
|---|---|---|---|
| fable and fable (one escalated) | 36 | 33 = 92% | usable |
| haiku and fable | 13 | 12 = 92% | n < 20 |
| haiku and haiku | 11 | 11 = 100% | n < 20 |

The first is run-to-run stability of one procedure; the others are
cross-model. Pooling them into one 93.3% would be a rate over a heterogeneous
denominator, which is why `gate-shard-truth.R` records per-row `model`
provenance.

**(b) MAYBE-tier pick precision is 48.6% [43.7, 53.5], against a published
72% [65, 78].** 189 of 389 scoreable cases (11 `UNRESOLVED` dropped, as
`pf_grade_verdicts()` drops them). On the looser denominator — only the 318
cases where an organisation was found at all — **59.4% [54.0, 64.7]**. Both
intervals are disjoint from the published one.

The published 72% is `ADJUDICATION-PLAN.md` §1: 200 hand-labelled cases of the
**unenriched** packet on a different population, so this is not a
contradiction of a like-for-like measurement. It is, though, the first
measurement of this figure on the current population, at four times the
sample, with truth produced under the protocol — and §7 lists the 72% as
settled and closed.

*What it does and does not disturb.* §7's decision — do not auto-accept MAYBE
— is made safer, not wrong. What moves is every downstream figure that prices
the MAYBE tier: the review queue's dollar coverage (T9) rests on how much of
the tier is recoverable, and half the picks being wrong is a different queue
from a quarter.

**(c) Two blocking passes behave very differently, and one barely works.**

| pass | n | right | |
|---|---|---|---|
| `A1-name-zip5` | 49 | 69% | |
| `D1-acronym` | 8 | 62% | n < 20 |
| `A3-name-dba` | 5 | 60% | n < 20 |
| `B1-token-state` | 222 | 50% | |
| `A2-name-state` | 32 | 50% | |
| `C1-name-any` | 48 | 35% | |
| **`B2-token-concat`** | **25** | **12%** | **superseded — §6b.9** |

`B2-token-concat` read as right on 3 of 25 here. **That did not hold: §6b.9
re-measured it at 28.2% on 71 cases, and the 12% was substantially a
small-sample artefact.** It is left in the table because it is what stage 1
measured and because the correction is the point — a 25-case cell with a
[4.2, 30.0] interval was never evidence for 12% specifically.
`C1-name-any` at 35% matches what the
hand read of six rejections found: two of the six were same-name-
different-state collisions, which is what matching on name alone produces.
These are the cascade's own cells, so they are a statement about the passes
rather than about the round.

**(d) A 29-point gap that is selection, not bias.** Pick precision is 69% on
rows haiku labelled and 40% on rows fable labelled, which looks like the gate
bending the figure. It is not: haiku marks `high` on the cases it finds easy,
easy cases are the ones the cascade also tends to get right, and the split was
made on haiku's confidence before any outcome was known. The check that
settles it is that **shard 1, all-fable, gives 48.9% against the round's
48.6%** — the all-fable shard and the gated shards agree on the figure. §6b.8's
38/38 is the direct evidence for the same point.

**(e) Truth here is model-produced.** Two Claude models wrote every label, and
where they agree they can be wrong together — which no figure above can see.
`TRUTH-LABELING-PROTOCOL.md` §6 step 4's hand-labelled slice remains the only
thing that converts any of this into an error rate, and it is now the single
most valuable unspent measurement in the round: a few dozen hand labels would
price all of (a) through (d).

### 6b.8 The high-only gate, and what it actually saved

Measured in `dev/SHADOW-HAIKU-SHARD01-20261103.log`: `claude-haiku-5-5` and
`claude-fable-5-1` labelling the same 92 cases of shard 1. Effective agreement
73/92 = 79.3%, and the shape rather than the number is the finding — on the 60
cases where both found an organisation they named the **same EIN 60 times out
of 60**, and no case in 92 had both resolve and disagree. 19 of 20
disagreements are haiku declining what fable settled: the known-price failure,
not the silent one. Haiku's own confidence separates them: high **38/38 = 100%
[90.8, 100]**, medium 30/33 = 90.9%, low 4/21 = 19.0%.

Hence the gate: accept haiku's `high`, escalate the rest to fable. Realised
over shards 2–5, 368 cases:

| | |
|---|---|
| haiku on all 368 | **$5.15** |
| accepted `high` | 145 (39%) |
| escalated to fable | **223 (61%)** |
| fable on the 223 | **$45.23** |
| **gated total** | **$50.38** |
| all-fable, at shard 1's $0.153/case | $56.44 |
| **saved** | **$6.06 — 11%** |

**The saving is a tenth of what the agreement figure implies, and the reason
generalises.** Escalated cases cost **$0.205/case** against $0.153 for an
average case, because the cases haiku cannot settle are the hard ones and hard
cases are where fable spends its searches. So the gate's economics are not
`(1 − high_rate) × cost`; they are `(1 − high_rate) × cost_of_the_hard_cases`,
and that is strictly worse. Any cheap-model gate on this task should be costed
that way.

*For stage 2.* The looser high+medium gate would escalate ~23% rather than
61%, and on these numbers lands near 50% saving rather than the 69% a flat
per-case price suggested. That remains the live option if stage 2's ~600 cases
need to be cheaper, at the cost of ~9% disagreement entering the truth set.

### 6b.9 The B2-token-concat top-up — 2026-11-03. 12% did not hold

`dev/B2-TOPUP-RUN-20261103.log` and `dev/B2-TOPUP-READOUT-20261103.log` are the
record; `dev/draw-b2-topup.R` and `dev/read-b2-topup.R` reproduce it.

§6b.7c put this pass at 3 of 25. 50 more cases were drawn from the same frame
and population, disjoint from stage 1's 26 by construction, and labelled by the
same model under the same protocol — $9.78 of tokens plus 295 web searches, at
$0.196/case, which is the hard-case rate §6b.8 predicts and not the round's
$0.153 average.

| | n | right | |
|---|---|---|---|
| stage 1 | 25 | 3 = **12.0%** | [4.2, 30.0] |
| top-up | 46 | 17 = **37.0%** | [24.5, 51.4] |
| **pooled** | **71** | **20 = 28.2%** | **[19.0, 39.5]** |

**The 12% was substantially a small-sample artefact.** The two intervals
overlap only over 24.5–30.0, and the pooled estimate is more than twice the
stage-1 figure. What a 25-case cell with a 26-point interval supported was
"this pass is bad", never "this pass is right one time in eight".

**What survives, and it is the part that matters.** Pooled B2 at [19.0, 39.5]
is **disjoint** from `B1-token-state` at 50.0% [43.5, 56.5], so the difference
between the two passes is real at 95% — which is what §6b.2 says 71 cases buys
against a 22-point gap. B2 is roughly *half* as precise as B1, not a *quarter*
as precise.

It is also not one stratum: 25% on `purpose` (n=40) against 32% on `bare`
(n=31).

*Why it still argues against the pass rather than for better scoring.* Of the
51 wrong scoreable cases, **17 are `NO_ORG_*`** — no exempt organisation exists
to match at all, so the cascade produced a false positive. A third of this
pass's errors are not "picked the wrong one of two real candidates" and cannot
be scored away; they are the key matching things that are not organisations.
The remaining 34 are real-organisation-wrong-EIN.

*What this does not fix.* Truth is still model-produced, so this figure
inherits whatever error rate the hand slice finds in stage 1's labels. More
cases narrowed the interval; they did not touch the accuracy.

*The lesson for stage 2's floors.* Every other sub-20 cell in §6b.7c —
`D1-acronym` at n=8, `A3-name-dba` at n=5 — is now a cell whose point estimate
has been shown capable of moving by 25 points. §6b.3's floors exist for this
reason, and this is the measured demonstration.

## 7. What needs no further test

* **Auto-accepting MAYBE.** Settled at 72% precision (95% CI 65–78%) on 200
  fresh cases against a first estimate of 18/18. Closed -- and the decision is
  now *safer* than when it was taken: §6b.7 measures **48.6% [43.7, 53.5]** on
  the current population over 389 scoreable cases, with truth produced under
  the protocol. The 72% stands as what it always was, a figure on the
  unenriched packet and another population, and should not be quoted for this
  one.
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
| 24,107 MAYBE identities; `cb3c78ff0f1a9546` | `dev/ADJ-ROUND-STAGE1-20261102.log` §1, §6 |
| 206 cells, 120 starved at n=400 | `dev/ADJ-ROUND-STAGE1-20261102.log` §3 |
| flags at 156 and 60 on the dry-run frame | `dev/ADJ-ROUND-STAGE1-20261102.log` §4 |
| `A4-dba-name` 11, `D2-prefix` 3 | `dev/ADJ-ROUND-STAGE1-20261102.log` §6 |
| deep arm $0.033-$0.066/case | `dev/ADJ-EXP-DEEP-RUN.log`, `dev/ADJ-CAL-DEEP-RUN.log` |
| overlap 7/15 on eight labelers; 24 on five | `dev/ADJ-ROUND-STAGE1-DEAL-20261103.log`, `-REDEAL-20261103.log` |
| B2 pooled 20/71 = 28.2%; stage 1's 12% did not hold | `dev/B2-TOPUP-READOUT-20261103.log` |
| B2 top-up $9.78 + 295 searches, $0.196/case | `dev/B2-TOPUP-RUN-20261103.log` |

See also `dev/PLAUSIBLE-WRONG-NUMBERS.md` for the defect class §3 refers to,
and `dev/METRIC-SHAPES.md` for the practice that a metric which cannot come out
wrong is not evidence.
