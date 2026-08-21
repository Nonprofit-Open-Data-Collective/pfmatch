# Optimizing the cascade for 990-PF

Every threshold in `np_config()` is an **npmatch default, tuned on
SAM/USASpending** — a registry of businesses and persons, matched with
generally complete addresses. 990-PF grants are a different population, and
nothing in the current configuration has been fitted to them. This plan says
what is worth testing, in what order, and — more importantly — what the
available labels can and cannot support.

Cascade mechanics and the full parameter list: `dev/CASCADE.md` §8.

---

## 0. The constraint that shapes everything: labels

| set | n | drawn from |
|---|---:|---|
| `dev/maybe-verdicts.csv` | 100 | **MAYBE only** |
| `data-dev/AUTOACCEPT-LABELLED-200.csv` | 200 | autoaccept sample |
| `dev/enrichment-verdicts.csv` | 56 | hard MAYBE cases |
| `dev/independent-verification.csv` | 12 | re-check of the above |

**Almost every human label sits inside the MAYBE tier.** That has three
consequences which govern the whole plan:

1. **YES precision is assumed, not measured.** The 99.8% state-consistency and
   82.8% ZIP5 figures are *proxies* — internal consistency of the match, not
   external truth. No sample of YES has been adjudicated against the world.
2. **NO recall is unmeasured.** Nobody has asked how many NO grants had a
   correct answer sitting in the reference.
3. **Tuning a tier boundary on labels drawn from one side of it is circular.**
   Moving `thresholds["yes"]` changes which grants are in MAYBE; scoring that
   against a MAYBE-drawn sample measures the sample, not the system.

So: **no threshold that moves a tier boundary can be honestly optimized until
labels span all three tiers.** Everything in §2 is blocked on §1.

## 1. Build the evaluation set first

### 1a. Silver labels — free, and already proven here

`dev/COMPARATOR-FINDINGS.md` established a construction that needs no human:

* **positives** — YES-tier matches whose **ZIP5 agrees exactly**, so the name
  match is corroborated by something independent of the name (1,897 collected)
* **negatives** — pairs of **distinct BMF EINs**, same state, JW ≥ 0.95.
  Different EIN means a different registered organisation by construction
  (340 collected)

This generalises. At full-file scale the positive pool becomes very large, and
it can be stratified by geo evidence (ZIP9 / street / ZIP5 / ZIP3 / city /
state-only) — which is exactly the axis `geo_weights` parameterises.

**Its limit, stated plainly:** silver positives are drawn from *accepted*
matches, so they cannot reveal errors the current thresholds already make. They
measure discrimination, not calibration. Use them to compare comparators and
weights; do not use them to set a tier boundary.

### 1b. Gold labels spanning all three tiers — the enabling step

The one thing that unblocks everything else. Target ~600, stratified:

| stratum | n | answers |
|---|---:|---|
| YES, state-only geo evidence | 150 | is the promotion floor's 4.3% sound? |
| YES, ZIP5/street confirmed | 100 | baseline YES precision |
| MAYBE, in the tie band | 150 | ranking within contention |
| MAYBE, outside the band | 100 | is `maybe` = 0.65 the right floor? |
| NO, best candidate scored 0.55–0.65 | 100 | what does the NO boundary cost? |

The YES and NO strata are the new information. Phase 4 of
`dev/DEVELOPMENT-PLAN.md` already plans ~1,000 labels on the enriched packet;
**this is that round, stratified to also answer the threshold questions** rather
than a separate effort. Label on the enriched packet (`pf_adjudicate()` with
NTEE text, mission, program descriptions) — it resolves 45 of 56 hard cases, so
it is what makes the YES and NO strata answerable at all.

## 2. What to test, ranked by expected value

### High — specific reasons to think the SAM default is wrong here

**2a. `name_geo` = 0.60 / 0.40.** SAM registrants have real business addresses.
990-PF grant addresses are frequently a **lockbox, a fiscal sponsor, or absent**
— `lockbox_address` is already a named failure mode in `maybe-verdicts.csv`, and
`pf_recover_name_from_street()` exists because the address field sometimes
contains the *name*. If address is less reliable here, 0.40 is too much weight.
*First step needs no labels:* measure what share of in-scope grants have a
usable address at each granularity, and what share of YES matches rest on
address evidence that a lockbox would produce.

