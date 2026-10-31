# What is actually in the NO tier

An LLM-with-search investigation of 100 identities drawn from the **725 NO
identities** of `dev/BASELINE-2026-10C` augmented. Run 2026-10-31. Scripts
`dev/adjudicate-1*.R`, instructions `dev/LLM-NO-INSTRUCTIONS.md`, results in
`dev/NO-EXP-*.log`.

This is the third experiment in the adjudication series and the first to look
at the tier the cascade rejects outright rather than the tier it cannot decide.

| | asks | tier | n |
|---|---|---|---:|
| `dev/ADJUDICATION-EXPERIMENT.md` | which of five candidates is right | MAYBE, 1,044 | 100 + 200 |
| `vignettes/adjudicating-maybe.Rmd` | which adjudication tier to buy | MAYBE, 1,044 | 227 |
| this | does the organisation exist in the BMF at all | **NO, 725** | 100 |

## Why this is a different question, and why there is only one arm

The MAYBE experiment ran three arms — a cheap model, an expensive one, and the
expensive one with web search — because all three could answer its question.
The candidate set contained the correct EIN 71% of the time, so a reviewer
confined to the packet had something real to decide, and the interesting result
was that the cheap arm got most of the way there for 1/44 of the cost.

Here it cannot. A NO case is one where the cascade found nothing worth
offering: either no blocking pass produced any record, or the best record
scored below the floor for review. **When there is an answer it is outside the
packet 100% of the time.** A model with no search can only report that the
filed name does not resemble the records that were already rejected, which is
what the cascade said. So there is one arm, it has search, and no cost
comparison is offered because there is no cheaper strategy that answers the
question.

That is a result in itself: the MAYBE tier supports a cost/quality frontier and
the NO tier does not.

## What the model decides and what the pipeline decides

The division is deliberate and it is the methodological core of this run.

**The model has no access to the reference and is told so.** It answers only
questions that require knowledge of the world:

- who is this payee, by name
- what is its EIN, *from a source that states it*
- what kind of entity is it (`entity_class`, 11 values)
- should an exempt-organisation record exist at all (`bmf_expectation`)
- if not, why not (`outside_reason`, 8 values)
- if so, why did the cascade miss it (`miss_hypothesis`, 10 values)

**The pipeline answers set membership by exact lookup.** Is the reported EIN in
the reference? Was it ever offered to the scorer? What score did it get?

`dev/NO-RESIDUAL-AUDIT.md` is explicit that its one unambiguous result was the
mechanical one — "it is a mechanical lookup" — while its softer findings carried
"a few points of slack" from a single adjudicator with no blind second pass.
Asking the model only what needs world knowledge, and reserving set membership
for code, keeps the load-bearing number out of the model's hands entirely.

## The circularity guard

This is the one design detail that decides whether the headline number means
anything.

A rejected near-miss row is shown to the reviewer, and it is shown deliberately:
the prior audit found that in 18 of 25 recoverable cases the correct record had
*already been offered* and merely scored too low, so hiding the near-misses
would hide the dominant mechanism. But an EIN read off such a row **is in the
reference by construction** — it is there because the blocker pulled it out of
the reference. Counting that as evidence that "the reference covers this tier"
is circular. The prior audit excluded four such EINs by hand for exactly this
reason.

So every verdict records `ein_source`:

- `WEB` — an outside source stated the EIN
- `CANDIDATE` — read off a rejected near-miss row
- `NONE` — no EIN established

The headline recoverability rate and the reference-coverage test are computed on
`WEB` only. The `CANDIDATE` cases are reported beside them, labelled, because
they are a real recovery route — just not evidence about coverage.

## Which NO, and why that one

`BASELINE-2026-10C` augmented leaves **725 NO of 4,748 identities (15.27%)**.
That is the tier sampled, because it is the tier the published match rate is
computed against: 2,979 YES + 1,044 MAYBE + 725 NO = 4,748. A recovery from
this tier adds to the same numerator a MAYBE clearance does, so the three
experiments compose.

`dev/NO-RESIDUAL-AUDIT.md` sampled a **different** population — the 592
identities that are NO under *both* references — and its figures are therefore
not interchangeable with these. It is the prior here, not the comparison:

| prior audit, 100 cases of 592 | n |
|---|---:|
| recoverable in pfmatch | 35 |
| genuine floor | 59 |
| unresolved | 6 |
| *of which, individual payees* | *37* |

and its robust mechanical result: **all 21 independently-established EINs were
already present in both references.** Zero missing from the BMF.

## Two shapes of NO, which are not the same case

`pf_status()` assigns NO for two different reasons and they must not be rolled
together:

- **no candidate at all** — no blocking pass produced any pair, so no
  comparator ever ran. The filed name reached nothing. Nothing can be shown to
  a reviewer beyond the filed record.
- **candidates, rejected** — records were retrieved and scored below the floor.
  A near-miss exists and is shown.

The packet records which, the renderer says so in words rather than leaving an
empty section, and the scoring stage reports the two separately.

## The sample

100 identities, `set.seed(20261101)`, in two strata that are not
interchangeable:

- **A, estimation (75).** Simple random from the NO identities carrying no
  prior human verdict. Unbiased, so its rates estimate the 725-case tier and
  carry Wilson intervals.
- **B, calibration (25).** Drawn from the NO identities that
  `dev/no-residual-verdicts.csv` already adjudicates by hand. These give
  agreement against a human rather than against another model. They are **not**
  random — an earlier audit's stratification chose them — so they never enter
  the recoverability numerator.

Every prior-verdict id leaves the estimation pool, not only the 25 drawn. The
audit selected them by a stratification this experiment does not model, so
leaving the undrawn ones in would import that stratification into a sample whose
entire claim is that it is simple random.

The two strata are shuffled into one `batch_order` and the model is never told
that strata exist.

## Reproducing

```
PFMATCH_DIR=. Rscript dev/adjudicate-10-no-packet.R    # ~30 min, re-runs the match
PF_NO_LIMIT=3 PF_NO_TAG=-smoke Rscript dev/adjudicate-11-no-search.R
Rscript dev/adjudicate-11-no-search.R                  # the 100-case run
Rscript dev/adjudicate-12-no-score.R
```

Stage 10 re-runs the match with `pairs` retained and **gates every identity's
tier against `BASELINE-2026-10C`**, stopping on any drift: a NO sample drawn
from a drifted run does not describe the baseline's NO tier, and its recovery
rate could not be added to the baseline's match rate.

---

# Results

Run 2026-10-31. 100 of 100 verdicts returned, every one through the
`submit_no_verdict` tool, no paused turns, 319 searches (3.2/case, 3 cases at
the cap of 15). Token cost $6.69 for the 100, i.e. $0.0669/case, cache writes
included; web search is billed per use on top of that and is not in the figure.

## The denominator, which turned out to be part of the answer

`pf_status()` reports **845 NO**, not the baseline's 725. The split:

| | n |
|---|---:|
| tier `NO` in the result frame — retrieved something, scored below the floor | 725 |
| **never scored at all** — no blocking pass produced any pair | **120** |
| total NO | **845** |

The full status table over all 4,903 identities is YES 2,979 / MAYBE 1,044 /
NO 845 / OOS 35. So the baseline's 4,748 "identities" are the *result frame*,
and its published 62.74% has a denominator that excludes 120 in-scope
identities — precisely the ones retrieval failed on hardest. On the in-scope
denominator of 4,868 the same run is **61.20%**, 1.55 points lower.

This is not a criticism of the arm; it is a statement about which number means
what. A match rate cannot drop the cases its retrieval step failed on.

## 1. How much of the tier is recoverable

Stratum A, n = 91, the only stratum that estimates a rate.

| | n of 91 | share | 95% Wilson |
|---|---:|---:|---|
| an EIN was established at all | 34 | 37.4% | |
| **and that EIN is in the reference** | **33** | **36.3%** | [27.1%, 46.5%] |

→ **~306 of the 845** NO identities, [229, 393].

Every one of the 34 EINs was `WEB`-sourced; **not one** was read off a rejected
near-miss row. So the circularity guard had nothing to exclude, and the
headline needs no caveat about it. That was not guaranteed going in — it is why
the guard was built.

Against the prior audit's 35 of 100 on a harder population, 36.3% is
strikingly close.

