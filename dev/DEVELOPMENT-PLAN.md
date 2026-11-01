# pfmatch development plan

Written 2026-08-20, consolidating the experiments of the last two days into
ordered phases. Supersedes the ad-hoc ordering in `dev/SCALE-PLAN.md` §7 and
`dev/ADJUDICATION-PLAN.md` §7, both of which remain accurate about their own
subjects.

**Revised 2026-08-20 (evening) to add Phase 0c, EIN dyads.** That work moved two
things already recorded below: the operating-arm problem now has a mechanism and
a measured fix, and the `pf_arm_order()` ordering policy has been promoted from
a cheap measurement to a blocking one, because it now governs auto-accepts
rather than only labels. See §"Phase 0c" and `dev/DYAD-FINDINGS.md`.

**Revised 2026-11-01 to add Phase 4b, the adjudication layers.** Phase 4 below
plans the MAYBE batch; Phase 4b is the wider question of which layer belongs on
which tier, now that the NO tier has been measured on two models
(`dev/NO-TIER-EXPERIMENT.md` §7) and a free deterministic layer exists beneath
both (`pf_fuzzy_recover()`). Two results there revise figures recorded
elsewhere in this file: the MAYBE cascade should escalate *without* web search,
and on the NO tier the cheap model's advantage is **1.73x on the full bill**
rather than the 5.1x token ratio, because search billing is the larger half of
the invoice.

## Where things stand

| tier | 5,000-grant benchmark | what is known about it |
|---|---:|---|
| YES | 56.4% | 99.8% state-consistent, 82.8% ZIP5. Treated as correct. |
| MAYBE | 20.1% | 63% contain the right EIN. No safe auto-accept rule exists (72% precision, measured twice). Text enrichment resolves 80% of hard cases. |
| NO | 21.9% | Candidate-generation failures plus genuine absences (government units, foreign, defunct). |
| OOS | 1.6% | Foreign only, after the recipient-type filter was narrowed. |

How the cascade actually works — comparisons, scoring formula, all eleven
passes, vetoes, tiering — is documented in `dev/CASCADE.md`. Every threshold in
it is an **npmatch default fitted on SAM/USASpending, not on 990-PF data**;
`dev/OPTIMIZATION-PLAN.md` says what is worth re-tuning and why the current
label set cannot support tuning a tier boundary.

Findings that shape everything below, each with its own memo:

* **Text enrichment is the largest available lever** — appending each candidate's
  NTEE description, 990 mission and program text resolves **45 of 56** hard MAYBE
  cases. `dev/ENRICHMENT-FINDINGS.md`.
* **No automated acceptance of MAYBE.** 72% precision on 200 labelled cases;
  independent verification upheld ~5 of 12 candidate-only labels.
  `dev/ADJUDICATION-PLAN.md` §1.
* **The operating-arm problem is the dominant structured error** and the cascade
  is at **27%** on it — worse than chance. `dev/AFFILIATION-FINDINGS.md`.
  **Now partly resolved**: collapsing disclosed substitutable pairs *before*
  selection removes the tie a grant has with itself and promotes **704 MAYBE
  grants to YES with no NO movement** on the 50k run. `dev/DYAD-FINDINGS.md`.
* **A transitive EIN cluster is not usable.** Connected components over the
  disclosure graph produce one component of **66,973 EINs across 56 states**.
  Direct edges only, and only after an exclusivity test — a bare Schedule A
  edge gives the YMCA Retirement Fund 905 "substitutable" partners.
  `dev/CLUSTER-FINDINGS.md` §2, `dev/DYAD-FINDINGS.md` §1.
* **The reference-side duplicate is bigger than the affiliation problem.**
  15.9% of the MAYBE tie band is two BMF rows carrying one name for one body
  (`Purdue University` twice); no disclosure can link an organisation to itself.
  `dev/CLUSTER-FINDINGS.md` §8.
* **Feature work should target ranking, not accepting**; the accept decision is
  label-limited, not feature-limited. `dev/FEATURE-ENGINEERING.md`.
* **The dev sampling design blocks a whole feature family.** Random grants means
  median 1 grant per filer. `dev/FUNDER-PROFILE-FINDINGS.md` §3.

---

## Phase 0 — consolidate and ship *(this session)*

1. Commit `R/affiliation.R`, `R/attached.R`, the `.datatable.aware` fix, and the
   seven findings memos.
2. `devtools::document()`, `R CMD check`, reinstall both packages.
3. Confirm the installed package reproduces the 5k benchmark.

**Exit criterion:** a clean tree and an installed `pfmatch` whose exported
surface matches the memos.

## Phase 0b — expand the reference before normalising

Added 2026-08-20. The reference is the ceiling on recall: a name the BMF does
not carry cannot be matched at any score. Three expansion stages, in order of
measured value. See `dev/CODE-AUDIT.md` sections 4-5.

| stage | source | adds | status |
|---|---|---|---|
| **1. Schedule I aliases** | `SI-P02-T01`, 2009-2024 | 2.45M observed names over 794,209 EINs; **+2.2 points** | **built** (`R/schedi.R`), not wired |
| **2. Schedule I EINs absent from the BMF** | same | ~15,800 after gating on `files_990 OR n_filers >= 2` | not built |
| **3. Form 990 filers absent from the BMF** | `F9-P00-T00-HEADER`, 2009-2024 | 22,604 in 2022 alone (4.1% of filers) | not built |

Gating rules that must survive into the implementation:

