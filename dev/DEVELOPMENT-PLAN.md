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

## Where things stand

| tier | 5,000-grant benchmark | what is known about it |
|---|---:|---|
| YES | 56.4% | 99.8% state-consistent, 82.8% ZIP5. Treated as correct. |
| MAYBE | 20.1% | 63% contain the right EIN. No safe auto-accept rule exists (72% precision, measured twice). Text enrichment resolves 80% of hard cases. |
| NO | 21.9% | Candidate-generation failures plus genuine absences (government units, foreign, defunct). |
| OOS | 1.6% | Foreign only, after the recipient-type filter was narrowed. |

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

> **BLOCKER, found 2026-08-21.** The augmented unified reference runs at
> **5,558 s per 1,000 identities** against the monthly BMF's 33.5 s per 1,000 —
> ~166x for 2.02x the rows. Three token/acronym passes generate 208,456 of
> 227,838 candidates and resolve 71 queries between them. Phase 1 is **not
> executable** against this reference: no amount of sharding fixes a 166x
> constant. The +2.2 recall points are real but have never been priced against
> runtime. Attribution test and the most promising fix (exclude alias rows from
> token blocking, since an alias only ever needs the exact-name passes) are in
> `dev/REF-PERFORMANCE.md`. **This now gates Phase 1 ahead of everything else.**

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

**Blocked on the Phase 0b performance defect** (`dev/REF-PERFORMANCE.md`). The
schedule below assumes 33.5 s per 1,000; the augmented unified reference
currently costs 5,558 s per 1,000. Resolve that first — the choice is not
"augmented or plain" but "fix the token passes or forfeit +2.2 points".

**Depends on Phase 0c.** Running without `dyads =` forfeits the MAYBE→YES
promotions and, more importantly, produces a review queue containing thousands
of grants whose "ambiguity" is one body against itself. Pass the dyad table to
`pf_link()` on the first run rather than reprocessing later — the collapse needs
the scored pairs, which the batch checkpoints do not retain.

The naive cost is prohibitive — 33.5 s per 1,000 grants is **117 hours**
single-threaded. Two levers make it tractable, and both must be measured rather
than assumed:

| lever | expected | how it is obtained |
|---|---|---|
| **dedup to distinct recipient identities** | 1.8x measured on 100k; expected to be much better at full scale because the whole file repeats the same grantees | `pf_dedup()` + `pf_propagate_matches()` |
| **parallel batches** | up to ~12x on 24 cores | `pf_run_batches()` per shard, one process per shard |

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

**Exit criterion:** a calibrated review process and the largest ground-truth set
the project has had.

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