## 2. The coverage test — is the right EIN already in the reference

The prior audit's robust result was 21 of 21. At nearly double the n:

| | in the reference |
|---|---|
| stratum A | 33 of 34 — 97.1% |
| both strata | **37 of 38 — 97.4%** [86.5%, 99.5%] |

The single exception is `COMMONWEALTH UNIV OF PENN`, EIN 23-2738930, which the
model classed `GOVERNMENT` — a Pennsylvania state university. A governmental
unit is not an exempt organisation, so the BMF is *correct* to omit it.

**There are zero genuine reference-coverage gaps in 38 independently
established EINs.** The NO tier is a name-resolution problem, not an absence
problem, and this is now established on the production tier rather than on the
NO-under-both subset.

## 3. Why the cascade missed them

For the 37 recoverable cases, was the correct EIN ever put in front of the
scorer? Answered by lookup against the cached pairs, not by replaying the
blocker.

| | n | share |
|---|---:|---:|
| **offered and rejected** — a scoring/threshold failure | **26** | 70.3% |
| never offered — a blocking/retrieval failure | 11 | 29.7% |

Where it was offered, the score the comparator gave the correct row: median
**0.360**, range 0.080 to 0.622, against a review floor of 0.65. Only 2 of 26
reached 0.60. The passes that found it were `B1-token-state`,
`B2-token-concat`, `C1-name-any`, `D1-acronym`.

`dev/replay-no-residual-blocking.R` got 18 retrieved of 25 by replaying the
whole blocker; 26 of 37 here is the same finding by a cheaper route.

The model's hypothesis for the miss, against what actually happened:

| `miss_hypothesis` | never offered | offered |
|---|---:|---:|
| LEGAL_NAME_DIFFERS | 2 | 7 |
| TRUNCATED | 1 | 6 |
| DBA_OR_TRADE_NAME | 3 | 4 |
| PARENT_OR_CHAPTER | 0 | 5 |
| ACRONYM | 1 | 1 |
| GEOGRAPHY_WRONG | 1 | 1 |
| PROGRAM_NAMED | 1 | 1 |
| PLAIN_MISS | 0 | 1 |
| TYPO | **2** | **0** |

Two patterns worth naming. `TYPO` is never retrieved — a misspelling in a
distinctive token (`THE WESMINSTER SCHOOL`, `COCORDIA UNIVERSITY`) removes the
only key the inverted index could have used, and both those cases scored *no*
candidates at all. `PARENT_OR_CHAPTER` is always retrieved and always
underscored: four of the five are `SALVATION ARMY` and `YOUNG LIFE` at 0.08,
where the name cannot discriminate and the geography term correctly refuses to
rescue it.

## 4. What lives outside the BMF

Stratum A, n = 91. The model's judgement; calibrated in section 6.

`entity_class` — what the payee **is**:

| | n | share | ~of 845 |
|---|---:|---:|---:|
| **INDIVIDUAL** | **39** | **42.9%** | 362 |
| NONPROFIT | 27 | 29.7% | 251 |
| FOREIGN | 5 | 5.5% | 46 |
| GOVERNMENT | 5 | 5.5% | 46 |
| GROUP_SUBORDINATE | 5 | 5.5% | 46 |
| AGGREGATE | 3 | 3.3% | 28 |
| CHURCH | 3 | 3.3% | 28 |
| PROGRAM_OR_EVENT | 2 | 2.2% | 19 |
| FISCALLY_SPONSORED | 1 | 1.1% | 9 |
| FOR_PROFIT | 1 | 1.1% | 9 |

`bmf_expectation` — should a record exist: `NOT_LISTED` 57 (62.6%), `LISTED` 33
(36.3%), `UNCERTAIN` 1.

### Not an organisation the BMF could ever hold

**53 of 91 — 58.2%** [48.0%, 67.8%], i.e. ~492 of the 845: individuals,
businesses, government bodies, foreign organisations and aggregate
placeholders such as `VARIOUS CHARITABLE ORGANIZATIONS` and `SEE SCHEDULE
ATTACHED`.

What the pipeline's own flags said about those 53:

- `looks_personal` is TRUE on **11**
- `recipient_type`: `other_unknown` 24, `individual` 20, `public_charity` 7,
  `foundation_pf` 1, `nonprofit_other` 1

So seven payees that are not organisations are affirmatively coded
`public_charity`.

On the 39 individuals specifically, the flags behave very asymmetrically:

| | caught | of 39 |
|---|---:|---:|
| `looks_personal` | 11 | 28.2% |
| filed status code reads `individual` | 19 | 48.7% |

And every one of the 11 cases `looks_personal` flagged in stratum A *is* an
individual — **11 of 11, no false positives**. So the flag is precise and
badly under-powered: it misses 28 of 39. That is the shape
`dev/NO-RESIDUAL-AUDIT.md` diagnosed — `.pf_looks_personal()` requires a token
from a 202-name given-name list, which cannot cover US given names — and it
matters because a precise, low-recall flag is the easy kind to improve. Nothing
has to be made more conservative; the list has to get longer.

### The structural floor

**6 of 91 — 6.6%** [3.1%, 13.6%]: a subordinate under a group ruling, a church,
or a programme inside another organisation. Two churches (`SEVIER HEIGHTS
BAPTIST CHURCH`, `ST AGNES CHURCH`), one diocesan high school, one fiscally
sponsored project (`New CT Farmers Alliance`), two named events
(`Scholarships for Future Engineers`, `DRIVE FOR EPILESPY CURE`). There is no
EIN to find and no amount of matching recovers them.

This is **much smaller** than the prior audit's 12 of 100 "payee has no
exemption of its own". The honest floor is a few percent, not a tenth.

### Untraceable

**0 of 91.** Search identified something in every case it was asked about. The
prior audit had 10 of 100 "no such organisation traceable" and 9 UNFINDABLE;
with search on every case that category essentially vanishes.

## 5. `entity_class` and `bmf_expectation` are not redundant

The `ICRC` case earns the schema its two separate fields: the model classed
`INTERNATIONAL COMMITTE OF THE RED CROSS` as `FOREIGN` — it is Swiss — and yet
`bmf_expectation` `LISTED`, because it holds a US exemption record. It does,
and the EIN it reported is in the reference. Collapsing "what the entity is"
into "should a record exist" would have scored that case wrong either way.

Across all 100 cases the two fields were **perfectly concordant with the
mechanical lookup**: every `LISTED` case produced an EIN that is in the
reference, and no `NOT_LISTED` case produced one that is (bar the state
university, which the model itself flagged as government).

That is a coherence result, not a correctness proof. An EIN can be in the
reference and still belong to the wrong organisation. Section 6 is the only
check on that.

## 6. The model against a human, on the same cases

`PF_NO_SET=cal` builds a packet from the 63 prior-audit cases that are still NO
in this arm, and stage 11 runs the identical arm over it. Stage 14 verifies the
filed name is identical on all 63 rows before comparing anything — the join is
re-checked at the point of use because a key that looked fine already produced
one silent mis-join in this experiment.

### Agreement on what the case is

4 cases carry a human verdict of `UNCLEAR`, which is a non-answer and is
excluded rather than folded into a class.

| | n | |
|---|---:|---|
| **agreement** | **49 of 59** | **83.1%** [71.5%, 90.5%] |
| Cohen's kappa | | **0.724** (observed 0.831, chance 0.386) |

Per-class recall against the human:

| class | | |
|---|---:|---:|
| NOT_AN_ORG | 11 of 11 | 100.0% |
| RECOVERABLE | 30 of 34 | 88.2% |
| NO_EXEMPTION | 5 of 6 | 83.3% |
| UNTRACEABLE | 3 of 8 | 37.5% |

**A mapping sensitivity, stated because it works in the model's favour.** Three
of the ten disagreements exist only because this script maps the human's
`UNCLEAR-GEO` to RECOVERABLE. All three are churches — `UNIVERSITY BAPTIST
CHURCH`, `ST BARTHOLOMEWS CHURCH`, `CHRIST CHURCH CATHEDRAL` — which the model
calls `CHURCH` / `NOT_LISTED` / `CHURCH_EXEMPT`. Dropping `UNCLEAR-GEO` as the
hedge it is gives **49 of 56 = 87.5%, kappa 0.795**. The headline above keeps
the conservative figure.