* **Corroboration is the only alias gate.** Precision runs 86.1% at one filer to
  99.0% at twenty. A token-overlap gate looks sensible and is wrong -- it
  discards acronyms and rebrands, which are the aliases worth having.
* **Exclude single-filer, single-mention, non-filing EINs.** 80.4% of the
  Schedule I EINs missing from the BMF are keying errors.
* **Guard group-ruling parents.** Some aliases attach a chapter name to a
  national EIN; `pf_group_siblings()` identifies those EINs and they need higher
  corroboration.
* **The alias justifies the match, not the name similarity.** The alias name
  enters the reference as its own row and is resolved by the existing exact-name
  pass. Scoring the query against the BMF *legal* name would veto the correct
  answer.

**Exit criterion:** one unified reference, with `row_source` recording where
each row came from, and the 5k benchmark re-run against it.

> **Cost, measured cleanly 2026-08-21.** The augmented unified reference costs
> **1.77x the monthly BMF for 2.02x the rows** — sublinear — and buys +43 YES
> per 1,000 identities. The recovery passes add 1.16–1.23x. Every combination is
> within budget (see Phase 1). **Use the augmented reference with all passes.**
>
> An earlier revision of this note claimed a 166x blocker. That was a
> `setDTthreads()` artefact in the benchmark harness — 6 threads in one
> diagnostic script, 14 in another — not a property of the reference.
> `dev/REF-PERFORMANCE.md` records the four wrong explanations and the real one.
>
> Separately: the reusable reference index (`ref_index` / `name_freq` /
> `token_idf`) is worth **~14x**, with identical results either way.

## Phase 0c — EIN dyads in the cascade

Added 2026-08-20. Full evidence in `dev/DYAD-FINDINGS.md`; the negative result
that shaped it is `dev/CLUSTER-FINDINGS.md`.

### The problem this solves

`np_tier()` demotes a YES to MAYBE whenever the margin to the runner-up falls
below `min_margin`. When the runner-up is **the same body under a second EIN** —
`EAGLE RANCH` and `EAGLE RANCH FOUNDATION` — that demotion is an artefact: the
grant is being held back for tying with itself. The median margin on affected
grants is exactly **0.000**.

### What is built

`R/dyads.R`, 41 tests in `tests/testthat/test-dyads.R`, table at
`data-dev/PF-DYADS-UNIFIED.rds`.

| | |
|---|---:|
| disclosed pairs (Sch A line 12g + Sch R Part II, 2009–2024) | 566,653 |
| **substitutable** | **29,230** |
| related | 537,423 |
| max substitutable degree | **5** |

### Three rules that are not negotiable

1. **Direct edges only, never a transitive closure.** Connected components give
   one component of 66,973 EINs across 56 states — 38% of the graph. A same-city
   gate does not fix it (407 EINs in Phoenix). `pf_dyad_collapse()` resolves
   groups *within one grant's candidate list*, which is what makes a per-batch
   collapse identical to a whole-file one.
2. **Substitution requires exclusivity, not merely a disclosed relation.** A
   bare Schedule A edge gave the *YMCA Retirement Fund* 905 substitutable
   partners; it supports 907 local YMCAs. 43% of Schedule A edges come from a
   supporter naming more than ten organisations. The mirror failure is the
   federated sibling — 337 `ALPHA LAMBDA DELTA` chapters share a name core.
   Both are degree, and the guards are `max_fanout = 3`, matching subsection
   codes, and `max_degree = 5`.
3. **Never collapse `related`.** It reports the *better* number (+983 against
   +704) by merging Mayo Fairmont with Mayo Lake City and the ACLU with its
   c(4). The unsafe variant is the one that flatters the metric.

### Measured effect, 50k run

| variant | grants merged | picks changed | MAYBE → YES | NO |
|---|---:|---:|---:|---:|
| **substitutable, operating-first** | 1,657 | 349 | **+704** | 0 |
| substitutable, keep-top | 1,657 | 311 | +398 | 0 |
| substitutable, arm-first | 1,657 | 558 | +258 | 0 |
| substitutable + related | 2,575 | 539 | +983 | +1 |

Promotions audited: 99% same city, 87% disclosed in 5+ tax years, 85% identical
name core, 4 of 704 sharing no content token (three of which are
`CARENET` / `CARE NET FOUNDATION`).

### Wiring

`pf_run_batches(dyads =)` runs the collapse between `pf_drop_self_matches()` and
`pf_status()` — the only point where the scored pairs still exist — and
`pf_link()` / `pf_run()` pass it through. Off when `dyads = NULL`.
**Changing `dyads` or `dyad_config` invalidates the batch checkpoints.**

### What this does *not* settle

The operating-vs-arm ordering policy. It rests on 15 adjudicated cases (60%,
CI 32–84%) and now governs 196 changed EINs among the promotions, and 446
promotions of difference between policies. The tier promotion is sound whichever
member truly received the money — the claim is "these are one body" — but which
EIN gets reported is not. **This moves recommendation 4 of
`dev/AFFILIATION-FINDINGS.md` from Phase 4 into the blocking path.**

### Confirmed against the augmented unified reference

**Exit criterion met**, on 1,000 grants / 978 identities against the 3,891,187-row
augmented unified reference (`dev/bench-dyad-1k.R`, `dev/BENCH-DYAD-1K.log`).
Three predictions were written down before the run:

| | prediction | result |
|---|---|---|
| 1 | promotions occur at a similar or higher rate than the 50k run's 6.5% of MAYBE | **9.5%** (19 of 200) |
| 2 | nothing is pushed into NO | **0**, in all three variants; every tier change on a collapsed identity |
| 3 | accuracy on the adjudicated answers does not fall | **77% → 77%** (10/13), operating-first and keep-top |

The dyad table itself was rebuilt on the unified BMF first
(`dev/build-dyads-unified.R`). It barely moved — 29,230 substitutable against
29,238, max degree 5 either way — even though BMF coverage of dyad EINs rose
from 62.6% to 88.9%. 753 pairs were promoted and 761 demoted: better coverage
adds name-core matches and subsection vetoes in almost equal measure. The guards
hold under a doubling of reference coverage.

### The `related` variant now has a measured cost, not just an argued one

| variant | YES | MAYBE | adjudicated accuracy |
|---|---:|---:|---:|
| baseline | 593 | 200 | 77% |
| operating-first | 612 | 181 | **77%** |
| keep-top | 609 | 184 | 77% |
| **+ related** | **620** | **173** | **54%** |

It promotes the most and is the only variant that **loses accuracy — 10 of 13
correct down to 7**. Until now the case against collapsing `related` rested on
inspection of the pairs it merges. It now rests on a measurement. Small n, so
the size of the drop is not established; the sign is.

## Phase 1 — the full-file production run

Input: `~/Documents/grants/2025_08_29_All_Years_990PFPart14Grants3A.csv`,
**12,559,051 grants**.

**Cost is not a blocker.** Measured 2026-08-21 on 1,000 identities, all threads,
idle machine (`dev/bench-cascade-clean.R`), for 12,559,051 grants **before any
dedup credit**:

| reference | passes | s per 1,000 | total | 12 shards |
|---|---|---:|---:|---:|
| monthly BMF | 9 | 128 | 445 h | 37 h |
| monthly BMF | 11 | 149 | 520 h | 43 h |
| augmented unified | 9 | 226 | 789 h | 66 h |
| **augmented unified** | **11** | **279** | **975 h** | **81 h** |

The worst combination is 81 h on 12 shards with no dedup at all, against a
117 h budget. Dedup — step 2 below — only improves it. **Run the augmented
unified reference with all passes.**

The 33.5 s per 1,000 figure this plan was written with came from the 2026-08-19
50k run and is 3.7x faster than anything reproducible today, for reasons left
open in `dev/REF-PERFORMANCE.md`. It changes no decision.

**Both packages must be installed first.** `npmatch` was stale and `pfmatch` was
not installed at all until 2026-08-21; every script here calls
`library(pfmatch)`.

**Depends on Phase 0c.** Running without `dyads =` forfeits the MAYBE→YES
promotions and, more importantly, produces a review queue containing thousands
of grants whose "ambiguity" is one body against itself. Pass the dyad table to
`pf_link()` on the first run rather than reprocessing later — the collapse needs
the scored pairs, which the batch checkpoints do not retain.

The naive cost is prohibitive — 33.5 s per 1,000 grants is **117 hours**
single-threaded. Two levers make it tractable, and both must be measured rather
than assumed:

| lever | outcome | how it is obtained |
|---|---|---|
| **dedup to distinct recipient identities** | **DONE 2026-08-22: 3.72x, 3,337,585 identities.** The expectation held — the dev samples understated it badly (1.002x on 1k, 1.323x on 100k) because random grant samples destroy the repetition dedup exploits | `pf_dedup()` + `pf_propagate_matches()` |
| ~~**parallel batches** — up to ~12x on 24 cores~~ | **withdrawn 2026-08-22: one shard fits** | `dev/SHARD-AND-COLLAPSE-FINDINGS.md` |

> ### The parallelism lever does not exist on this machine
>
> Measured 2026-08-22 (`dev/SHARD-AND-COLLAPSE-FINDINGS.md` §1). A shard at the
> production config peaks at **~37 GB of working set, flat in batch size** —
> 36.82 GB at 2,000 identities, 37.41 GB at 8,000. The reference bundle is
> 3.59 GB of that; the other ~33 GB is a fixed cost each process pays in full.
> On 68 GB that is **one concurrent shard**, at any batch size.
>
> "~12x on 24 cores" counted cores. The binding resource is memory, and every
> `/12 shards` figure in the table above should be read as `/1`.
>
> Cost also *rises* with batch size on the augmented reference — 366 s/1k at
> 2,000 against 433 at 8,000 — so there is no memory-for-speed trade to make.
> With dedup now settled at 3.72x (3,337,585 identities), one shard is
> **401 h** in the production config and **183 h** with B2-token-concat off.
> The budget is 117 h, so the run is 1.6–3.4x over and the dedup lever is spent.
>
> `dev/MEMORY-FINDINGS.md` locates the 33 GB: it is **transient churn inside
> `np_cascade()`**, not data anyone holds — the cascade peaks at 31 GB to return
> a 0.06 GB pair set, and no single pass exceeds 8.75 GB. Threads (1/4/14 all
> 31.2 GB), B2 (−1.15 GB) and the reference collapse (−10.5%) are all measured
> and all fail to buy a second shard. The one lever aimed at the mechanism —
> having the cascade reduce each pass before starting the next — is an npmatch
> change and would put peak near ~9 GB, i.e. six shards.
>
> The `(name, state, zip5)` reference collapse was built and tested as the fix
> and **is a null** — 7.9x off the blocking cost driver for 0% runtime — while
> manufacturing an 80-grant MAYBE→YES gain that is 88% converted abstention.
> §4 of the findings memo. Do not adopt it.
>
> What remains: re-decide **B2-token-concat** (2.18x faster for −1.55% of
> matches, and that trade reads differently at 406 h than at 67 h), establish
> the **full-file dedup ratio**, or add a second machine.

