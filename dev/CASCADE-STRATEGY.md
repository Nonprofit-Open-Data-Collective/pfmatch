# The two-tier cascade: BMF first, matchdb on the residual

**Recommendation: tier 1 against the augmented BMF, tier 2 against matchdb on
everything tier 1 did not clear, with candidate lists unioned rather than
replaced. Measured 69.0% against 62.6% for the best single reference.**

Written 2026-10-22 from two complete runs over the same 5,000 grants
(`inputs/ef1k_grants_0*.csv`), so the cascade is simulated exactly rather than
estimated. Script: `dev/simulate-two-tier.R`.

---

## 1. Why a single reference is the wrong question

Neither reference dominates.

| | augmented BMF | matchdb |
|---|---:|---:|
| reference rows | 3,880,431 | 6,671,061 |
| distinct EINs | 3,698,124 | 3,761,212 |
| clear rate | **63.0%** | 60.1% |
| match time, 5k grants | ~17 min | 48 min |

matchdb is the richer reference — 460,490 corroborated aliases against 193,063,
plus 207,786 former names the BMF has no equivalent for — and it still scores
**lower**. More true names per EIN mechanically produces more in-band rivals,
and `np_tier()` reads "crowded" as "uncertain".

The movement, not the net, is the point:

| | n | share |
|---|---:|---:|
| YES → YES, same EIN | 2,564 | 52.7% |
| MAYBE → MAYBE | 693 | 14.2% |
| NO → NO | 592 | 12.2% |
| **YES → MAYBE, demoted** | **364** | 7.5% |
| **MAYBE → YES, cleared** | **244** | 5.0% |
| MAYBE → NO | 121 | 2.5% |
| **YES → NO, lost** | **76** | 1.6% |
| NO → MAYBE, surfaced | 75 | 1.5% |
| **NO → YES, recovered** | **67** | 1.4% |
| YES → YES, **EIN changed** | 46 | 0.9% |

314 gained, 440 lost, net −126. **The gross movement is 15× the net.** A single
reference forces a choice between those two columns; a cascade does not.

## 2. The cascade, and what each scope buys

Tier 1 runs the augmented BMF over everything. Tier 2 runs matchdb over only
what tier 1 left open. Tier-1 YES is never revisited.

| | clear rate | tier-2 volume |
|---|---:|---:|
| tier 1 alone | 62.6% | — |
| **+ tier 2 on MAYBE** | **67.7%** | 22% of the file |
| **+ tier 2 on MAYBE + NO** | **69.0%** | 37% of the file |

Extending tier 2 from MAYBE to MAYBE+NO costs 15 points of extra file coverage
and buys **+67 YES** plus **75 NO→MAYBE** cases that gain reviewable candidates
where they previously had none. On compute alone that is worth it: tier 2 over
37% of the file at matchdb's 2.8× unit cost is roughly the same wall-clock as
running matchdb over the whole file once, and it yields 9 points more.

**Union, do not replace.** The simulation above shows 121 MAYBE→NO, which looks
like a cost of widening the scope. It is an artifact of the simulation swapping
tier 1's answer for tier 2's. In the real design tier 2 *adds* candidates to the
tier-1 list, so a tier-1 MAYBE cannot become a NO. Implemented that way, the
MAYBE+NO scope has no downside beyond compute.

## 3. What a two-tier cascade structurally cannot fix

Tier 2 never sees a tier-1 YES, so every tier-1 YES is final.

* **46 identities** are YES in both runs on a **different EIN**. If tier 1 holds
  the wrong one, that error is permanent and invisible.
* **440 identities** are tier-1 YES that matchdb demotes or loses. If matchdb is
  right to doubt them, those are tier-1 false positives the cascade locks in.

Both numbers are **unadjudicated**. Which side is correct is the single most
important quantity still missing, and no amount of further crosstabulation will
produce it — it needs ground truth.

This is the real cost of the design and it should be stated plainly: the
cascade trades a guaranteed recall gain for an unmeasured precision risk on
roughly 10% of tier-1 YES.

### The variant you proposed: tier 1 → adjudicate → rematch the remainder

Strictly better on precision, and it addresses exactly the gap above, because
adjudication can overturn a tier-1 YES where tier 2 cannot. The cost is
sequencing: adjudication is the slowest stage and putting it mid-cascade means
tier 2 cannot start until it finishes.

A middle option gets most of it: run tier 2 first on MAYBE+NO, then adjudicate
once over the **union** of what remains unresolved, with both references'
candidates in the packet. Adjudication sees more candidates per case and runs
once instead of twice, and the only thing still protected from review is the
tier-1 YES set — which is what the sampling in §5 is for.

## 4. Why not just fix the tier rule instead

Worth testing before accepting the cascade as permanent. Of the 364 YES→MAYBE
demotions, **212 (58%) keep the same EIN as the top pick** — matchdb found the
same answer and `np_tier()` demoted it only because an extra name row entered
the tie band. Those are not disagreements, they are confidence lost to
information gained, which is the wrong direction for a scoring rule.

If a margin or tie-band adjustment recovers those 212 without also promoting the
152 genuine displacements, matchdb alone would land near 64% and the case for a
cascade weakens considerably. That experiment is cheap and has not been run.

## 5. What has to be measured before this is the default

In priority order:

1. **Adjudicate the disputed cells**, not the undifferentiated MAYBE tier. The
   decision-relevant populations are the 244 newly cleared, the 46 EIN
   disagreements, and a sample of the 364 demotions. Those three settle whether
   the cascade's gains are real and whether its locked-in tier-1 YES are sound.
2. **Test the tier rule** on the 212 same-EIN demotions, per §4.
3. **Internet-check a NO sample** to establish how much of the residual is
   genuinely unmatchable rather than merely unmatched.
4. **Normalise the `EIN-` prefix** matchdb emits. It silently breaks every join
   against BMF-keyed artifacts, and it already produced one bogus "100% churn"
   result in this analysis.

## 6. Default, pending those measurements

```
tier 1   augmented BMF, all grants
tier 2   matchdb, on tier-1 MAYBE + NO, candidates UNIONED
tier 3   adjudicate the union of unresolved, both references' candidates
```

69.0% cleared before any human review, against 63.0% today, for tier-2 compute
on 37% of the file. Adopt tier 1 and tier 2 now; hold the claim that tier-1 YES
is safe until the sampling in §5 says so.