Worth noting that `dev/NO-RESIDUAL-AUDIT.md` discusses those same three cases
and concludes they "should not be forced through" — so the model's `NOT_LISTED`
is arguably the operationally correct call, and the human's own write-up agrees
with it even though the label does not.

### The `UNTRACEABLE` class is not a model failure

37.5% recall looks bad until the cases are read. Of the 8 human `UNFINDABLE`
verdicts the model agreed on exactly 3 — and those 3 are precisely the ones
where it returned **low** confidence and identified no organisation at all
(`THRIVE 1035`, `THE PURPOSEFUL LIVING CENTER`, `MERCY MISSIONS TO THE WORLD`).

On the other 5 it identified something at medium or high confidence:

| filed | what the model found |
|---|---|
| `DOCKS TO DOORWAYS` | a Belgrade Lakes Association campaign — the filed street literally reads `PO Box 551 Belgrade Lakes Associati[on]`; EIN 01-0377308, in the reference |
| `AMERICAN SHRINE ASSOCIATES` | the Basilica of the National Shrine at the filed address; EIN 53-0196626, in the reference |
| `505 Main Street Canton` | a Haywood Pantries outreach depot — the filed "name" is a street address |
| `GERALD R MACCARTHY MEMORIAL FUND` | a named fund at the UNC Arts & Sciences Foundation, at the filed address |
| `GIFTS TO THE NEEDYINDIGENT` | a description of a kind of giving, not an organisation |

**The model's confidence tracks the disagreement exactly.** Where it says low it
agrees with the human's "untraceable"; where it says medium or high it found
what the human could not. That is the single most reassuring pattern in this
experiment, and it is the opposite of what the MAYBE search arm showed, where
confidence rose as accuracy fell.

### Agreement on the EIN

No vocabulary mapping needed: the same nine digits or not.

| | |
|---|---|
| both name an EIN | 24 |
| **identical** | **23 of 24 — 95.8%** [79.8%, 99.3%] |
| human only | 1 |
| model only | 11 |
| neither | 27 |

The one disagreement is `The Salvation Army`: the model gives 36-2167910 (the
Illinois corporation), the human 58-0660607 (the Southern territory). Both are
real Salvation Army EINs and which is right depends on which corporation
received the money — a genuine dispute on the hardest name in the file.

The single human-only EIN is `Hamilton Co Gen Hlt Dist`, 31-6000063, where the
model said `GOVERNMENT` / `NOT_LISTED`. A county health district is a
governmental unit, and that EIN is the one human EIN **not** in the reference.
The model was right to decline it.

All 11 model-only EINs are in the reference, and 5 of them are cases the human
called `REAL-ORG` without being able to produce an EIN.

### The two sides land in the same place

| | recoverable share of the same 63 |
|---|---:|
| human | 34 — 54.0% |
| model | 35 — 55.6% |

And the coverage test from both sides:

| | in the reference |
|---|---|
| model EINs, web-sourced | **33 of 33 — 100%** |
| human EINs, independently established | 24 of 25 — 96.0% |

The human's one absence is the county health district above. **Neither side
found a single genuine reference-coverage gap.**

Retrieval versus scoring on this set: 25 of 35 offered and rejected, 10 never
offered — the same 70/30 shape as the random sample, and consistent with
`dev/replay-no-residual-blocking.R`'s 18-of-25 from replaying the whole blocker.



## 6. Cost

$0.0669/case in tokens, cache writes included, plus 3.2 web searches per case
billed separately. Projected over the 845-case tier: **$56.50** in tokens plus
~2,700 searches.

No cost ratio against the MAYBE experiment's arms is quoted. Those ratios were
computed from that experiment's own runs, some logged before the cache-write
accounting was fixed, and restating them here from a different denominator is
exactly the arithmetic that produced two wrong projections already.

Confidence against search outcome, all 100:

| | CONFIRMED | CONTRADICTED | INCONCLUSIVE |
|---|---:|---:|---:|
| high | 82 | 6 | 0 |
| medium | 9 | 1 | 0 |
| low | 0 | 0 | 2 |