Order of work:

1. **Ingest and preprocess** the full file once; write a Parquet/RDS staging copy
   outside Dropbox.
2. **Dedup** and report the true collapse ratio. This number decides the schedule.
3. **Benchmark** one shard end-to-end with the production config to get an honest
   seconds-per-1,000 on *deduped identities*, not on grants.
4. **Run** all shards in parallel with per-shard checkpointing, so a failure costs
   one shard rather than the run.
5. **Propagate** matches back from identities to grants and write the tiered
   output.

**Exit criterion:** every grant carries a status and, where applicable, an EIN;
runtime and tier counts reported against the 5k benchmark.

## Phase 2 — the development databases

Written to `~/Documents/grants/` — deliberately outside Dropbox and outside the
package repo, because these are multi-gigabyte derived artefacts.

| file | contents | purpose |
|---|---|---|
| `PF-YES.parquet` | every YES grant with EIN, scores, match provenance | feature development; the silver-label pool |
| `PF-MAYBE.parquet` | every MAYBE grant with its full candidate set | adjudication development; the review queue |
| `PF-NO.parquet` | every NO grant with whatever candidates were surfaced | recall work; internet-search queue |
| `PF-OOS.parquet` | foreign and non-BMF recipients | reporting only |
| `PF-IDENTITIES.parquet` | the dedup crosswalk | joins everything back to grants |

Each also gets a compact CSV extract for quick inspection.

**Exit criterion:** the four partitions plus the crosswalk, with row counts that
reconcile to 12,559,051.

## Phase 3 — feature development on the partitions

Now possible for the first time, because the full file has intact filer
portfolios and every recipient's full appearance history.

1. **Recipient clustering across the whole file.** The same body appears under
   dozens of spellings across thousands of foundations. Cluster on name+geo over
   the YES partition, then use the cluster to propagate EINs into MAYBE and NO.
   This is the single most promising recall lever and it is only available at
   full scale.
   Two `pf_dedup()` defects must be fixed first, both of which only bind at
   full scale: `max_block = 2000` silently skips larger blocks (~500k of
   3.38M keys), and the per-pair accumulator grows a vector quadratically.
2. **Funder NTEE profiles with the entropy gate**, scored against a size-matched
   null rather than a flat threshold (`dev/FUNDER-PROFILE-FINDINGS.md` §2).
3. **Persistence** — year-over-year grantee overlap per filer. Untestable until
   now; a repeat grantee is a near-certain identity link.
4. **Grantee prior** — distinct funders per recipient EIN. Measured at 0.577 AUC
   overall but **0.877 and 76% top-1 on the 20% of grants where it fires**.
5. **Arm clusters** at scale — `pf_cluster_arms()` over the full candidate sets,
   with the Schedule A line-5 override. Now the *complement* of Phase 0c rather
   than a duplicate of it: the dyad table classifies pairs that appear in a
   filing and cannot invent them, and 273 of 752 known arm pairs have no filing
   at all. Name+geo remains the only route to those.
6. **Reference-side duplicate resolution.** 15.9% of the MAYBE tie band is two
   BMF rows with one name for one body, 45% of them co-located — `Purdue
   University`, `Johns Hopkins University`, `Memorial Sloan Kettering`, each at
   two EINs. This is **larger than everything the dyad table reaches (13.2%)**
   and no disclosure can address it, because an organisation does not file a
   relationship with itself. Either a canonical-row rule on the unified BMF or a
   same-EIN-body equivalence table. `dev/CLUSTER-FINDINGS.md` §8.

**Exit criterion:** each feature measured as pair AUC and fire-rate on the
adjudicated gold set, with the negative results recorded as carefully as the
positive ones.

## Phase 4 — adjudication

1. **Ship the enriched candidate packet** — `pf_candidate_frame()` gains NTEE
   description text, 990 mission and program descriptions for *every* candidate.
   Prototype exists in `dev/build-enriched-hard.R`.
2. **Label ~1,000 cases** on the enriched packet, with `NONE` as a first-class
   verdict and an evidence class (`QUOTE` / `NTEE` / `INFER` / `NONE`) on each.
   Stratify to over-sample arm pairs and restricted-gift purposes.
   **The arm-pair stratum is no longer a by-product — pull it forward.** Phase
   0c made the ordering policy govern 196 reported EINs on a 50k sample and 446
   promotions of difference between policies, on a 15-case basis. ~100 labelled
   arm pairs settle it and do not need the rest of the labelling round to
   finish. `data-dev/DYAD-PROMOTIONS.csv` is a ready-made sampling frame.
3. **Verify a stratified subsample independently** and report accuracy per
   evidence class. No accuracy claim ships without this step.
4. **Build the dollar-sorted review queue** — ~740 reviews cover 70% of the
   recoverable unresolved dollars at 50k scale; re-derive the number at full
   scale.
