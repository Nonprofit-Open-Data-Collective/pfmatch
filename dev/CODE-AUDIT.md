# Where the code stands — audit, 2026-08-20

Three questions: what is implemented and running, what is built and measured but
not wired in, and what is still to build. Plus two augmentation sources the plan
did not previously name, and one reconciliation — a parallel session built the
Schedule I alias module while this one was working on affiliation and features.

---

## 1. Implemented and wired into `pf_run()`

These execute on every run today. 16 modules, ~3,200 lines.

| module | exported | what it does in the pipeline |
|---|---|---|
| `recipient-type.R` | 5 | standardises `SIGOCPYRFSTA`, sets `in_scope`; 98.6% coverage over ~1,400 spellings |
| `prepare.R` | 3 | name coalesce, line-2 disposition, ZIP repair, foreign detection, individual/government flags, name-from-street recovery |
| `dedup.R` | 4 | identity keys, fuzzy merge, `pf_propagate_matches()` |
| `match.R` | 5 | reference build, pass definitions, the cascade call |
| `recover.R` | 4 | three-tier initialisms, stage-4 acronym passes |
| `selfmatch.R` | 1 | drops the filer matching itself |
| `batch.R` | 2 | batched execution with resume |
| `pipeline.R` | 5 | `pf_prepare` → `pf_reference` → `pf_link` → `pf_adjudicate` → `pf_run` |
| `report.R` | 5 | status, crosstab, geo agreement, audit |
| `enrich.R` | 4 | BMF context, candidate frame |
| `text.R` | 2 | EIN → NTEE / mission / program text |
| `purpose.R` | 6 | purpose tokens, IDF coverage, tiebreak (**off by default**) |

**Confirmed behaviour:** 56.4% YES / 20.1% MAYBE / 21.9% NO / 1.6% OOS on the
5,000-grant benchmark, 99.8% state agreement on YES, 33.5 s per 1,000 grants.

## 2. Built and measured, **not** wired in — awaiting an integration decision

This is the real answer to "what is in testing". Five things are finished code
with measurements behind them, and none of them execute on a default run.

| module | measured worth | why it is not wired | decision needed |
|---|---|---|---|
| **`schedi.R`** (7 fns) + `pf_bmf_augment()` | **+2.2 points**, conservative | `pf_reference()` still defaults to the plain BMF | **switch the default reference to the augmented BMF** |
| **`affiliation.R`** (7 fns) | cascade is at **27%** on arm pairs; any stated policy beats it | needs a hook between `np_select()` and `np_tier()` | wire `pf_cluster_arms()` + `pf_arm_order()` |
| `attached.R` (3 fns) | 497 returns, $394M in the 150k sample | standalone by design — it is a separate product | none; it is finished |
| `pf_purpose_tiebreak()` | +2 grants in 28 | flag exists, defaults off | leave off until the ranker exists |
| enriched candidate packet | resolves **45 of 56** hard MAYBE cases | prototype lives in `dev/build-enriched-hard.R`, not in `pf_candidate_frame()` | promote into `R/enrich.R` |

The Schedule I one is the most consequential and the most time-sensitive: the
augmented reference **already exists on disk** —
`data-dev/BMF-AUGMENTED-unified.csv`, 3,880,431 rows (+5.2%), 192,996 net new
alias rows — and the full-file run currently in progress is configured against
the *plain* BMF. That has to change before the match step starts.

## 3. Not built

| item | status | blocked by |
|---|---|---|
| recipient-name clustering **across the corpus** | not started | needed the full file; now available |
| funder NTEE profiles, entropy, persistence | not started | needed intact filer portfolios; now available |
| grantee prior (distinct funders per EIN) | prototype only, `dev/test-grantee-prior.R` | — |
| pairwise ranker | designed, `dev/FEATURE-ENGINEERING.md` §5 | Phase 4 labels |
| accept / abstain calibration | designed | ~1,000 gold labels with NONE |
| 990-filer EIN expansion | **measured here, not built** | see §5 |
| vignettes, test promotion | not started | low value |

---

## 4. Schedule I as a BMF expansion — reconciled

A parallel session built this while this session was on affiliation and
features. Its findings (`dev/SCHEDI-ALIAS-FINDINGS.md`) are more thorough than
the check run here, and the two agree on the thing that matters.

Their build, 2009–2024 from `efile_v2_2`:

| | |
|---|---:|
| Schedule I grant rows | 8,986,064 |
| rows with a well-formed EIN | 8,377,563 (93.2%), **0 malformed** |
| alias rows `(ein, name, city, state, zip5)` | 2,454,949 |
| distinct EINs | 794,209 (~41% of the BMF) |
| names mapping to exactly one EIN | 90.2% |

**Precision is a clean dial on corroboration**, and this session reproduced that
independently on 2022 alone before knowing the module existed:

| distinct filers writing the name | agreement with the accepted EIN |
|---|---:|
| 1 | 86.1% |
| 2–4 | 95.4% |
| 5–19 | **98.0%** |
| 20+ | **99.0%** |

Recall: 18.1% of the NO tier gets an alias hit; 52.2% of those are both
BMF-present and multi-filer — about **+2.2 points**, against +1 grant in 63 for
the entire grant-purpose investigation.

### One correction to carry forward

The independent check here proposed a second gate — require the alias to share a
content token with the BMF name — and **that gate is wrong**. It discards
precisely the highest-value aliases, because acronyms and rebrands share no
tokens by construction:

```
NATIONAL ASSOCIATION STUDENT PERSONNEL   ->  NASPA
CAL POLY                                 ->  CALIFORNIA POLYTECHNIC STATE UNIVERSITY
NEIGHBORHEALTH                           ->  EAST BOSTON NEIGHBORHOOD HEALTH
```

Use `n_filers` alone, as the module already does. If a second gate is ever
wanted, `pf_initials()` is the right one — it recognises the acronym relation
these examples share.

### A risk the module should guard

Some aliases attach a **chapter name to a group-parent EIN**:
`AMERICAN VETERINARY MEDICAL ASSOCIATION` → `UNIVERSITY CALIFORNIA DAVIS SAVMA`,
`ROAD RUNNERS CLUB AMERICA` → `TOWN CELEBRATION`. Those aliases are true of the
chapter, not of the EIN, and would make a national EIN match a local grant.
`pf_group_siblings()` already identifies group-ruling EINs; aliases attaching to
one should require higher corroboration or be excluded.

## 5. EINs that file a 990 but are absent from the BMF — a real, separate gap

Measured here, not covered by the Schedule I module (which only carries EINs
that appear as *recipients*):

| | n | share |
|---|---:|---:|
| distinct 2022 Form 990 filers | 545,261 | — |
| present in the BMF | 522,657 | 95.9% |
| **absent from the BMF** | **22,604** | **4.1%** |

Split 12,288 990-EZ / 10,316 990. These are live organisations — they filed a
return — that the reference cannot match at any score. Sixteen years of header
files are already downloaded (`~/Documents/grants/F9-P00-T00-HEADER-*.CSV`).

Separately, 80,574 EINs appear on Schedule I but not in the BMF. Most are
keying errors and must not enter the reference: only 19.6% are either
corroborated by ≥2 filers or independently known to file a 990. **80.4% are
single-filer, single-mention, non-filing — exclude them.**

**Recommended preprocessing stage, before normalisation:**

```
BMF (1.92M EINs)
  + Schedule I aliases, gated on n_filers          [BUILT, not wired]
  + Schedule I EINs gated on files-990 OR >=2 filers   [NOT BUILT]
  + 990 header EINs absent from the BMF                [NOT BUILT]
  = unified reference
```

## 6. The two clustering augmentations

**Cluster by recipient name across the corpus** — partially exists. `pf_dedup()`
clusters *within the grant file* and is running now at **3.72x collapse** on the
full 12.56M rows, far above the 1.8x the 100k sample suggested. What does not
exist is clustering that spans the grant file *and* the reference, so that an
EIN resolved for one spelling propagates to every spelling of the same body
anywhere in the corpus. That is the single largest recall lever left, and it only
becomes possible with the full file.

Two defects to fix first, both in `pf_dedup()`:

1. `max_block = 2000` **silently skips** larger blocks. At 100k it never binds;
   at full scale ~500k of 3.38M keys sit in blocks too large to be compared, and
   they are the densest neighbourhoods.
2. `ei <- c(ei, a)` inside the per-pair loop grows a vector quadratically. At
   100k (~12k joins) it is invisible; at full scale it is a real term. Collect
   into a list and `unlist()` once.

**Cluster by foundation** — not built. Now unblocked: the full file has a median
of **5 grants per filer-year** and 51% of filer-years carry ≥5, against a median
of 1 in every dev sample used to date. Funder profiles, entropy gates, and
year-over-year persistence all become computable for the first time.

---

## 7. Immediate decisions

1. **Point the full run at the augmented BMF.** `data-dev/BMF-AUGMENTED-unified.csv`
   exists; `dev/full-03-shard.R` currently names the plain BMF. Worth +2.2 points
   and costs a one-line change plus a reference-cache rebuild.
2. **Commit `R/schedi.R`** and its five dev scripts — currently untracked, along
   with modified `DESCRIPTION` and `NAMESPACE`.
3. **Fix the two `pf_dedup()` defects** before the corpus-wide clustering work.
4. **Add the two reference-expansion stages** in §5.
5. **Wire `affiliation.R`** into the selection step.
