# The hand-labelled slice — shard 99

40 cases of stage 1, to be labelled **by hand**. This is
`dev/TRUTH-LABELING-PROTOCOL.md` §6 step 4, and it is the step that turns the
round's agreement figures into an error rate.

Read `dev/TRUTH-LABELING-PROTOCOL.md` first. It is the same protocol the model
labelers worked from, and this is the same task — §1 through §4 apply
unchanged. What follows is only what is specific to this slice.

## Your two files

| file | what it is |
|---|---|
| `shard-99-cases.csv` | your 40 cases. Same columns the models got. |
| `shard-99-truth.csv` | the template you fill. `grant_id`, `population`, `labeler` and `shard` are already set — **do not change them.** |

## Do not open this one

**`HELD-slice-design-and-model-labels.csv`** holds what the models said, and
also the slice's sampling weights. Leave it closed until your own 40 rows are
finished.

It is one file rather than two because the slice is stratified on the model's
verdict, so a design table sitting beside the cases would leak the answer. The
rows in `shard-99-cases.csv` are shuffled for the same reason.

## You are labelling, not scoring

Work each case and write your own verdict. Do not look up what a model said
and mark it right or wrong — that is a *review*, and a review is the worst
available instrument here:

- The model notes are well argued. A confident wrong answer with a plausible
  chain of reasoning is exactly the error this slice exists to find, and
  reading the chain first is how you end up agreeing with it.
- A review can only catch errors you notice. Labelling independently catches
  the case where you find an EIN the model never considered.

It is the same principle §6 step 3 already applies to the models: where two
labelers agreed, the consolidated row keeps the **weaker** basis of the two,
because concurrence is not corroboration.

**You will see the cascade's pick** (`cascade_ein` and the `cascade_*` columns).
That is deliberate and the models saw it too — §4 asks for `wrong_ein` "an EIN
you ruled *out* ... especially when it is the cascade's pick", which you cannot
supply without being told what it was. Withholding it from you would make the
comparison invalid, because you would be doing a different task.

## What to fill

One row per case: `verdict`, `correct_ein` (9 digits, required when
`ORG_FOUND`), `wrong_ein`, `basis`, `confidence`, `source_url` (**required when
`basis` is `web`**), and `note` — one sentence on what decided it. Leave
`truth_id` blank; the model labelers did too, because the round is at identity
grain and `truth_id` is a grant-row key.

The five verdicts, and the boundaries that actually bite:

| verdict | use it when |
|---|---|
| `ORG_FOUND` | an exempt organisation exists and you can name its EIN |
| `NO_ORG_NOT_EXEMPT` | the payee is real but has no exemption of its own — a government body, a public school, a program of a larger entity |
| `NO_ORG_INDIVIDUAL` | the payee is a person |
| `NO_ORG_UNFINDABLE` | an organisation probably exists but the evidence cannot separate two or more real candidates |
| `UNRESOLVED` | you cannot settle it at all |

`NO_ORG_NOT_EXEMPT` against `NO_ORG_UNFINDABLE` is the call most likely to
differ between you and a model for reasons that are *not* error. Worth walking
through two or three cases before committing to all forty — the grade treats
these as different outcomes.

**Leave a row blank rather than guess.** `pf_read_truth()` reports blank rows
as missing, so a partial slice is still usable. A guess is not: it goes into
the denominator under every figure graded against this.

## Then

```bash
Rscript dev/grade-hand-slice.R
```

It validates your file the same way a model shard is validated, converts the
model labels into the arm schema, and grades them against yours with
`pf_grade_verdicts()`. Output separates `CORRECT` / `WRONG_EIN` /
`FALSE_MATCH` / `MISSED` / `RULED_OUT`, weights the result back to the
400-case round using the slice's sampling fractions, and lists every case the
models did not get right.

## How this slice was built

`dev/draw-hand-slice.R`, seed `20261103`, population `cb3c78ff0f1a9546`.

Stratified on the model's verdict with floors on the small classes — 24
`ORG_FOUND`, 5 `NO_ORG_NOT_EXEMPT`, 5 `NO_ORG_UNFINDABLE`, 3
`NO_ORG_INDIVIDUAL`, 3 `UNRESOLVED` — because a simple random 40 of 400 would
have held one or two of each `NO_ORG_*` class, and the model's *declines* are a
quarter of the measured error. Weights are recorded so the round-level rate is
recovered without bias.

The small per-class cells are there to **detect** a broken class, not to
measure one: four `NO_ORG_UNFINDABLE` cases all turning out findable is a
signal worth having, and is not a rate.

7 of the 40 happen to be cases two models labelled and agreed on — not
stratified for, since that would load the slice toward cases the models found
easy, but reported as a free subgroup read. That subgroup is the one nothing
inside the round can see.
