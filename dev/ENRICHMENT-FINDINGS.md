# Does appending NTEE, mission and program text help adjudicate MAYBE?

Yes — far more than the similarity experiments predicted, and for a reason those
experiments could not detect. This is the measurement, plus an independent check
on how accurate candidate-only review actually is.

**Short version.** Adding the candidate's own Form 990 text resolves **45 of 56
(80%)** hard cases that name and geography could not close. But almost none of
that comes from comparing the grant purpose to the mission. It comes from the
support organization *naming its parent in plain English* — "SUPPORTING AFFILIATE
OF EAGLE RANCH, INC." — and from the reader being able to see, definitively, that
none of the five candidates is the recipient. Both are reading tasks, not
similarity tasks, which is why `dev/PURPOSE-MATCH-FINDINGS.md` measured them at
near zero.

And the uncomfortable half: **candidate-only review, with no text and no search,
survives independent verification on roughly 5 of 12 cases.** The dominant error
is not picking a random wrong org — it is failing to separate an operating entity
from its own fundraising arm, in both directions.

---

## 1. The experiment

The 200 labelled auto-accept cases (`dev/autoaccept-verdicts.csv`) were labelled
from a view showing **only** name, city, state, ZIP and match scores. The 56 that
came back WRONG (37) or AMBIGUOUS (19) are exactly the population that needs
adjudication.

`dev/build-enriched-hard.R` rebuilds those cases with everything the design memo
proposed appending, for **all five** candidates:

| field | source |
|---|---|
| NTEE code + IRS definition + NTEEv2 description text | BMF + `inputs/nteev2-descriptions-tidy-format.csv` |
| IRS activity-code text, subsection, revenue | BMF |
| Form 990 Part III mission | `data-dev/F9-P03-TEXT-WIDE-2022.rds` |
| Form 990 Part III program service descriptions | same |

Output: `data-dev/HARD-ENRICHED.csv`, 895 candidate rows. Verdicts on re-reading:
`dev/enrichment-verdicts.csv`; scoring: `dev/score-enrichment.R`.

## 2. Result

| outcome | n | share |
|---|---:|---:|
| **RESOLVED_ALT** — text identifies a *different* candidate as correct | 14 | 25% |
| **RESOLVED_PICK** — text confirms the top pick after all | 8 | 14% |
| **RESOLVED_NONE** — text proves no candidate is the recipient | 23 | 41% |
| HELPS — narrows, does not decide | 9 | 16% |
| SILENT — adds nothing | 2 | 4% |

**45 of 56 resolved (80%, 95% CI 68–90%)**: 22 yield a usable EIN, 23 yield a
confident NO. Split by the original label:

| original | ALT | PICK | NONE | HELPS | SILENT |
|---|---:|---:|---:|---:|---:|
| WRONG (37) | 9 | 1 | 20 | 5 | 2 |
| AMBIGUOUS (19) | 5 | 7 | 3 | 4 | 0 |

Of 37 cases the rule got wrong, **9 are recovered to a different EIN** and **20
become a confident NO** instead of an unresolved MAYBE. The second number is worth
as much as the first: `DEFINITE NO` is a terminal state in the cascade, and these
cases can now enter it instead of consuming a review slot forever.

## 3. Why it works, and why similarity missed it

62% of resolutions rest on a **verbatim string in the candidate's own 990**:

* Eagle Ranch Foundation — "IS THE SUPPORTING AFFILIATE OF EAGLE RANCH, INC."
* Kansas Food Bank Foundation — "TO SERVE AS A FUNDRAISING AND SUPPORT
  ORGANIZATION FOR THE KANSAS FOODBANK WAREHOUSE, INC."
* Dallas Arboretum Foundation — "THE SOLE PURPOSE ... IS TO HOLD ASSETS TO SUPPORT
  THE OPERATIONS OF THE DALLAS ARBORETUM AND BOTANICAL SOCIETY, INC."
* Brauser Maimonides — the BMF row reads `MAIMONIDES SHALOM ACADEMY`, but its own
  990 mission opens "THE LEON AND LEONA BRAUSER MAIMONIDES ACADEMY". Same EIN,
  two names. Independently confirmed: EIN 65-0213879 carries both.

This is a **relation between two candidates in the same list**, not a similarity
between a candidate and the grant purpose. Cosine and IDF containment compare the
purpose to each candidate independently and therefore cannot see it. The earlier
finding — that text similarity is worth about +2 grants in 28 — stands; it was
measuring a different thing.