5. **Run the production adjudication through the Batch API, on the MAYBE tier
   only.** Both halves of that sentence are load-bearing.

   *MAYBE tier only*, because the dedup collapse and the tier filter are worth
   more than any model or pricing decision. Measured end to end
   (`dev/ADJUDICATION-EXPERIMENT.md`), at $0.000674/case for Haiku:

   | scope | n | cost |
   |---|---:|---:|
   | every grant row | 17,253,199 | $11,635 |
   | every unique identity | 4,585,061 | $3,092 |
   | **MAYBE identities only** | **~1,008,000** | **$680** |

   17.25M rows collapse to ~4.59M identities at the 3.72x measured in
   `dev/FULL-01-PREPARE.log`, and 22.0% of those route to MAYBE. Adjudicating
   the tier rather than the corpus is a 17x saving before a single prompt
   changes. Never submit the YES mass to a reviewer: it is not what MAYBE
   adjudication is for, and precision over YES needs its own stratified sample
   (`BASELINE-2026-10C/MANIFEST.md`).

   *Batch API*, because **rate limits bind long before price does.** The
   100-case run did 52 s at 6 concurrent workers; 1.01M calls at that observed
   throughput is ~150 h on one synchronous stream, spent mostly on 429
   back-off. The 50% discount ($680 → $340, and $8,107 → $4,054 for the
   cascade) is almost incidental next to not managing that. Batch supports
   structured outputs and prompt caching, which is what stage 01 depends on;
   results return in any order, so key by `custom_id` and never by position.

   Three things the batch path must carry over from the experiment.

   *Escalate on the cheap arm's own stated confidence* — high 12/12 and medium
   10/11 correct against known answers, low 0/4 — which puts ~18% into a second
   pass and reaches 96.3% against 92.6% for running the expensive arm over
   everything, at a tenth of the cost.

   *Escalate to Opus **without** web search.* The ablation
   (`PF_ADJ_NOSEARCH=1`, `dev/ADJ-EXP-ABLATION.log`) decomposes the two-arm gap
   into **+7.4 points of model and +3.7 points of search**, and the search step
   is one case in 27 (McNemar exact p = 1.000). Search costs +124% in tokens —
   it re-caches a growing prefix, writing 537,198 tokens against the no-search
   arm's 28,785 — plus per-use billing. Over the tier: **$6,175 without search
   against $12,984 with it and ~399,000 searches, for identical measured
   accuracy.** Search's real effect was on confidence (high 51% → 73%), not
   correctness, and the no-search arm actually cleared *more* (49/68 vs 47/68).

   *Keep a search tier for the residue, not the bulk.* It is the only
   configuration that can establish an answer is **absent**: 13 of the search
   arm's 18 NONEs are `CONTRADICTED` — the organisation was found and its EIN
   shown not to be among the candidates. A no-search NONE means "cannot tell
   from the packet" and still needs a human; a search NONE can be closed. Route
   what the cheap-plus-Opus pass cannot close to search, and budget per use.

   Blocked on nothing but Phase 1 producing the identities.

**Exit criterion:** a calibrated review process and the largest ground-truth set
the project has had.

## Phase 4b — the adjudication layers, and which one for which tier

Added 2026-11-01. Phase 4 above settles the MAYBE batch. This section is the
wider question it does not answer: **there are now four layers that can be put
between the cascade and a human, they have different costs and different
failure modes, and MAYBE and NO want different ones.** Every figure is printed
by `dev/adjudicate-18-layer-costs.R`; none is typed into this prose. Read
"What these numbers are not" at the end before quoting any of them.

### The four layers

| | layer | what it is | needs an API key |
|---|---|---|---|
| 0 | **character recovery** | `pf_fuzzy_recover()` — Jaro-Winkler inside a ZIP5 block, on the residual | no |
| 1 | **cheap packet review** | a small model reading the candidate packet only | yes |
| 2 | **deep packet review** | a large model reading the same packet, no web | yes |
| 3 | **deep search review** | a large or small model with `web_search` | yes, plus per-search billing |

They compose rather than compete: 0 changes what the packet *contains*, 1–3
change what is *concluded* from it. Layer 0 must run first, because a pair it
recovers is a pair layers 1–3 then get to see.

### The recommendation, in one table

| tier | recommended | why this one |
|---|---|---|
| **MAYBE** | layer 1 everywhere, escalate the cheap arm's own `low`-confidence 18% to **layer 2** | 96.3% (26/27) for **$6,016** over ~983,000 identities. Layer 3 reaches the same 26/27 for $16,541. Layer 2 everywhere is 92.6% for $29,742. |
| **NO** | **layer 3 with the cheap model**, `max_uses` capped | The answer is outside the packet in 100% of this tier, so layers 1–2 can only restate the cascade. Cheap-with-search recovers 33.0% against the large model's 36.3% and named the *same EIN* 31 times out of 31. |
| **both** | layer 0 first, always | Free, and it is the only layer whose bill does not scale with the corpus. |

**The MAYBE recommendation is to escalate *without* search, and that is the
non-obvious part.** The ablation (`PF_ADJ_NOSEARCH=1`) decomposes the two-arm
gap into **+7.4 points of model and +3.7 points of search**, and the search
step is one case out of 27 — McNemar exact p = 1.000. Search's one measurable
effect was on *confidence* (high 51% → 73%), not correctness, and the no-search
arm actually cleared **more** (49/68 against 47/68). So on this tier search
makes the model surer rather than righter, and that is not the thing being
bought.

### What each layer costs over the whole corpus

17,253,199 grant rows → 17,046,161 in scope → **4,582,301 identities** at the
3.72x collapse measured in `dev/FULL-01-PREPARE.log`. Tier shares are taken on
the **in-scope** denominator of 4,868, which puts MAYBE at ~983,000 and NO at
~795,000.