**2b. `geo_weights["city"]` = 0.50 and `["state"]` = 0.20.** With the 0.6/0.4
split, a perfect name plus a city match scores `0.6·1.0 + 0.4·0.5 = 0.80` —
**over the 0.78 auto-accept line on name and city alone**. The state-conflict
gate closed the cross-state version of this, but the same-state version stands.
Ask directly: of YES matches whose best geo evidence is `city`, what is the
precision? This is a stratum of §1b.

**2c. `min_margin` = 0.05, post-dyad.** The margin brake was set before the
dyad collapse existed. Now that same-body runner-ups are removed first, the
brake fires on a cleaner population, and the right value may differ. Cheap to
sweep because the dyad artefacts are already built: re-run
`pf_dyad_collapse()` at several `min_margin` values and count tier movement.
Needs labels only to choose among them.

### Medium — measurable, weaker priors

**2d. `distinct_name_floor_xstate` = 0.72.** Documented as ~40% correct on
SAM data. `dev/PROMOTION-FLOOR-FINDINGS.md` measured the same-state floor on PF
grants: 121 YES (4.3% of the tier) exist only because of it, and **97% of those
have state-only geo evidence**. That is a precision question the YES/state-only
stratum answers directly.

**2e. `jw_threshold` = 0.85.** Flooring below this is essential (see
`dev/CASCADE.md` §1), but 0.85 is a SAM number. Silver labels from §1a can
sweep it — this is discrimination, exactly what they measure well.

**2f. Token blocking: `max_ref_freq` 25,000, `min_pair_idf` 8.** Pure
cost/recall trade, no labels needed. `B2-token-concat` spends 121,738 candidates
to resolve 5, and `D1-acronym` 30,276 to resolve 1. Sweep and plot recall
against candidate volume. Only worth doing if cost becomes binding — it is not
today (`dev/REF-PERFORMANCE.md`).

### Low — leave alone

**2g. `thresholds` 0.78 / 0.65.** The most tempting knob and the one most
likely to produce a fake improvement. It cannot be moved credibly without the
§1b YES and NO strata, and once those exist the honest output is a
**precision/recall curve with the operating point chosen by review capacity**,
not an "optimal" threshold.

**2h. The comparator.** Already investigated and closed:
`dev/COMPARATOR-FINDINGS.md` measured the generic-head problem, found the
signal real, and concluded it was not worth fixing. Do not reopen without new
evidence.

## 3. Method, and how not to fool ourselves

* **Fourteen parameters against a few hundred labels will overfit.** Sweep
  **one parameter at a time**, holding the rest at default, and report the tier
  movement alongside the accuracy change. A joint search is not supportable at
  this label budget and should not be attempted.
* **Hold out 30% of the gold set from the first look** and touch it once, at the
  end. Anything tuned on the visible 70% and confirmed on the held-out 30% is
  reportable; anything that only works on the visible portion is not.
* **Report the null.** `dev/DEVELOPMENT-PLAN.md` already carries a "deliberately
  not on this list" section. Parameters found not to matter belong there, with
  their measurement, so the next person does not re-sweep them.
* **Precision and recall separately, never accuracy.** A tier-boundary change
  trades one for the other by construction; a single accuracy number hides which.
* **State the operating point.** The deliverable is not "the optimal config".
  It is a curve plus a recommended point justified by how much review capacity
  exists.

## 4. Sequence

1. Build silver positives/negatives at scale, stratified by geo evidence (§1a).
2. Run the no-label probes: address availability (2a), candidate volume vs
   recall (2f), `min_margin` tier movement post-dyad (2c).
3. Draw and label the ~600-case stratified gold set (§1b) — this is the Phase 4
   round, re-stratified.
4. Single-parameter sweeps in the §2 order, 70/30 hold-out.
5. Publish curves and a recommended operating point; fold nulls into the
   development plan.

**Do not start at step 4.** The temptation is to sweep thresholds now because it
is one line of code. On MAYBE-only labels that produces a number that will not
survive contact with a stratified sample.
