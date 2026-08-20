# Matching grant purpose to what the organization does

> **Superseded in part.** This memo was written before any of it was measured.
> `dev/PURPOSE-MATCH-FINDINGS.md` reports what happened when it was built and run
> against labeled cases, and corrects it: the NTEE bridge (§3a) and the per-field
> weighting (§4) do not survive; the containment metric (§2) and the
> keep-the-name-out rule (§5) do. Read the findings first.

A design proposal for using Part XIV column (d), `SIGOCPYPOGOC` ("purpose of
grant or contribution"), against the recipient's own description of itself: NTEE
code text, Form 990 Part III mission, Part III program service accomplishments,
and legacy IRS activity codes.

Everything below is measured on `data/50k_grants.csv`, the 1.92M-record BMF
(`bmf_2026_01_processed.csv`), and the 553,488 tax-year-2022 Part III returns
assembled by `dev/build-990-text-wide.R`.

---

## 0. The text table this depends on

`dev/build-990-text-wide.R` collapses the five Part III extracts into one row
per `OBJECTID`:

| output | shape |
|---|---|
| `data-dev/F9-P03-TEXT-LONG-2022.csv` | 585,107 rows, one per return × program |
| `data-dev/F9-P03-TEXT-WIDE-2022.csv` / `.rds` | 553,488 rows × 58 cols |

Wide columns are `mission`, then `program_01_desc/_exp/_grant/_rev` through
`program_10_*`, then `prog_overflow_{n,desc,exp,grant,rev}` for the 317 returns
with more than ten programs (max 70), then `n_programs`,
`n_programs_with_text`, `has_mission`.

Slot number is the **990 line**, not a compacted sequence: `program_01` is line
4a (`PROGRAM-ONE`), `_02` is 4b, `_03` is 4c, and `_04`+ are the repeating 4d
entries from `PROGRAMS-OTHER` ordered by `TABLE_ID`. An organization that filled
only line 4b leaves `program_01_*` empty. That keeps the table joinable back to
the source rows. 54 duplicate `OBJECTID` rows in the mission file and 47
duplicate OID/slot rows in the program files were dropped, first occurrence kept.

Two facts from that build shape everything after it:

* **990-EZ filers have a mission and never a program description.** 205,502 of
  553,488 returns (37%) are `990EZ`; the Part III program tables cover only the
  347,986 full-990 filers. So program-text availability is not missing at
  random — it tracks organization size.
* **Mission text is short.** Median 129 characters, p90 358, capped near 1,010.
  Concatenated program text for a full-990 filer runs median 217 characters, p90
  1,231, max 26,326. The two fields are not comparable documents.

---

## 1. Why this is a re-ranking problem, not a linkage problem

Record linkage wants a field that (a) is populated on both sides and (b) is close
to unique per entity. Grant purpose fails both tests, and it is worth being
precise about how badly.

**Coverage on the reference side.** Of 1,924,822 BMF records:

| signal | share of BMF EINs |
|---|---|
| NTEE definition, usable (not `UNDEFINED`/blank) | 66.9% |
| any 2022 Part III text | 27.1% |
| mission text | 27.1% |
| ≥1 program description | 17.2% |
| IRS activity-code text | 37.2% |

Candidates that actually surface skew much richer than the BMF at large — 84.7%
of the top-1 `YES` EINs from the 50k run have 2022 text, 65.1% of `MAYBE`, 39.6%
of `NO` — but a third of the tier this is meant to fix still has no 990 text at
all, and only the NTEE definition to fall back on.

**Discriminativeness on the query side.** `SIGOCPYPOGOC` is populated (only 0.6%
empty) and almost contentless:

| | |
|---|---|
| median length | 18 characters, 2 words |
| p90 | 50 characters, 7 words |
| empty or pure funding boilerplate | **58.9%** |
| grants with ≥1 content token after stoplisting | 55.1% |
| grants with ≥2 content tokens | 39.7% |

`GENERAL SUPPORT` occurs 2,931 times in 50,000 grants; `CHARITABLE` 2,201;
`GENERAL` 1,753. A blocking key built on this field would produce buckets tens of
thousands wide, on 41% of records would carry no information at all, and on the
reference side would be undefined for 73% of the BMF.

**So: never block on purpose, and never let it generate a candidate.** It is a
feature computed *over pairs the name cascade already produced*, used to reorder
them. That is also where `dev/AUDIT-FINDINGS.md` §4 landed independently, from
100 hand-adjudicated cases: *"treat it as a tiebreak signal, not a scoring
field."*

There is one blocking-adjacent use that does pay. `token-any` generates 96% of
all candidate pairs, and most of them are junk. A cheap sector-disagreement test
is usable as a **pruning filter** on that pass's output before the expensive
comparison runs — a negative filter, never a positive block, and only where both
sides have real text.

---

## 2. The fuzzy-match analogue for two blocks of text

Name matching uses edit distance because names are short strings that get
mistyped. Text blocks are different objects: order barely matters, length varies
by two orders of magnitude, and the failure mode is vocabulary mismatch rather
than character noise. The ladder, cheapest first:

**Jaccard / Dice on token sets.** The direct analogue of a name key, and the
thing MinHash + LSH hashes efficiently. Useless here on its own: with a 2-word
query against a 5,000-character document, |A ∩ B| / |A ∪ B| is dominated by the
document's length and every score collapses toward zero.

**TF-IDF cosine.** The right lexical baseline, and `npmatch` already owns the
machinery — `np_token_idf()` computes exactly this weighting for names. Reuse it
with the org-text corpus as the document collection so that `GENERAL`,
`CHARITABLE`, and `SUPPORT` self-cancel by low IDF.

**IDF-weighted containment — the primary scorer.** This is the one design point
that matters most. The query is 2 words; the document is 5,000. Symmetric
similarity is structurally near-zero for *every* pair, so it cannot rank them.
What you actually want to ask is asymmetric:

> what fraction of the purpose's content weight is present in the org text?

    coverage(q, d) = Σ_{t ∈ q ∩ d} idf(t) / Σ_{t ∈ q} idf(t)

Bounded 0–1, insensitive to document length, and undefined-by-construction when
the purpose has no content tokens — which is exactly the 45% of grants that
should abstain rather than score. BM25 is the standard alternative and handles
the same asymmetry through length normalization; either is defensible, and
coverage has the advantage of being trivially explainable in a review sheet
("2 of your 3 content words appear in their program text").

**Character 4-gram cosine.** Runs alongside as a morphology backstop. It is what
gets `SCHOLARSHIP` to `Scholarships` and `EDUC` to `Education` without a stemmer,
and it costs one more hashed vector. Noisy alone, useful as a second opinion.

Recommendation: `coverage` as primary, char-4gram cosine as secondary, both
computed only over pairs already in the candidate frame.

---

## 3. Matching meaning rather than words

Three tiers. Build the first, evaluate before buying the second.

### 3a. Bridge both sides through NTEE (build this)

The controlled vocabulary is already in the repo and is better than it looks.
`data/nteev2-descriptions-tidy-format.csv` has 1,086 codes with a five-level
hierarchy, human labels at every level, and a `keywords` column carrying 6,231
distinct keyword phrases across 42% of codes. Tokenized, labels plus keywords
give a 5,355-token domain vocabulary.

Measured against it:

| | |
|---|---|
| grants whose purpose shares ≥1 token with the NTEE vocabulary | 46.8% of all grants |
| …among grants with any content token | **85.1%** |

The residual misses are mostly morphology and jargon, not genuine gaps —
`SCHOLARSHIP` (1,667 grants) misses only because the vocabulary spells it
`Scholarships`, which the char-n-gram layer or a stemmer recovers. The real
unreachables are administrative noise (`PAYOUT`, `BUDGET`, `MIP`, `MEF`,
`DISCRETIONARY`), which is correctly unreachable.

So the design is: **map both sides into NTEE space and compare codes, not text.**

* Query side: purpose text (plus the grantee name, see §5) → predicted NTEE
  code(s) with a score.
* Reference side: the candidate's NTEE code, already in the BMF for 66.9% of
  records.
* Compare with a graded hierarchy penalty rather than a binary test: same level-5
  code > same level-4 > same level-3 > same major group > same sector >
  different sector. The tidy file's `level1`–`level5` columns give this for free.

The classifier does not need to be exotic. A weighted lexicon (IDF-weighted
centroid or multinomial naive Bayes) over the NTEE label + keyword +
`Category Description` text is a working first version. But there is a much
better training set sitting in the file we just built: **553,488 mission
statements, each labelable with its filer's own BMF NTEE code by an EIN join.**
That is a genuine supervised corpus for `text → NTEE`, in exactly the register
(self-described nonprofit purpose prose) that grant purposes are written in. Fit
on missions, apply to purposes.

This tier is cheap, offline, deterministic, explainable in a review sheet, and
degrades gracefully — when the purpose is contentless the classifier abstains
instead of guessing.

### 3b. Distributional similarity (evaluate, then decide)

NTEE bridging still fails when the purpose and the org text share neither tokens
nor an obvious code — the audit's `HANDICAP LIVING` → `GIANT STEPS ILLINOIS`
(B28 Specialized Education) case. Embeddings close that gap.

Cheapest option that works offline in pure R: **LSA — truncated SVD (≈300 dims)
of the TF-IDF matrix over the 553k mission + program corpus** (`Matrix` is
already installed; add `irlba`). Deterministic, no external service, no Python,
and it captures most of the available synonymy. Escalate to a sentence encoder
(via `reticulate` or a batch API call) only if an eval on labeled cases shows LSA
short — do not start there.

One caution that matters in this system specifically: an embedding score is
*dense*. Every pair gets a nonzero, plausible-looking number, including pairs
that share nothing. That is corrosive in a pipeline whose tiering depends on
crisp abstention. Use it to order candidates inside the tie band; never let it
clear an accept threshold on its own.

### 3c. LLM adjudication for the residual

The `MAYBE` tier is 11,040 of 50,000 grants, but the subset where this is worth
paying for is much smaller: top-2 within the tie band **and** the purpose has
content. That is the "foundation arm vs operating entity" class the audit
identified (Denver Art Museum vs Denver Art Museum Foundation; LiveOnNY vs
LiveOnNY Foundation) — seven cases in 100, and the class where every automatic
signal is structurally tied because both entities share a name, a ZIP, and a
sector. Batch the candidates with their NTEE and mission text and ask for a pick
plus a confidence. Keep it strictly last, on a strictly bounded subset.

---

## 4. One combined block, or per-field scores?

**Per field, weighted, with an explicit availability mask.** Four reasons, in
descending order of how much they cost you if ignored:

1. **Coverage differs per field by a factor of four** (§1: NTEE 66.9%, mission
   27.1%, program 17.2%, activity 37.2%). Concatenate them and a missing field
   silently dilutes the score — you can no longer distinguish *no evidence* from
   *evidence against*, which is precisely the distinction this pipeline's
   `MAYBE`/`NO` split rests on.
2. **Length asymmetry swamps the most reliable field.** A curated 6-word NTEE
   definition concatenated with a 5,000-character program block contributes ~1%
   of the term mass. The single most trustworthy signal would be the one that
   disappears.
3. **Reliability differs.** NTEE is externally assigned; mission is self-written
   and heavily boilerplate; program text is the most informative and the most
   padded; activity codes are frozen in 1970s vocabulary. These deserve different
   weights, and you can only estimate different weights if they are separate
   features.
4. **Auditability.** The review sheet needs to say *which* field agreed. A single
   blob is unauditable, and this project's whole method has been per-signal
   accounting.

Concretely, per (grant, candidate) pair:

| feature | source | note |
|---|---|---|
| `sim_ntee` | `ntee_code_definition` + level labels | plus the §3a code-distance term |
| `sim_mission` | `mission` | 990 + 990-EZ |
| `sim_program_max` | max over `program_NN_desc` | best single program |
| `sim_program_all` | all programs concatenated | purpose spanning programs |
| `sim_activity` | `activity_code_definitions` | 37% populated |

Do combine all program descriptions into **one field group** — they are the same
990 field repeated, not different fields. But keep both `max` and `all`: a
30-program hospital system should not have its one matching program diluted by
29 others (`max` handles that), while a purpose spanning several programs scores
better on `all`. Cheap to carry both and let the weights decide.

Combine availability-aware rather than as a plain mean:

    purpose_score = Σ_f w_f · s_f · avail_f  /  Σ_f w_f · avail_f
    n_fields_available = Σ_f avail_f

and carry `n_fields_available` forward, because a 0.8 from one field is not the
same evidence as a 0.8 from four. Fit `w_f` on labeled cases — do not hand-tune.
`dev/maybe-verdicts.csv` has 100 adjudicated cases, which is enough to sanity
check and not enough to fit four weights; expand it first.

---

## 5. Should the nonprofit name be in the match text?

**No — not in the block that is compared against grant purpose.** Two reasons,
and the second is the important one.

The weak reason is double counting: the name is what produced the candidate, so
folding it back into a second score re-uses the same evidence twice and inflates
agreement on pairs that were never in doubt.

The strong reason is that **including the name is positively correlated with the
error this feature exists to fix.** The mis-ranked `MAYBE` cases are precisely
the ones where the names are identical or near-identical — `Denver Art Museum`
vs `Denver Art Museum Foundation`, five identical `PURDUE UNIVERSITY` rows with
five different EINs, five identical `OHIO STATE UNIVERSITY` rows that are all 4-H
clubs. Adding the name to the text block on both sides gives every tied candidate
the same boost and destroys exactly the discrimination the feature was added for.

Two qualifications, both of which keep the name out of the *comparison* while
using it elsewhere:

* **The grantee name is a good input to the query-side NTEE classifier.** For the
  45% of grants with no content-bearing purpose it is the only text available,
  and `FOOD PANTRY`, `HISTORICAL SOCIETY`, `SYMPHONY` are strong sector cues.
  Use it to *predict a sector*, then compare codes — never to compute a text
  similarity against the candidate's name.
* **The filing foundation's own name and NTEE belong in a separate prior.** A
  foundation that funds only Jewish education, or only Ohio hospitals, carries
  real information about what its next grant is. `pf_candidate_frame()` already
  joins filer NTEE. That is a `filer_sector_prior` feature, not part of the
  recipient text block.

---

## 6. Where it plugs in

```
pf_prepare_grants()                          existing
pf_build_reference()                         existing, cached
pf_build_org_text()          NEW  ein -> {ntee_text, mission, prog_all,
                                          prog_list, activity_text}, normalized,
                                          tokenized, IDF from the corpus; cached
                                          like BMF-REFERENCE-BUNDLE.rds
pf_match_grants()                            existing -> candidate frame
pf_purpose_is_contentless()  NEW  rule cascade, query side
pf_purpose_features()        NEW  the five sims + availability mask, over
                                  candidate pairs only
pf_purpose_rerank()          NEW  applied inside the tie band only
pf_report()                                  existing
```

`pf_purpose_is_contentless()` should be a rule cascade in the shape of
`pf_standardize_status()`, not a stoplist lookup. The field contains `GOS`,
`As needed`, `Gen'l`, and at least one check stub
(`05/23/23CHECK 130CHARITABLE PURPOSES`); a cascade generalizes to spellings the
sample does not contain, which is the same argument that already won for column
(c).

### Guardrails

* **Tie band only.** Apply where name and geography have already failed to
  separate candidates. This protects the 49.5% `YES` that currently works and
  matches the audit's recommendation.
* **Never creates a match.** Purpose may reorder a candidate set and may promote
  `MAYBE` → `YES` when name evidence is already strong *and* purpose agrees. It
  may not admit a candidate the name cascade did not produce.
* **Abstain loudly.** Contentless purpose or no reference text ⇒ `NA`, not 0. A
  zero is evidence against; an `NA` is no evidence, and the tiering needs to tell
  them apart.
* **Watch the sign on the sector filter.** Purpose–NTEE *disagreement* is a
  weaker signal than agreement, because a grant's purpose describes the
  beneficiary program, which need not be the recipient's primary sector. Use
  disagreement as a soft veto at most.

### Join keys and vintage

The text table is keyed on `OBJECTID` and joins to candidates by `ORG_EIN`. Two
things to settle before wiring it up:

* **8,571 EINs have more than one 2022 return** (amended, short period, or
  successive filings). Pick one deterministically — prefer non-amended, then
  latest `TAX_PERIOD_END_DATE`, then longest mission — or the join fans out.
* **Vintage.** The 50k grant sample is tax year 2023; the text is 2022. That is
  fine as a proxy, but the org-text table should be built as *latest available
  return per EIN across years*, not 2022 only. Building it 2022-only leaves
  recall on the table for organizations that skipped or filed late.

### What to measure

Against `dev/BENCHMARK-NOTES.md`: 49.5% `YES` / 22.1% `MAYBE` / 22.8% `NO` /
5.6% `OOS` on 50k. The claim to test is not "the match rate went up" but the two
things this feature can actually do:

1. On the `MAYBE` tier, does the correct EIN move to rank 1 more often? The audit
   measured 53 of 100 already at rank 1 and 63 of 100 in the top five — the
   headroom is those 10 cases, and NTEE/activity text was decisive in 9 of the
   10 mis-ranked ones.
2. Does anything currently `YES` get *demoted* or reordered? It should not. Any
   movement there is a regression, not a gain.
