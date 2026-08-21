# The cascade, end to end

What is compared, how it is scored, in what order, and how a grant lands in
YES / MAYBE / NO. Written 2026-08-21 against `npmatch` at `1e27647` and
`pfmatch` at the Phase 0c merge.

Division of labour: **npmatch** owns generic record linkage — canonicalization,
normalization, blocking, comparison, scoring, vetoes, selection, tiering.
**pfmatch** owns everything 990-PF-specific — grant parsing, recipient-type
scoping, dedup to identities, reference augmentation, recovery keys, dyads,
status and reporting.

---

## 1. What is compared

Both sides carry **two name slots**. This is the point most often got wrong: it
is not one query name against two reference names.

| slot | query (`pf_map_grants()`) | reference (`np_map_bmf()`) |
|---|---|---|
| `name` | `recip_name` | `org_name_join` |
| `dba` | `recip_name_alt` (untruncated line1+line2) | `dba_name` |
| `street` / `unit` / `city` / `state` / `zip5` | `recip_*` | `org_addr_*` |

Effective name similarity is the **best of the cross-product**:

```
s_name = max( name×name, name×dba, dba×name, dba×dba )
```

Four comparisons. USASpending gets six because `np_compare()` also scores
`division×name` and `division×dba`; `pf_map_grants()` maps no division, so those
two terms are always zero. Same machinery, two fewer inputs — not a different
comparison count by design.

Address is **not** one comparison. `np_compare()` emits seven location signals,
mostly cheap exact tests:

`geo_zip9`, `geo_zip5`, `geo_zip3`, `geo_state`, `geo_stnum`, `geo_pobox`, plus
fuzzy `city` and `street_key` reused from the JW columns.

### Jaro-Winkler flooring

Comparators are `cmp_jarowinkler(threshold = 0.85)` for text, `cmp_identical()`
for `zip5`. **reclin2's `threshold=` is the Winkler prefix *boost*, not a
cutoff** — unrelated strings still return ~0.5. Every fuzzy similarity is
therefore floored to 0 below `jw_threshold` in both `np_compare()` and
`.np_hier_score()`. Without that, ~0.5 leaks into every score in the file.

## 2. The score

`method = "hier"` (`.np_hier_score`). Two terms:

```
score = 0.60 · s_name  +  0.40 · geo
```

where the geo term takes the **strongest confirmed granularity**, not a sum:

```
geo = max( 1.00·zip9,  0.95·street,  0.90·zip5,  0.90·pobox,
           0.55·zip3,  0.50·city,    0.20·state )
```

`max` is deliberate. Correlated address fields cannot double-count, and a wrong
city cannot pull down a ZIP-confirmed match. The score also degrades gracefully
as geo fields go missing, which matters because grant addresses are frequently
a lockbox or nothing at all.

`street` fires only on street number **and** street body ≥ 0.9 and not a PO box;
`pobox` on a PO box with matching number.

### Three adjustments applied after the base score

1. **State-conflict gate.** When both states are known and differ, `city` and
   `zip3` credit are zeroed. A shared city *name* across states is a coincidence
   of naming (Patterson LA / Patterson NC), and a ZIP3 is an SCF region inside
   one state, so a cross-state ZIP3 "match" means one side is wrong. Ungated,
   such a pair scored `0.6·1.0 + 0.4·0.5 = 0.80` and auto-accepted — this was
   the whole remaining cross-state false-positive channel on the 990-PF
   benchmark.

2. **Distinctive-name promotion.** An exact name match (≥ 0.95) on a name that
   is *rare* in the reference (`name_freq` ≤ 3) is floored to **0.90** when the
   state agrees and **0.72** when it does not. Rationale: an exact match on a
   rare legal name is trustworthy without address corroboration; cross-state
   exact-name-only is near a coin flip (~40%), so it lands in MAYBE for review
   rather than auto-accepting. Restricted to matches made on the **primary**
   name (`distinct_name_main_only`) — a DBA is often a short generic trade name
   whose rarity says nothing, and it is not what `name_freq` measured.

3. **Token-overlap cap.** A match found *only* by containment/acronym recovery
   is capped **below YES** and floored to MAYBE when strong (≥ 0.80). Token
   overlap cannot separate a parent from its subsidiary, auxiliary or chapter —
   even distinctive full containment is ~1-in-4 correct on the labelled set. So
   it recovers a false negative into review but never auto-accepts.

## 3. Vetoes

`np_veto()` applies `np_default_rules()` before selection.

