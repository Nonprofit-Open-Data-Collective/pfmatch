# pfmatch

Matching **990-PF grant recipients** (Form 990-PF Part XIV Table 3a, "grants
paid during the year") to the **IRS Business Master File** to recover recipient
EINs.

The record-linkage machinery is [`npmatch`](../npmatch): normalization, blocking,
comparison, hierarchical scoring, the veto layer, and YES / MAYBE / NO tiering
are all used unchanged. This package holds only what is specific to the 990-PF
grant context.

## Install

```r
# npmatch first — pfmatch Imports it
install.packages("../npmatch", repos = NULL, type = "source")
install.packages(".",          repos = NULL, type = "source")
```

## Use

Four stages, or one call:

```r
library(pfmatch)

res <- pf_run(grants = "inputs", bmf = ".../bmf_2026_01_processed.csv")

# or stage by stage, when you want to cache between them
prep <- pf_prepare(grants, dedup = "fuzzy")        # read -> repair -> scope -> dedup
ref  <- pf_reference(bmf)                          # build or load the cached bundle
lnk  <- pf_link(prep, ref, batch_size = 25000)     # cascade -> self-guard -> propagate
adj  <- pf_adjudicate(lnk, bmf)                    # the review sheet
```

| stage | does | key functions |
|---|---|---|
| `pf_prepare()` | read grants, repair name-in-street, standardize the recipient-status field, decide scope, collapse to distinct recipient identities | `pf_read_grants()`, `pf_prepare_grants()`, `pf_standardize_status()`, `pf_dedup()`, `pf_recipients()` |
| `pf_reference()` | read + normalize the BMF, name frequency, token IDF, blocking index, acronym/prefix keys — cached, and excluded from match timings | `pf_build_reference()` |
| `pf_link()` | the staged blocking cascade in checkpointed batches, self-match guard, then propagate each identity's result to every grant row | `pf_staged_passes()`, `pf_recovery_passes()`, `pf_run_batches()`, `pf_propagate_matches()` |
| `pf_adjudicate()` | candidate sheet with BMF and foundation context, optional purpose tiebreak | `pf_candidate_frame()`, `pf_build_org_text()`, `pf_purpose_tiebreak()` |

Results are summarized by `pf_report()`, `pf_status()`, and `pf_crosstab()`.

## Repository layout

```
R/               the package
data/            nteev2.rda — the only bundled data (built by data-raw/)
data-raw/        make-nteev2.R
inputs/          grant CSVs, 990 Part III extracts, NTEE source files  (not shipped)
data-dev/        derived artifacts, caches, checkpoints                (not shipped)
dev/             benchmarks, probes, findings                          (not shipped)
```

`inputs/` was called `data/` until the package skeleton was added; it holds
600 MB+ of source files and had to give up the name to R's reserved `data/`.

## What is specific to this problem

### 1. `R/recipient-type.R` — standardizing `SIGOCPYRFSTA`

Column (c) of the grants table asks the filer for the "foundation status of
recipient" and the IRS supplies no controlled vocabulary. Across 155,000 sample
grants the field carries **~1,400 distinct spellings** of about eight concepts.

`pf_standardize_status()` is a rule cascade, not a lookup table, so unseen
spellings land in the right bucket. Two normalizations do most of the work:

* **section collapsing** — `501(c)(3)`, `501C 3`, `501 C 3`, `501c3` all become
  the single token `501C3`; likewise `509A1`, `170B1A`, `4942J3`.
* **de-spacing** — every pattern is also matched against a space-free copy of
  the string, so `PUB CHAR`, `PUBLIC CH`, and `OTHERPUBLICCHARITY` are all caught
  by one pattern.

Order matters: operating foundations are tested before the generic 501(c)(3)
rules (an operating foundation *is* a c3 but is emphatically not a public
charity), and government before the bare-`PUBLIC` fallback (so "PUBLIC
UNIVERSITY" does not become a public charity).

| level | share of 155k |
|---|---|
| `public_charity` | 70.5% |
| `other_unknown` | 20.6% |
| `nonprofit_other` | 4.3% |
| `individual` | 3.6% |
| `foundation_pf` | 1.1% |

Coverage is 98.6%; the 1.4% residual is text that answers a different question
("PAID", "CASH", "VARIOUS", "ACTIVE", "SEE GENERAL EXPLANATION"). Use
`pf_status_audit(x, detail = "unrecognized")` to see what a new extract still
misses before trusting the split.

A finer `recipient_type_detail` is carried alongside, because `other_unknown`
mixes cases that behave very differently — `government` and `foreign` can never
be in the BMF, while `blank` and `unrecognized` are usually organizations the
filer simply did not code. **Only the detail level drives scope**
(`pf_oos_details()`).

Two judgment calls worth knowing about:

* **`NC`** is the standard shorthand for a *non-charity* recipient — the filers
  who spell it out write "NC: NON-EXEMPT". It says what the recipient is *not*,
  so it is not promoted to "nonprofit (other)", but it stays **in scope**: a
  501(c)(4) or a taxable entity may still hold a BMF row.
* **Equivalency determinations** are how a US foundation grants to a foreign org
  with no IRS ruling, so they are classified `foreign` and held out of the match.

### 2. `R/prepare.R` — recipient name and address

The data dictionary settles the name-field question. There are three columns:

* `SIGOCPYRPNAM` — "Name of Grantee — **Person**"
* `SIGOCPYRBNBN1` — "Name of Grantee — **Business** Line 1"
* `SIGOCPYRBNBN2` — "Name of Grantee — **Business** Line 2"

So `BNBN1`/`BNBN2` are a two-line **wrap of one name**, not a main name and a
DBA — confirming the working assumption. `PNAM` and `BNBN1` never co-occur
(0 of 155,000 rows carry both), so the recipient name is a straight coalesce.

`PNAM` is **not** a usable individual flag: filers routinely put organizations in
it ("World Central Kitchen", "Surfrider Foundation"), which is why scope is
decided from `SIGOCPYRFSTA` instead.

Line 2, when present, is one of four things and each is handled separately:

| line 2 is | n (5k sample) | handling |
|---|---|---|
| a genuine continuation | 2,047 | joined onto line 1 as an alternate name |
| a duplicate of line 1 | 983 | dropped |
| a care-of / attention line | 735 | dropped (address data in a name field) |
| an FBO beneficiary | 27 | dropped, trailing `FBO` stripped from line 1 |

The joined continuation is carried in npmatch's `dba` slot. That is a deliberate
reuse rather than a claim that it is a DBA: `np_compare()` scores the full
name/DBA cross-product and keeps the best, so a record can match on either the
truncated line-1 form or the complete one — whichever the BMF happens to hold.
It earns its keep: the `exact-name-dba` pass resolves 86 YES on the 5k sample.

Other handling: 4-digit ZIPs are repaired (a dropped New-England leading zero),
spelled-out state names are folded to postal codes, and a state value that is
not a US postal jurisdiction marks the record foreign. `SIGOCAFFRFACO` (country)
is in the schema but empty throughout the sample, so foreign detection has to
come from the state field.

`looks_personal` is a diagnostic only and never drives scope: a 2-3 token name
with no institutional token *and* a positive person signal (a single-letter
initial, or a common given name). It fires on 0.7% of YES matches and 18% of
out-of-sample rows, which is the right direction.

### 3. `R/match.R` — two cascades

**`pf_staged_passes()` is the production cascade** (state-blocked bulk plus a
cheap cross-state exact sweep) and **`pf_default_passes()` is the state-free
measurement baseline**. On 5,000 grants the staged `lean` configuration is 1.48x
faster, uses 2.0x fewer candidate pairs, and returns 13 *more* YES matches. See
`dev/SCALE-PLAN.md` for the full comparison.

The single most efficient pass is `A1`, which blocks on **name + ZIP5 with no
state key**: 1,834 matches from 8,285 candidates. It is also what makes state
blocking safe, because it catches the "filer typed the wrong state" cases (right
city, right ZIP, wrong two-letter code) without any cross-state sweep.

The unblocked *token* sweep is off by default (`sweep = "lean"`). Measured, it
generated 59% of all candidate pairs and produced **zero** additional YES
matches — its only product is extra MAYBE candidates. Turn it on with
`sweep = "full"` when filling the adjudication queue matters more than runtime.

### 3b. The state-free baseline and why it exists

npmatch's default cascade blocks every pass on `state` and only opens up to a
cross-state token pass at the end. That is right when query and reference are
the same establishment; it is wrong here, because a New York foundation
routinely funds a California charity and the address the filer types is whatever
was on the check. Every pass in `pf_default_passes()` is state-free:

| pass | criterion |
|---|---|
| `exact-name` | name == name, any state |
| `exact-name-dba` | name == dba, any state |
| `exact-dba-name` | dba == name, any state |
| `exact-dba-dba` | dba == dba, any state |
| `token-any` | shared distinctive token (IDF-pruned), any state |

"No blocking" cannot mean a full cross product — 5,000 grants against 1.9M BMF
rows is 9.6 billion pairs. What is dropped is *geographic* blocking. Candidates
are still generated by exact name keys and by a shared distinctive name token,
which is a recall device rather than a geographic constraint. State is used only
downstream, as scoring evidence.

`pf_build_reference()` does the one-time BMF work (read, normalize, name
frequency, token IDF, blocking index) and caches it, so it is excluded from the
match timings. `pf_match_grants()` times **only** the cascade.

### 4. `R/report.R` — the four-way outcome

* `YES` — one candidate cleared the auto-accept threshold with a clear lead
* `MAYBE` — candidates surfaced but need adjudication (below threshold, a
  near-tie with the runner-up, or a soft veto)
* `NO` — no candidate surfaced, or the best one scored below the review floor
* `OOS` — out of sample: a natural person, a government unit, or a foreign
  organization. Nothing to find, so not counted as a miss.

`pf_report()` prints the outcome split, the outcome x recipient-type crosstab,
geographic-agreement diagnostics, the per-pass cascade table, and the runtime;
`pf_status()`, `pf_crosstab()`, and `pf_geo_agreement()` return the frames.

## Benchmarks and development

```bash
PF_SET=1k Rscript dev/run-test-match.R      # the five 1,000-row files
PF_SET=50k Rscript dev/run-test-match.R
PF_SET=100k Rscript dev/run-test-match.R
Rscript dev/run-full-file.R                 # checkpointed production run
```

The first run builds `data-dev/BMF-REFERENCE-BUNDLE.rds` (~5 min, 1.3 GB) and
reuses it thereafter. Set `NPMATCH_DIR` / `PFMATCH_DIR` to relocate.

`dev/` scripts use `devtools::load_all()` rather than `library(pfmatch)`, so they
can reach internal and unexported functions. They are not part of the package.

Planning documents: `dev/PACKAGE-PLAN.md` (what packaging still owes),
`dev/NPMATCH-PROMOTION-PLAN.md` (three modules to move upstream, and one npmatch
defect this project found).

## Results, 5,000-grant sample

See `dev/BENCHMARK-NOTES.md` for the full read-out and what it implies for the
next round.

## Audits

`dev/AUDIT-FINDINGS.md` reports three 100-case manual audits of the NO, OOS, and
MAYBE tiers, with per-case verdicts in `dev/maybe-verdicts.csv`. Short version:
the NO tier is mostly real nonprofits we failed to reach (13 of 15 web-confirmed
EINs are in the BMF), the OOS flag is wrong 24% of the time because column (c)
describes the beneficiary rather than the payee, and 63% of MAYBE cases contain
the correct EIN in the top five candidates.