> A NO-tier budget built on `BASELINE-2026-10C`'s 725 NO under-counts the tier
> by 14%. Those 4,748 "identities" are the *result frame*; the 120 in-scope
> identities no blocking pass produced a pair for are simply absent from it, and
> they are the hardest retrieval failures in the file. The tier is 845.

| tier | arm | tokens | searches | search bill | total |
|---|---|---:|---:|---:|---:|
| MAYBE | layer 1 — cheap, packet only | $662 | 0 | $0 | **$662** |
| MAYBE | layer 2 — deep, packet only | $29,742 | 0 | $0 | **$29,742** |
| MAYBE | layer 3 — deep + search | $66,595 | 2,162,002 | $21,620 | **$88,215** |
| NO | layer 3 — cheap + search | $10,420 | 3,499,795 | $34,998 | **$45,418** |
| NO | layer 3 — deep + search | $53,213 | 2,545,306 | $25,453 | **$78,666** |

And the MAYBE cascade, which is the recommendation:

| policy | tokens | searches | total | accuracy on the 27 |
|---|---:|---:|---:|---|
| layer 1 only | $662 | 0 | $662 | 81.5% (22/27) |
| **escalate `low` → layer 2** | **$6,016** | **0** | **$6,016** | **96.3% (26/27)** |
| escalate `low` → layer 3 | $12,649 | 389,160 | $16,541 | 96.3% (26/27) |
| layer 3 everywhere | $66,595 | 2,162,002 | $88,215 | 92.6% (25/27) |

Escalation is keyed on **the cheap arm's own stated confidence**, which orders
its accuracy almost perfectly: high 12/12, medium 10/11, low **0/4**. That it
has *zero* confident-and-wrong verdicts is what makes the policy safe — its
failures announce themselves, which is exactly what the ZIP5+margin
auto-accept rule could not do (72% precise, §1 of `dev/ADJUDICATION-PLAN.md`).

### On the NO tier the model choice is not the cost driver

`dev/NO-TIER-EXPERIMENT.md` §7 reports the cheap arm as **5.1x cheaper, not
the 40x the sticker prices suggest**. That is the correct *token* ratio and it
was the honest number for what it measured. At tier scale it is not the bill:

| | tokens only | full bill |
|---|---|---|
| cheap vs deep | deep costs **5.1x** | deep costs **1.73x** |

Search is **77% of the cheap arm's bill and 32% of the deep arm's**, because
the cheap arm ran *37% more searches* (4.4/case against 3.2) and searches are
billed per use at $10/1,000. Over the tier the model choice is worth **$33,248**
and the search budget is worth **$34,998**.

**So `max_uses` is the lever, and picking the cheap model is not.** The cheap
model is still the right default — 33.0% against 36.3%, 31/31 agreement on the
EIN, and taxonomy kappas of 0.65–0.91 — but it should be chosen on the
*evidence that it is as good*, not on a price ratio that does not survive
multiplication.

### Keep a search tier for the residue, not the bulk

Layer 3 is the only configuration that can establish an answer is **absent**:
13 of the search arm's 18 NONEs are `CONTRADICTED` — it found the organisation
and showed its EIN is not among the candidates. A no-search NONE means "I
cannot tell from the packet" and still needs a human; a search NONE can be
closed. Those are different claims even when the verdict string is identical,
and they route differently.

### Layer 0 is free and should not be optional

`dev/NO-EXP-16-fuzzy.log`, cutoff 0.90, on the 4,868-identity in-scope run:

* **521 s, 8.9% of the 5,830 s match it supplements.** ~136 core-hours at
  corpus scale — compute, not billing.
* **+24 identities to YES** on a 2,009 residual, **+0.49 points** of clear
  rate, and **0 YES identities broken** (asserted by the function and
  re-checked independently by the regression script).
* It reaches **3 of the 33** EINs web search established, agrees on 2 and
  **contradicts 1** — see the caveats.

At 0.85 it clears **25** rather than 24 — one more identity for 1,105 more
pairs and a personal-name margin that falls to 0.002. The cutoff is set from
the collision, not the recall, and the 0.85 arm is what justifies that: there
is essentially no recall left to buy.

### The user options this implies

None of layers 1–3 is in the package today. `pf_adjudicate()` builds the packet
and stops; every model call lives in `dev/adjudicate-*.R` behind environment
variables (`PF_ADJ_*`, `PF_NO_MODEL`). That is right for an experiment and
wrong for a shipped feature: the measured result above is a *policy*, and a
policy belongs in a config object the caller can read, print and override.

Proposed, for Phase 4b implementation:

```r
pf_llm_config(
  model          = "claude-haiku-5-5",   # the cheap arm
  escalate_to    = "claude-opus-5-5",    # NULL disables escalation
  escalate_when  = "low",                # the cheap arm's own confidence
  search         = FALSE,                # layer 2 escalation, the measured default
  max_uses       = 6L,                   # the cost lever when search is on
  effort         = "medium",
  batch          = TRUE,                 # rate limits bind before price does
  seed_known     = 0.15                  # known-answer cases mixed into the batch
)

pf_adjudicate_llm(packet, config = pf_llm_config(), tier = c("MAYBE", "NO"))
```

Four things about that signature are load-bearing, each for a measured reason:

1. **`search` defaults to `FALSE`, and `tier = "NO"` must override it to
   `TRUE`.** Those are the two measured defaults and they are opposite. A
   single global default is wrong for one of the two tiers whichever way it is
   set, so the tier has to carry it.
2. **`max_uses` is a first-class argument, not a tuning detail.** It governs
   the larger half of the NO-tier invoice.
3. **`batch` defaults to `TRUE`.** The 100-case run did 52 s at 6 concurrent
   workers; 983,000 calls at that throughput is ~150 h on one synchronous
   stream, spent mostly on 429 back-off. The 50% discount is almost incidental
   next to not managing that.
4. **`seed_known` is not optional instrumentation.** Measured accuracy on
   known-answer cases is the only check on whether a production run is
   trustworthy, and mixing them in costs nothing.

`escalate_when = "low"` should accept an evidence class too (`INFER`), because
evidence class orders accuracy independently of confidence (QUOTE 93.3%
agreement, INFER 71.4%) — but escalating on low **and** INFER reached the same
26/27 for 2.5x the cost, so it is an option and not the default.

### What these numbers are not

Every figure above is honest about what it measured and none of it is a
guarantee. Before any of it goes into user-facing documentation:

* **The accuracy denominators are 27 and 91 cases.** "96.3% (26/27)" is one
  case away from 92.6%. The *ordering* of the arms is the claim; the size of
  each gap is not. Confidence intervals are in the source experiments and
  should travel with the numbers.
* **The deep arm is the reference standard for the MAYBE cases that have no
  hand-adjudicated answer**, and it carries a ~7% error rate that every
  derived figure inherits. It is not ground truth.
* **Model behaviour is not a fixed property.** These were measured on
  `claude-opus-5-5` and `claude-haiku-5-5` on 2026-10-31 with
  `web_search_20260209`. Model versions, default effort, tokenizers and
  pricing tiers all change, and two of them changed *during* this project —
  Haiku 5.5's tokenizer counts ~30% higher than 4.5's, and its two-tier
  pricing is what made the first cost estimate wrong by a factor of three.
  Re-measure before trusting any dollar figure.
* **Prices are list prices at the time of measurement**, and the Batch API's
  50% discount is applied to *tokens only* above. Whether per-use server-tool
  billing is discounted is not established in this repo and is not assumed.
* **Package versions matter to the cascade, not just to the models.** Every
  figure here sits on a specific `npmatch` normalizer; `v1-592912060053c4c3`
  changed `street_key` on 34,280 BMF rows against its predecessor, and
  `pf_check_reference()` exists because a stale key silently resolves fewer
  rows. The regression above runs on the matchdb `active-observed` tier
  (6.67M rows), **not** the augmented reference the baseline was measured on
  (3.88M), so its tier counts are not comparable to the published 62.74%.
* **The corpus projections multiply a 4,868-identity benchmark by ~940.** The
  3.72x dedup collapse is measured on a 12.56M-grant run rather than
  extrapolated — an earlier 1.8x estimate from a 100k sample was wrong by a
  factor of two — but tier shares on the full corpus are still an assumption
  that the full run will test.
* **Layer 0 has a measured false-positive mode.** Of the 3 web-established
  EINs it reaches, it cleared one (`G002196`) to YES on a *different* EIN than
  the search arm found. One of the two is wrong and the pipeline has no way to
  tell which. A 1-in-3 contradiction rate on n=3 is not a rate, but it is the
  right shape of warning: a fuzzy pair clears the same bar as an exact pair,
  so it can be confidently wrong in the same way.
* **Nothing here measures precision on the YES mass**, which every layer can
  only add to. That needs its own stratified sample
  (`dev/BASELINE-2026-10C/MANIFEST.md`).

## Phase 5 — the pairwise ranker

Only after Phase 4 supplies labels. Pairwise, within-grant, trained on silver
YES plus the Phase 3 features; the gold set held out, never trained on. Keeps
the accept/abstain decision separate and rule-based until calibration data
exists. Design in `dev/FEATURE-ENGINEERING.md` §5.

---

## What is deliberately *not* on this list

* **Auto-accepting MAYBE.** Measured twice, rejected twice.
* **Blocking on NTEE.** `has_ntee` is anti-predictive (AUC 0.425) and missing
  most often on large organisations. Rank on it, never block.
* **Recovering `SEE ATTACHED` grant detail from the XML.** Tested; the
  itemisation was never filed electronically. `dev/ADJUDICATION-PLAN.md` §6.
* **Semantic re-ranking on purpose text.** +2 grants in 28.
* **A foundation-portfolio NTEE prior applied unconditionally.** At chance
  without the entropy gate.
* **A transitive EIN cluster id.** One component of 66,973 EINs. Dyads only.
  `dev/CLUSTER-FINDINGS.md` §2.
* **Collapsing `related` dyads.** Reports a better number by merging different
  hospitals and cross-subsection pairs. `dev/DYAD-FINDINGS.md` §3.
* **Pooling more years of disclosure for recall.** 2009–2024 buys 49% → 52% of
  known arm pairs over 2022 alone. The ceiling is non-filing, not vintage.
* **A name gate on the exclusive-support dyad path.** Removes a third of the
  table and zero firing edges, and would delete exactly the acronym and rebrand
  cases (`NFTE ENDOWMENT FUND`, `MOMA AUXILIARIES`, `CAF PROPERTY`) that are the
  only reason disclosure beats a name rule.

---

## The stop rule: when to stop matching R&D and start consolidating

