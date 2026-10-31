# Two-tier LLM adjudication of the MAYBE tier

An experiment, not a product. It asks two questions about the 1,044 MAYBE
identities in `BASELINE-2026-10C`'s augmented arm, on a batch of 100:

1. **How many would clear to YES on inspection?**
2. **How reliable is a cheap LLM adjudicator**, measured against a
   high-reasoning model with web search and against hand-adjudicated truth?

Question 2 is the one that decides whether any of this scales. A frontier model
with search, run on 1,044 cases, is affordable once; run on the 50,000-case
population it is not. If the cheap arm is trustworthy on an identifiable
subset, the tier becomes tractable. If it is not, this is the measurement that
says so before the money is spent.

## Why the MAYBE tier and not something else

`dev/BASELINE-2026-10C/MANIFEST.md`, augmented arm:

| | identities | YES | MAYBE | NO | clear rate |
|---|---:|---:|---:|---:|---:|
| augmented | 4,748 | 2,979 | 1,044 | 725 | 62.74% |

YES+MAYBE is 84.73%, and the manifest is explicit that this **is not a clear
rate**: there is no safe automatic acceptance of MAYBE. The gap between 62.74%
and 84.73% is 22 points of grant volume sitting in a tier nobody has measured
the recoverable share of. That is what this experiment measures.

The figures above are 10C. A 10B-era note may quote 2,982 / 1,041 / 62.81% —
four identities moved across the normalizer change, in both directions, and
nothing here depends on which of the two is used.

## Why it is not simply "run the LLM and count the YESes"

Three things are already known about this tier, and each one shapes the design.

**Auto-acceptance has been tried and it failed.** `dev/ADJUDICATION-PLAN.md`
section 1: a `ZIP5 agrees AND margin >= 0.05` rule measured 100% precise on 18
cases, then **72%** on 200 fresh ones (95% CI 65–78%). No tightening rescued
it; the best variants reached ~80% on ~20 cases, an interval consistent with
56%. The structural reason is that 79% of the firing cases were
`TOKEN_OVERLAP` matches — the population npmatch caps below YES *on purpose*,
because containment cannot separate a parent from its subsidiary, auxiliary or
chapter. Any result here that looks that good should be assumed to be the same
mistake until the interval says otherwise. Hence Wilson intervals on every
rate in the output, and no point estimate quoted without one.

**`NONE` is a common correct answer.** 24 of 82 hard cases in the labelled set
had no correct candidate in the packet at all. A reviewer that cannot answer
`NONE`, or that is scored as if an answer always exists, manufactures exactly
those 24 false positives. This is why `truth_in_packet` exists and why the
scoring stage treats "a human found the organisation" and "the organisation is
among the five candidates" as different facts.

**Candidate-only review does not survive verification.** Plan section 7 step 7:
candidate-only review survived independent checking on only ~5 of 12 checks,
and "no accuracy claim should be made without this step." The deep arm *is*
that step. It is not a luxury tier; it is the only arm that can establish
whether the recipient is in the packet at all.

## Design

```
stage 00   re-run the match, keep `pairs`, gate against the frozen baseline
           |
           +-- sample 100 MAYBEs in two strata, shuffle, freeze the packet
                   |
      +------------+------------+
      |                         |
stage 01  LIGHT              stage 02  DEEP
  claude-haiku-5-5             claude-opus-5-5, effort high
  packet only, no tools        + server-side web_search
  structured JSON output       + strict submit_verdict tool
      |                         |
      +------------+------------+
                   |
             stage 03  score
```

### The sample is two strata and they do different jobs

| | n | drawn how | what it measures |
|---|---:|---|---|
| **A** estimation | 68 | simple random from the 1,012 MAYBEs with no prior adjudication | the clearance rate, **unbiased**, with a usable CI |
| **B** calibration | 32 | every MAYBE that `PF-TRUTH-V2.csv` already adjudicates by hand | **absolute accuracy** of both arms against a human verdict |

`PF-TRUTH-V2.csv` carries population id `0b5126ef02f2a8b0`, which is this
benchmark's population, so its `grant_id`s key correctly. 32 of its 172 rows
are MAYBE in the augmented arm; 27 name a `correct_ein`.

