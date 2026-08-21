# Phase 3: the disambiguation and feature libraries

What the full-file YES tier is *for*. The match itself is the means; these two
libraries are the durable product, and both need the 12.5M-grant run to exist
because both are statements about repetition that the dev samples destroyed
(median 1 grant per filer, against 5 per filer-year in the real file).

Written 2026-08-20. Specifies the tables, how each is built, and what has to be
true before any of it is trusted.

---

## 0. Which cascade to run

**Recommendation: the current staged cascade, unchanged, against the augmented
unified reference** — `pf_staged_passes("lean")` plus `pf_recovery_passes(state
= TRUE)`, batch size 25,000, ten shards.

Not because it is the best possible configuration, but because it is the only one
with a measured benchmark behind it (2,821 YES / 1,006 MAYBE / 1,093 NO / 80 OOS
on 5k). Changing the cascade and the reference in the same run would make the
result uninterpretable. Two changes go in first because they are measured and
cheap:

| change | why | measured |
|---|---|---|
| collapse identical `(name, state, zip5)` reference rows | group-ruling subordinates add nothing the matcher can use | reference −7%, cost driver −8x |
| `pf_dedup()` sub-blocking + list accumulator | ~500k keys were never fuzzy-compared | behaviour-identical at 100k |

Everything else — the affiliation hook, the enriched packet, the ranker — waits
until after the run, so the run is a clean baseline for them.

---

## 1. The disambiguation library

**The problem it solves.** Two EINs, one apparent organisation. The matcher sees
`EAGLE RANCH` and `EAGLE RANCH FOUNDATION` and cannot separate them; a human
needs to know they are a real pair with a real relationship, and which one
receives grants. Today that knowledge lives in `R/affiliation.R` for arm pairs
and nowhere else.

**What the YES tier supplies that nothing else does.** 12.5M grants written by
134,651 different foundations produce, for each EIN, a *distribution of observed
names and addresses* — the same organisation as dozens of different people typed
it. That is the raw material for saying which variants belong to one EIN and,
crucially, which variants are shared between two EINs and therefore dangerous.

### `pf_variant_library()` — one row per (EIN, observed variant)

| column | meaning |
|---|---|
| `ein` | the resolved EIN |
| `name_variant`, `name_key` | as filed, and normalised |
| `street_variant`, `city`, `state`, `zip5` | as filed |
| `n_grants`, `n_filers`, `first_year`, `last_year` | how much support this variant has |
| `median_score`, `min_score` | how confidently it resolved |
| `source` | `pf_yes` / `schedi` / `bmf` / `bmf_dba` |

Built from the YES partition, restricted to confident rows (exact or near-exact
name with geographic agreement) so the library is not seeded with the cascade's
own guesses. Schedule I aliases already provide an independent version of the
same object (2.45M rows, 794,209 EINs); the two should be merged with `source`
retained, and disagreements between them are themselves a signal.

**The corroboration rule carries over unchanged.** Schedule I precision runs
86.1% at one filer to 99.0% at twenty. A variant observed once, by one
foundation, is a hypothesis; observed by twenty, it is a fact. `n_filers` is the
dial, and the *token-overlap gate is not* — it discards acronyms and rebrands,
which are the variants worth having.

### `pf_collision_library()` — one row per (variant, competing EINs)

The half that does not exist today and matters more. A normalised name or
address that resolves to **two or more EINs** is where every MAYBE comes from.

| column | meaning |
|---|---|
| `name_key` | the ambiguous string |
| `eins` | the EINs it has been observed to mean |
| `n_eins`, `n_grants_each` | how crowded and how balanced |
| `relation` | `arm` / `sibling` / `unrelated` / `unknown` |
| `evidence` | `SCHED_A` / `SCHED_R` / `BMF_GROUP` / `NAME_GEO` / none |
| `disambiguator` | the field that separates them: `zip5`, `city`, `state`, `none` |

`relation` comes from the existing machinery: `pf_cluster_arms()` for
operating/fundraising pairs, `pf_group_siblings()` for federated chapters,
`pf_build_affiliation_links()` for Schedule A/R disclosure. `disambiguator` is
the practically useful column — it tells the cascade whether a tie is breakable
at all, which is exactly the judgement it currently gets wrong 27% of the time on
arm pairs.

