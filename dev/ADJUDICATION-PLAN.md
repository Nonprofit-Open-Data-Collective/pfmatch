# Adjudicating the MAYBE tier

MAYBE is the largest remaining lever: 20.1% of grants, and 63% of them contain
the correct EIN among the surfaced candidates. This is the plan for resolving
them, and the measurement behind it.

The design mirrors `npmatch`'s own YES/MAYBE/NO fork: sort into an **easy
branch** that can be closed automatically, and a **hard branch** that gets a
best-guess default plus a review packet. Nothing is discarded.

---

## 1. Can it be automated? Measured twice, and the answer is no

> **Superseded, 2026-08-20.** An earlier version of this section recommended
> auto-accepting on `ZIP5 agrees AND margin >= 0.05`, measured at **18/18 =
> 100%** on the first 100-case sample. That rule was then tested on **200 fresh
> labelled cases** drawn from a larger pool (`dev/autoaccept-verdicts.csv`).
> **It is 72% precise, not 100%.**

| verdict on the 200 | n | share |
|---|---:|---:|
| CORRECT | 144 | 72.0% |
| AMBIGUOUS | 19 | 9.5% |
| **WRONG** | **37** | **18.5%** |

Strict precision **72% (95% CI 65-78%)**; 80% if AMBIGUOUS cases are excluded.
18 successes gives a 95% CI of 82-100%, so the first estimate was not merely
small — the true value sits below even that interval, because the second sample
was drawn from a different mix.

### Why it failed, structurally

**79% of the firing cases are `TOKEN_OVERLAP` matches.** npmatch caps those
below YES *deliberately* — its own comment says containment "cannot separate a
parent from a subsidiary, auxiliary or chapter". The rule was auto-accepting
precisely the population npmatch had already marked unsafe.

No tightening rescues it:

| rule | fires | precision | 95% CI |
|---|---:|---:|---|
| as proposed | 200 | 72% | 65-78% |
| + `name_ver == MAIN` | 41 | 66% | 49-80% |
| + MAIN & name_sim = 1 & margin >= 0.20 | 19 | 79% | 54-94% |
| + score >= 0.95 & margin >= 0.20 | 20 | 80% | 56-94% |

The best variants reach ~80% on ~20 cases — an interval consistent with 56%.
Note that `name_ver == MAIN` *lowers* precision here (66% vs 74% for
TOKEN_OVERLAP), which is the opposite of what one would guess.

### The three error shapes

All are invisible to score and geography:

1. **Entity vs its own foundation** — 10 wrong and 10 ambiguous of 55 such
   cases. `EASTERN VIRGINIA MEDICAL SCHOOL` to its Foundation, `MATER DEI HIGH
   SCHOOL` to `MATER DEI FOUNDATION`. In 13 cases the plain entity is sitting in
   the list **as the runner-up** and the rule took the foundation anyway.
2. **Institution to its auxiliary** — `CONY HIGH SCHOOL` to the middle-school
   parent group; `BEEKMANTOWN CENTRAL SCHOOL DISTRICT` to `Beekmantown
   Athletics`; `NEW UTRECHT HIGH SCHOOL` to `FRIENDS OF HISTORIC NEW UTRECHT`.
3. **Shared local token, unrelated body** — `Town of Westport` to `BAHAIS OF
   WESTPORT TOWN`; `STANFORD LAW SCHOOL` to the business-school alumni
   association; `UNICEF USA` to `UNICEF USA IMPACT FUND` while `UNITED STATES
   FUND FOR UNICEF` — the actual legal name — was the runner-up.

### What survives

* **No fully automated acceptance of MAYBE.** The whole tier goes to review.
* **One useful negative rule:** an exact-name candidate sitting as runner-up
  behind a `... FOUNDATION` top pick is a reliable demote-or-review flag. It
  fired on 13 of 200.
* The 200 labelled cases are now the project's largest ground-truth set and are
  reusable for any later scoring work.

## 2. The fork