### The mechanical versions do not survive

Two attempts to extract the signal without a reader, both measured:

| rule | fires | precision as a demote flag | 95% CI |
|---|---:|---:|---|
| top pick's 990 text matches a support-phrase regex, runner-up's does not | — | — | — |
| top pick carries an NTEE support code (`?11`/`?12`), runner-up does not | 15 | 60% | 32–84% |
| top pick is `X FOUNDATION`, runner-up is exactly `X` | 7 | 71% | 29–96% |

The regex is worse than useless: the support phrase fires on **11%** of WRONG top
picks and **22%** of CORRECT ones — the wrong direction, because legitimate
grantees describe themselves as supporting their community. The NTEE code rule
points the right way but is 60% precise on 15 cases, and a usable NTEE is present
on only **52%** of top picks, missing most often on exactly the large
organizations that create the ambiguity.

Neither is shippable as an automatic demotion. Both are usable as **review
priority flags**.

## 4. Coverage is the ceiling

| | hard cases | correct cases |
|---|---:|---:|
| candidate has 990 Part III text | 42.8% | 47.5% |
| candidate has a usable NTEE | 63.6% | 64.0% |
| candidate has program descriptions | 34.5% | 37.4% |
| grants where *every* candidate has text | 7% | 14% |
| grants where *no* candidate has text | 16% | 9% |

Text is scarcer precisely where it is needed. The 80% resolution rate is achieved
*despite* only 43% of candidates having any 990 text — because the reader needs
text on only one candidate, usually the support arm, whose 990 is the one that
names the relationship. That asymmetry is what makes the approach work at this
coverage.

---

## 5. How accurate is candidate-only review? Independently checked

The 200 labels were produced by an LLM reading candidates only, with no search.
Scoring those labels against themselves would be circular, so **12 cases were
verified independently** by web search against GuideStar / ProPublica / Charity
Navigator / IRS records, stratified across the three verdict classes.

| outcome of independent check | n |
|---|---:|
| label confirmed | 5 |
| label wrong, **conservative** — rejected a defensible correct pick | 4 |
| label wrong, **permissive** — accepted or tolerated an incorrect pick | 3 |

Reweighting the strata to the population mix gives roughly **45% of labels
surviving unchanged**, on 12 checks — an interval far too wide to quote as a
point estimate, but not consistent with the 72% the labels imply about themselves.

The failures are one shape:

* **#11 Blackhawk** — labelled WRONG. EIN 39-1391659's GuideStar profile is
  literally *"Blackhawk Vocational Technical District Educational Foundation"* —
  the grant recipient's exact name. The label was wrong; the pick was right.
* **#90 Families First of Palm Beach County** — labelled CORRECT. The picked EIN
  45-5184288 is the *Foundation*; the operating organization named on the grant is
  EIN 65-0166352. A false accept.
* **#46 Anna Jaques** — labelled AMBIGUOUS. The recipient, Anna Jaques Community
  Health Foundation, has its own EIN 04-3318952, distinct from the hospital's
  04-2104338. The pick was simply wrong.
* **#19 College of Lake County**, **#76 South Haven Public Schools**, **#169 Valley
  View Elementary** — the same public-institution-vs-its-foundation question,
  labelled WRONG, CORRECT and WRONG respectively. Independent evidence says all
  three are genuinely open. The reviewer was inconsistent on identical structure,
  which is visible without any ground truth at all.

**The reviewer is not confused about which organization is which. It is guessing
which of two real, related EINs received a particular check — and the 990 does not
record that.** Some of these have no determinate answer from any public source.

### The enriched read agrees with the independent check

