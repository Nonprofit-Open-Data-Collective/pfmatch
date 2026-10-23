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

# suggested: retrieval and the variable dictionary
remotes::install_github("Nonprofit-Open-Data-Collective/panel990")
remotes::install_github("Nonprofit-Open-Data-Collective/concordance990")
```

## The data source

Grants come from the **NCCS e-file (ef2) release**, retrieved through
[`panel990`](https://github.com/Nonprofit-Open-Data-Collective/panel990), which
owns release resolution and defaults to the current published version and to
parquet:

```r
pf_efilepf_fetch(years = 2015:2025)       # panel990 picks the release
pf_efilepf_build(out = "inputs/grants.csv")   # schema = "v2", dedup = TRUE
pf_source_provenance()
#> $efile_version  "v3_1"
#> $efile_root     "https://nccs-efile.s3.us-east-1.amazonaws.com/public/efilepf_v3_1/"
#> $efile_format   "parquet"
#> $concordance_version "2.0.3"
```

Column names are the **concordance990 v2** research variables
(`PF_15_G_PAID_RECIP_NAME_ORG_L1`, `ORG_EIN`, …), documented in the
[990-PF data dictionary](https://nonprofit-open-data-collective.github.io/concordance990/articles/data-dictionary-990pf.html).
`pf_concordance_vars()` reads them from the installed concordance rather than
hardcoding them, and warns if pfmatch expects a name the concordance has
renamed — so a dictionary change surfaces as a warning instead of a column that
silently reads as all-missing.

### A note on the earlier source

This package was prototyped against GT's Data Mart extract, whose columns carry
the concordance990 **v1** names (`SIGOCPYRPNAM`, `SIGOCPYRBNBN1`, `FILEREIN`,
…). Those are superseded. The GT extract is also truncated at the recent end —
2024 is under-represented roughly tenfold and 2025 is absent — so it is kept
only in `inputs/archive-gt/` for reproducing pre-migration artifacts, never for
measurement. `pf_read_grants()` refuses to concatenate the two vintages.

Readers accept either naming through an internal resolver, so files built before
the migration still work; new code should use the v2 names.

### Duplicate and superseded filings

`pf_efilepf_build()` deduplicates by default. The unit is
`(EIN2, TAX_YEAR, group flag, partial flag)` — a filing can only supersede
another covering the same reporting context — and within a context identical
filings collapse, an amended filing supersedes the original, and filings that
disagree with no amendment to settle them are **all kept** and flagged.

On the 17,560,767-row corpus that removes 307,568 rows (**1.75%**) across 9,882
of 977,677 filings, leaving 5 contexts flagged for review. Two properties are
deliberate and tested:

* a **short-period** return is never dropped for sharing a tax year with a
  full-year one — they cover different periods, and in 97 of 310 such pairs the
  partial return reports *more* grants
* the dedup unit is **not** keyed on the tax period, because in 18 units an
  amendment corrected the period dates; keying on it would stop the amendment
  superseding its original

990-PF filers do not file group returns (`RETURN_GROUP_X` is `FALSE` on every
row), but the flag stays in the key so the behaviour holds if that changes.

Rows are addressed by `OBJECTID | TABLE_ID`, the published ef2 row key —
`OBJECTID` identifies the filing, `TABLE_ID` counts rows within it. Verified
unique across all 17.5M rows.

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

### 1. `R/recipient-type.R` — standardizing `PF_15_G_PAID_RECIP_STAT`

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

* `PF_15_G_PAID_RECIP_NAME_PERS` — "Recipient Person Name"
* `PF_15_G_PAID_RECIP_NAME_ORG_L1` — "...business name line 1"
* `PF_15_G_PAID_RECIP_NAME_ORG_L2` — "...business name line 2"

So The two `_ORG_L1`/`_ORG_L2` columns are a two-line **wrap of one name**, not a main name and a
DBA — confirming the working assumption. `_NAME_PERS` and `_ORG_L1` never co-occur
(0 of 155,000 rows carry both), so the recipient name is a straight coalesce.

`_NAME_PERS` is **not** a usable individual flag: filers routinely put organizations in
it ("World Central Kitchen", "Surfrider Foundation"), which is why scope is
decided from `PF_15_G_PAID_RECIP_STAT` instead.

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
not a US postal jurisdiction marks the record foreign. `PF_15_G_PAID_RECIP_ADDR_CNTR` (country)
is in the schema but empty throughout the sample, so foreign detection has to
come from the state field.

`looks_personal` is a diagnostic only and never drives scope: a 2-3 token name
with no institutional token *and* a positive person signal (a single-letter
initial, or a common given name). It fires on 0.7% of YES matches and 18% of
out-of-sample rows, which is the right direction.

### 3. `R/match.R` — the cascade

Full walkthrough in **`dev/CASCADE.md`**: what is compared, the scoring formula,
all eleven passes, the vetoes, and how a grant lands in YES / MAYBE / NO. The
short version:

**Both sides carry two name slots**, so name similarity is the best of a
cross-product — `max(name×name, name×dba, dba×name, dba×dba)`. The query `dba`
is `recip_name_alt`, the untruncated line1+line2 form. Address is not one
comparison either: seven location signals are emitted and the geo score takes
the strongest, never a sum.

```
score = 0.60 · name  +  0.40 · geo

