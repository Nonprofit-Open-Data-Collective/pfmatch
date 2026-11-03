# Establishing ground truth for a shard of the labelling round

Written 2026-11-02. An **appendix** to `dev/LLM-REVIEW-INSTRUCTIONS.md`, not a
replacement for it. That file is how to decide whether a candidate is the
recipient, and all of it still applies: the name traps, the lockbox and
national-headquarters exceptions, the arm-vs-operating-entity rule, and above
all that **`NONE` is a correct and common answer** — 24 of 82 hard cases had no
correct candidate at all.

Read that file first. This one says what is different when you are producing
**truth** rather than a reviewer's verdict, and it is different in three ways
that matter.

---

## 1. You are not an arm. You have more than the arms do.

The round grades four model arms against these labels. Those arms see a
five-candidate packet and, in one case, a web search. You see the packet **and**
the whole reference, the whole web, and no obligation to pick from the five.

This is the only thing that makes the round mean anything. If you decide the
case from the packet alone, you are the deep arm under another name, and grading
the deep arm against you measures agreement between two instances of the same
procedure — which comes out high and tells nobody anything.
`dev/METRIC-SHAPES.md` is in the repository because that figure looks like
evidence and is not.

So: **look the organisation up.** Search for the name and city. Open the
organisation's own site. Check the BMF for the EIN you land on. A case you
cannot settle that way is an `NO_ORG_UNFINDABLE` or an `UNRESOLVED`, which are
both real answers, and both more useful than a packet-shaped guess.

---

## 2. The verdict set is different, because the question is different

`pf_verdict_levels()` — `MATCH` / `NONE` / `AMBIGUOUS` — answers "what did a
reviewer conclude from these five candidates". You are answering "what is the
right answer for this grant", so you use `pf_truth_levels()`:

| verdict | when |
|---|---|
| `ORG_FOUND` | an exempt organisation received this grant and you have its EIN |
| `NO_ORG_INDIVIDUAL` | the payee is a person — a scholarship or hardship grant paid to a named individual |
| `NO_ORG_NOT_EXEMPT` | a real payee with no exemption of its own: a government body, a for-profit, a chapter filing under a parent, a fiscally sponsored project |
| `NO_ORG_UNFINDABLE` | an organisation almost certainly received it and you could not establish which, after looking |
| `UNRESOLVED` | you cannot even tell which of the above applies |

Two of these are easy to conflate and must not be. `NO_ORG_UNFINDABLE` says
*you* failed; `NO_ORG_NOT_EXEMPT` says *the BMF* has nothing to find. A pipeline
that returns nothing is wrong in the first case and right in the second, and
pooling them makes the recall figure meaningless.

`UNRESOLVED` costs the round one row and nothing else — `pf_grade_verdicts()`
excludes it from the denominator. A wrong `ORG_FOUND` costs the round a false
label that every downstream figure is then measured against. When in doubt,
`UNRESOLVED`.

---

## 3. `basis` has to be earned

Every row carries a `basis`, and it is not a description of how you feel about
the answer. It is the column a later analysis uses to decide which rows are
allowed to grade a model arm, and `pf_read_truth()` enforces part of it.

| `basis` | what it requires |
|---|---|
| `web` | a page you actually opened, named in `source_url`. **`pf_read_truth()` refuses a `web` row with no URL.** |
| `reference` | the BMF/reference row itself settled it — name, address and activity text agree and nothing contradicts |
| `inference` | neither: you concluded it from the packet, the funder's sector, the grant purpose |

An `inference` row is honest and usable. An `inference` row labelled `web` is
the defect: it claims an independent check that did not happen, and it will be
the row that licenses a 96% accuracy claim.

`confidence` is `high` / `medium` / `low`, and means the same as everywhere else
in this project — your own read, collected so that it can be *tested*, not
trusted. Over the two MAYBE rounds on disk, reviewer accuracy fell monotonically
with it in 5 of 5 arms (100/81/25% in the steepest). Use `low` freely; a `low`
row can be filtered out by `min_confidence`, and a `high` row that is wrong
cannot.

---

## 4. What you are given, and what you return

Two files, named for your shard:

* `shard-NN-cases.csv` — your cases. `grant_id`, `stratum`, and the case
  features from the draw.
* `shard-NN-truth.csv` — the template you fill. `grant_id`, `population` and
  `shard` are **already filled in. Do not change them.** `population` is a
  16-character fingerprint of the grant file these labels belong to.
  `grant_id` is a `PFI-` id derived from the recipient's own normalized name
  and address, so it names the organisation rather than its position in a
  file — see `pf_identity_id()`.

  Until 2026-11-03 it was `R<k>`, a position among the deduplicated
  recipients, and that was a real hazard rather than a pedantic one: a rebuild
  that merged duplicate identities renumbered everything after the first merge,
  so a label would re-attach to a *different* organisation while still passing
  the `population` check. Any label file carrying `R<k>` ids predates the fix
  and must not be re-attached to a current frame.

Fill one row per case: `truth_id`, `verdict`, `correct_ein` (9 digits, required
when `ORG_FOUND`), `wrong_ein` (an EIN you ruled *out* — a negative constraint
is worth recording, especially when it is the cascade's pick), `basis`,
`confidence`, `labeler` (your model id and harness, or your name — the same
string on every row), `source_url`, and `note`: one sentence on what decided it.

Leave a row blank if you did not get to it. `pf_read_truth()` reports blank rows
as missing rather than refusing the file, so a partial shard is still usable.
A guess is not.

---

## 5. Two rules about other people's shards

**Work only your own shard.** Some cases were dealt to two labelers on purpose,
and agreement on those is the measurement that decides whether this truth set is
worth anything ([`pf_labeler_agreement()`]). Nothing in your files tells you
which ones they are, and that is deliberate.

**Do not open `SHARD-KEY.csv`.** It names the overlap. Reading it does not
corrupt your answers in any way you would notice, which is exactly the problem:
the agreement figure would then be unfalsifiable, and an unfalsifiable figure is
not evidence.

---

## 6. How this gets checked, so you know what the labels are for

1. `pf_read_truth()` validates every shard and refuses the schema violations
   above.
2. `pf_labeler_agreement()` reports agreement on the blinded overlap, overall
   and **per labeler**. A labeler that disagrees with everyone shows up here.
3. `pf_consolidate_truth()` collapses the round to one row per case. Where two
   labelers agreed, the row keeps the **weaker** basis and confidence of the two
   — concurrence is not corroboration. Where they disagreed, the case becomes
   `UNRESOLVED`; it is not tie-broken on confidence, because self-reported
   confidence is the thing `ADJUDICATION-PREREQS.md` T3 exists to test.
4. A hand-labelled slice is scored against the labelers with
   `pf_grade_verdicts()`. **That** is what turns agreement into accuracy, and
   until it exists the round's truth has an unknown error rate.

Step 4 is the one that is not automatable, and the reason step 2's figure is
reported with the sentence "agreement is NOT accuracy" printed underneath it.
