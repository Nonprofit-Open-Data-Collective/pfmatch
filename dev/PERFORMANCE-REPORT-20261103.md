# Standardized performance report — 2026-11-03

    generated      2026-11-03 10:49:08, by hand; see §9 for the function this
                   should become
    R              4.5.1
    npnormalize    0.1.9
    npmatch        0.1.1.9000      np_signature_stamp() ABSENT (PR #35 unmerged)
    matchdb        0.1.1.9000
    pfmatch        0.1.0           main @ 955ecdd, work branch truth-shard-harness @ 4a9783b
    normalizer     v1-5e901add4a04a5d6      read, not quoted
    suite          887 pass / 0 fail / 1 skip, 25 files

The suite line was re-measured at `4a9783b` immediately before this file was
committed: the branch advanced by two commits (878 -> 887 tests) while the
report was being written, which is the §9 argument for generating this rather
than assembling it. The adjudication-side counts did not move: `grade` 60,
`round` 85, `shards` 94, `verdicts` 38, `status-convention` 17.

Every rate below carries a Wilson 95% interval from `pf_wilson()`, the
population it was measured on, the **grain** that population is counted at, and
one of three statuses. Nothing in this file is copied from an earlier note; the
figures were re-derived today from the logs and artifacts named against each
one, and the stack line above was read off this machine rather than quoted
(`dev/COMPARABILITY-PLAN.md` §5).

---

## 1. The three statuses, and why they cannot be mixed

| status | means |
|---|---|
| **MEASURED** | counted on a real population, against a real answer key where accuracy is claimed |
| **PROJECTED** | a measured rate multiplied by a count measured somewhere else |
| **UNMEASURED** | no answer key exists; any number here would be invented |

The failure this discipline exists to prevent is already on the record twice: a
clear rate read as an accuracy (`BASELINE-2026-10C` "What this baseline does NOT
establish"), and two runs joined on positional ids that returned base rates
(`dev/COMPARABILITY-PLAN.md` §1a). A report that prints a rate without its
status invites both.

**A clear rate is not an accuracy.** Nothing in §3 is adjudicated. YES means
the cascade placed the identity in its top tier, not that the EIN is right.

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
there is no safe automatic acceptance of the MAYBE tier (§4a).

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

### 4a. Automatic acceptance of MAYBE: tested twice, rejected twice

`dev/ADJUDICATION-PLAN.md` §1. The `ZIP5 agrees AND margin >= 0.05` rule
measured **18/18 = 100%** on the first 100-case sample, then **144/200 = 72.0%**
(CI 65 – 78) on 200 fresh labelled cases, with **37 = 18.5% outright WRONG**
(`dev/autoaccept-verdicts.csv`). 18/18 gives a 95% interval of 82 – 100, so the
true value sits *below* even that interval, because the second sample was drawn
from a different mix. 79% of the firing cases were `TOKEN_OVERLAP` matches,
which npmatch caps below YES deliberately.

**There is no automatic acceptance of the MAYBE tier.** A settled negative
result, not an open question — and the reason it is settled is that the failures
were *silent*, the same property that makes §4b's zero confident-and-wrong
verdicts the figure that matters there.

### 4b. LLM adjudication of MAYBE — MEASURED on 27 hand-adjudicated cases

`dev/ADJUDICATION-EXPERIMENT.md`, run 2026-10-31. Light = `claude-haiku-5-5`
(effort medium); deep = `claude-opus-5-5` (effort high, `web_search_20260209`,
`max_uses` 12). 100/100 verdicts both arms, no API failures.

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
what the ZIP5+margin rule could not do.

Inter-arm reliability: raw agreement 77%, chance 46.6%, **Cohen's κ = 0.570**
("moderate"). Where both named an EIN they agreed on *which* 89.4% of the time;
7 cases agreed on MATCH while naming different EINs — verdict concordance alone
would have scored those as agreement.

Every figure in §4b inherits the deep arm's ~7% error rate, because the deep arm
is the reference standard for the 68 cases that were not hand-adjudicated.

### 4c. The two structural flags — MEASURED, and below their floor

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
| deep-arm clearance of MAYBE | **70.7%** tie-adjusted, CI 59.4 – 81.9 | 47/68 raw = 69.12% (57.36 – 78.83), tie-corrected |
| benchmark clear rate after adjudication | 62.74% → **78.28%**, +15.5 pt (CI +13.1 to +18.0) | §3b × clearance |
| NO-residual recovery, if realized | +4.3 pt of clear rate | §3c |
| individual-payee flag fix | 69.0% → ~72.3% | `dev/NO-RESIDUAL-AUDIT.md` |
| Haiku on the whole MAYBE tier | $680 ($340 batched) | $0.000674/case × 1.01M |
| + Opus no-search on the flagged 18% | **~$6,175** (~$3K batched) | vs $68,355 for Opus-with-search on every MAYBE |

The MAYBE share is **the least certain input and the projection is linear in
it** — 22.0% is measured on one 4,748-identity sample of one population, and
§3a's frame puts it at 25.65% on a deliberately harder one.

Two costs these figures exclude, both pushing up: **per-use web search** (2.2
searches/case measured → ~399,000 searches on an 18% escalation), and **rate
limits rather than price** as the binding constraint — 1.01M calls at the
observed throughput is ~150 h of wall clock on one stream, which is the real
argument for the Batch API, the 50% discount being almost incidental.

---

## 6. UNMEASURED — and no figure may be invented for these

| quantity | why there is no number | tracked as |
|---|---|---|
| **Precision on the YES mass** | every row of `PF-TRUTH-V2.csv` came from a cell the pipeline itself produced, so it measures recovery of known-hard cases, not precision over the 62.74%. Needs a fresh stratified random sample, adjudicated. **No such sample exists.** | T11 |
| Accuracy of the stage-1 round | drawn and dealt, **not labelled** (§7) | T1, T2 |
| Confidence monotonicity on the enriched packet | the `ADJ-CAL-*` / `ADJ-EXP-*` rounds used the **unenriched** packet, so their confidence levels do not transfer | T3 |
| Whether evidence class discriminates | same reason | T4 |
| Layer accuracy per tier, on common cases | no common-case comparison exists | T5, T6 |
| Flag precision at usable n | §4c: 60 cases against a floor of 100 | T8 |
| Dollar-coverage curve | not re-derived since the v2 corpus | T9 |
| Batch API behaviour at ~10k | no pilot run | T10 |
| **The denominator itself** | ~37% of the NO residual are individual payees that arguably do not belong in it; removing them lifts both arms ~3 points | `NO-RESIDUAL-AUDIT.md` |

**The headline gap:** the pipeline's precision on its own top tier — 45.4% of
the production frame, 62.7% of the benchmark — has never been measured. Stage 1
is the round that would measure it, and it is unlabelled.

---

## 7. The labelling round — drawn, dealt, not labelled

| | |
|---|---|
| frame | 23,340 MAYBE identities of 91,008 (§3a) |
| drawn | **400**, seed 20261102, 14 strata (`tier · pass · purpose`) |
| population / frame_id / normalizer | `cb3c78ff0f1a9546` / `89a2a597ed0ea128` / `v1-5e901add4a04a5d6` |
| dealt | 8 shards of 50 primaries + 40 blinded overlap (10%), seed 20261103 |
| key | `data-dev/round-stage1-key/SHARD-KEY.csv` — **not** to be given to a labeler |
| **labels written** | **0 of 440 rows.** All eight `shard-NN-truth.csv` templates hold ids and blank verdict cells. |

Drawn dollars $146,301,632; median identity $5,000. Margin band tie/narrow/clear
143/117/140; dollar quartiles 123/95/95/87.

Two passes are **absent at any round size**, not under-sampled: the MAYBE tier
holds 11 `A4-dba-name` and 3 `D2-prefix` identities in total, whose proportional
share of 400 is 0.18 and 0.05. A per-pass accuracy claim for either is
unavailable at any n.

Proportional allocation puts 219 of 400 in `B1-token-state` and 50 in the next
pass. **Stage 1 is not sized to compare passes**; it reads the realized
confidence and evidence-class distribution (PREREQS §6b.1c), and the per-arm
comparison is stage 2's with floors set from what stage 1 shows.

Ids are now content-derived — `PFI-<16 hex>` from `pf_identity_id()`, the hash
of the identity's smallest exact dedup key — so a label can no longer re-attach
to a different organisation. The redraw after the rekey picked **the same 400
identities**.

---

## 8. Defects that bound every figure above

| | status |
|---|---|
| `REF-augmented.rds` is missing `name_acro`, `name_pre`, `name_is_acro`, so `D1-acronym` and `D2-prefix` run against absent columns unless the caller goes through `pf_run_batches()` (which rebuilds them in 197.5 s) | **open**; `pf_check_schema()` built (detects it), bundle not yet completed — COMPARABILITY-PLAN step 2 |
| the script that built the current reference **is not in the repo**, so the reference is not reproducible | **open** |
| `TRI-V2-MATCH-20261025-prestack.rds` records no normalizer, reference or config, so no difference between the Oct and Nov runs is attributable | **not retroactively fixable** |
| `npmatch` PR #35 unmerged — `np_signature_stamp()` absent from the install, confirmed live today; its DESCRIPTION pin is a release behind | **open** |
| grant-**row** ids are still positional when a file carries no key of its own (`pf_prepare_grants()`) | **open by choice** — changing it would invalidate labels already written against those ids |
| `C2-dba-any` matches on `name_key` ≤ 4 chars in 46.3% of cases | **open**, `dev/C2-DBA-ANY-20261103.log` |
| `pf_consistency()` — the one ground-truth-free metric — has **zero test coverage** | **open** |
| for 7 of 100 cases the close band holds more candidates than the packet's `k = 5` shows (41, in one case), so a `NONE` may mean "not in the five" | **open** |

---

## 9. What this report should become

The adjudication library already holds every piece this document assembles by
hand: `pf_wilson()`, `pf_status()`, `pf_result_tiers()`, `pf_crosstab()`,
`pf_report()`, `pf_evaluate()`, `pf_grade_verdicts()`, `pf_grade_by()`,
`pf_grade_layers()`, `pf_consistency()`, `pf_population_id()`,
`pf_identity_id()`, `pf_frame_id()`, `pf_check_schema()`. Assembling them by
hand is what makes a table go stale within the week —
`dev/COMPARABILITY-PLAN.md` §6 is two documents that already did.

A `pf_performance_report()` therefore has **three hard requirements** that
`pf_report()` does not currently meet:

1. **It must take a stamped frame, not an artifact.** `pf_report()` requires a
   `pf_match`; the production run is `list(status, grants)` and cannot be passed
   to it at all. This is the same shape problem `pf_round_sample()` had to
   solve. The right input is COMPARABILITY-PLAN step 4's `pf_eval_frame()`,
   carrying `population`, `frame_id` and `normalizer` as attributes — so the
   report **cannot be generated from an unstamped frame**.
2. **Every rate must carry its status.** MEASURED / PROJECTED / UNMEASURED, from
   the computation rather than from a hand annotation: a rate with no answer key
   joined to it is UNMEASURED by construction, and the report prints that word
   instead of a number. A report that silently omits §6 is worse than no report,
   because the gap it hides is the precision claim.
3. **Grain and population must be printed beside every count.** §3a and §3b
   differ by 17 points for reasons that have nothing to do with pipeline
   quality, and a report that stacks them in one table manufactures a
   regression.

**Order of work**, following COMPARABILITY-PLAN §7 rather than cutting across
it: `pf_eval_frame()` (step 4) → `pf_stack()` (step 6, which replaces this
file's header block) → `pf_performance_report()` on top of both. Building the
report first would mean writing the artifact-joining code that step 4 exists to
delete.

---

## 10. Provenance

| | |
|---|---|
| tier counts §3a | `dev/TRI-V2-BUILD-20261103.log`, four batch lines summed, reconciled to 91,008 |
| population filter §3a | `dev/build-triangulation-v2.R:56-60`, read today |
| benchmark §3b | `dev/BASELINE-2026-10C/MANIFEST.md` + its 2026-11-02 addendum |
| NO residual §3c | `dev/NO-RESIDUAL-AUDIT.md`, run 2026-10-22 |
| adjudication §4b | `dev/ADJUDICATION-EXPERIMENT.md` "Results, 2026-10-31"; `dev/ADJ-EXP-RESULTS.log` |
| flags §4c | `dev/ADJ-ROUND-STAGE1-20261102.log` §4 |
| corpus §2 | `dev/EFILEPF-DEDUP.log`, `dev/FULL-01-PREPARE.log` (2026-08-22) |
| round §7 | `dev/ADJ-ROUND-STAGE1-20261103.log`, `dev/ADJ-ROUND-STAGE1-DEAL-20261103.log`; templates counted on disk today |
| defects §8 | `dev/COMPARABILITY-PLAN.md`, `dev/C2-DBA-ANY-20261103.log`; test coverage grepped today |
| all Wilson intervals | `pf_wilson()`, computed today |
| stack header | read live via `packageVersion()` and `npmatch::np_normalize_signature()` |