```
MAYBE (1,006 in the 5k sample)
├── EASY   ZIP5 agrees AND margin >= 0.05          ~18%  -> auto-accept as YES
└── HARD   everything else                         ~82%  -> best guess + review packet
           ├── best_guess = top pick, always populated
           ├── confidence = high | medium | low
           └── review packet -> LLM or human
```

**Superseded** -- with no safe auto-accept rule, all ~1,006 go to review. The
fork below is retained as the design for CONFIDENCE tiering within the review
queue, not for skipping review.

The hard branch always carries a `best_guess` so preliminary analysis can run on
messy data immediately, with `confidence` available as a filter. Nobody has to
wait for adjudication to finish to get a usable file — they just have to know
which column they are trusting.

### Confidence tiers on the hard branch

| tier | criterion | ~share of hard | use |
|---|---|---:|---|
| high | margin ≥ 0.10, or name_sim = 1.0 with one candidate in band | ~35% | usable in aggregate analysis |
| medium | ZIP5 or state agrees but the field is crowded | ~40% | usable with caveats |
| low | no geographic corroboration, or ≥3 candidates tied | ~25% | do not use unresolved |

---

## 3. What the review batch actually contains

From the labelled set, of the 82 cases a ZIP5+margin rule does *not* auto-accept:

| | n | note |
|---|---:|---|
| top pick was right anyway | 35 | reviewer confirms; cheap |
| correct EIN present, ranked lower | 10 | reviewer picks from the list |
| ambiguous among related EINs | 13 | foundation arm vs operating entity |
| no correct candidate present | 24 | reviewer must return NONE |

**Only 55% of the review batch is resolvable from the candidate list at all.**
A reviewer — human or LLM — must be able to answer NONE, and must not be scored
against a target that assumes an answer exists. This is the single most important
thing to get right in the instructions.

---

## 4. Prioritize by dollars, not by row

Grant dollars are extremely skewed (`dev/GRANT-DOLLARS-FINDINGS.md`). Sorting the
review queue large-to-small:

| review effort | share of recoverable unresolved dollars |
|---:|---:|
| 195 cases | 50% |
| **738 cases** | **70%** |
| 1,475 cases | 80% |
| 3,528 cases | 90% |

**~740 reviews covers 70% of the recoverable unresolved dollars.** That is the
budget to plan against — roughly a week of one person, or a modest LLM batch.

Two exclusions before the queue is built:
* **Non-itemizing returns** (`SEE ATTACHED`) — 497 returns, $394M. Unresolvable
  by review; they get their own report, see §6.
* **Foreign recipients** — no BMF row exists. Reported separately, not reviewed.

---

## 5. LLM review, and how to keep it honest

The review packet is `pf_candidate_frame()` output: per candidate, the BMF name,
address, NTEE code and definition, activity text, subsection, assets, plus the
grant purpose and the filing foundation's own NTEE and state.

**Amended 2026-08-20.** It must also carry, for **every** candidate and not just
the top pick, the NTEEv2 description text and the Form 990 Part III mission and
program descriptions. Measured on 56 hard cases, that addition resolves **45 of
56 (80%)** -- 22 to a usable EIN, 23 to a confident NO. See
`dev/ENRICHMENT-FINDINGS.md`. Nothing else tested on this project moves the
MAYBE tier by a comparable amount, and it is data plumbing rather than modelling.

Instructions live in `dev/LLM-REVIEW-INSTRUCTIONS.md`. The design constraints
that matter:

1. **NONE must be a first-class answer.** 24 of 82 hard cases have no correct
   candidate. An instruction set that implies one of the five is right will
   manufacture 24 false positives.
2. **Every verdict carries the evidence that decided it**, so the output is
   auditable rather than a bare EIN.
3. **Seed the batch with ~15% known-answer cases** drawn from
   `dev/maybe-verdicts.csv`. Measured accuracy on those is the only check on
   whether the run is trustworthy, and it costs nothing to include them.