**As built (seed 20261031), the calibration stratum resolves to:**

| | n | correct answer |
|---|---:|---|
| `ORG_FOUND`, EIN **is** among the 5 candidates | 18 | `MATCH` on that EIN |
| `ORG_FOUND`, EIN is **not** among them | 9 | `NONE` |
| `UNRESOLVED` | 5 | excluded — no target |

So **27 scorable cases, 18 of them answerable from the packet and 9 not.**
That 9 is the load-bearing group: it is where a reviewer that never says
`NONE` gets caught, and it is a third of the scorable set, close to the 29%
the hand-adjudicated reference distribution predicts. There are no `NO_ORG_*`
rows in the MAYBE overlap at all, so every `NONE` target here is the harder
kind — a real organisation that the packet simply failed to surface.

Stratum B is **not random** — earlier audits selected those cases — so it must
never enter the clearance-rate numerator, and stage 03 keeps it out. Its job is
different and it is the more important of the two: inter-model agreement alone
cannot distinguish "both arms are right" from "both arms are wrong the same
way", and 32 known answers can.

### Stratum A came out tie-heavy, and the estimate is corrected for it

The realised draw is **75.0% ties (51/68) against the tier's 59.1%** —
`binom.test` p = 0.009, so about a 1-in-110 draw rather than a bug in the
sampler. Ties are the hard cases (npmatch could not separate the top two
candidates at all), so the raw clearance rate is biased **downward**; on the
fixture that imbalance moved the headline figure by 5–8 points.

Stage 03 therefore **post-stratifies on `tie`**: it estimates clearance within
each tie class and reweights by the tier's own 59.1 / 40.9 split, which is
known for all 1,044 identities. Both the raw and the adjusted rate are
printed, the adjusted one carries the stratified variance
(`sum(W² · p(1−p)/n)`, so a thin stratum widens the interval rather than
narrowing it), and the projections are labelled `[tie-adj]` or `[raw]`.

Re-drawing until a sample looked balanced was the alternative and is worse:
"draw until it passes a balance test" is itself a selection rule, and the
intervals afterwards would not mean what they say. Post-stratification removes
the imbalance's effect without that problem. The seed is unchanged, so the
sample is still reproducible.

Other margins came out close to the tier (`views_agree` 22.1% vs 25.1%,
B-token passes 42.6% vs 42.5%); `tie` is the one that moved, and it is the one
adjusted.

Both strata are shuffled into one batch under `batch_order`, truth lives in a
separate file, and neither tier is told that strata exist. The instruction
file's calibration section depends on the reviewer being unable to tell.

### Both tiers read the same instructions and the same case text

`dev/LLM-REVIEW-INSTRUCTIONS.md` is read from disk by both stages, and
`adj_render_case()` in `dev/adjudicate-lib.R` is called by both. The deep arm's
prompt is the light arm's prompt **plus** a search mandate, and nothing else
differs. This is deliberate: if each tier formatted its own prompt, every
disagreement would be confounded by wording and question 2 would be
unanswerable.

The packet carries, for **every** candidate and not just the top pick, the
NTEEv2 description text and the Form 990 Part III mission and program
descriptions. On 56 hard cases that addition resolved 45
(`dev/ENRICHMENT-FINDINGS.md`); without it the experiment measures a different
and much weaker reviewer. Roughly 43% of candidates have this text, and where
it is absent the field is empty — which is not evidence either way, and the
packet says so rather than omitting the field.

### Why a re-run is needed at all

`build-baseline.R` strips the `pairs` attribute from the saved benchmark — it
is 194 MB of a 198 MB object. Adjudication needs the **losers**, so stage 00
re-runs the match with `pairs` retained, using byte-identical arguments, and
**stops** if any identity's tier disagrees with the frozen baseline. A packet
drawn from a different MAYBE set would answer a different question.

## What the output says, and what it is worth

Stage 03 writes `dev/ADJ-EXP-RESULTS.log` in four parts.