**A collision with no disambiguator is a permanent MAYBE.** Recording that
explicitly is worth as much as resolving it, because it stops the case being
re-reviewed forever.

---

## 2. The feature library

One row per entity, built once, joined everywhere. Three grains.

### `pf_ein_features()` — per recipient EIN

| feature | definition | why it is not obvious |
|---|---|---|
| `n_grants`, `n_filers`, `n_years` | volume and breadth | `n_filers` measured at **0.877 pair AUC and 76% top-1 on the 20% of grants where it separates candidates** — precise, rarely applicable |
| `first_year`, `last_year`, `active_span` | when this EIN receives | a grant dated outside the span is evidence against |
| `median_grant`, `p95_grant`, `total_received` | size profile | a $500 grant to a $50M recipient is unusual |
| `n_name_variants`, `name_entropy` | how many ways it is written | high entropy means the matcher will keep seeing it |
| `in_collision` | appears in `pf_collision_library()` | a hard flag, not a score |

### `pf_filer_features()` — per foundation

| feature | definition | the caveat that must ship with it |
|---|---|---|
| `n_grants`, `n_grantees`, `n_years` | portfolio size | — |
| `ntee_profile` | distribution over recipient NTEE major groups | **51% of matched grantees have no usable NTEE**, so a profile needs ~10 matched grants to rest on 5 codes |
| `modal_ntee`, `top_share` | the concentration | must be scored against a **size-matched null**, not a flat threshold: observed top-share equals the null median at every portfolio size tested, and only ~11% of funders with ≥5 grantees beat their own null p95 |
| `ntee_entropy` | normalised Shannon | the gate; low entropy is what licenses using the profile at all |
| `persistence` | mean year-over-year Jaccard of the grantee set | **untestable until now** — 92% of funder-years in the dev sample held exactly one grant, forcing the statistic to zero |
| `repeat_rate` | share of grantees appearing in ≥2 years | the cleanest version of the same idea |

**Persistence is the one to watch.** A grantee that appears in a foundation's
portfolio in consecutive years is a near-certain identity link, and it is the
feature the sampling design has been hiding all along. If it works, it resolves
MAYBE cases by propagation rather than by scoring — the foundation already told
us who this is, last year, more legibly.

### `pf_pair_features()` — per (filer, EIN)

| feature | definition |
|---|---|
| `n_grants`, `years`, `total` | this funder to this grantee |
| `is_repeat` | seen in a prior year |
| `name_variants_used` | how this funder writes this grantee |

`is_repeat` is the operational form of persistence and the single cheapest
candidate feature to test on the adjudicated set.

---

## 3. Order, and what gates each step

```
full run  ->  YES partition
              |
              +-> pf_variant_library     (needs: confident-YES filter)
              +-> pf_collision_library   (needs: variant library + affiliation.R)
              |
              +-> pf_ein_features        (needs: YES partition only)
              +-> pf_filer_features      (needs: NTEE join + size-matched null)
              +-> pf_pair_features       (needs: YES partition only)
                        |
                        +-> re-score MAYBE with the new features
                        +-> measure each on the adjudicated gold set
```

**Nothing is adopted on an AUC alone.** Every feature gets pair AUC *and* a
fire-rate, and the negative results get recorded as carefully as the positive
ones — the pattern that has already killed semantic re-ranking, NTEE blocking,
unconditional funder profiles, and the `is_arm` main effect.

**The circularity to avoid.** These features are derived from the cascade's own
YES decisions, so feeding them back to re-score MAYBE risks amplifying whatever
the cascade already prefers. Two guards: build the priors only from
*unambiguous* YES (exact name, geographic agreement, no runner-up in band), and
evaluate on the 156 adjudicated cases, which were labelled independently of any
of this.

---

## 4. What this does not fix

The features are about repetition. The dominant MAYBE failure is an operating
entity and its own fundraising arm, which **repeat together** — the same
foundation gives to the same body every year, and the ambiguity is about which
EIN the cheque named, not which body received it. Persistence will not touch it,
and neither will the NTEE profile, since arm and parent share a sector by
construction.

That case needs the enriched candidate packet (45 of 56 hard cases resolved), the
Schedule A line-5 override where the parent is a governmental unit, and a stated
ordering policy. Those are Phase 4, and this library does not substitute for
them.
