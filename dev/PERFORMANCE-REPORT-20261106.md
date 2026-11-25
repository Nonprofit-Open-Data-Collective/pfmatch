# Standardized performance report — 2026-11-06

    generated      2026-11-06 14:15, by hand; see §9 for the function this
                   should become
    R              4.5.1
    npnormalize    0.1.9
    npmatch        0.1.1.9000      RemoteSha 169ba81, built 2026-11-03 00:38 UTC
                                   np_signature_stamp() ABSENT from this install
                                   upstream main is 8b2d92e -- five merged PRs ahead
    matchdb        0.1.1.9000
    pfmatch        0.1.0           main @ 1b2c485
                                   work branch overlap-dealt-not-sampled @ 4bb832b
    normalizer     v1-5e901add4a04a5d6      read, not quoted
    suite          1048 pass / 0 fail / 1 skip, 25 files

**This supersedes `dev/PERFORMANCE-REPORT-20261103.md`** (commit `9fe7c84`,
cherry-picked into this branch as `373e700`, then renamed to this file). That
report was three days old and wrong in four places. §11 names them. The
largest correction is structural rather than numeric: the round it called
*unlabelled* is now labelled, by models, and three statuses were not enough to
say what that is worth.

The suite line was re-measured today: 1048 tests against the 887 the Nov-3
header recorded, the growth almost all in `test-shards.R` (94 → 242) from the
dealt-overlap work. Adjudication-side counts now: `grade` 60, `round` 85,
`shards` 242, `verdicts` 38, `status-convention` 17.

Every rate below carries a Wilson 95% interval from `pf_wilson()`, the
population it was measured on, the **grain** that population is counted at, and
one of four statuses. The stack line above was read off this machine rather
than quoted (`dev/COMPARABILITY-PLAN.md` §5).

---

## 1. The four statuses, and why they cannot be mixed

| status | means |
|---|---|
| **MEASURED** | counted on a real population, against a **human** answer key where accuracy is claimed |
| **MEASURED-vs-MODEL** | counted on a real population against labels a **model** wrote. A real measurement of the pipeline; the error rate of its own denominator is **unpriced** |
| **PROJECTED** | a measured rate multiplied by a count measured somewhere else |
| **UNMEASURED** | no answer key of any kind exists; any number here would be invented |

The Nov-3 report had three. The fourth exists because of what happened in the
three days since: 400 cases went from unlabelled to labelled by five model
labelers, which produced the first precision figure the MAYBE tier has ever
had (§4b) — and collapsing that into MEASURED would claim an error rate the
round cannot support, while leaving it in UNMEASURED would discard a real
measurement. Both are wrong, so there are four statuses.