Added 2026-08-22, because "keep looking for levers" has no natural end and this
project now has enough measurements to state one.

**Stop matching R&D and move to consolidation when all three hold.** Two already
do; the first is the only one genuinely open.

### 1. Cost clears the budget with a gated configuration

Phase 1 completes in **≤117 h** using a configuration whose answers are gated
against `BASELINE-2026-08`. Status: **not met, and close.** One shard is 401 h;
ten state shards would be ~40 h, but partition equivalence is unproven
(`dev/STATE-PARTITION-FINDINGS.md`). This is the only remaining reason to keep
doing R&D — and it is *engineering*, not matching.

### 2. Every remaining un-built lever moves <1% of grants

Measured on grants or dollars — not on candidate counts, not on a subpopulation.
The record so far:

| lever | reach | verdict |
|---|---:|---|
| B2-token-concat removal | 1.55% of YES | keep B2; runtime trade only |
| dyad collapse | 3.1% of identities | **built** |
| matchdb `group_id` | **0.79% of grants**, 0.90% of dollars | matchdb builds it |
| reference-row collapse | 0% runtime, spurious YES | **rejected** |
| semantic re-ranking | +2 grants in 28 | rejected |
| group signature index | +1.0 pt rank-1 for +6% candidates | rejected (matchdb) |
| funder NTEE prior, ungated | chance | rejected |

**Four of the last five candidates evaluated were rejected, and the survivor
reaches 0.79% of grants.** That is what diminishing returns looks like in the
record rather than in the abstract.

### 3. The binding constraint is labels, not capability

Already true, since `dev/FEATURE-ENGINEERING.md` §1. The accept decision cannot
be fitted on 156 adjudicated cases of which independent verification upheld ~5 of
12; 41% of hard cases resolve to NONE; and the dominant residual — operating
entity versus its own fundraising arm — **has no determinate answer in any public
source**.

Three independent measurements now say the residual ambiguity is *structural*:
15.9% of the MAYBE tie band is one body under two BMF rows
(`CLUSTER-FINDINGS.md` §8); a group cluster in the close set never co-occurs with
YES (matchdb `GROUP-STRUCTURE-FINDINGS.md` §3); and **10.5% of benchmark EINs are
exact score ties** (`STATE-PARTITION-FINDINGS.md` Part 3). No threshold tuning
addresses any of them.

### The override

**Any change requiring a re-freeze of `BASELINE-2026-08` must clear a higher
bar** — ≥1% of grants *and* adopted deliberately — because the freeze gates
matchdb's phases too. A re-freeze is a cross-repo event, not a commit.

Pending under this clause: the deterministic tie-break (`npmatch@f14f1d9`), which
moves 10.5% of reported EINs and 0% of tiers.

### What consolidation means

Run Phase 1; build the Phase 2 partitions; ship the enriched adjudication packet;
spend the budget on **~1,000 labels with NONE as a first-class verdict**. That
round is the only thing measured to unlock anything further — it gates threshold
optimization (`OPTIMIZATION-PLAN.md` §1b), the ranker (Phase 5), and any honest
precision claim.

---

## What matchdb's group work changes here

Reviewed 2026-08-22: `matchdb/dev/GROUP-STRUCTURE-FINDINGS.md`,
`matchdb/dev/RELATION-BUILD-PLAN.md`.

**It confirms this project's central negative result from independent data.**
pfmatch measured one connected component of 66,973 EINs and concluded "direct
edges only, never a transitive closure" (`CLUSTER-FINDINGS.md` §2,
`DYAD-FINDINGS.md` §1). matchdb, after loading every source, reports a largest
related-entity component of **117,869 EINs**. The giant grew; the rule holds
harder.

**`group_id` is the principled version of the collapse this project rejected.**
`pf_collapse_reference()` was rejected because merging rows that merely *share a
name* manufactured an 80-grant YES gain, 88% of it converted abstention.
matchdb's components merge rows *disclosed to be one group*, and the measurement
is the mirror image: a group cluster in the close set **never co-occurs with
YES** (0 of 3,015), appearing equally in MAYBE and NO. It marks not-YES rather
than promoting to YES — the opposite failure mode, and the safe one. Same
blowups, too: `DUCKS UNLIMITED` 5,363 → 740 there, 5,363 rows here.

**It is nearly disjoint from the affiliate-suffix veto** — Jaccard 0.015, the
lexical veto firing 170 times of which 8 are actual subordinates. Additive, not
redundant.

**Consequences:**

1. **It does not change Phase 1.** 0.79% of grants is below the §2 threshold.
   Consume it in Phase 3/4 disambiguation, not in blocking, and not as a reason
   to delay the run.
2. **It interacts with state partitioning, unchecked.** Group members span states
   — median 2 for federated chapters, 3 for group rulings and dispersed networks.
   A collapse applied inside a state shard sees only the part of the group in
   that state. The dyad collapse carries the same exposure and the same
   mitigation (it resolves *within one grant's candidate list*), but this needs
   stating before either runs partitioned.
3. **Pull the e-file affiliate names forward.** 0.19% of index tokens carrying
   10.6 of 46.9 rank-1 points is the best return on data acquisition either
   project has measured, and it is reference expansion — Phase 0b's business.
4. **Their rank-metric correction applies here.** `na.rm=TRUE` on a conditional
   rank metric, and `ties.method="min"`, each inflated their results
   substantially. Any retrieval metric this project reports must be unconditional
   and break ties randomly.