geo   = max( 1.00·zip9,  0.95·street,  0.90·zip5,  0.90·pobox,
             0.55·zip3,  0.50·city,    0.20·state )
```

Taking the `max` means correlated address fields cannot double-count and a wrong
city cannot pull down a ZIP-confirmed match. Fuzzy similarities are floored to 0
below `jw_threshold` (0.85) — reclin2's `threshold=` is the Winkler prefix
*boost*, not a cutoff, so unrelated strings otherwise leak ~0.5 into every score.

Eleven passes run cheapest-first and **a query resolved to YES leaves the pending
set**, so expensive passes only see the residue. Stage A (exact, state-blocked)
resolves the bulk on a few thousand candidates; stages B–D spend two orders of
magnitude more candidates on the tail.

Tiering is `score ≥ 0.78 → YES`, `≥ 0.65 → MAYBE`, else `NO`, with two
demotions from YES to MAYBE: a **margin under 0.05** to the runner-up (an
ambiguity brake — something else is nearly as good), and a **soft veto**. The
soft vetoes that matter here are `affiliate_suffix` (candidate ends
FOUNDATION / ENDOWMENT / AUXILIARY / BOOSTERS and the query does not) and
`government_entity`.

> **These thresholds are npmatch defaults, fitted on SAM/USASpending — not on
> 990-PF data.** What is worth re-tuning, what the current label set can support,
> and why tier boundaries cannot be tuned on MAYBE-only labels:
> `dev/OPTIMIZATION-PLAN.md`.

### 3a. Two pass configurations

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

### 5. `R/dyads.R` — EIN dyads

A grant reported to `EAGLE RANCH` may have been paid to `EAGLE RANCH
FOUNDATION`. When both are candidates, the margin brake in §3 fires on a
runner-up that is *the same body under a second EIN* — median margin on affected
grants is exactly **0.000**, a grant held back for tying with itself.

`pf_build_dyads()` reads Schedule A Part I line 12g and Schedule R Part II
disclosures (2009–2024) and classifies each disclosed pair as `substitutable` or
merely `related`. `pf_link(dyads = )` then collapses substitutable candidates
*within one grant's candidate list* before selection and re-runs the tiering:
**704 MAYBE grants become YES on the 50k run, with nothing moving into NO.**

Two rules are not negotiable, both learned the hard way:

* **Direct edges only, never a transitive closure.** Connected components over
  the disclosure graph produce a single component of 66,973 EINs across 56
  states.
* **Substitution requires exclusivity.** A bare Schedule A edge gave the *YMCA
  Retirement Fund* 905 "substitutable" partners — it supports 907 local YMCAs.

`dev/DYAD-FINDINGS.md` for the evidence, `dev/CLUSTER-FINDINGS.md` for the
negative result that shaped the design.

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
