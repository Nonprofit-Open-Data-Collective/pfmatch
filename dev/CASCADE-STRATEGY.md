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

Of the three, two are now adjudicated by hand against the filed grant, both
references' BMF rows, and the 990 mission/program text.

**The 46 EIN disagreements (44 judged).** BMF correct 23, matchdb correct 14,
neither 3, unclear 4. The BMF side wins **62% of decided cases** (95% CI
45-78%), so locking tier-1 YES costs roughly **17 identities = 0.36% of the
file**. That is the price of never revisiting a tier-1 YES, and it is small.
The disagreements are almost entirely the affiliate/endowment family:
`GEORGIA TECH FOUNDATION` vs the Alumni Association, `SPECIAL OLYMPICS INC` vs
its Endowment Fund, `GREENPEACE FUND` vs Greenpeace Vision Fund. matchdb's wins
are the mirror image — it is right when the filed name is the *operating* entity
and the BMF legal name is not (`CHILDREN'S HOSPITAL OF PITTSBURGH FOUNDATION`,
whose matchdb mission says "sole fundraising arm"; `TOLEDO ZOO & AQUARIUM`,
where the BMF side picked the American Dental Assistants Association).

**The 244 newly cleared (33 judged).** This cell is not homogeneous and a
blended sample would describe neither half of it:

| stratum | n | sampled | correct | wrong | unclear | precision |
|---|---:|---:|---:|---:|---:|---|
| same EIN as tier 1's top pick | 131 | 16 | 14 | 1 | 1 | 93% (68-100%) |
| different EIN | 113 | 17 | 13 | 2 | 2 | 87% (60-98%) |

Weighted over the full cell: **~220 of 244 correct, 90%**. Tier 2 therefore
introduces roughly **24 wrong YES = 0.49% of the 4,869 identities** in exchange
for +5.0 points of clear rate. The same-EIN half is the safer one, which is what
you would expect: tier 1 had already chosen that organisation and matchdb only
supplied the corroboration needed to clear the threshold.

The different-EIN half is where tier 2 earns its keep, and the wins are the ones
no amount of BMF tuning reaches: `MIT` to Massachusetts Institute of Technology,
`CAMP` to Children's Association for Maximum Potential (whose mission text opens
"CAMP'S MISSION"), `YWCA Seattle` to Young Women's Christian Association of
Seattle, `COLUMBIA UNIVERSITY` to Trustees of Columbia University. These are
acronym and legal-name expansions that exist as *observed* or *dba* name
variants in matchdb and simply are not in the BMF.

Both failure modes in that half are geographic, not nominal:
`MONTROSE COMMUNITY COLLEGE` to Montrose Community **Band**, and a St Francis
Hospital in Manhattan standing in for the one in Poughkeepsie. The single
same-EIN failure is the same shape — Habitat for Humanity in Woody Creek CO
matched to the Vail Valley affiliate. Tier 2 widens the name space without
widening the geographic discipline, and that is where it breaks.

**The 364 demotions are still unjudged**, and they remain the larger exposure:
if matchdb is right to doubt them, they are tier-1 false positives the cascade
makes permanent. §4 is the cheaper route to that answer than adjudication.

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

## 5. What is measured, and what is left

**Done.** The 46 EIN disagreements and the 244 newly cleared are adjudicated
(§3). Between them they put a number on both sides of the trade: the cascade
buys +5.0 points of clear rate at ~90% precision on the gains, and the cost of
never revisiting a tier-1 YES is ~0.36% of the file.

Remaining, in priority order:

1. **Test the tier rule** on the 212 same-EIN demotions, per §4. This is the
   cheapest remaining experiment and it bears on the largest unmeasured cell.
2. **Judge a sample of the 364 demotions.** Still the biggest exposure, because
   the cascade makes every one of them permanent.
3. ~~**Internet-check a NO sample**~~ — **done**, see `dev/NO-RESIDUAL-AUDIT.md`.
   Of the 592 NO-under-both identities, ~35% are recoverable (worth 4.3 points)
   and ~59% are a genuine floor, mostly individuals and payees with no exemption
   of their own. All 21 independently established EINs were already in **both**
   references, so the residual is name resolution, not missing data — widening
   the reference again will not help. Two side findings matter more than the
   split: the individual-payee flags miss about a quarter of what they should
   catch (a 202-entry given-name whitelist), which
   inflates the denominator behind every clear rate in this project, and one
   case in 100 has a filed state that contradicts its own ZIP and so is invisible
   to state blocking.
4. **Add a geographic gate to tier 2.** All three adjudicated tier-2 errors in
   the cleared cell are geographic, not nominal — a wrong affiliate or a wrong
   city under a correct name. Tier 2 widens the name space; it should not widen
   the place space with it.
5. **Normalise the `EIN-` prefix** matchdb emits. It silently breaks every join
   against BMF-keyed artifacts, and it already produced one bogus "100% churn"
   result in this analysis.

## 6. Default

```
tier 1   augmented BMF, all grants
tier 2   matchdb, on tier-1 MAYBE + NO, candidates UNIONED
tier 3   adjudicate the union of unresolved, both references' candidates
```

69.0% cleared before any human review, against 63.0% today, for tier-2 compute
on 37% of the file. The adjudication in §3 supports adopting tier 1 and tier 2
now: the gains are real at ~90%, and locking tier-1 YES is a 0.36% cost, not the
open-ended risk it looked like before the cells were judged. What is still
unsupported is the stronger claim that tier-1 YES is *sound* — the 364 demotions
have not been judged, and item 1 above is the cheap way to find out.