**(a) Absolute accuracy on the 32, and it gates everything else.** Both arms
are scored against the human verdict, strictly (right EIN) and leniently (right
EIN even if hedged), with the confident-and-wrong count called out separately
because that is the error that is never reviewed again. If the deep arm is
under 75% here, the script says the gate failed and reports the rest as
*agreement between two models*, not as the light arm's reliability — a light
case matching a deep arm that is often wrong is not evidence of anything.

**(b) Agreement on all 100.** Verdict concordance, exact-EIN concordance among
cases where both named one, and Cohen's kappa. Kappa is there because two
reviewers who both favour `MATCH` agree often by construction; raw concordance
on this tier is close to meaningless on its own. The cell where both say
`MATCH` and name **different** EINs is reported separately — verdict
concordance alone would score those as agreement.

**(c) Where the light arm fails.** Accuracy and agreement sliced by the light
arm's own stated confidence and evidence class, and by tie, margin band and
pass. This is the only actionable section: if agreement is flat across the
light arm's confidence levels, its confidence signal cannot route anything and
a cheap pass is untrustworthy everywhere. If it rises, the high-confidence
subset is a candidate for acceptance and the rest for escalation — which is the
economics the whole experiment is about.

**(d) Twelve worked disagreements**, confirmed-by-search first, with the truth
where it is known. Error *shapes* on this tier have been more useful than error
rates every previous time (plan section 1 found three recurring ones), and a
rate with no examples has not been enough to act on.

Clearance is reported at three thresholds — any `MATCH`, `MATCH` at medium+
confidence, and `MATCH` the deep arm externally **confirmed** — because "clears
to YES" is a policy choice and not a measurement. Each is projected onto the
1,044-case tier and onto the benchmark's clear rate, with the interval carried
through.

### What it cannot establish

* **It is not precision over the cleared cases.** The deep arm is a model. Its
  own error rate on the 32 known answers is the honest discount on every
  clearance figure, and the log applies it rather than leaving it implied.
* **32 calibration cases is a small denominator.** A 75%-vs-85% difference
  between the arms will not be separable at that n. The intervals will say so.