Eight of the twelve verified cases are in the 56-case hard set. The text-enriched
re-read agrees with independent verification on **8 of 8** — including every case
where it *disagreed* with the original candidates-only label (#11, #19, #46,
#169, #194). Small, and not blind: the enriched read was done knowing the earlier
labels. But it disagreed in exactly the places verification did.

## 6. Confidence: yes, and here is the variable to calibrate

The evidence class recorded during the enriched read is the natural confidence
signal, because it is a property of the *evidence*, not of the reader's feeling:

| class | n | what it means | proposed confidence |
|---|---:|---|---|
| QUOTE | 28 | a verbatim sentence in a candidate's own 990 decides it | high — auditable |
| NTEE | 2 | the classification code alone decides it | medium |
| INFER | 24 | no single string; reasoning over the whole packet | low — needs a second pass |
| NONE | 2 | nothing to read | none — route to search |

This is worth adopting for one reason above the rest: a QUOTE verdict can be
**audited** — the reviewer names the sentence, and anyone can check it. That
converts adjudication from an opinion into a citation. A model's self-reported
probability has no such property and, on the evidence of §5, would have been
confidently wrong on #90 and #11 alike.

Calibration is not yet measured. It requires labelling a fresh batch with the
evidence class attached, then verifying a stratified subsample independently. That
is the next measurement, not a claim already established.

## 7. Are we at the limit?

For **record linkage**, close to it. Name and geography are exhausted: YES is 99.8%
state-consistent, the promotion floor, the comparator fix, truncation-aware
comparison and the IDF gate were each measured and each moved single-digit numbers
of cases. `dev/COMPARATOR-FINDINGS.md` and `dev/TRUNCATION-FINDINGS.md` are both
negative results. There is no remaining string trick of consequence.

For **adjudication**, no — and this experiment is the evidence. The 80% resolution
rate on cases the cascade could not close is a large amount of headroom, and it
was invisible to every automated metric tried. But the headroom is only reachable
by a reader, and only with the text appended.

The genuine floor is different from both, and it is not a modelling problem:

1. **The operating-entity-vs-fundraising-arm question often has no determinate
   answer.** The foundation reports a name and an address; both entities share
   both. Nothing in any public dataset records which EIN was on the check. A
   perfect system returns AMBIGUOUS here, and the honest target for this
   population is a well-calibrated AMBIGUOUS rate, not a higher match rate.
2. **Government units are not in the BMF.** School districts, towns, public
   universities. The grant is real, the recipient is real, and there is no row to
   match to. `RESOLVED_NONE` is the correct answer and it is 41% of the hard set.
3. **Text coverage is 43% and structurally biased.** 990-EZ filers have no program
   descriptions; small real grantees have no text at all.

## 8. What to do with this

1. **Ship the enriched candidate view as the review packet.** `pf_candidate_frame()`
   should carry NTEE definition text, mission and program descriptions for every
   candidate, not just the top pick. This is the single highest-value change
   available and it is data plumbing, not modelling.
2. **Require an evidence class and a quoted sentence on every verdict.** Reject
   verdicts that assert a QUOTE class without a quotable string.
3. **Make NONE prominent.** 41% of the hard set resolves to "no candidate is the
   recipient". An instruction set that implies one of five is right will
   manufacture false positives at exactly that rate.
4. **Add the two structural flags as review-priority signals, not as decisions** —
   NTEE support code on the pick with a non-support runner-up (60% precise), and
   the `X FOUNDATION` / `X` name shape (71% precise).
5. **Treat the entity-vs-arm cases as a named category with its own policy.**
   Either accept the operating entity by convention and record the convention, or
   return AMBIGUOUS. Do not let it be decided case by case — §5 shows that
   produces inconsistent answers on identical structure.
6. **Calibrate before trusting.** Label a fresh batch *with* the evidence class,
   verify a stratified subsample independently, and report accuracy per class.

## 9. Other ideas for MAYBE, ranked by expected value

| idea | why it might work | status |
|---|---|---|
| **Cross-year consistency within a filer** | The same foundation names the same grantee across years, sometimes with a fuller name in one year. Propagating the best-resolved form across a filer's own history is free and uses no external data. | untested, highest EV |
| **Grantee-side corroboration** | Large grants appear on the *recipient's* 990 Schedule B / Part III. If a candidate's own 990 text names the filing foundation, that is direct confirmation of the pair. Narrow but decisive when it fires. | untested |
| **Recipient co-occurrence across foundations** | An org receiving grants from many foundations under near-identical name+address is a real, active grantee. A distinctive-name cluster with many distinct filers is strong evidence. | untested |
| **Portfolio prior from resolved grants** | Measured and weak — foundations spread across a median 5 NTEE major groups. | rejected, `PURPOSE-MATCH-FINDINGS.md` §2 |
| **Files-a-990-at-all as a tiebreak** | Best single content-free feature (AUC 0.81 on `text_len`), but it is a size prior that systematically disfavours small real grantees. | measured, use only inside the tie band |
| **Purpose ↔ mission similarity** | +2 grants in 28. | measured, marginal |