The failure this discipline exists to prevent is already on the record twice: a
clear rate read as an accuracy (`BASELINE-2026-10C` "What this baseline does NOT
establish"), and two runs joined on positional ids that returned base rates
(`dev/COMPARABILITY-PLAN.md` §1a). A report that prints a rate without its
status invites both.

**A clear rate is not an accuracy.** Nothing in §3 is adjudicated. YES means
the cascade placed the identity in its top tier, not that the EIN is right.

**Model agreement is not accuracy either.** Two labelers sharing a training
distribution and a web-search tool are wrong together, and nothing inside the
round can see it. The only instrument that converts §4b into an error rate is
the hand-labelled slice, which holds **0 of 40** labels (§7).

---

## 2. Scope accounting — the corpus

Grain matters more than any single figure here: a rate over grant **rows** and
the same rate over deduplicated **identities** are different quantities, and the
collapse between them is 3.72x.

| | n | source | status |
|---|---:|---|---|
| grant rows, raw | 17,560,767 | `dev/EFILEPF-DEDUP.log` | MEASURED |
| after amended-return dedup | **17,253,199** | same; confirmed live by `dev/TRI-V2-BUILD-20261103.log` ("chunk 9 17,253,199 scanned") | MEASURED |
| in scope at 98.8% | 17,041,111 | rate from `dev/FULL-01-PREPARE.log` (12,559,051 → 12,404,667) | PROJECTED |
| in-scope identities at 3.72x | **~4,585,000** | same log: 3,337,585 identities on 12.40M in scope | PROJECTED |

The 3.72x is a **floor**, not a point estimate: collapse rises with corpus size
because more rows mean more repeated names, so ~4.59M over-states the identity
count and the cost projections in §5 therefore err high. The superseded 1.8x
from `dev/measure-dedup.R` would have given 9.47M and is wrong.

---

## 3. Tier distribution — MEASURED, but on three different populations

This is the section most likely to be misread, so each population is stated
before its numbers. **These three are not three measurements of one thing.**
Unchanged from the Nov-3 report; the four batch lines were re-summed today.

### 3a. The production triangulation run — the largest frame that exists

`data-dev/TRI-V2-MATCH.rds`, built 2026-11-02 22:02 → 2026-11-03 02:14,
240.9 min (0.159 s/identity), rekeyed in place the same day.

    population  cb3c78ff0f1a9546
    frame_id    89a2a597ed0ea128
    normalizer  v1-5e901add4a04a5d6
    reference   REF-augmented.rds, 3,880,431 rows
    grain       deduplicated recipient identities

| tier | n | share | Wilson 95% |
|---|---:|---:|---|
| YES | 41,341 | **45.43%** | 45.10 – 45.75 |
| MAYBE | 23,340 | **25.65%** | 25.36 – 25.93 |
| NO | 26,327 | **28.93%** | 28.63 – 29.22 |
| OOS | 0 | 0% | — |
| **total** | **91,008** | | |

Summed from the four batch lines in `dev/TRI-V2-BUILD-20261103.log`; the
components reconcile to 91,008 exactly and MAYBE agrees with the 23,340 the
stage-1 draw reports independently.

> **This 45.43% is not a corpus clear rate and must never be quoted as one.**
> The population is drawn from `GROUP-INDEX.rds` filtered to `n_names > 1` —
> address groups where **one address carries two or more distinct recipient
> names** — with PO boxes dropped and groups of 25+ names dropped as fiscal
> sponsors and DAF custodians (`dev/build-triangulation-v2.R:56-60`). It is
> deliberately enriched for the hardest thing the matcher does. A frame selected
> for name ambiguity should clear *worse* than the corpus, and it does, by about
> 17 points.
>
> `OOS 0` is the same story: the draw pre-filters to in-scope identities, so the
> out-of-scope class never enters. The benchmark in §3b has a real OOS class
> (4,748 scored of 4,868 in scope). Comparing a clear rate across the two
> without saying that is the `pf_result_tiers()` / `pf_status()` convention
> hazard `R/report.R:102-145` documents.
>
> **Everything in §4b is measured on this frame**, so every precision figure in
> this report inherits the enrichment too.

### 3b. The frozen 1k benchmark — the comparable, random-population figure

`dev/BASELINE-2026-10C`, frozen 2026-10-31. Population `efv2_1k`, 4,903 grants,
population id `0b5126ef02f2a8b0`. Grain: identities in the result frame.

| arm | identities | YES | MAYBE | NO | clear rate | Wilson 95% |
|---|---:|---:|---:|---:|---:|---|
| active | 4,687 | 2,667 | 986 | 1,034 | **56.90%** | 55.48 – 58.31 |
| augmented | 4,748 | 2,979 | 1,044 | 725 | **62.74%** | 61.36 – 64.11 |

Augmented arm by tier: MAYBE **21.99%** (20.83 – 23.19), NO **15.27%**
(14.27 – 16.32).

**Reproduced exactly** on 2026-11-02 under normalizer `v1-d49b18cc81ab79fb`,
two signatures on from the one it was frozen under: 2,979 / 1,044 / 725 on the
same 4,748-row frame, not one identity moved
(`dev/BENCH-MD-AUGMENTED-20261102.log`). The active arm was **not** re-run and
the two matchdb tiers **could not be** — their published bundles predate the
current normalizer and matchdb declines to serve them. So on today's normalizer
this benchmark has **one confirmed arm, not three**.

YES+MAYBE is 84.73% augmented and 77.94% active. **That is not a clear rate**:
there is no safe automatic acceptance of the MAYBE tier (§4a), and §4b now puts
a number on how far from safe.

### 3c. The NO residual — what survives both references

100 identities drawn from the 592 that are NO under *both* references, 12.2% of
4,869 identities. Internet-audited 2026-10-22, `dev/NO-RESIDUAL-AUDIT.md`.

| | n of 100 | Wilson 95% | of the 592 |
|---|---:|---|---:|
| **recoverable in pfmatch** | 35 | 26.36 – 44.75 | ~207 |
| — of which, a real organisation missed | 32 | 23.67 – 41.66 | ~189 |
| genuine floor | 59 | — | ~349 |
| unresolved | 6 | — | ~36 |

The residual is a **name-resolution problem, not an absence problem**: all 21
EINs established independently of the reference were present in *both*
references. Zero missing from the BMF, zero from matchdb.

---

## 4. Accuracy — what has an answer key

Read the status column before the number. §4a, §4e and §4f are measured against
**hand** labels. §4b, §4c and §4d are measured against labels **models** wrote,
and they are the new material in this report.

### 4a. Automatic acceptance of MAYBE: tested twice, rejected twice — MEASURED

`dev/ADJUDICATION-PLAN.md` §1. The `ZIP5 agrees AND margin >= 0.05` rule
measured **18/18 = 100%** on the first 100-case sample, then **144/200 = 72.0%**
(CI 65 – 78) on 200 fresh labelled cases, with **37 = 18.5% outright WRONG**
(`dev/autoaccept-verdicts.csv`). 18/18 gives a 95% interval of 82 – 100, so the
true value sits *below* even that interval, because the second sample was drawn
from a different mix. 79% of the firing cases were `TOKEN_OVERLAP` matches,
which npmatch caps below YES deliberately.

**There is no automatic acceptance of the MAYBE tier.** A settled negative
result, not an open question — and the reason it is settled is that the failures
were *silent*, the same property that makes §4e's zero confident-and-wrong
verdicts the figure that matters there.

### 4b. The cascade's pick precision on MAYBE — MEASURED-vs-MODEL

**New since Nov 3, and the most consequential figure in this report.** All 400
stage-1 cases are labelled (§7). `dev/ROUND-STAGE1-READOUT-20261103.log`.

    population  cb3c78ff0f1a9546      the §3a frame -- enriched for name ambiguity
    grain       deduplicated recipient identities
    truth       five model labelers, no human label in the denominator

| | n | rate | Wilson 95% |
|---|---:|---:|---|
| **pick precision** | 189 / 389 | **48.59%** | 43.7 – 53.5 |
| on the looser denominator (an org was found at all) | 189 / 318 | 59.43% | 54.0 – 64.7 |

The denominator drops 11 `UNRESOLVED` cases. That drop can move the headline by
at most **2.75 points** in either direction — all-wrong gives 189/400 = 47.25%,
all-right 200/400 = 50.00% — so the figure is not an artifact of who was
excluded.

Verdicts over all 400 cases:

| verdict | n | share | Wilson 95% |
|---|---:|---:|---|
| `ORG_FOUND` | 318 | 79.50% | 75.3 – 83.2 |
| `NO_ORG_NOT_EXEMPT` | 35 | 8.75% | — |
| `NO_ORG_UNFINDABLE` | 25 | 6.25% | — |
| `NO_ORG_INDIVIDUAL` | 11 | 2.75% | — |
| **any `NO_ORG_*`** | **71** | **17.75%** | 14.3 – 21.8 |
| `UNRESOLVED` | 11 | 2.75% | 1.5 – 4.9 |

**17.75% of the MAYBE tier has no exempt organisation to match at all.** Those
are false positives, not wrong picks among real candidates, and better scoring
does not touch them — only not blocking on the key that produced them does.

By the cascade's own blocking pass, which makes these *its* cells rather than
the round's strata:

| pass | n | right | rate | Wilson 95% | usable |
|---|---:|---:|---:|---|---|
| `A1-name-zip5` | 49 | 34 | **69.39%** | 55.5 – 80.5 | yes |
| `D1-acronym` | 8 | 5 | 62.50% | 30.6 – 86.3 | no, n<20 |
| `A3-name-dba` | 5 | 3 | 60.00% | 23.1 – 88.2 | no, n<20 |
| `B1-token-state` | 222 | 111 | **50.00%** | 43.5 – 56.5 | yes |
| `A2-name-state` | 32 | 16 | 50.00% | 33.6 – 66.4 | yes |
| `C1-name-any` | 48 | 17 | **35.42%** | 23.4 – 49.6 | yes |
| `B2-token-concat` | 25 | 3 | 12.00% | 4.2 – 30.0 | superseded by §4c |

`A1-name-zip5` and `C1-name-any` do not overlap at 95%: the cascade's strongest
and weakest usable passes are separated, which is the first direct evidence that
the ordering of the passes means something.

The draw allocated 50 / 32 / 5 / 225 / 26 / 54 / 8 to those seven passes
(`data-dev/ADJ-ROUND-STAGE1.csv`, read today); the gap to the scoreable n above
is exactly the 11 `UNRESOLVED` cases, 6 of them in `C1-name-any`.

Two passes carry **no figure at any round size**: the MAYBE tier holds 11
`A4-dba-name` and 3 `D2-prefix` identities in total. A third, `C2-dba-any`,
drew nothing at all (§8).

**A selection effect that must not be read as a model comparison.** The readout
also cuts the figure by which model produced the label — `pass1` (haiku, kept at
its own `high` confidence) 83/121 = 68.60% (59.9 – 76.2), `pass2` (fable, on the
escalated rest) 106/268 = 39.55% (33.9 – 45.5). That 29-point gap is **the
gate working, not fable labelling worse**: everything haiku was unsure about went
to fable, so `pass2`'s cases are the hard ones by construction. The cut exists
to show the gate did not bend the headline, and it does not.

### 4c. `B2-token-concat` — the one pass separated from its neighbour

**New since Nov 3.** `dev/B2-TOPUP-READOUT-20261103.log`. Stage 1 put 25
scoreable cases in `B2-token-concat` and they came back 3/25 = 12.0%, an
interval 26 points wide. A disjoint 50-case top-up was drawn from the same
frame under the same normalizer and labelled by the same model, so the two pool:

| | n | right | rate | Wilson 95% |
|---|---:|---:|---:|---|
| stage 1 | 25 | 3 | 12.00% | 4.2 – 30.0 |
| top-up | 46 | 17 | 36.96% | 24.5 – 51.4 |
| **pooled** | **71** | **20** | **28.17%** | 19.0 – 39.5 |

The pooled figure is **separated from `B1-token-state` at 95%** — 28.17%
(19.0 – 39.5) against 50.00% (43.5 – 56.5), intervals disjoint — so B2 is
genuinely worse than the pass it has to be told apart from, which is the
finding. Its 5 dropped `UNRESOLVED` cases bound it to 26.3% – 32.9% on the
full 76.

Of its 51 wrong scoreable cases, **17 carry a `NO_ORG_*` verdict**: a third of
B2's failures are false positives. By purpose band, 10/40 = 25% on stated
purposes against 10/31 = 32% on bare ones, so this is not one stratum.

That a cell moved from 12.0% to 28.2% on its own 51 additional cases is the
cleanest argument in this file for §9: a hand-assembled table publishes
whichever n it was written at.

### 4d. The cheap labeler against the expensive one — MEASURED-vs-MODEL

**New since Nov 3.** `dev/SHADOW-HAIKU-SHARD01-20261103.log`.
`claude-haiku-5-5` and `claude-fable-5-1` labelled the **same 92 cases** of
shard 01, both at effort high with up to 12 web searches.

| | n | rate | Wilson 95% |
|---|---:|---:|---|
| strict agreement | 72 / 92 | 78.26% | 68.8 – 85.5 |
| effective agreement | 73 / 92 | 79.35% | 70.0 – 86.4 |
| **same EIN where both found an organisation** | **60 / 60** | **100.00%** | 94.0 – 100.0 |

**No case in 92 had both resolve and disagree.** 19 of the 20 disagreements are
haiku *declining* what fable settled — a visible failure, not a silent one. And
haiku's own confidence separates the two outcomes cleanly:

| haiku's confidence | n | agrees with fable | Wilson 95% |
|---|---:|---:|---|
| high | 38 | **100.00%** | 90.8 – 100.0 |
| medium | 33 | 90.91% | 76.4 – 96.9 |
| low | 21 | **19.05%** | 7.7 – 40.0 |

This replicates §4e's confidence-orders-accuracy finding at n=92 against n=27,
and — unlike §4e — **on the enriched packet**, which is what `T3` asked for. It
is an agreement measurement, not an accuracy one.

`dev/gate-shard-truth.R` turned it into the round's labelling policy: accept
haiku's `high`, escalate everything else to fable. `medium` is **not** accepted
although it agrees 90.9%, because 9% disagreement entering a truth set is the
same contamination as putting a cheap labeler on the panel, arriving by a
cheaper route. Measured over shards 2–5:

| | n of 368 | share | Wilson 95% |
|---|---:|---:|---|
| accepted at `high` | 145 | 39.40% | 34.5 – 44.5 |
| **escalated** | **223** | **60.60%** | 55.5 – 65.5 |

**That 60.60% is the number §5's cost projection should be read against.** §4e
priced a cascade at an 18% escalation rate, measured on the *unenriched* packet
with a `low`-only gate. A `high`-only gate on the enriched packet escalates
three times as often. The two are different gates on different packets for a
different task, so 60.60% does not replace the $6,175 — but it fixes the sign of
the error, and the sign is up.

### 4e. LLM adjudication of MAYBE — MEASURED on 27 hand-adjudicated cases

`dev/ADJUDICATION-EXPERIMENT.md`, run 2026-10-31. Light = `claude-haiku-5-5`
(effort medium); deep = `claude-opus-5-5` (effort high, `web_search_20260209`,
`max_uses` 12). 100/100 verdicts both arms, no API failures. **These 27 are the
only hand-adjudicated cases anywhere in this report.**

| arm | strict accuracy | Wilson 95% | right EIN if hedged | confident-and-wrong |
|---|---|---|---|---|
| light | 22/27 = **81.48%** | 63.30 – 91.82 | 24/27 = 88.9% | **0/27** |
| deep | 25/27 = **92.59%** | 76.63 – 97.94 | 25/27 = 92.6% | 1/27 |

The intervals overlap heavily. **The ordering is the claim, not the 11.1-point
gap** — on n=27 that gap is three cases.

The light arm's self-reported confidence orders its own accuracy, which is what
makes a cascade possible:

| light confidence | n | agreement with deep | Wilson 95% | accuracy on the 27 |
|---|---:|---|---|---|
| high | 35 | **97.14%** | 85.47 – 99.49 | 12/12 = 100% |
| medium | 47 | 83.0% | — | 10/11 = 90.9% |
| low | 18 | **22.2%** | — | **0/4 = 0%** |

| policy | escalated | cost for 1,044 | accuracy on the 27 |
|---|---:|---:|---|
| light only | 0% | $0.70 | 81.5% |
| **escalate `low` only** | **18%** | **$13.44** | **96.3%** (26/27) |
| deep only | 100% | $71.45 | 92.6% |

Escalating the low-confidence 18% reaches deep-arm accuracy for a fifth of the
cost. The honest claim against deep-only is **parity, not superiority** — one
case at n=27. What makes the policy safe is the **zero** confident-and-wrong
verdicts in the cheap arm: its failures announce themselves, which is precisely
what the ZIP5+margin rule could not do, and what §4d saw again at n=92.

Inter-arm reliability: raw agreement 77%, chance 46.6%, **Cohen's κ = 0.570**
("moderate"). Where both named an EIN they agreed on *which* 89.4% of the time;
7 cases agreed on MATCH while naming different EINs — verdict concordance alone
would have scored those as agreement.

Every figure in §4e inherits the deep arm's ~7% error rate, because the deep arm
is the reference standard for the 68 cases that were not hand-adjudicated.

### 4f. The two structural flags — MEASURED, and below their floor

Computed on the 1,006-case dry-run frame (`dev/ADJ-ROUND-STAGE1-20261102.log`
§4). Neither flag exists in package code; `ADJUDICATION-PLAN.md` §7 step 4 is
unbuilt.

| flag | n | share of frame | Wilson 95% | T8 floor of 100 |
|---|---:|---:|---|---|
| `flag_arm_shape` | 156 | 15.51% | 13.40 – 17.87 | **met** |
| `flag_ntee_support` | 60 | 5.96% | 4.66 – 7.60 | **short** |

Overlap 31 cases. `pf_round_sample()` refuses a floor of 100 on a pool of 60 and
quotes the reason: at n=60 the interval is ~24 points wide. Correct refusal — T8
exists because 60% on n=15 cannot carry a decision, and 60% on n=60 cannot
either.

---

## 5. PROJECTED — measured rates on counts measured elsewhere

Each of these is a multiplication. None is a measurement.

| quantity | value | the two inputs |
|---|---:|---|
| MAYBE identities, full corpus | ~1,008,713 | 22.0% (§3b, one 4,748-identity sample) × ~4.59M (§2) |
| **right picks in the §3a MAYBE tier** | **~11,340 of 23,340** | 48.59% (§4b) × 23,340 — *same population as the measurement* |
| deep-arm clearance of MAYBE | **70.7%** tie-adjusted, CI 59.4 – 81.9 | 47/68 raw = 69.12% (57.36 – 78.83), tie-corrected |
| benchmark clear rate after adjudication | 62.74% → **78.28%**, +15.5 pt (CI +13.1 to +18.0) | §3b × clearance |
| NO-residual recovery, if realized | +4.3 pt of clear rate | §3c |
| individual-payee flag fix | 69.0% → ~72.3% | `dev/NO-RESIDUAL-AUDIT.md` |
| Haiku on the whole MAYBE tier | $680 ($340 batched) | $0.000674/case × 1.01M |
| + Opus no-search on the flagged 18% | **~$6,175** (~$3K batched) | vs $68,355 for Opus-with-search on every MAYBE |

The MAYBE share is **the least certain input and the projection is linear in
it** — 22.0% is measured on one 4,748-identity sample of one population, and
§3a's frame puts it at 25.65% on a deliberately harder one.

**No corpus-wide pick-precision projection is offered.** 48.59% was measured on
the §3a frame, which is selected for name ambiguity; multiplying it by a corpus
MAYBE count would manufacture exactly the comparison §3a's warning box forbids.
The one projection above stays inside the population it was measured on.

Three costs these figures exclude, all pushing up:

* **per-use web search** — 2.2 searches/case in the adjudication experiment, but
  the round measured **7.7/case** across its two passes (3,072 searches over 400
  cases), billed per search and in none of the dollar figures above;
* **the escalation rate** — §4d measured 60.60% at a `high`-only gate on the
  enriched packet against the 18% these projections assume;
* **rate limits rather than price** as the binding constraint — 1.01M calls at
  the observed throughput is ~150 h of wall clock on one stream, which is the
  real argument for the Batch API, the 50% discount being almost incidental.

For scale, what producing 400 truth labels actually cost (`dev/LABEL-*.log`,
token cost only, searches excluded):

| | cases | cost | per case |
|---|---:|---:|---|
| shard 01, fable throughout | 92 | $14.11 | $0.153 |
| shards 02–05, haiku pass 1 | 368 | $5.15 | $0.014 |
| shards 02–05, fable pass 2 | 223 | $45.23 | $0.203 |
| **the round** | **400** | **$64.49** | **$0.161** |
| B2 top-up (§4c), fable | 50 | $9.78 | $0.196 |
| shadow haiku (§4d), outside the round | 92 | $1.17 | $0.013 |

This is the cost of producing **truth**, not of adjudicating the corpus: a
truth labeler runs at high effort with a 18,256-character protocol prompt and
up to 12 searches, deliberately. It is here because it is the only
end-to-end-measured per-case cost in the project, and it is 240x the
$0.000674/case the §5 projection assumes for the cheap arm.

---

## 6. UNMEASURED — and no figure may be invented for these

| quantity | why there is no number | tracked as |
|---|---|---|
| **Precision on the YES mass** | every row of `PF-TRUTH-V2.csv` came from a cell the pipeline itself produced, so it measures recovery of known-hard cases, not precision over the 62.74%. Needs a fresh stratified random sample **of the YES tier**, adjudicated. **No such sample exists**, and no amount of MAYBE labelling produces one. | T11 |
| **The round's own truth error rate** | §4b, §4c and §4d are measured against model labels. The hand slice that would price them holds **0 of 40** (§7). This is the single open input to this whole report. | T1, T2 |
| Whether evidence class discriminates | the round records `basis` **web 446 / inference 12 / reference 2** of 460 rows — it barely varies, so it cannot discriminate anything | T4 |
| Layer accuracy per tier, on common cases | no common-case comparison exists | T5, T6 |
| Flag precision at usable n | §4f: 60 cases against a floor of 100 | T8 |
| Dollar-coverage curve | not re-derived since the v2 corpus | T9 |
| Batch API behaviour at ~10k | no pilot run | T10 |
| **The denominator itself** | ~37% of the NO residual are individual payees that arguably do not belong in it; removing them lifts both arms ~3 points | `NO-RESIDUAL-AUDIT.md` |

`T3` (confidence monotonicity on the enriched packet) **left this table** on
2026-11-03: §4d measures it at n=92, as agreement rather than accuracy.

**The headline gap, restated.** On Nov 3 it was that no tier had a precision
figure. The MAYBE tier now has one — 48.59%, against model truth. The **YES**
tier still has none: 45.4% of the production frame and 62.7% of the benchmark
sit on it, it is where the pipeline's output actually goes, and nothing in the
round touches it. T11 needs its own draw.

---

## 7. The labelling round — drawn, dealt, labelled by models; one gate open

| | |
|---|---|
| frame | 23,340 MAYBE identities of 91,008 (§3a) |
| drawn | **400**, seed 20261102, 14 strata (`tier · pass · purpose`) |
| population / frame_id / normalizer | `cb3c78ff0f1a9546` / `89a2a597ed0ea128` / `v1-5e901add4a04a5d6` |
| dealt | **5 shards × 92 rows = 460**, 60 cases (15%) to a second shard as the blinded overlap, seed 20261103 |
| overlap per labeler | **24, 24, 24, 24, 24** — clears `pf_labeler_agreement()`'s `min_n` of 20, so the per-labeler cut exists for this round and not only the pooled rate |
| key | `data-dev/round-stage1-key/SHARD-KEY.csv` — **not** to be given to a labeler |
| **labels written** | **460 of 460 rows, all 400 cases.** `data-dev/round-stage1-labelled/` |
| **hand slice** | **0 of 40.** `data-dev/round-stage1-handslice/shard-99-truth.csv` |

Drawn dollars $146,301,632; median identity $5,000. Margin band tie/narrow/clear
143/117/140; dollar quartiles 123/95/95/87.

**The deal changed on 2026-11-03** from 8 shards of 50 primaries plus a 10%
overlap to 5 shards of 92 with a 15% overlap, because the k=8 deal **sampled**
the overlap and landed 7 and 15 cases on two labelers against an expectation of
10 — below `min_n` on one of them, which would have left the per-labeler cut
unavailable. `pf_truth_shards()` now **deals** the overlap rather than sampling
it, which is what the branch name records. The superseded key is kept at
`data-dev/round-stage1-k8-superseded/` because three citations in `R/shards.R`,
its roxygen and `ADJUDICATION-PREREQS.md` §6b.6 point at that imbalance figure.

### How the 460 labels were produced

Five labelers, none of them human:

| shard | labeler | how |
|---|---|---|
| 1 | `claude-fable-5-1/truth-01` | fable on all 92 |
| 2–5 | `claude-haiku-5-5-high+claude-fable-5-1/truth-0N` | haiku on all 92, then the `high`-only gate of §4d; 223 of 368 escalated to fable |

Per-row provenance is kept in a `model` column beside the schema, which is what
lets §4b cut the figure by model at all. Without it the gated shards would be a
haiku/fable mixture reported as one number, against all-fable shard 1 — the
defect class `dev/METRIC-SHAPES.md` and `dev/PLAUSIBLE-WRONG-NUMBERS.md`
catalogue.

### The blinded overlap

| | n | rate | Wilson 95% |
|---|---:|---:|---|
| strict | 56 / 60 | **93.33%** | 84.1 – 97.4 |
| effective | 56 / 60 | 93.33% | 84.1 – 97.4 |

Per labeler, 22/24, 21/24, 23/24, 23/24, 23/24 — no labeler is an outlier. By
which models actually produced each pair: `pass2`-vs-`pass2` 33/36 = 92%
(one procedure run twice: run-to-run stability), `pass1`-vs-`pass2` 12/13 = 92%
and `pass1`-vs-`pass1` 11/11 = 100% (both n<20, cross-model). Three different
questions; **none of them is accuracy.**

### The hand slice — the open gate

`dev/TRUTH-LABELING-PROTOCOL.md` §6 step 4, drawn by `dev/draw-hand-slice.R`,
scored by `dev/grade-hand-slice.R`. 40 cases, assigned to **`jesse-lecy/hand-01`**,
**zero verdicts written.**

It is stratified **on the model's verdict** with floors on the small classes —
`ORG_FOUND` 24, `NO_ORG_NOT_EXEMPT` 5, `NO_ORG_UNFINDABLE` 5,
`NO_ORG_INDIVIDUAL` 3, `UNRESOLVED` 3 — because a simple random 40 would hold
one or two of each `NO_ORG_*` class and the model's *declines* are a quarter of
the measured error. A `slice_weight` per cell recovers the overall rate without
bias. Because the stratum is the model's answer, the design table and the model
labels live together in `HELD-slice-design-and-model-labels.csv`, which the
labeler does not open until their own 40 rows are done, and the cases are
written in shuffled order.

The labeler **labels, and does not score**. Reading a model's verdict and
marking it right or wrong is a *review*, and a review is the worst available
instrument here: the notes are well argued, a confident wrong answer with a
plausible chain is exactly the error being hunted, and a reviewer cannot find
the EIN the model never considered. It is the same principle that protocol's
§6 step 3 already
applies to the models — where two agreed, the consolidated row keeps the
**weaker** basis, because concurrence is not corroboration.

Everything else for the slice is on disk: the 40 shuffled cases, `SLICE-KEY.csv`,
the held file, and the grader. The 40 verdicts are the only input in this entire
report that cannot be machine-generated, because being independent of the models
is the whole of their value.

### Ids

Ids are content-derived — `PFI-<16 hex>` from `pf_identity_id()`, the hash of
the identity's smallest exact dedup key — so a label can no longer re-attach to
a different organisation. The redraw after the rekey picked **the same 400
identities**. `pf_read_truth()` refuses a label carrying an `R<k>` id.

---

## 8. Defects that bound every figure above

| | status |
|---|---|
| **the round's truth is model-produced and its error rate is unpriced** — §4b, §4c, §4d all rest on it | **open**; the instrument exists and holds 0 of 40 labels (§7) |
| `REF-augmented.rds` is missing `name_acro`, `name_pre`, `name_is_acro`, so `D1-acronym` and `D2-prefix` run against absent columns unless the caller goes through `pf_run_batches()` (which rebuilds them in 197.5 s) | **open**; `pf_check_schema()` built (detects it), bundle not yet completed — COMPARABILITY-PLAN step 2 |
| the script that built the current reference **is not in the repo**, so the reference is not reproducible | **open** |
| `TRI-V2-MATCH-20261025-prestack.rds` records no normalizer, reference or config, so no difference between the Oct and Nov runs is attributable | **not retroactively fixable** |
| `npmatch` is **five merged PRs behind** on this machine: #35 (`np_signature_stamp()`) merged 2026-11-03 04:21 UTC, the install is RemoteSha `169ba81` built 00:38 UTC the same day, and the function is still ABSENT | **changed since Nov 3** — this is now a reinstall (COMPARABILITY-PLAN step 3), not a merge |
| grant-**row** ids are still positional when a file carries no key of its own (`pf_prepare_grants()`) | **open by choice** — changing it would invalidate labels already written against those ids |
| `C2-dba-any` matches on `name_key` ≤ 4 chars in 46.3% of cases | **open**, `dev/C2-DBA-ANY-20261103.log`; note `C2-dba-any` drew **0 of 400** in stage 1 — verified in the draw, which holds 7 passes — so §4b says nothing about it. It held 5.7% of the MAYBE tier of the *superseded* Oct-25 frame; its share of the current frame is unmeasured |
| `pf_consistency()` — the one ground-truth-free metric — has **zero test coverage** | **open**, re-grepped today |
| for 7 of 100 cases the close band holds more candidates than the packet's `k = 5` shows (41, in one case), so a `NONE` may mean "not in the five" | **open** |

---

## 9. What this report should become

The adjudication library already holds every piece this document assembles by
hand: `pf_wilson()`, `pf_status()`, `pf_result_tiers()`, `pf_crosstab()`,
`pf_report()`, `pf_evaluate()`, `pf_grade_verdicts()`, `pf_grade_by()`,
`pf_grade_layers()`, `pf_labeler_agreement()`, `pf_read_truth()`,
`pf_consistency()`, `pf_population_id()`, `pf_identity_id()`, `pf_frame_id()`,
`pf_check_schema()`. Assembling them by hand is what makes a table go stale
within the week — and this file is now the third document to prove it, after the
two `dev/COMPARABILITY-PLAN.md` §6 names. It went stale in **three days**: §11.

A `pf_performance_report()` therefore has **four hard requirements** that
`pf_report()` does not currently meet:

1. **It must take a stamped frame, not an artifact.** `pf_report()` requires a
   `pf_match`; the production run is `list(status, grants)` and
   `pf_status()`'s opening `stopifnot(inherits(x, "pf_match"))` means it
   cannot be passed to it at all. This is the same shape problem
   `pf_round_sample()` had to solve. The right input is COMPARABILITY-PLAN
   step 4's `pf_eval_frame()`, carrying `population`, `frame_id` and
   `normalizer` as attributes — so the report **cannot be generated from an
   unstamped frame**.
2. **Every rate must carry its status**, from the computation rather than from a
   hand annotation: a rate with no answer key joined to it is UNMEASURED by
   construction, and the report prints that word instead of a number. A report
   that silently omits §6 is worse than no report, because the gap it hides is
   the precision claim.
3. **The status must distinguish a human answer key from a model one.** This
   requirement is new, and it is new because three days of labelling moved one
   quantity out of UNMEASURED into a status that did not exist. `pf_read_truth()`
   already carries the `labeler` of every row; whether any of them is human is a
   property of the truth table, so the status is **derivable** rather than
   annotated — which is the only version of it that survives the next round.
4. **Grain and population must be printed beside every count.** §3a and §3b
   differ by 17 points for reasons that have nothing to do with pipeline
   quality, and a report that stacks them in one table manufactures a
   regression. §4b's 48.59% is on §3a's enriched frame and is not a corpus
   figure, which is why §5 declines to project it.

**Order of work**, following COMPARABILITY-PLAN §7 rather than cutting across
it: `pf_eval_frame()` (step 4) → `pf_stack()` (step 6, which replaces this
file's header block) → `pf_performance_report()` on top of both. Building the
report first would mean writing the artifact-joining code that step 4 exists to
delete. Verified in `NAMESPACE` today: `pf_eval_frame`, `pf_compare_frames`,
`pf_stack`, `pf_performance_report` and `pf_add_recovery_keys` are all **absent**;
`pf_check_schema` is exported.

---

## 10. Provenance

| | |
|---|---|
| tier counts §3a | `dev/TRI-V2-BUILD-20261103.log`, four batch lines re-summed today, reconciled to 91,008 |
| population filter §3a | `dev/build-triangulation-v2.R:56-60` |
| benchmark §3b | `dev/BASELINE-2026-10C/MANIFEST.md` + its 2026-11-02 addendum, re-read today |
| NO residual §3c | `dev/NO-RESIDUAL-AUDIT.md`, run 2026-10-22 |
| **round pick precision §4b** | `dev/ROUND-STAGE1-READOUT-20261103.log` |
| **B2 pooling §4c** | `dev/B2-TOPUP-READOUT-20261103.log`, `dev/B2-TOPUP-RUN-20261103.log` |
| **cheap-vs-expensive labeler §4d** | `dev/SHADOW-HAIKU-SHARD01-20261103.log`; the gate policy and its reasoning in `dev/gate-shard-truth.R`; escalation counts in `dev/GATE-SHARDS2-5-20261103.log` |
| adjudication §4e | `dev/ADJUDICATION-EXPERIMENT.md` "Results, 2026-10-31"; `dev/ADJ-EXP-RESULTS.log` |
| flags §4f | `dev/ADJ-ROUND-STAGE1-20261102.log` §4 |
| corpus §2 | `dev/EFILEPF-DEDUP.log`, `dev/FULL-01-PREPARE.log` (2026-08-22) |
| **labelling costs and searches §5** | `dev/LABEL-SHARD01-FABLE-20261103.log`, `dev/LABEL-SHARD01-HAIKU-20261103.log`, `dev/LABEL-SHARDS2-5-HAIKU-20261103.log`, `dev/LABEL-SHARDS2-5-FABLE-PASS2-20261103.log`, `dev/B2-TOPUP-RUN-20261103.log` |
| draw and deal §7 | `dev/ADJ-ROUND-STAGE1-20261103.log`, `dev/ADJ-ROUND-STAGE1-REDEAL-20261103.log` |
| **hand slice §7** | `dev/draw-hand-slice.R`, `data-dev/round-stage1-handslice/README.md`, allocation read from `HELD-slice-design-and-model-labels.csv`; fill state counted on disk today |
| defects §8 | `dev/COMPARABILITY-PLAN.md`, `dev/C2-DBA-ANY-20261103.log`; `npmatch` install compared against upstream `main` today; test coverage re-grepped today |
| all Wilson intervals | `pf_wilson()`, computed today |
| stack header | read live via `packageVersion()`, `packageDescription()` and `npmatch::np_normalize_signature()` |

---

## 11. What changed since 2026-11-03, and why that is §9's argument

Four things, in a report that was three days old.

| § | the Nov-3 report said | today |
|---|---|---|
| 7 | "**0 of 440 rows.** All eight `shard-NN-truth.csv` templates hold ids and blank verdict cells." | 460 rows over 400 cases, **all labelled** — and the deal is 5 shards of 92, not 8 of 50, because the k=8 deal sampled the overlap and starved a labeler below `min_n` |
| 6 | "Accuracy of the stage-1 round — drawn and dealt, **not labelled**" under UNMEASURED | §4b, pick precision **48.59%** (43.7 – 53.5) — which needed a **fourth status** to state, because the truth is model-produced |
| 6 | "Confidence monotonicity on the enriched packet" under UNMEASURED (`T3`) | §4d, measured at n=92: high 100%, medium 90.9%, low 19.0% |
| 8 | "`npmatch` PR #35 **unmerged**" | merged 2026-11-03 04:21 UTC along with #36–#39; the **install** is five PRs behind, so it is a reinstall now |
| header | suite 887 pass | 1048 pass, `test-shards.R` 94 → 242 |

And one figure that moved inside the new material rather than correcting the old:
`B2-token-concat` was **12.0%** on stage 1's 25 cases and is **28.2%** pooled
over 71 (§4c). Nobody published the 12% — but a hand-written table would have,
because it was the only number available on the day the cell was first read.

That is the whole case for §9. Every one of these five rows is a figure that was
stated correctly, in a file that stamped its own date and provenance, and was
wrong within seventy-two hours. The defect is not carelessness; it is that a
hand-assembled report freezes the state of the work at the moment someone had
time to write it down, and the work does not stop. A generated report is wrong
for at most as long as it takes to re-run.
