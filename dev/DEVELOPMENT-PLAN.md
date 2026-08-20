# pfmatch development plan

Written 2026-08-20, consolidating the experiments of the last two days into
ordered phases. Supersedes the ad-hoc ordering in `dev/SCALE-PLAN.md` §7 and
`dev/ADJUDICATION-PLAN.md` §7, both of which remain accurate about their own
subjects.

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

## Phase 1 — the full-file production run

Input: `~/Documents/grants/2025_08_29_All_Years_990PFPart14Grants3A.csv`,
**12,559,051 grants**.

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
2. **Funder NTEE profiles with the entropy gate**, scored against a size-matched
   null rather than a flat threshold (`dev/FUNDER-PROFILE-FINDINGS.md` §2).
3. **Persistence** — year-over-year grantee overlap per filer. Untestable until
   now; a repeat grantee is a near-certain identity link.
4. **Grantee prior** — distinct funders per recipient EIN. Measured at 0.577 AUC
   overall but **0.877 and 76% top-1 on the 20% of grants where it fires**.
5. **Arm clusters** at scale — `pf_cluster_arms()` over the full candidate sets,
   with the Schedule A line-5 override.

**Exit criterion:** each feature measured as pair AUC and fire-rate on the
adjudicated gold set, with the negative results recorded as carefully as the
positive ones.

## Phase 4 — adjudication

1. **Ship the enriched candidate packet** — `pf_candidate_frame()` gains NTEE
   description text, 990 mission and program descriptions for *every* candidate.
   Prototype exists in `dev/build-enriched-hard.R`.
2. **Label ~1,000 cases** on the enriched packet, with `NONE` as a first-class
   verdict and an evidence class (`QUOTE` / `NTEE` / `INFER` / `NONE`) on each.
   Stratify to over-sample arm pairs and restricted-gift purposes, which settles
   the `pf_arm_order()` policy as a by-product.
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