| rule | severity | fires when |
|---|---|---|
| `number_conflict` | hard | embedded numbers disjoint (chapter / local / district #) |
| `ordinal_conflict` | hard | FIRST vs SECOND … |
| `direction_conflict` | hard | SOUTHWEST vs SOUTHEAST … |
| `forprofit_form` | hard | query legal name ends LLC / LP / LLP / PLLC |
| **`affiliate_suffix`** | **soft** | candidate's last token is FOUNDATION / ENDOWMENT / AUXILIARY / BOOSTERS, the query lacks it, and the name match is ≥ 0.95 |
| `government_entity` | soft | query is a municipality / special district / authority |

Hard removes the pair. Soft caps it at MAYBE.

**`affiliate_suffix` is the operating-arm problem in veto form** — it fires on
exactly the `X FOUNDATION` candidate when the grant says `X`. This is why, in
the dyad promotion audit, 0% of *kept* candidates carried a soft veto against
**64% of dropped** ones: `pf_dyad_collapse(policy = "operating")` and
`affiliate_suffix` identify the same candidate by different routes. See
`dev/DYAD-FINDINGS.md` §4.

Note that `np_tier()`'s own documentation gives "a generation marker on one side
only" as its soft-veto example. That is `JR` / `SR` — person-name generational
suffixes inherited from npmatch's SAM/person-matching heritage
(`.np_gen_rank <- c(JR = "2", SR = "1")`). It essentially never fires on
organisation names and is **not** an org-type flag.

## 4. The cascade: 11 passes, cheapest first

`pf_staged_passes("lean")` + `pf_recovery_passes(state = TRUE)`. Each pass
blocks differently; **a query resolved to YES leaves the pending set**, so each
successive, more expensive pass sees only what earlier ones could not settle.

| stage | pass | blocking key | 978-identity run: candidates → resolved |
|---|---|---|---|
| **A** exact, state-blocked | `A1-name-zip5` | name + ZIP5 | 781 → 307 |
| | `A2-name-state` | name + state | 8,056 → 79 |
| | `A3-name-dba` | query name == ref dba, + state | 174 → 16 |
| | `A4-dba-name` | query dba == ref name, + state | 3 → 1 |
| | `A5-dba-dba` | dba == dba, + state | 0 → 0 |
| **B** token, state-blocked | `B1-token-state` | shared token + state | 56,442 → 65 |
| | `B2-token-concat` | + concatenated adjacent tokens | 121,738 → 5 |
| **C** unblocked sweep | `C1-name-any` | name == name, **any state** | 10,360 → 0 |
| | `C2-dba-any` | name == dba, any state | 323 → 0 |
| **D** recovery | `D1-acronym` | shared token incl. initials | 30,276 → 1 |
| | `D2-prefix` | 18-char name prefix (truncated names) | 11 → 0 |

Token passes are gated by `max_ref_freq` (25,000 same-state) and
`min_pair_idf` (8) so a common token cannot generate the whole reference.

**Read the shape, not just the totals.** Stage A resolves 403 of 405 on ~9,000
candidates. B, C and D spend ~219,000 candidates to resolve 71. That is what a
cascade is *for* — cheap passes take the easy mass — but it is also why `B2` and
`D1` are the first place to look if cost ever becomes binding.

## 5. Selection: three views

`np_select()` picks a winner three ways per query:

* **overall** — highest `score`
* **name** — highest `name_sim` (the JW name key)
* **addr** — highest `addr_sim` (mean of the address comparison columns)

`views_agree` records whether they concur — the same structure used on the
USASpending runs, and a cheap disagreement signal for review.

It also computes, per query:

```r
runner_up_score  = score of the second-best DISTINCT entity
overall_margin   = overall_score - runner_up_score
n_close          = candidates within tie_band (0.05) of the top
tie              = n_close >= 2
```

## 6. Tiering

```
score >= 0.78  ->  YES
score >= 0.65  ->  MAYBE
otherwise      ->  NO
```

with two demotions from YES to MAYBE:

* **`overall_margin < min_margin` (0.05).** If the second-best distinct entity
  scores within 0.05 of the winner, the grant is held for review. This is an
  *ambiguity brake*, not a quality judgement: the top pick may be excellent, but
  something else is nearly as good. Top 0.82 / runner-up 0.79 → margin 0.03 →
  MAYBE.
* **soft veto fired.**

`pf_status()` adds a fourth outcome, `OOS`, for grants excluded before matching
(foreign, individuals, government) — see `R/recipient-type.R`.

## 7. Where the dyad collapse sits

Entirely outside the above. It does not affect blocking, comparison or scoring.
Between `pf_drop_self_matches()` and `pf_status()` — the only point at which the
scored pairs still exist — `pf_dyad_collapse()` merges candidates *within one
grant's candidate list* that are disclosed as the same body, drops the losing
members from the pair set, and re-runs `np_select()` / `np_tier()`.

The re-run is the entire point, and it targets §6's margin brake specifically.
When the runner-up is the same organisation under a second EIN, that demotion is
an artefact: median margin on affected grants is exactly **0.000**. Removing the
phantom competitor lets the margin recover. 704 MAYBE→YES on the 50k run with
zero movement into NO. `dev/DYAD-FINDINGS.md`.

## 8. Configuration reference

Every tunable, with its default and where it acts:

| parameter | default | acts on |
|---|---:|---|
| `name_geo["name"]` / `["geo"]` | 0.60 / 0.40 | score composition |
| `geo_weights` | zip9 1.00, street 0.95, zip5 0.90, pobox 0.90, zip3 0.55, city 0.50, state 0.20 | geo sub-score |
| `jw_threshold` | 0.85 | floors every fuzzy similarity |
| `thresholds["yes"]` | 0.78 | tiering |
| `thresholds["maybe"]` | 0.65 | tiering |
| `min_margin` | 0.05 | YES → MAYBE demotion |
| `tie_band` | 0.05 | `n_close`, and the dyad collapse band |
| `tie_high` | 0.95 | when npmatch's own tiebreak applies |
| `distinct_name_maxfreq` | 3 | promotion eligibility |
| `distinct_name_floor` | 0.90 | promotion floor, same state |
| `distinct_name_floor_xstate` | 0.72 | promotion floor, cross state |
| `overlap_maybe_floor` | 0.80 | token-overlap MAYBE floor |
| `max_ref_freq` (state / any) | 25,000 / 5,000 | token blocking |
| `min_pair_idf` | 8 | token blocking |

**None of these have been tuned on 990-PF data.** They are npmatch defaults
carried over from SAM/USASpending. See `dev/OPTIMIZATION-PLAN.md`.