* **It says nothing about the YES mass.** Precision over the 62.74% is still
  unmeasured and needs its own stratified sample (`MANIFEST.md`, "What this
  baseline does NOT establish").
* **One run is one draw.** Nothing here is deterministic — `temperature` cannot
  be set at all on API version 2026-10-21, where it returns a 400 on every
  model. Run-to-run variance is measured by repeating a stage under
  `PF_ADJ_TAG`, not assumed away.
* **The 68-case estimate is a rate, not a list.** It projects how much of the
  tier is recoverable. It does not adjudicate the other 944.

## Running it

Needs `ANTHROPIC_API_KEY` in `C:\Users\<user>\Documents\.Renviron` (the file
that already holds `OPENAI_API_KEY`), as a single `ANTHROPIC_API_KEY=sk-ant-...`
line. `Rscript` reads `.Renviron` at startup, so an `export` in the calling
shell does **not** reach it.

> **The `HOME` trap, which wasted an hour.** `R` resolves `.Renviron` from
> `HOME`, and `HOME` differs by shell on Windows. Launched from **PowerShell**,
> R resolves it to `…/Documents` and reads the file. Launched from **Git Bash**,
> it resolves to the POSIX-style home, finds no `.Renviron` at all, and reports
> *every* key as unset — including ones that were already working. That is
> indistinguishable from a missing key and it produced a confident wrong
> diagnosis once.
>
> `adj_key()` now defends against it: if the variable is unset it calls
> `readRenviron()` on each candidate path before giving up, and says which file
> it recovered the key from. It also **rejects placeholder values** by name
> (`PASTE…`, `REPLACE…`, a literal `sk-ant-...`), because a placeholder that
> reaches the API 401s on all 100 cases and reads like an auth outage.

### An API key is not the only option

`adj_credential()` accepts either of two credentials and sets the right headers
for each — they are **not** interchangeable, which is the usual way this is got
wrong:

| credential | headers |
|---|---|
| API key | `x-api-key: sk-ant-...` |
| `ant auth login` profile | `Authorization: Bearer <short-lived token>` **and** `anthropic-beta: oauth-2025-04-20` |

The API key wins when both are present, matching the official SDKs' own
resolution order. The OAuth token is fetched per request rather than cached,
since it is short-lived and `ant` refreshes it — so a long batch keeps working.
The `oauth-2025-04-20` beta header is mandatory and is appended to, never
overwritten by, any other beta the request needs.

The OAuth route needs the CLI (`npm install -g @anthropic-ai/ant`, then
`ant auth login`). On this machine neither `ant` nor `npm` is installed, so the
API key is the shorter path here; the OAuth path is wired and header-tested
either way.

```sh
Rscript dev/adjudicate-preflight.R                  # 4 live checks, <1 cent
PFMATCH_DIR=. Rscript dev/adjudicate-00-packet.R    # ~34 min, once
PFMATCH_DIR=. Rscript dev/adjudicate-00b-patch-fdn.R  # only for a pre-fix packet
PF_ADJ_LIMIT=3 Rscript dev/adjudicate-01-light.R    # smoke test, cents
PF_ADJ_LIMIT=2 Rscript dev/adjudicate-02-deep.R     # smoke test
Rscript dev/adjudicate-01-light.R                   # the batch of 100
Rscript dev/adjudicate-02-deep.R
Rscript dev/adjudicate-03-score.R
```

Run the preflight first. It makes one real request per shape — credentials,
the light arm's structured output, the deep arm's `web_search` + strict tool,
and two concurrent requests — because each of those has a failure mode that is
silent or misleading when first hit inside a 100-case parallel batch, and by
then the cost is spent either way. It exits non-zero if any shape is rejected.

Stages 01–03 read only the frozen packet, so they are cheap to re-run and
stage 00 never needs repeating.

### Knobs

| variable | default | what it does |
|---|---|---|
| `PF_ADJ_N` / `PF_ADJ_NTRUTH` | 100 / 32 | batch size and calibration stratum |
| `PF_ADJ_SEED` | 20261031 | the sample draw |
| `PF_ADJ_K` | 5 | candidates per case, as shipped |
| `PF_ADJ_LIMIT` | 0 | first N cases only — use before any full run |
| `PF_ADJ_TAG` | "" | suffix for the output files; a second run for variance |
| `PF_ADJ_WORKERS` | 6 / 4 | concurrent requests |
| `PF_ADJ_EFFORT_LIGHT` | medium | light-arm effort |
| `PF_ADJ_EFFORT_DEEP` | high | deep-arm effort (`medium` is the model default) |
| `PF_ADJ_MAXSEARCH` | 6 | `max_uses` on the web_search tool |
| `PF_ADJ_NOSEARCH` | unset | ablation: deep model, no web. Isolates *search* from *model* |
| `PF_ADJ_ROUNDS` | 4 | `pause_turn` continuations before giving up |

`PF_ADJ_NOSEARCH=1 PF_ADJ_TAG=-nosearch` is worth running once. Comparing it
with the search arm separates how much of the deep arm's advantage is the
bigger model and how much is the web — which the two-arm design on its own
cannot distinguish, and which decides whether a mid-tier model without search
would do.

### Cost

Light arm: ~$0.01–0.03 for 100 cases, with the instruction prefix cached across
the batch. Deep arm: a few dollars in tokens for 100, **plus** per-search
billing that the log reports as a search count rather than folding into a
dollar figure it would understate. Both stages print a per-case cost and a
projection to all 1,044.

## Results, 2026-10-31

Full output in `dev/ADJ-EXP-RESULTS.log`. Light `claude-haiku-5-5` at effort
medium; deep `claude-opus-5-5` at effort high with `web_search_20260209`,
`max_uses` 12. 100/100 verdicts on both arms, no API failures, no unparsed
responses, no paused turns. Light 52 s and **$0.067**; deep 353 s, 220
searches (2.2/case), **$4.09** in tokens plus per-search billing. Both figures
include cache traffic: `usage.input_tokens` excludes cached tokens, so an
earlier version of `adj_cost()` that charged only input+output understated the
light arm by 8% and the deep arm by 25% (4.08M cache-read tokens against 298K
billed input).

### The gate: absolute accuracy on the 27 hand-adjudicated cases

| | strict (CORRECT) | right EIN even if hedged | confident-and-wrong |
|---|---|---|---|
| light | 22/27 = **81.5%** (CI 63.3–91.8) | 24/27 = 88.9% | **0/27** |
| deep | 25/27 = **92.6%** (CI 76.6–97.9) | 25/27 = 92.6% | 1/27 |

Gate met, so the deep arm is usable as a reference standard for the other 68 —
carrying a ~7% error rate that every figure below inherits. Deep beats light by
11.1 points, on a denominator where that is 3 cases: the intervals overlap
heavily and the ordering is the claim, not the gap.

### Q1 — clearance

The deep arm clears **47 of 68** stratum-A cases to MATCH; tie-adjusted
**70.7%** (CI 59.4–81.9). Projected onto the tier: **738 of 1,044 cases**
(CI 620–855), taking the benchmark from 62.74% to **78.28%**, **+15.5 points**
(CI +13.1 to +18.0).

Three things make that figure more solid than the auto-accept rule that died at
72%:

* **Confidence costs nothing here.** All 47 MATCHes are medium or high — the
  deep arm never returned a low-confidence MATCH — so "any MATCH" and "MATCH at
  medium+" are the same 47 cases. Requiring external confirmation too only
  drops it to 46.
* **The NONEs are active, not lazy.** 13 of 18 are `CONTRADICTED`: search
  established the recipient and showed its EIN is *not* among the candidates.
  That is the ceiling asserting itself, not a reviewer giving up.
* **The tie adjustment barely moved it** (+1.6 pt), because clearance turned out
  similar across tie classes (66.7% tied vs 76.5% untied). The correction was
  still right to apply — that it was small is a result, not a reason to skip it.

### Q2 — reliability, and the routing policy that follows

Raw verdict agreement is 77%, but chance agreement is 46.6%, so **Cohen's
kappa is 0.570 — "moderate"**. Where both named an EIN they agreed on *which*
89.4% of the time; 7 cases agreed on MATCH while naming different EINs, which
verdict concordance alone would have scored as agreement.

The light arm is the **more conservative** of the two (MATCH 55% vs 70%), and
its errors run that way: 7 cases where it declined and the deep arm matched,
against only 2 where it matched and the deep arm declined.

Its stated confidence orders its own accuracy almost perfectly:

| light confidence | n | agreement with deep | accuracy on the 27 |
|---|---:|---|---|
| high | 35 | **97.1%** | **12/12 = 100%** |
| medium | 47 | 83.0% | 10/11 = 90.9% |
| low | 18 | **22.2%** | **0/4 = 0%** |

Evidence class orders it too (QUOTE 93.3% agreement, INFER 71.4%). Two
independent self-reported signals both tracking accuracy is harder to get by
chance than one, and it converts directly into a cascade:

| policy | escalated | cost for 1,044 | accuracy on the 27 |
|---|---:|---:|---|
| light only | 0% | $0.70 | 81.5% |
| **escalate `low`** | **18%** | **$8.39** | **96.3%** (26/27) |
| escalate low + INFER | 47% | $20.77 | 96.3% |
| escalate low + medium | 65% | $28.46 | 92.6% |
| deep only | 100% | $43.41 | 92.6% |

**Escalating only the light arm's low-confidence 18% reaches deep-arm accuracy
for a fifth of the cost.** It scores one case higher than deep-only, which is
not a real difference at n=27 — the honest claim is parity, not superiority.
That the cheap arm has **zero** confident-and-wrong verdicts is what makes the
policy safe: its failures announce themselves as low confidence, which is
exactly what the ZIP5+margin rule could not do.

### Scaling to the full corpus

The 100-case figures are only interesting if they survive multiplication. Three
numbers decide it, and two of them are already measured elsewhere in this repo.

**Rows.** `dev/EFILEPF-DEDUP.log`: 17,560,767 grant rows become **17,253,199**
after `pf_efilepf_dedup()` removes amended-return duplicates.

**Unique identities.** This is the number that makes the job tractable, and it
is *measured*, not guessed. `dev/FULL-01-PREPARE.log`, settled 2026-08-22:
12,559,051 grants → 12,404,667 in scope (98.8%) → **3,337,585 in-scope
identities, 3.72x collapse**. Carried to the v2 corpus:

| | |
|---|---:|
| rows | 17,253,199 |
| in scope at 98.8% | 17,041,111 |
| identities at the measured 3.72x | **~4,585,000** |

An earlier estimate of 1.8x — extrapolated from a 100k sample in
`dev/measure-dedup.R` — would give 9.47M and is superseded;
`CODE-AUDIT.md` §6 notes the full run came in "far above" it. The direction of
that error matters: collapse *rises* with corpus size, because more rows mean
more repeated names (the Salvation Army appears 28,096 times). So 3.72x
measured on 12.56M is a **floor** for a 17.25M corpus, and ~4.59M identities is
an over-estimate. Good: the cost projection errs high.

**MAYBE share.** 1,044 of 4,748 identities in 10C's augmented arm = **22.0%**;
`ADJUDICATION-PLAN.md` quotes 20.1% of grants. At 22% of 4.59M that is
**~1.01M MAYBE identities** — three orders of magnitude above this experiment's
100, and a thousand times the 1,044 in the benchmark.

**What it costs.** At the corrected $0.000674/case for Haiku:

| scope | n | Haiku |
|---|---:|---:|
| naive, every grant row | 17,253,199 | $11,635 |
| every unique identity | 4,585,061 | $3,092 |
| **the MAYBE tier only** | **1,008,713** | **$680** |
| same, Batch API at 50% | 1,008,713 | **$340** |

The dedup collapse is worth more than any model choice here: it takes the bill
from $11,635 to $3,092 before a single prompt changes, and adjudicating only
the MAYBE tier takes it to $680. Running the cheap arm over the whole tier is a
rounding error against the cost of the match itself (`SHARD-AND-COLLAPSE-FINDINGS.md`
§3 budgets 401 h of compute for one shard of 3.34M identities).

The cascade is where the real money is, and it is still affordable:

| policy | n escalated | cost |
|---|---:|---:|
| Haiku on all 1.01M MAYBEs | — | $680 |
| + Opus on the 18% it flags low-confidence | 181,568 | $7,427 |
| **cascade total** | | **$8,107** (**$4,054** batched) |
| Opus on every MAYBE, for contrast | 1,008,713 | $41,261 |

**~$8K against ~$41K**, for parity on the 27 known answers. Batched, ~$4K.

Three things that figure does **not** include, all pushing up:

* **Web search is billed per use**, at 2.2/case measured. The 18% escalation is
  ~399,000 searches, and that is a separate line nobody should discover later.
* **Rate limits, not price, are the binding constraint at 1M calls.** This run
  did 100 light calls in 52 s at 6 workers. 1.01M at that rate is ~150 h of
  wall clock on one stream, which is why the Batch API is the right surface
  here — the 50% discount is almost incidental next to not managing 429s.
* **The 22% MAYBE share is measured on a 4,748-identity sample** of one
  population. It is the least certain of the three inputs, and the whole
  projection is linear in it.

### What the disagreements were actually about

Nearly every one is the light arm declining at low confidence on something only
the open web could settle, and the deep arm settling it:

* `DISABLED AMERICAN VETERANS` — the filed Cold Spring KY address *was* DAV's
  national HQ until it moved; DAV's own donate page states the EIN.
* `CISE` — the 2016 grant **predates CISE's own exemption** (Sept 2017), so in
  2016 it was an Archdiocese of Cincinnati program. A temporal fact no packet
  field carries.
* `DIOCESE OF FALL RIVER` — the civil corporation is "Roman Catholic Bishop of
  Fall River", which is the name candidate 5 carries.
* `THE SALVATION ARMY` — the Golden State Division's gift page publishes the
  Western Territory tax ID.
* `SOIL` — a bare acronym whose DBA expands to "Sustainable Organic Integrated
  Livelihoods".

These are the cases that justify the search arm existing. None is resolvable
from five BMF rows, and the light arm was right to be unsure rather than guess.

### Two defects this run exposed in the harness itself

* **The packet was hiding its most discriminating field.**
  `CAND_org_name_display` was in the data but not in the prompt. Two candidates
  both matched as "Wake Forest University" are in fact **Mortar Board** and
  **Psi Chi The International Honor Society In Psychology**. Now rendered
  wherever it differs from the matched name — **61 of 100 cases**. Everything
  above was measured *with* the fix.
* **`max_uses` 6 was binding.** On `G002887` the model used all six and said
  "I couldn't get the sort names ... because I hit the search limit." Raised to
  12; actual use settled at 2.2/case, so the cap is no longer the constraint.

### What this still does not establish

Everything in "What it cannot establish" above stands. In particular the 81.5%
and 92.6% are accuracy on **previously-audited** cases, which is why clearance
is estimated from stratum A instead; and `G002887` is a reminder that for 7 of
100 cases the close band holds more candidates than the packet's `k = 5` shows
(41, in that case), so a `NONE` there may mean "not in the five" rather than
"not in the BMF".

## The packet as built (2026-10-31, seed 20261031)

Stage 00 ran in 2,045 s and the determinism gate **passed**: 4,748 identities,
every tier identical to `BASELINE-2026-10C` (YES 2,979 / MAYBE 1,044 / NO 725).

* **479 candidate rows over 100 cases** — 90 cases have the full 5 candidates,
  10 have fewer (one has a single candidate).
* **990 text coverage is 36.5% of candidate rows** (mission), 30.9% (programs).
  Higher on the top pick, 54%, than on ranks 2–5, ~31% — which matters, because
  it means the *competitors* are the ones more often described only by NTEE
  code. **13 of 100 cases have no 990 text on any candidate**; those are the
  cases where the enrichment that resolved 45 of 56 hard cases simply is not
  available, and stage 03 can be sliced on it.
* **Prompt size**: case text runs 2,414–15,100 characters (median 5,023); the
  instruction prefix is 10,281 characters, ~2,700 tokens, cached after the
  first call. Estimated input for 100 light calls: ~412K tokens uncached,
  ~144K with caching.
* **Foundation name** needed the `00b` patch — `pf_status()` reads `FILERNAME1`,
  which the efv2 files do not have (they use `ORG_NAME_L1/L2`), so it was NA on
  all 100. Now populated on 100 of 100; the foundation's state and NTEE were
  already present on 100 of 100.

A representative case is `G000083`: filed `SAN FRANCISCO OPERA ASSOCIATION`,
SF CA 94102, on an employee matching gift from the Gates Foundation. Candidate
1 is an exact name and ZIP match at score 0.98, `name_sim` 1.0, NTEE `A6A
Opera`. It is in MAYBE anyway, because `SAN FRANCISCO OPERA GUILD` sits at the
same ZIP and npmatch will not separate an organisation from its own auxiliary
on containment. That is the reference-side-competition hypothesis in one case,
and the kind this experiment exists to count.

## Files

| file | role |
|---|---|
| `dev/adjudicate-preflight.R` | 4 live checks on credentials and both request shapes |
| `dev/adjudicate-00-packet.R` | re-run, gate, sample, enrich, freeze |
| `dev/adjudicate-00b-patch-fdn.R` | one-off: backfills the foundation name into a packet built before that fix |
| `dev/adjudicate-lib.R` | Messages API client; the **shared** case renderer and verdict schema |
| `dev/adjudicate-01-light.R` | tier 1 |
| `dev/adjudicate-02-deep.R` | tier 2 |
| `dev/adjudicate-03-score.R` | the two answers |
| `data-dev/ADJ-EXP-PACKET.rds` | candidate-level packet, one row per (grant, candidate) |
| `data-dev/ADJ-EXP-CASES.rds` | case-level, with stratum and `batch_order` |
| `data-dev/ADJ-EXP-TRUTH.rds` | stratum B truth. Read by stage 03 only, never by a tier |
| `data-dev/ADJ-EXP-SCORED.rds` | every case with both verdicts and its grade |
| `dev/ADJ-EXP-RESULTS.log` | the report |

There is no API plumbing anywhere else in this repository; `adjudicate-lib.R`
is the first. Earlier "LLM review" on this project was done by a model reading
packets in a session, which is why no cost or agreement figure exists for it
and why this experiment had to be built before the question could be answered.