4. **Foundation arm vs operating entity is a real distinction, not a tie to
   break.** `DENVER ART MUSEUM` and `DENVER ART MUSEUM FOUNDATION` are two EINs.
   Where the grant purpose does not disambiguate, `AMBIGUOUS` is the correct
   answer.

---

## 6. Non-itemizing returns — a separate product

`pf_attached_report()` (`R/attached.R`), one row per filer-year:
`filer_ein`, `filer_name`, `taxyear`, `n_placeholder_rows`, `placeholder_amount`,
`n_itemized_rows`, `itemized_amount`, `total_amount`, `pct_dollars_hidden`,
`placeholder_text`, `url`.

Over the 150,000-grant sample: **497 returns, 509 rows, $394,077,696 not
itemized, and 466 of those returns hide 100% of their grant dollars.**

### The e-file does not contain the detail — tested

Eight of these returns were fetched and inspected
(`dev/probe-attached-xml.R`, `dev/check-xml-attachments.R`):

* Every one files **exactly one** `GrantOrContributionPdDurYrGrp`, whose
  `BusinessNameLine1Txt` is the placeholder text and whose `Amt` is the full
  year's total.
* Every one declares **`binaryAttachmentCnt="0"`**.
* No `SupplementalInformationDetail`, no `AttachmentInformation`.
* The three returns with any line over 400 characters hold narrative text
  (grant-program descriptions, compensation explanations), not grant lists.

Verbatim, from the Craig H. Neilsen Foundation's 2021 return:

```xml
<GrantOrContributionPdDurYrGrp>
  <RecipientBusinessName>
    <BusinessNameLine1Txt>SCHEDULE AVAILABLE UPON REQUEST</BusinessNameLine1Txt>
  </RecipientBusinessName>
  <RecipientUSAddress>
    <AddressLine1Txt>ADDL RECORDS AT 16830 VENTURA BLVD</AddressLine1Txt>
  </RecipientUSAddress>
  <Amt>29850070</Amt>
</GrantOrContributionPdDurYrGrp>
```

**An XML-recovery script cannot work.** The itemization was never filed
electronically; it exists on paper, "available upon request". The address line is
the filer's own record-keeping address, not a recipient.

What the XML *does* give reliably is the filer EIN, tax year and authoritative
Part XIV totals — already in the report. If the detail is ever wanted it has to
come from a written request to the foundation, or from a different source
(grantee-side 990 Schedule B, foundation annual reports).

---

## 7. Order of work

Revised 2026-08-20 after the auto-accept rule failed validation (section 1) and
the text-enrichment experiment succeeded (`dev/ENRICHMENT-FINDINGS.md`).

1. ~~Label 200 fresh cases and confirm precision >= 97%.~~ **Done. 72%.** No
   automated acceptance of MAYBE.
2. **Extend `pf_candidate_frame()` to attach NTEE description text, 990 mission
   and program descriptions to every candidate.** Highest-value item on the
   project; `dev/build-enriched-hard.R` is the working prototype.
3. Implement `pf_adjudicate_auto()` emitting `best_guess` + `confidence` on every
   row -- for *tiering the review queue*, never for skipping review.
4. Add the two structural review-priority flags: NTEE support code on the pick
   with a non-support runner-up (60% precise, n=15), and the `X FOUNDATION` / `X`
   name shape (71% precise, n=7). Flags, not decisions.
5. Build the dollar-sorted review queue (~740 cases for 70% of dollars).
6. Run the LLM batch on the **enriched** packet, requiring an evidence class
   (QUOTE / NTEE / INFER / NONE) and a quoted sentence on every verdict.
7. **Calibrate**: verify a stratified subsample of the batch independently by
   search and report accuracy per evidence class. Candidate-only review survived
   independent verification on only ~5 of 12 checks; no accuracy claim should be
   made without this step.
8. Set an explicit policy for the entity-vs-fundraising-arm category rather than
   deciding it case by case -- inconsistency on identical structure is the
   dominant measured failure.
