# Where the published figures come from

Written 2026-11-01. An audit, not a fix: nothing outside this file was changed,
and no compute script was written. Where a figure could not be settled by
reading, what would settle it is recorded instead.

This applies practice 1 of `dev/PLAUSIBLE-WRONG-NUMBERS.md` — "compute every
published figure; retype none" — to the figures already in the repo, and asks of
each one whether a reader could re-derive it. The standard is that note's:
**a figure that cannot be re-derived by running a file is a figure nobody can
check.** Practice 4, "read the denominator", is applied to every table reached.

Classes, as commissioned:

* **(a) re-derivable** — a named `dev/*.R` prints *that* figure.
* **(b) retyped from a run log** — the number is in a `.log`, hand-carried into
  prose.
* **(c) unattributable** — no script and no log ties to it.

**What was executed.** R 4.5.1 is installed at
`/c/Program Files/R/R-4.5.1/bin/Rscript.exe`. It is **not on `PATH`**, which is
why a first pass of this audit wrongly recorded that nothing could be run; that
caveat has been removed and the affected verdicts redone. What ran, all
read-only and all writing nothing:

* `dev/adjudicate-18-layer-costs.R` — executed as committed. Every §Phase 4b
  dollar figure reproduced, **including the wrong ones**: it printed
  "521 s, 8.9%" and "~136 core-hours" in front of me, which is finding 2
  demonstrated rather than inferred.
* `dev/ab-idf-gate.R` — executed read-only against the cached
  `data-dev/PF-MATCH-RESULT-1k.rds`. Reproduced two rows of
  `PROMOTION-FLOOR-FINDINGS.md`'s CORRECTION table exactly, and surfaced a live
  assertion failure nobody had recorded (finding 4a).
* `data-dev/ADJ-FUZZY-REGRESS.rds` and `data-dev/ADJ-FUZZY-CUTOFF.rds` — read
  directly. These are richer than the logs and settle findings 1 and 2 at the
  source rather than through prose.
* a scratch script re-deriving **every** arithmetic claim in this file from the
  figures the notes publish. 47 checks, 47 consistent. It found one error in
  **this audit's own** arithmetic, corrected below.

So a class-(a) verdict here means "I ran it and got this" for
`adjudicate-18-layer-costs.R` and `ab-idf-gate.R`, and "the script's saved frame
holds this" for `adjudicate-16-fuzzy-regress.R` and
`adjudicate-17-fuzzy-cutoff.R`. For every other script it still means "the
committed log prints this figure". Part 4 says which those are.

Exposure is graded on two questions: does the figure support a recommendation or
a go/no-go, and **would an error in it flatter the pipeline?** The catalogue's
own observation is that a figure showing the work going well invites less
scrutiny, so a flattering class-(c) number behind a recommendation sorts first.

## Counts

Of **96** numeric claims classified across the notes reached:

| class | n | of which behind a recommendation | of which flattering if wrong |
|---|---:|---:|---:|
| (a) re-derivable — **33 of these re-derived by running the script or reading its saved frame** | 45 | 33 | 19 |
| (a−) printed by a script, but **rounded, scaled or recombined by hand** in the prose | 14 | 11 | 9 |
| (b) retyped from a log, log's label checked and correct | 23 | 9 | 6 |
| (b−) retyped from a log whose label or run does **not** match the claim | 3 | 3 | 3 |
| (c) unattributable | 11 | 6 | 4 |

The class-(a−) row is the one worth noticing. It is not a bookkeeping category:
a script that computes a number the note then rescales by hand is **exactly
defect 2's shape**, and nine of the fourteen would flatter.

---

# Part 1 — Highest exposure first

Ten findings. The first four each sit behind a live recommendation and each
would flatter the pipeline if wrong. Two of them are wrong, and both are now
confirmed by running or reading what the scripts themselves produced.

## 1. `DEVELOPMENT-PLAN.md` publishes the margin that defect 3 corrected — with the sign flipped back

**Class (b−). Behind a recommendation. Flatters. Confirmed wrong.**

`dev/DEVELOPMENT-PLAN.md` §"Layer 0 is free and should not be optional":

> At 0.85 it clears **25** rather than 24 — one more identity for 1,105 more
> pairs and a personal-name margin that falls to **0.002**.

The margin at 0.85 is **−0.004**. `dev/NO-EXP-17-cutoff.log` SUMMARY prints it,
`dev/adjudicate-17-fuzzy-cutoff.R` computes it, and
`dev/NO-TIER-EXPERIMENT.md` §9 publishes it correctly in the cutoff table.

`0.002` is the pre-correction value from catalogue defect 3 — "margin **+0.002**
… computed with an approximate normalizer standing in for `np_normalize()`". The
correction was applied in `NO-TIER-EXPERIMENT.md` and **never propagated to
`DEVELOPMENT-PLAN.md`.**

The sign is the whole finding, and it is the catalogue's own example of practice
7: `0.002` reads as *tight but positive clearance*, where `−0.004` means the
cutoff sits **underneath** the top personal-name collision (0.854, `ALEXANDER
SCHWEIG` → `ALEXANDER GRAHAM BELL`). A reader of the plan sees a cutoff with a
little room left; the measurement says it has none. That is the difference
between "0.85 is tight" and "0.85 has stopped separating organisations from
individuals", and the plan's sentence is an argument for *not* lowering the
cutoff that accidentally undercuts itself.

**Settled by reading the frame.** `data-dev/ADJ-FUZZY-CUTOFF.rds`, which
`adjudicate-17` writes, is a list of three: `summary` (the cutoff table),
`top_personal = 0.8536738` and `in_here = 33`. Its `margin` column is
`-0.004` at 0.85, `0.046` at 0.90, `0.096` at 0.95.

The frame also shows **why `0.002` could never have been right**, which the log
alone does not. `margin` is not measured independently — it is `cutoff −
top_personal`, and all three rows reproduce exactly from
`0.8536738`. A positive margin at 0.85 therefore requires a top personal-name
similarity of **≤ 0.850**; the measured value is **0.8537**. `0.002` implies
`top_personal = 0.848`, which is the approximate-normalizer artefact defect 3
describes. So the wrong figure is not a transcription slip — it is the
pre-correction *measurement*, carried forward intact.

*Remaining work:* the figure should be read from this frame rather than retyped a
third time. A parallel pass is doing exactly that; see "Status of these findings".

## 2. The exemplar script holds a constant from a superseded run — the defect it was written to prevent

**Class (b−). Behind a recommendation. Flatters. Confirmed wrong.**

`dev/adjudicate-18-layer-costs.R` exists so that the Phase 4b figures cannot
drift from their runs. Its header is explicit about why, and it cites inputs at
point of use. One of those citations does not hold:

```r
# dev/NO-EXP-16-fuzzy.log, cutoff 0.90, on the 4,868-identity in-scope run
FZ_SEC <- 521; MATCH_SEC <- 5830
```

`dev/NO-EXP-16-fuzzy.log` at cutoff 0.90 reports **545.97 s**, and its own prose
line reads `546.0 s (9.37% of the 5830 s match it supplements)`. The value
**521** — and the **8.9%** the plan prints beside it — appear only in
`dev/NO-EXP-16-fuzzy-run1.log`: `521.1 s (8.94% …)`.

`run1` is the superseded run. It is the one that produced catalogue **defect 4**
(its SUMMARY reports `moved` as 142/159/157 where the corrected log reports
7/28/32). So the exemplar for practice 1 carries a constant hand-copied from the
log of the run that generated defect 4 — which is defect 2's mechanism exactly,
one level up.

Two things inherit it. `dev/DEVELOPMENT-PLAN.md` §"Layer 0" prints
"**521 s, 8.9% of the 5,830 s match**", and the script's corpus projection
scales it: "~**136** core-hours". At 546 s the projection is ~143 core-hours.

The deeper problem is that **no single value is the right one.**
`NO-TIER-EXPERIMENT.md` §9 says so plainly:

> the 535–681 s spread across the three arms is contention with a concurrent
> job, not a property of the cutoff

So §9 reports "about **9%**" and declines to harden it. `DEVELOPMENT-PLAN.md`
hardened the hedge into two decimal places *and* drew the value from the wrong
run. The source note was more careful than the note that quotes it — which is
the general hazard this audit kept finding.

**Demonstrated, not inferred.** Running `dev/adjudicate-18-layer-costs.R` as
committed prints, in front of me:

```
pf_fuzzy_recover() at the 0.90 default: 521 s, 8.9% of the 5830 s match
Projected to 4,582,301 identities the scan is ~136 core-hours
```

And `data-dev/ADJ-FUZZY-REGRESS.rds`, the frame `adjudicate-16` saves, read
directly:

```
  cutoff seconds residual pairs moved to_yes to_maybe yes_broken
2   0.90  545.97     2009  2650    28     24        3          0
```

So the script's own upstream stage has held **545.97** on disk the whole time.
At that value the projection is **~143 core-hours**, not 136.

*To settle:* have `adjudicate-18-layer-costs.R` read the timing from that frame
instead of holding a literal — no re-run needed, the frame is already there. The
honest published form is a range, or the figure with its contention caveat
attached. A parallel pass has done this; see "Status of these findings".

**This is an eighth instance for the catalogue**, and arguably the sharpest:
a constant hand-copied from a superseded run's log, inside the one script
written so that those figures cannot drift, hardening a figure the source note
deliberately left soft. `dev/PLAUSIBLE-WRONG-NUMBERS.md` is not edited here, as
instructed.

## 3. `PROMOTION-FLOOR-FINDINGS.md` §5 recommends what its own CORRECTION retracts

**Class (a−)/(c). Behind a recommendation. Flatters. Confirmed stale.**

§5 "Recommendation" says:

> **Ship `distinct_name_min_idf = 10`.** Cheap, targeted, four errors removed
> for one questionable demotion.

The CORRECTION section below it says:

> §4 above shipped `distinct_name_min_idf` on the strength of a probe showing it
> demoted 5 of 121 promoted matches, 4 of them errors. **A clean A/B on the live
> pipeline showed it moves 2 cases, net zero. The probe was wrong.**

and its Disposition sets **`distinct_name_min_idf = 0`** — disabled — as the
shipped default, catching **0 of 3** known errors against `main_only`'s 3 of 3.

The retracted recommendation is left standing, unmarked, under a heading that
says "Recommendation". A reader who stops at §5 — which is where a recommendation
is meant to live — ships the opposite of the default. The retracted figure
("four errors removed for one questionable demotion") is the flattering one; the
true figure is "moves 2 cases, net zero".

This is not strictly a provenance defect, but it is the same failure the
catalogue describes: a well-formed number supporting a recommendation, where
nothing in the file's structure tells the reader it is dead.

> **Still live on `origin/main`, and now contradicted three ways inside one
> file.** Checked after PR #29: §5 line 181 still reads "Ship
> `distinct_name_min_idf = 10`", while the note's own header (line 16) lists the
> shipped defaults as `distinct_name_main_only = TRUE,
> distinct_name_min_idf = 0` and the Disposition (line 297) says the default was
> "changed to disabled". §1 on `main` now also explains *why* §5 said it — the
> floor's benefit was published without its cost, and "the direction of the
> error flattered the floor". So the cause is documented and the recommendation
> it produced is not yet withdrawn. This is the oldest open finding here and the
> cheapest to close.

## 4. The same note's headline cannot be reproduced from its own table

**Class (c). Behind a recommendation. Flatters.**

`PROMOTION-FLOOR-FINDINGS.md` §1:

| | YES | MAYBE | NO |
|---|---:|---:|---:|
| promotion ON (default) | 2,814 | 1,037 | 1,069 |
| promotion OFF | 2,698 | 885 | 1,337 |

> **121 YES matches (4.3% of the tier) exist only because of the floor**, and all
> 121 fall to **MAYBE, not NO**, when it is disabled — so the floor is not
> creating recall out of nothing, it is deciding whether these get adjudicated or
> auto-accepted.

Two things in that sentence are not in the table above it.

**121 against 116.** YES falls 2,814 → 2,698, which is **116**. The note's
headline number is not the one its table supports, and the note does not say
which convention either figure uses. The likely explanation is the collision of
defect 4 — 121 **pairs** against 116 **identities** — and the geo-evidence table
below it sums to exactly 121, so the pair reading is probably right. But the
note names neither side, which is precisely what practice 5 asks for.

> **Resolved on `main`, and the resolution refutes my explanation as well as
> the note's.** `PROMOTION-FLOOR-FINDINGS.md` §1 on `main` now names the piece
> that was missing from both: **the floor also *costs* identities**, and that
> side was never printed. Six identities are YES only with the floor *off*
> (`OHIO FOUNDATION`, `RUTGERS…`, `GEORGIA STATE UNIVERSITY`, `UC San Diego
> Foundation`, `Lakes Region Community Services`, `FAMILY AND CHILDREN'S
> ASSOCIATION`), so the current net is **+103 = 109 − 6**. On the figures as
> first published, "five identities had to be moving the other way for both
> numbers to be true" — 121 won, 5 lost, net 116.
>
> So **my pairs-vs-identities hypothesis was wrong.** §1 now says explicitly
> that these are "identities (`pf_status()` rows), not pairs" on both sides. The
> discrepancy was never a convention collision; it was a gross win-count printed
> beside a net it did not reconcile with, which `main` now calls out as the
> catalogued shape — "and the direction of the error flattered the floor, which
> is why §5 below recommended keeping it on a benefit with no cost beside it."
>
> That is finding 4 confirmed and finding 3's cause explained, with my reasoning
> corrected on the way. Noting it because it is the **third** time in this audit
> that checking something refuted my own account of a defect I had correctly
> spotted — the first being the monotonicity argument I replaced this blockquote
> with, which was also wrong: the real mechanism is the margin route in
> `np_tier()`, not slot promotion in `np_select()` (finding 4a). Spotting that a
> number does not reconcile is cheap; being right about *why* is not.

**"All 121 fall to MAYBE, not NO" is contradicted.** When the floor is off,
MAYBE does not rise by 121 — it *falls* by 152, and NO rises by **268**. Whatever
the 121 are, 268 identities land in NO when the floor is disabled, so the
reassuring conclusion ("deciding whether these get adjudicated or auto-accepted")
is not what the table shows. The flattering reading is the published one.

**A third set of counts, unreconciled.** The CORRECTION's own table gives
"neither gate" as 2,834 / 1,028 / 1,058 — the same configuration as §1's
"promotion ON", 20 YES apart. Both sum to 4,920, so it is the same population,
but the baseline moved between §1 and the CORRECTION and neither says so. That
makes the CORRECTION's "demotes **13** YES" non-comparable with §1's 121.

**And the population is never named.** The tier counts sum to **4,920**, a
denominator that appears nowhere else in the repo — not 4,748 (10C result
frame), not 4,868 (in scope), not 4,903 (all identities). The note says only
"measured on 990-PF grants".

**Partly settled by running it.** `dev/ab-idf-gate.R` is read-only (it rescores
stored pairs, writes nothing) and runs off the cached
`data-dev/PF-MATCH-RESULT-1k.rds`. Executed:

```
min_idf = 0    YES  2821  MAYBE  1006  NO  1093
min_idf = 10   YES  2822  MAYBE   986  NO  1112
```

Those are **exactly** two rows of the CORRECTION's four-config table —
`main_only` only (2,821 / 1,006 / 1,093) and both gates (2,822 / 986 / 1,112).
So the CORRECTION's table is **class (a), re-derived**, not class (c) as first
recorded here, and the unnamed population of **4,920** is confirmed by
execution. That is the good news in this finding: the retracted recommendation
is stale, but the measurement that retracted it holds up exactly.

*Still open:* §1's `promotion ON/OFF` table (2,814 / 1,037 / 1,069) needs
`dev/probe-promotion-floor.R`, which **writes to `data-dev`** (`saveRDS` at
line 89) and so was not run. That is the run that would settle 121-vs-116
directly, by printing pairs and identities side by side with the population id.

## 4a. `ab-idf-gate.R` asserted something false, and printed the refutation

**Class (a), re-derived. Resolved on `main` in PR #29.**

> **This finding's description was wrong twice before it was right, and both
> wrong versions are mine.** It was first written up as "a failed assertion
> nobody has recorded", then — on a peer session's framing, which I adopted
> without checking — as an "unenforced invariant" where the script "measures a
> violation". Both presume the invariant is *correct and merely unchecked*. It
> is not correct, and there is no violation. The peer retracted its own framing
> and pointed at evidence on `main`; I verified that evidence before changing
> this, and it is conclusive. What follows is the corrected account.

The same run above ends with:

```
YES gained (should be 0): 2
```

The script states the invariant, measures it, gets 2, prints it — **and carries
on.** Nothing in `PROMOTION-FLOOR-FINDINGS.md` mentions it, and no `.log` for
this script exists in `dev/`, so the only way to see it is to run the script.

**The gain of 2 is correct behaviour.** The invariant was false. `np_tier()`
demotes on the **margin** to the runner-up, so a veto that *removes* a runner-up
**raises** the winner's margin and can legitimately carry an identity
MAYBE → YES. `dev/AB-IDF-GATE.log`, landed on `main` in PR #29, prints the two
and settles it:

```
YES gained by the gate: 2
                           name    was score_off score_on margin_off margin_on
                OHIO FOUNDATION  MAYBE       0.9    0.888          0     0.068
 FAMILY AND CHILDREN'S ASSOCIAT  MAYBE       0.9    0.820          0     0.140
reconciliation: net YES +1 = gained 2 - demoted 1 = +1
```

`margin_off` is **exactly 0** in both — ties, which is why they were MAYBE — and
the winning **score falls** (0.900 → 0.888, 0.900 → 0.820). A score that falls
is the signature of a *different pair winning* once the floored one is vetoed,
not of anything being raised. The mechanism is documented in `R/dyads.R`
*"Collapse before selection"* and under *"What it hides"* in `R/match.R`.

`dev/PROMOTION-FLOOR-FINDINGS.md:210` on `main` now states it as a false
invariant, and `ab-idf-gate.R` on `main` asserts **the invariant that does
hold** — that no gained identity's *score* rose, which a veto cannot cause —
and `stopifnot()`s it, plus the reconciliation `net == gained − demoted`.

**Why the distinction decides the fix, which is the whole value of this entry.**
The two framings point at opposite repairs. "An invariant nobody enforced"
invites *enforcing* it — which would halt the run on correct behaviour. The
accurate entry is **"an assertion that was false, which a reader would have been
trained to skip"**: a metric that cries wolf costs the same attention as one
that cannot alarm at all, and that is a distinct failure from the catalogue's
seven. So the classification stands — a class of its own, not an eighth number —
and only the description changes.

**One connection worth keeping.** Both gained identities, `OHIO FOUNDATION` and
`FAMILY AND CHILDREN'S ASSOCIATION`, are two of the **six** identities §1 on
`main` now finds the floor *costs*. One tie-driven selection mechanism, seen
from either side of the floor.

## 5. Two notes publish two sets of dollars for the identical policy

**Class (a−). Behind the Phase 4 go/no-go. One convention flatters.**

The same recommendation — escalate the cheap arm's low-confidence 18% to the
no-search deep arm, over the whole MAYBE tier — is costed twice:

| source | MAYBE tier | light only | escalate → deep− | escalate → deep+ |
|---|---:|---:|---:|---:|
| `ADJUDICATION-EXPERIMENT.md` §"Cost" + §"Scaling" | 1,008,713 | $680 | **$6,175** | $12,984 |
| `DEVELOPMENT-PLAN.md` §"Phase 4b" (= `adjudicate-18`) | 982,728 | $662 | **$6,016** | $12,649 |

The arithmetic is identical and both are internally consistent; the entire gap is
the **denominator**. The experiment takes the MAYBE share as *1,044 of 4,748 =
22.0%* — the 10C **result frame**. Phase 4b takes it on the **in-scope** 4,868,
and says in a blockquote why the result frame is the wrong base:

> Those 4,748 "identities" are the *result frame*; the 120 in-scope identities
> no blocking pass produced a pair for are simply absent from it.

So Phase 4b corrects the convention and `ADJUDICATION-EXPERIMENT.md`
§"Scaling to the full corpus" still publishes the superseded set, unmarked.
Anyone quoting "$6,175" is quoting the base the project rejected.

**`DEVELOPMENT-PLAN.md` carries both conventions itself.** §Phase 4 step 5
(~line 396) prints the 4,585,061 / 22.0% / ~1,008,000 / $680 / $6,175 set;
§Phase 4b (~line 488) prints the 4,582,301 / 21.45% / 982,728 / $662 / $6,016
set. Ninety lines apart, same document, no cross-reference. Phase 4b explains
the correction; Phase 4 does not point forward to it.

The direction is worth stating because it cuts against the usual pattern: for
**MAYBE** the result-frame base *overstates* the tier (all 120 missing
identities are NO), so these particular figures err high and the error does not
flatter. The same convention applied to **NO** understates by 14%, which does.
The risk is not this table; it is the convention travelling.

## 6. The recommendation to build the review queue rests on a note that does not exist

**Class (c). Behind a recommendation. Dangling citation.**

`dev/ADJUDICATION-PLAN.md` §4:

> Grant dollars are extremely skewed (`dev/GRANT-DOLLARS-FINDINGS.md`). …
> **~740 reviews covers 70% of the recoverable unresolved dollars.** That is the
> budget to plan against.

**`dev/GRANT-DOLLARS-FINDINGS.md` does not exist**, in `dev/` or
`dev/superseded/`. It is cited twice — `ADJUDICATION-PLAN.md:127` and
`PACKAGE-PLAN.md:375` — and `DEVELOPMENT-PLAN.md:387` carries the figure forward
as a Phase 4 work item without a citation at all. The whole dollar-skew table
(195 / 738 / 1,475 / 3,528 cases for 50/70/80/90% of dollars) has no reachable
source.

It is the only genuinely dangling *local* note citation I found. The other
apparent misses — `PROCESS.md`, `PLAN.md`, `GROUP-STRUCTURE-FINDINGS.md`,
`RELATION-BUILD-PLAN.md`, `EXTRACTION.md` — are all cited with a `matchdb/` or
npnormalize prefix and live in sibling repositories, which is fine.
`dev/PLACES.md` in `PLACES-SYNC.md` is probably npmatch's and I did not confirm
it.

**Run, and it disagrees on every row.** `dev/analyze-grant-dollars.R` is
read-only (no writes anywhere in it) and runs off the cached
`data-dev/PF-MATCH-RESULT-50k.rds`. Executed at `PF_SET=50k`, its curve is:

| dollars covered | `ADJUDICATION-PLAN.md` §4 | re-derived now | ratio |
|---|---:|---:|---:|
| 50% | 195 cases | **113** | 1.7x |
| **70%** | **738 cases** | **489** | **1.5x** |
| 80% | 1,475 cases | **1,094** | 1.3x |
| 90% | 3,528 cases | **2,806** | 1.3x |

All four published rows are **higher** than the re-derivation — i.e. the note
overstates the review burden, so this error does *not* flatter the pipeline. It
is conservative, which is why this ranks sixth and not first.

**The likely cause is a denominator, and it is the practice-4 question again.**
The script's curve is over *unresolved* dollars (MAYBE + NO, $958,815,724 across
23,842 cases). §4 says "**recoverable** unresolved dollars" and then lists two
exclusions — non-itemizing `SEE ATTACHED` returns (497 returns, $394M) and
foreign recipients. Removing unreachable dollars from the target changes how
many cases 70% takes, which could account for a 1.5x gap. The script applies
neither exclusion.

So the published table is probably right for a denominator the script does not
compute, and the note that would say so is the missing
`dev/GRANT-DOLLARS-FINDINGS.md`. **That is the whole cost of a dangling
citation**: two plausible tables, 1.5x apart, and no way to tell which
population either describes.

*To settle:* re-run with the two §4 exclusions applied and see whether 489 moves
to 738. That needs a definition of "recoverable" that only the missing note
holds — so this one needs its author, not a run.

Minor, same figure: the table says **738** cases and the prose rounds to
**~740**, which is honest. But `ADJUDICATION-EXPERIMENT.md` §Q1 independently
projects "**738 of 1,044 cases**" cleared by the deep arm. Two unrelated 738s,
one note apart. Not a defect; a collision worth keeping apart in anyone's head.

## 7. `$8,107` appears once in the repo and derives from nothing

**Class (c). Behind a recommendation.**

`DEVELOPMENT-PLAN.md` §Phase 4 step 5, arguing for the Batch API:

> The 50% discount ($680 → $340, and **$8,107 → $4,054** for the cascade) is
> almost incidental next to not managing that.

`$680 → $340` checks out (`ADJUDICATION-EXPERIMENT.md`, and halving is the
documented batch discount). **`$8,107` occurs exactly once in `dev/`** and is not
derivable from any cascade total in the repo: the candidates are $6,175 and
$6,016 (escalate → deep−), $12,984 and $12,649 (→ deep+), $662 and $680 (light
only). `$4,054` is a clean halving of it, so the pair is internally consistent
and externally unattached — the signature of a figure that survived a cost
correction its neighbours did not.

Exposure is real but bounded: the sentence's argument is that the discount
*does not matter*, so an error in the base does not flatter the pipeline's
performance. It does mean a published dollar figure has no provenance at all.

*To settle:* no existing script prints it. This one needs its author.

## 8. The published sample design is not the sample that was drawn

**Class (b−)/(c). Supports the NO-tier recommendation. Does not change the rates.**

`NO-TIER-EXPERIMENT.md` §"The sample":

> - **A, estimation (75).** Simple random from the NO identities carrying no
>   prior human verdict.
> - **B, calibration (25).** Drawn from the NO identities that
>   `dev/no-residual-verdicts.csv` already adjudicates by hand. These give
>   agreement against a human.

`dev/NO-EXP-10-packet.log` records what actually ran:

```
N=100  (calibration=25, estimation=75)  seed=20261101  k=5
  (58 have since moved tier and are therefore not eligible for stratum B)
stratum A estimation : 91 drawn simple-random from 836 eligible
stratum B calibration: 9 drawn from 9 adjudicated-and-still-NO
```

So 75/25 is the **requested** split; the realised draw is **91/9**. Stratum B
could not be filled because 58 of its pool had moved tier, and A absorbed the
shortfall. This is why the headline denominator is 91 — and §1 switches to
"Stratum A, n = 91" with no reconciliation, eighty lines after telling the reader
it is 75.

Worse, the note's description of stratum B is contradicted by the script that
built it. `dev/adjudicate-10-no-packet.R:284`:

> stratum B is 9 arbitrary identities, not 9 adjudicated ones, so it
> **calibrates nothing.** `SET=cal` exists to do that job properly.

The note says stratum B gives "agreement against a human". The code says it
gives nothing, because the draw keyed on `grant_id`, which §3 of the same note
shows is not a valid join key. The defect is recorded in code, left deliberately
uncorrected so the determinism check keeps passing — and **not propagated to the
note that publishes the design.** Third instance of that pattern in this audit
(see findings 1 and 5).

**What this does not touch.** The headline rates are unaffected, and both the
note and the script say why: stratum A is a simple random draw from 836 of the
845 NO identities, the 9 exclusions are content-independent, so 33/91 = 36.3%
stands as a tier estimate. §6's human-agreement figures are on the separate
`PF_NO_SET=cal` set (63 cases, n=59 after excluding 4 `UNCLEAR`), correctly
denominated and clearly labelled. Nothing here is a wrong number. It is a wrong
*account* of where the numbers came from, in the note a reader would check.

**A label hazard alongside it.** `adjudicate-10-no-packet.R` writes three
stratum labels across its branches — `A-estimation`, `B-calibration`
(line 303) and `C-calibration` (line 271, the `SET=cal` path). Catalogue defects
6 and 7 were both filters against labels that did not exist. Three labels, two
nearly identical, is the condition those defects need.

## 9. `62.74% → 78.28%` is the headline on the contested denominator

**Class (a−). Behind the Phase 4 go-ahead. Flatters.**

`ADJUDICATION-EXPERIMENT.md` §Q1:

> Projected onto the tier: **738 of 1,044 cases** (CI 620–855), taking the
> benchmark from 62.74% to **78.28%**, **+15.5 points**.

The projection is sound and the arithmetic checks: `(2,979 + 738) / 4,748 =
78.29%`. But `4,748` is the result frame, and both `NO-TIER-EXPERIMENT.md`
§"The denominator" and `DEVELOPMENT-PLAN.md` §Phase 4b hold that the in-scope
4,868 is the right base — the same correction as finding 5. On 4,868 the pair is
**61.20% → 76.36%**.

The *gain* barely moves (+15.16 against +15.5 points), which is why this ranks
ninth rather than higher. The **level** moves 1.9 points, and the level is what
gets quoted. `78.28%` is the most quotable number in the adjudication work and it
sits on the base the project rejected, in a note that does not mention the
choice.

---

# Status of these findings

Recorded because this file is one of four parallel passes on issue #15 and a
reader needs to know which findings are already moving. **This audit changed
nothing but this file**; everything below is other sessions' work.

* **Findings 1 and 2 are fixed in a parallel pass, on an unpushed branch.**
  Commit `ca82a0b` on local branch `fix-retyped-figures`, "Derive the layer-0
  figures instead of retyping them; two were wrong", touches
  `adjudicate-18-layer-costs.R` and `DEVELOPMENT-PLAN.md`. The script there
  reads both saved frames via `assert-lib`'s `need_cols()` / `need_rows()`
  instead of holding `FZ_SEC` as a literal, and prints 546 s / 9% / ~143
  core-hours / margin −0.004. The "to settle" lines above are what that pass
  acted on.

  **The defect is still live on `origin/main`.** `ca82a0b` is on no remote
  branch and has no PR, and `origin/main:dev/DEVELOPMENT-PLAN.md:564` still
  reads "a personal-name margin that falls to 0.002". So anyone quoting that
  passage from `main` today is quoting the wrong figure, fix or no fix.

  The user has chosen to keep `fix-retyped-figures` local and unpushed, so the
  live defect on `main` is a deliberate decision rather than an oversight.

  > **A warning for whoever lands the fix.** `0.002` occurs twice in `dev/`.
  > The second, `PLAUSIBLE-WRONG-NUMBERS.md:20`, is the catalogue's own
  > reported-vs-true record of defect 3 — "margin **+0.002**" against
  > "**−0.004**" — and is *correct as written*. It must not be "fixed". A
  > repo-wide replace acting on finding 1 would destroy the record of the
  > defect that finding 1 is about.
* **Findings 4 and 4a are resolved on `origin/main` by PR #29** ("Run five of
  the six redefined metrics, and commit the logs"), which landed
  `dev/AB-IDF-GATE.log` and rewrote `PROMOTION-FLOOR-FINDINGS.md` §1. Both are
  kept here with their resolutions recorded, because the resolution of each
  corrected this audit's own account of it.
* **Findings 3, 5, 6, 7, 8 and 9 are open.** Finding 3 is confirmed still live
  on `main` after #29 — §5 line 181 against the defaults at line 16. None is
  touched by `fix-retyped-figures`, nor by PR #25
  (`claude/vigilant-franklin-8b512d`, "Apply practice 7: redefine the metrics
  that could not come out wrong"), which is proposal 4 and was scoped away from
  the margin and `FZ_SEC` deliberately.
* **Finding 2 is an eighth catalogue instance.** Finding 4a is **not** a ninth —
  see below. `dev/PLAUSIBLE-WRONG-NUMBERS.md` is deliberately not edited here;
  a sibling pass appends to it.

## Two catalogue candidates this audit withdraws

Recorded because withdrawing a finding is part of the job, and because the first
one is this audit making the exact error it was written to catch.

**Withdrawn: Haiku's two-tier pricing as a catalogue instance.** An earlier
version of this file called `NO-TIER-EXPERIMENT.md` §7's "$0.46 against $1.308"
an eighth (later tenth) instance. **It is not one.** The catalogue's seven are
numbers that *were* wrong and *would have shipped*. §7 published **$1.308**, the
correct figure, computed by `adj_cost_tiered()`, which was added for this; it
states the 22-of-100 step crossings and names the counterfactual in the
conditional — banking against the cheap rate *would have* reported $0.46. So
nothing wrong was published: the hazard was caught, priced correctly, and
documented at the point of use. It belongs with **practice 1 as a near-miss the
compute-don't-retype habit caught**, not in the defect table. Counting a
near-miss as a defect inflates the catalogue, which is the same failure as
deflating it.

**Reclassified twice, not withdrawn: finding 4a.** It is not a wrong number, so
it is not an eighth-or-ninth instance of the catalogued class — that part held
from the start. But the *description* was wrong in both earlier versions of this
file: "a failed assertion", then "an unenforced invariant" where the script
"measures a violation". Both presume a correct-but-unchecked invariant. The
invariant was **false**, and the gain of 2 is correct behaviour; `main` proves it
in `dev/AB-IDF-GATE.log`. The accurate entry is **"an assertion that was false,
which a reader would have been trained to skip"** — a metric that cries wolf,
costing the same attention as one that cannot alarm at all. It matters because
the two descriptions point at opposite fixes, and the wrong one invites enforcing
a false invariant and halting correct runs. Details in finding 4a.

---

# Part 2 — Full inventory

Per note, for every numeric claim a reader could act on.

## `dev/adjudicate-18-layer-costs.R` — the exemplar, and what its discipline does and does not buy

Every figure in `DEVELOPMENT-PLAN.md` §Phase 4b is printed by this script. **I
ran it.** Every derived figure in §Phase 4b reproduced exactly — the five
whole-tier totals, the four cascade rows, the two ratios, the search shares, the
batch column — and matched `dev/NO-EXP-18-layer-costs.log` line for line. The
practice works as advertised for everything downstream of the inputs.

It also reproduced the two wrong figures, which is the point: a script that
faithfully recomputes a bad constant is still a script nobody can catch by
running it. Re-derivability is necessary and not sufficient; the inputs have to
be re-derived too.

What it does not buy is the inputs. The script derives nothing it does not first
retype: **~20 literal constants**, each cited at point of use. Verifying each
against its cited source is the audit that matters, and it is reported here
because it has not been done before:

| constant | value | cited source | verdict |
|---|---|---|---|
| `ROWS` | 17,253,199 | `EFILEPF-DEDUP.log` | **(b) ✓** log line 4 |
| in-scope rate | 0.988 | `FULL-01-PREPARE.log` | **(a−)** log says 98.8%, itself rounded from 98.771% |
| `COLLAPSE` | 3.72 | `FULL-01-PREPARE.log` | **(a−)** log says 3.72x, rounded from 3.7167 |
| `BENCH_IN` | 4,868 | `NO-TIER` §denominator | **(b) ✓** |
| `BENCH` YES / MAYBE | 2,979 / 1,044 | 10C `MANIFEST.md` augmented arm | **(b) ✓** |
| `BENCH` NO | 845 | `NO-TIER` §denominator | **(b) ✓** 725 + 120 |
| `SEARCH_USD` | 0.01 | "$10 per 1,000, list price" | **(c)** external; unverifiable in repo |
| `usd_case` light / deep− / deep+ | 0.000674 / 0.030265 / 0.067765 | `ADJUDICATION-EXPERIMENT` §Cost | **(b) ✓** all three |
| `usd_case` NO Haiku / Opus | 0.0131 / 0.0669 | `NO-TIER` §7 | **(b) ✓** |
| `searches` MAYBE deep+ | 2.2 | `ADJ-EXP-RESULTS.log` 220/100 | **(b) ✓** exact |
| `searches` NO Haiku / Opus | 4.4 / 3.2 | `NO-TIER` §7, 436 and 319 per 100 | **(a−)** 4.36 and 3.19, rounded |
| `ESC` | 0.18 | §Q2, low = 18 of 100 | **(b) ✓** exact |
| `FZ_SEC` | 521 | `NO-EXP-16-fuzzy.log` | **(b−) ✗ finding 2** — that log, and the saved frame, say 545.97 |
| `MATCH_SEC` | 5,830 | both fuzzy logs | **(b) ✓** |

Eighteen of twenty hold. One is wrong (finding 2). The `(a−)` rows are the ones
to watch: a two-significant-figure search rate measured on 100 cases, multiplied
by 795,408 identities, is published as **"$34,998"** and **"$33,248"**. Carrying
4.36 and 3.19 instead gives ≈$34,680 and ≈$33,490 — note that the second moves
*up*, so the rounding is not conservative. The figures are not wrong —
they are *reported to four more digits than their inputs support*, in the two
places the plan uses to argue that `max_uses` and not model choice is the cost
lever. That argument survives either way; its precision does not.

One citation slip, no exposure: `DEVELOPMENT-PLAN.md:488` attributes the whole
chain "17,253,199 grant rows → 17,046,161 in scope → 4,582,301 identities" to
"the 3.72x collapse measured in `dev/FULL-01-PREPARE.log`". That log holds
**12,559,051** rows; only the ratio is in it. The script's own comment cites both
logs correctly. A reader following the plan's citation will not find the row
count.

## `dev/DEVELOPMENT-PLAN.md`

§Phase 4b, 31 figures. All class (a) via `adjudicate-18`, verified against the
log, **except**:

* the margin **0.002** — finding 1, class (b−), **wrong**
* **521 s / 8.9% / ~136 core-hours** — finding 2, class (b−), **wrong**
* **+0.49 points**, **+24 to YES**, **2,009 residual**, **0 YES broken**,
  **3 of the 33 / agrees on 2 / contradicts 1** — class (b), all verified
  against `NO-EXP-16-fuzzy.log` (`to_yes` 24, `llm_overlap` 3,
  `llm_ein_matched` 2, `llm_contradicted` 1, clear rate 58.73% → 59.22%). The
  script prints none of these; §Phase 4b carries them from the log. Correct, but
  class (b) inside a section that claims "every figure is printed by
  `dev/adjudicate-18-layer-costs.R`". That claim is true of the dollars and not
  of layer 0.
* **25 rather than 24 / 1,105 more pairs** — class (b) ✓ (3,755 − 2,650 = 1,105),
  but recombined by hand with a figure from a *different* script
  (`adjudicate-17`) in the same sentence, which is how the wrong margin got in
* **~940x**, **~983,000**, **~795,000** — class (a−), honest roundings of
  982,728 and 795,408, flagged with `~`

§Phase 4 step 5, 11 figures: the superseded-convention set (finding 5), plus
`$8,107` (finding 7) and `~740` (finding 6). `~150 h` is class (a−) but
reproducible: 1,008,713 × 0.52 s/case = 146 h.

§"What these numbers are not" is the strongest prose in the repo on this subject
and names four of the exposures above before this audit did — the 27 and 91
denominators, the deep arm's inherited ~7% error, model and pricing drift, the
~940x projection, and layer 0's 1-in-3 contradiction on n=3. It does not catch
findings 1 or 2, both of which are in the section it introduces.

## `dev/NO-TIER-EXPERIMENT.md`

The most carefully denominated note in the sweep, and the one that does the most
self-correction in place. §9 records two corrections the recompute forced, §"The
full-file regression" records defect 4 in a blockquote, and §9's cutoff table
publishes the corrected **−0.004**.

* **845 = 725 + 120** (§denominator) — class (b) ✓, `NO-EXP-10-packet.log`
  line 28. This is the figure the whole Phase 4b NO budget rests on and it holds.
  The composition is also *internally* checkable and checks:
  2,979 + 1,044 + 845 = 4,868 exactly, and + 35 OOS = 4,903. An identity with no
  pair cannot be YES or MAYBE, so routing all 120 to NO is sound.
* **61.20%, 1.55 points lower** — class (a−) ✓, 2,979/4,868 = 61.196%
* **33/91 = 36.3%**, Wilson [27.1%, 46.5%], **~306 of the 845** [229, 393] —
  class (b) ✓ and arithmetically consistent. Denominator is finding 8's: 91 is
  the realised draw, not the published design.
* **30/91 = 33.0%** (Haiku) — class (b) ✓
* §7 cost table, **$6.690 / $0.0669 / 319** and **$1.308 / $0.0131 / 436** —
  class (b) ✓. The "**5.1x cheaper, not 40x**" framing is labelled a token ratio
  at point of use, and Phase 4b's correction of it to 1.73x on the full bill
  credits it as "the honest number for what it measured". Correct on both sides.
* §7's **22 of 100 crossed the 100K step**, and the counterfactual that banking
  against the cheap rate would have understated by nearly three — class (b),
  supports the tiered-pricing fix. **A near-miss, not a defect**: the published
  figure is the correct $1.308, computed by `adj_cost_tiered()`, and the wrong
  figure appears only in the conditional. This audit first miscounted it as a
  catalogue instance; see "Two catalogue candidates this audit withdraws".
* §6b **$56.50 over 845** — class (a−) ✓, 845 × 0.0669 = $56.53. §6b also
  explicitly *declines* to quote a cross-experiment cost ratio, "exactly the
  arithmetic that produced two wrong projections already". That refusal is the
  best single instance of practice 1 in the repo.
* §6 agreement figures — **49 of 59 = 83.1%**, kappa 0.724, and the stated
  sensitivity to **49 of 56 = 87.5%, kappa 0.795** — class (b) ✓, denominators
  named, the mapping choice disclosed *because it favours the model*. Per-class
  recalls sum correctly (11 + 34 + 6 + 8 = 59).
* §6 EIN agreement **23 of 24 = 95.8%** — class (b) ✓; 24 + 1 + 11 + 27 = 63 ✓
* §9 regression table and cutoff table — class (a), `adjudicate-16` and
  `adjudicate-17`, both verified against their logs
* §"The sample" 75/25 — finding 8

## `dev/ADJUDICATION-EXPERIMENT.md`

* §gate **22/27 = 81.5%**, **25/27 = 92.6%**, CIs, **0/27** confident-and-wrong —
  class (b) ✓ against `ADJ-EXP-RESULTS.log`. The note states the fragility
  itself: "11.1 points, on a denominator where that is 3 cases".
* §Q1 **47 of 68**, tie-adjusted **70.7%**, **738 of 1,044** — class (b) ✓;
  the 62.74% → 78.28% framing is finding 9
* §Q2 confidence table — class (b) ✓, and **denominators correct**: the `n`
  column is 35 + 47 + 18 = 100 (all cases) while accuracy is 12 + 11 + 4 = 27
  (hand-adjudicated only), and the two are labelled distinctly. Two populations
  in one table, done right.
* §ablation **+7.4 / +3.7 / +11.1 pt**, McNemar p = 0.687 / 1.000 / 0.375,
  **49/68 vs 47/68**, confidence **51% → 73%** — class (b) ✓ against
  `ADJ-EXP-ABLATION.log`. `adjudicate-04-ablation.R` "reads both arms' costs out
  of the saved runs instead of retyping them", which is practice 1 applied where
  defect 2 happened.
* §Cost **$0.000674 / $0.030265 / $0.067765**, **+124%** — class (b) ✓; these are
  the constants `adjudicate-18` retypes
* §Scaling — finding 5. Plus one unattributable: the table gives "in scope at
  98.8% | **17,041,111**" and "identities at the measured 3.72x | **~4,585,000**",
  but 17,041,111 / 3.72 = **4,580,944**. The note's own two rows disagree by
  ~4,000, and the cost table's **4,585,061** matches neither — it implies an
  in-scope count of 17,056,427, or 98.86% of rows, a share appearing nowhere in
  the repo. Class (c). It also
  differs from Phase 4b's 4,582,301 for the same corpus, because one applied the
  rounded 0.988 and the other did not — and neither says which. Immaterial to
  the dollars (0.03%), but **4,585,061** is published to seven significant
  figures for a quantity the same paragraph calls "an over-estimate" and a
  "floor". The precision is the defect regardless of the arithmetic.
* §"Two cost corrections" — the catalogue's defects 1 and 2 at source.
  **537,198 write tokens at $5.00/MTok = $2.69, 40% of total**: class (b) ✓, and
  $537,198 × $5.00/10⁶ = $2.686 is self-checking, which is why it is trustworthy.
  Against **28,785** for the no-search arm.

## `dev/BASELINE-2026-10C/MANIFEST.md`

**The strongest provenance in the repo, and the model the rest should follow.**
Not because its figures are class (a) — most are class (b) — but because it
makes itself checkable in four ways nothing else does:

1. `manifest.csv` and `environment.txt` are **generated**, and the file says so,
   confining the hand-written part to "the provenance reasoning that is not
   derivable from the artifacts"
2. the **reproducing commands** are given verbatim, for both arms and the
   manifest
3. the **denominator is stated**: "The clear rate is **YES over identities**",
   with YES+MAYBE explicitly named as *not* a clear rate
4. the population is **pinned by id** — `efv2_1k`, 4,903 grants,
   `0b5126ef02f2a8b0` — and the normalizer by hash,
   `v1-3e7b9f9d59bbb19e` (npmatch 0.1.1, `76964a0`)

Figures: the two arms (4,687 / 4,748 identities, 56.90% / 62.74%) and the 10B
deltas are class (a) via `dev/build-baseline.R`. All verified internally:
2,667 + 986 + 1,034 = 4,687 ✓ and 2,979 + 1,044 + 725 = 4,748 ✓;
2,667/4,687 = 56.90% ✓; 2,979/4,748 = 62.74% ✓; YES+MAYBE 77.94% ✓ and 84.73% ✓.

Three disclosures are models of practice 7 and 4:

* **"Timings are NOT usable in this baseline"** — 685.6 s and 1,624.2 s against
  10B's 497.9 s and 1,319.0 s, with the cause named (Dropbox syncing 4.5 GB off
  the same disk) and the standard cited. A figure published *with its own
  refutation* attached.
* **"The denominator is still contested"** — ~37% of the NO residual are
  individual payees that "arguably do not belong in it", worth ~3 points on both
  arms. The note flags that its own headline could be 3 points better and does
  not take the credit.
* the `active_col` deviation, recorded "because the artifact no longer matches
  its documented recipe, not because the figures are affected"

One thing the manifest cannot carry, which the plan does disclose: 10C is
measured under `v1-3e7b9f9d59bbb19e`, while the adjudication and fuzzy runs are
under `v1-592912060053c4c3` (`NO-EXP-17-cutoff.log`) against the matchdb
`active-observed` tier (6.67M rows) rather than the augmented reference (3.88M).
So `adjudicate-18` composes tier *shares* from 10C with *rates* from runs on a
different reference. Phase 4b states this ("so its tier counts are not
comparable to the published 62.74%") and 10C's own "What this baseline does NOT
establish" covers the rest. Disclosed, not latent — but it is the seam under the
whole Phase 4b projection and worth naming once more.

## `dev/ADJUDICATION-PLAN.md`

* §4 dollar-skew table (195 / **738** / 1,475 / 3,528) — finding 6. Class (c)
  as published: the cited note is missing, and running the obvious candidate
  script gives 113 / **489** / 1,094 / 2,806 instead. The published rows are all
  ~1.3–1.7x higher, i.e. conservative.
* §4 exclusions: **497 returns, $394M** non-itemizing — class (c), no log
  reached. Supports an exclusion from the review queue, **and is the most likely
  reason the table above does not reproduce** — "recoverable" unresolved dollars
  are not the "unresolved" dollars `analyze-grant-dollars.R` curves over.
* **72% precise** for the ZIP5+margin auto-accept rule — class (b), quoted in
  Phase 4b as the thing the confidence cascade beats. Cited to §1 of this note;
  I did not reach the run behind it.
* **20.1% of grants** route to MAYBE — class (c) here, and worth noting it sits
  beside Phase 4b's 21.45% and the experiment's 22.0% as a *third* MAYBE share.
  `ADJUDICATION-EXPERIMENT.md` names the discrepancy ("`ADJUDICATION-PLAN.md`
  quotes 20.1% of grants") and explains it — grants, not identities — which is
  practice 5 done correctly.

## `dev/PROMOTION-FLOOR-FINDINGS.md`

Findings 3 and 4. Remaining figures:

* geo-evidence profile of the floor-dependent pairs (0 / 4 / **117** / 0) —
  class (c); sums to 121 and the shares 3% / 97% are on 121, so this table is
  consistent with the 121 convention and **not** with the table above it (116).
  That makes the pair/identity reading of finding 4 the likely one.
* **~85%** hand-checked precision on 30 — class (c) by construction and
  *labelled* as hand-checked, which is the honest form. Denominator slop
  acknowledged by its own range: "25–26 correct, 2 clearly wrong, 2–3 doubtful"
  spans 29–31 for n = 30. ~85% = 25.5/30 ✓. Supports "Keep the floor", and the
  note does the right thing by contrasting it with the code's claimed ~97% "from
  a different dataset".
* CORRECTION's four-config table — **class (a), re-derived.** Two of its four
  rows reproduced exactly by running `dev/ab-idf-gate.R` (finding 4). No log
  exists for that script, so this is the one figure in the sweep that went from
  unattributable to re-derived purely by running something. The **0 of 3 / 3 of
  3** known-error column, which carries the disposition, is still a hand count.
* **13** YES demoted, all DBA matches — class (a−); 2,834 − 2,821 = 13 ✓, and
  2,821 is now confirmed by execution
* the "should be 0" invariant — finding 4a. **A false assertion, not a defect**,
  and now resolved on `main`: `dev/AB-IDF-GATE.log` exists (PR #29), §1 states
  the invariant was false, and `ab-idf-gate.R` asserts the true one instead.
* §1 on `main` adds the figure that was missing from every earlier version —
  **the floor costs 6 identities**, net **+103 = 109 − 6** — and names the
  omission as the catalogued shape, flattering the floor. That is finding 4
  confirmed and finding 3's cause explained.

## `dev/TRUNCATION-FINDINGS.md`

Zero script and log citations, and **the lowest-exposure note in the sweep** —
worth recording as the shape of a note that needs no provenance machinery. Its
conclusion is *negative* ("measured, and not worth building"), so an error would
cause over-building rather than flatter the pipeline, and it opens by retracting
its own premise: "several motivating examples were artifacts of my own
reporting" — `substr(x, 1, 34)` display width mistaken for BMF truncation.

**1,495 of 1,924,822 (0.08%)** at the 70-character cap — class (c), but
self-checking (1,495/1,924,822 = 0.078% ✓) and its denominator **matches 10C's
active reference row count exactly**, which is the kind of cross-note agreement
that makes a class-(c) figure believable without a log.

## `dev/COMPARATOR-FINDINGS.md`

Zero citations; class (c) throughout. Low exposure for the same reason —
it justifies *not* building ("deliberately not fixed"), so an error costs a
missed improvement rather than a false result.

* JW **0.978** on two different congregations, **0.936** head-stripped — (c)
* separation table (`jw` 0.963 vs 1.000; `jw_tail` 0.578 vs 0.879;
  `idf_disagree` 17.7 vs 0.0) on **1,897** collected negatives — (c)
* **`idf_disagree ≤ 15` blocks 61% of negatives while losing 4% of positives** —
  (c), and this is the one figure here behind a (declined) recommendation
* **~0.03% of the YES tier**, "one case per 5,000 grants" — (c)

One cross-note mismatch: `PROMOTION-FLOOR-FINDINGS.md` §5 sizes the same
prefix-bonus problem at "**6% of promoted pairs**" while this note sizes it at
"**0.03% of the YES tier**". Different denominators (121 promoted pairs against
2,814 YES), so not a contradiction — 6% of 121 ≈ 7 pairs, 0.03% of 2,814 ≈ 1 —
but the two are quoted as if interchangeable. The *rates* differ by 200x where
the underlying counts differ by about 9x, so a reader comparing the percentages
directly draws the wrong conclusion about which note thinks the problem is
bigger. Practice 5.

---

# Part 3 — Denominator ledger

Practice 4, applied to every table reached. Free on all of them, and it produced
findings 4, 5, 8 and 9.

**Checked and correct** (denominator is the population the prose describes):

* 10C `MANIFEST.md` both arms — tiers sum to identities, clear rate stated as
  YES/identities, YES+MAYBE explicitly excluded from the term
* `NO-TIER` §denominator — 725 + 120 = 845; 2,979 + 1,044 + 845 + 35 = 4,903
* `NO-TIER` §1 — 34 and 33 on 91, labelled "the only stratum that estimates a
  rate"
* `NO-TIER` §6 — 59 after excluding 4 `UNCLEAR` from 63, stated; per-class
  recalls sum to 59; EIN table sums to 63
* `ADJUDICATION-EXPERIMENT` §Q2 — `n` on 100, accuracy on 27, in one table,
  distinctly labelled
* `ADJUDICATION-EXPERIMENT` §gate — 27, with the 3-case fragility stated
* `adjudicate-18` — `stopifnot(sum(BENCH) + 35 == 4903)`, the only *asserted*
  denominator check in the repo, and the practice-3 defence applied to a total
* `TRUNCATION` §2 — 1,924,822 matches 10C's active reference

**Checked and contested or wrong:**

| note | share | its denominator | the population the prose describes |
|---|---|---|---|
| `PROMOTION-FLOOR` §1 | 121 YES / 4.3% | 121 pairs(?) on 2,814 | table shows 116 identities — finding 4 |
| `PROMOTION-FLOOR` §1 | "all 121 fall to MAYBE" | — | NO rises 268 — finding 4 |
| `PROMOTION-FLOOR` all | tiers sum to 4,920 | unnamed population | never stated |
| `ADJUDICATION-EXPERIMENT` §Scaling | 22.0% MAYBE | 4,748 result frame | 4,868 in scope — finding 5 |
| `ADJUDICATION-EXPERIMENT` §Q1 | 62.74% → 78.28% | 4,748 result frame | 4,868 in scope — finding 9 |
| `ADJUDICATION-PLAN` | 20.1% MAYBE | grants | identities elsewhere — disclosed |
| `ADJUDICATION-PLAN` §4 | 738 cases = 70% of $ | "recoverable unresolved" | script's "unresolved" gives 489 — finding 6 |

**Three live MAYBE shares** — 20.1% (grants), 21.45% (in-scope identities),
22.0% (result-frame identities) — and **three identity counts for one corpus** —
4,580,944, 4,582,301, 4,585,061. Each is defensible on its own base. None of the
notes that use one says which of the others it is not, except Phase 4b.

---

# Part 4 — What this audit does not cover

An audit that implies completeness it does not have is itself a plausible wrong
number, so plainly:

**Notes swept in full:** `PLAUSIBLE-WRONG-NUMBERS.md`, `DEVELOPMENT-PLAN.md`
§Phase 4 step 5 / §Phase 4b / §"What these numbers are not",
`NO-TIER-EXPERIMENT.md` (§sample, §denominator, §1, §6, §6b, §7, §9),
`ADJUDICATION-EXPERIMENT.md` (§results, §gate, §Q1, §Q2, §ablation, §cost,
§scaling, §two cost corrections), `BASELINE-2026-10C/MANIFEST.md`,
`PROMOTION-FLOOR-FINDINGS.md`, `TRUNCATION-FINDINGS.md`,
`COMPARATOR-FINDINGS.md`, `ADJUDICATION-PLAN.md` §4.

**`dev/*-FINDINGS.md` NOT reached — 11 of 17.** I triaged the family by citation
density and read the three with no script or log references (highest class-(c)
risk) plus the two Phase 4b depends on. Unreached, with line counts and citation
counts as the only thing I can say about them:

| note | lines | script refs | log refs |
|---|---:|---:|---:|
| `STATE-PARTITION-FINDINGS.md` | 658 | 10 | 6 |
| `PURPOSE-MATCH-FINDINGS.md` | 634 | 11 | 1 |
| `DYAD-FINDINGS.md` | 466 | 7 | 0 |
| `SCHEDI-ALIAS-FINDINGS.md` | 408 | 3 | 0 |
| `AUDIT-FINDINGS.md` | 303 | 4 | 0 |
| `CLUSTER-FINDINGS.md` | 296 | 1 | 0 |
| `AFFILIATION-FINDINGS.md` | 274 | 2 | 0 |
| `ENRICHMENT-FINDINGS.md` | 247 | 2 | 0 |
| `REFIT-1K-FINDINGS.md` | 235 | 2 | 1 |
| `REFERENCE-TIER-FINDINGS.md` | 223 | 3 | 0 |
| `SHARD-AND-COLLAPSE-FINDINGS.md` | 194 | 3 | 1 |
| `MEMORY-FINDINGS.md` | 181 | 2 | 0 |
| `FUNDER-PROFILE-FINDINGS.md` | 142 | 1 | 0 |
| `DETERMINISM-FINDINGS.md` | 114 | 2 | 0 |

Citation density is a weak proxy and I want to be clear it is not a provenance
verdict: `TRUNCATION-FINDINGS.md` has zero of both and is the lowest-exposure
note I read, while a note with ten script references can still rescale by hand in
its prose — which is `DEVELOPMENT-PLAN.md`'s actual defect. **Two notes should be
read next on exposure grounds**, not density: `CLUSTER-FINDINGS.md` (1 script
reference for 296 lines, and `DEVELOPMENT-PLAN.md` cites its §2 to justify *not*
building a transitive EIN cluster id — a figure behind a deliberate omission) and
`DYAD-FINDINGS.md` §3 (cited the same way, "reports a better number by merging
different hospitals", which is a flattering-if-wrong claim by its own
description).

**Also not covered:**

* **Other note families entirely.** `SCALE-PLAN.md` (24k), `PLACES-SYNC.md`
  (38k), `PACKAGE-PLAN.md` (18k), `UNIT-UPSTREAM-SYNC.md` (21k),
  `PURPOSE-MATCH-DESIGN.md`, `BENCHMARK-NOTES.md`, `CASCADE*.md`,
  `DICTIONARY-PASS.md`, `NPNORMALIZE.md`, `JARO-NOT-JAROWINKLER.md`,
  `NAME-METRIC-EVALUATION.md`, `FEATURE-ENGINEERING.md`, `FUZZY-KEY-DESIGN.md`,
  `NO-RESIDUAL-AUDIT.md`, `CODE-AUDIT.md`, `OPTIMIZATION-PLAN.md`,
  `REF-PERFORMANCE.md`, `VARIANT-CLASS-AB.md`, `SHARD-*`, `LLM-*`,
  `DICTIONARY-*`, `MATCHDB-PLAN.md`, `NPMATCH-PROMOTION-PLAN.md`,
  `PHASE3-LIBRARIES.md`. `DEVELOPMENT-PLAN.md` outside the three sections named
  above — including §"What is deliberately *not* on this list", which is ten
  figures each justifying an omission and is the single densest unaudited
  concentration of recommendation-bearing numbers I saw.
* **The earlier baselines.** `BASELINE-2026-08`, `-10`, `-10B` and
  `dev/superseded/` were not opened. 10B is cited by 10C's delta table, so 10C's
  Δ column is class (b) against a manifest I did not read.
* **`R/`, `tests/`, `man/`, vignettes, `README`.** Out of scope by instruction.
  **No figure published to users was audited** — this covers the research record
  only. `DEVELOPMENT-PLAN.md` §Phase 4b's own caveat says these numbers should
  carry their confidence intervals "before any of it goes into user-facing
  documentation"; whether anything already has is unexamined.
* **Most scripts were still not run, though three were.** An earlier version of
  this file claimed nothing could be run because `Rscript` was absent. **That
  was wrong** — R 4.5.1 is installed, just not on `PATH`, and a `command -v
  Rscript` check is what produced the false conclusion. Recording it here
  because it is the same failure mode as the rest of this audit: a plausible
  negative result from a check that did not measure what it appeared to.
  What ran is listed under "What was executed" at the top.

  Of the scripts behind the inventory, **three were executed**
  (`adjudicate-18-layer-costs.R`, `ab-idf-gate.R`, `analyze-grant-dollars.R`)
  and **two saved frames read** (`ADJ-FUZZY-REGRESS.rds`,
  `ADJ-FUZZY-CUTOFF.rds`). Everything else was not, for stated reasons:

  | not run | why |
  |---|---|
  | `probe-promotion-floor.R` | `saveRDS` to `data-dev` (line 89) |
  | `adjudicate-17-fuzzy-cutoff.R` | writes `ADJ-FUZZY-CUTOFF.rds`; frame read instead |
  | `adjudicate-16-fuzzy-regress.R` | ~2 h first run, writes `data-dev`; frame read instead |
  | `adjudicate-10/11/12/14/15-*.R` | API calls, and stage 10 re-runs the match |
  | `adjudicate-03/04-*.R` | API calls |
  | `build-baseline.R` | full benchmark run, writes a baseline directory |
  | everything behind the 11 unreached notes | not reached at all |

  So class (a) means "I ran it and got this" for two scripts and "the saved
  frame holds this" for two more. For the rest it still means "the committed log
  prints this figure" — and finding 2 is precisely a case where a committed log
  and its citing prose disagreed, so that is a weaker warrant than it looks.

* **The two runs sit on data older than the notes.**
  `PF-MATCH-RESULT-1k.rds` is dated 2026-08-20 and `PF-MATCH-RESULT-50k.rds`
  2026-08-19, both well before the 2026-10-31 normalizer reinstall. The
  `ab-idf-gate.R` result reproducing the CORRECTION table exactly suggests that
  note was written against this same cached match; the `analyze-grant-dollars.R`
  disagreement may partly be the same staleness rather than the denominator
  I argue for in finding 6. I cannot separate those two causes without a fresh
  match, which is not a cheap run.

* **The inventory describes the repo at `26e6cd4` (PR #21); this branch now
  carries `main` through PR #34.** Merged in as `064a523` so that a pull request
  from here shows only this file. The audit was *written* against the older
  tree, so two things follow.

  **What main has since changed.** #24 adopted `pf_result_tiers()` inside
  `dev/adjudicate-16-fuzzy-regress.R` and wired `dev/assert-lib.R` into
  `adjudicate-03-score.R`, `-04-ablation.R` and `-12-no-score.R`, so the version
  of `adjudicate-16` on `main` differs from the one that wrote the
  `ADJ-FUZZY-REGRESS.rds` I read — the frame's 545.97 is what the *pre-#24*
  script measured. #29 resolved findings 4 and 4a. `dev/METRIC-SHAPES.md` and
  `dev/assert-lib.R` are new and were **not audited**: they postdate the sweep
  and nothing here covers them.

  **Every other finding was re-checked against the merged tree and is still
  live.** Not assumed — grepped after the merge: finding 1 (`falls to 0.002`),
  3 (`Ship distinct_name_min_idf = 10`), 5 (`$6,175` twice in
  `ADJUDICATION-EXPERIMENT.md` and once in `DEVELOPMENT-PLAN.md`; `4,585,061` in
  both), 6 (`GRANT-DOLLARS-FINDINGS.md` still cited in `ADJUDICATION-PLAN.md`
  and `PACKAGE-PLAN.md`, still absent), 7 (`$8,107`), 8 (`estimation (75)`) and
  9 (`78.28`). Seven of nine open after thirteen merged PRs.

* **`dev/METRIC-SHAPES.md` cites this file, and that citation has gone stale in
  the direction this file is about.** Its box at lines 26–50 says the audit is
  "on a branch that was never pushed to `origin`" and that "none of it is on
  `origin`, so a clone cannot see it and it survives only in this working copy".
  That was true when written and is **no longer**: the branch is on `origin`,
  and this merge is on it. The box also lists the audit's history as `159f4b3`,
  `ecc8e9b`, `0d16fd1` and so predates `bd1b59c`, which corrected finding 4a —
  the one framing that note's own author had supplied.

  The part that still holds is narrower and worth keeping: `FIGURE-PROVENANCE.md`
  has never existed on `main`.

  **Corrected on this branch, on the user's authorization**, as a dated
  superseding paragraph at the top of that box rather than a rewrite — the box
  itself argues that a wrong claim is "worth recording rather than quietly
  repairing", so both original paragraphs are left verbatim as the record and
  the new one marks them as such. **This is the one place this audit edits a
  file other than itself**, which is why it is called out here: the statements
  were false, they were false specifically *about this branch*, and leaving them
  on `main` when I could date them accurately would have been worse than the
  rail against editing audited notes is worth. `METRIC-SHAPES.md` postdates the
  sweep and is not among the notes audited.

  It is recorded at length because it is the cleanest instance in the repo of
  the pattern below: that note set out to document finding 6 reproducing itself,
  was careful enough to correct its own first draft about reachability, and still
  went stale on the one fact it took most trouble over — because the world moved
  under it, not because anyone was careless. A figure that depends on where a
  branch lives is a figure with a shelf life.
* **External prices.** `SEARCH_USD = 0.01`, the $0.10/$0.50 and $0.50/$2.50
  Haiku tiers and the $5.00/MTok cache-write rate are unverifiable inside the
  repo. Phase 4b flags this ("prices are list prices at the time of
  measurement"). Every dollar figure in this audit is conditional on them.
* **Figure-free claims.** Prose assertions with no number attached were not
  assessed, and a recommendation can be wrong without a wrong figure in it.

**What the counts are not.** 96 is the number of claims I classified, not the
number in the repo, and the denominator of "11 class (c)" is my sweep rather than
`dev/`. The catalogue's closing sentence applies here unchanged: nothing above
says how many remain unaudited, and by construction that is the one number this
file cannot provide. The narrower honest summary is that **of the figure classes
`PLAUSIBLE-WRONG-NUMBERS.md` singled out as unguarded, one — the corpus
projections — checked out arithmetically and carries its caveats, while the other
— anything measured once — turned out to have a defect the catalogue had already
caught and corrected in one note and not the other, twice.**

## The pattern worth taking forward

Findings 1, 5 and 8 are one failure in three places: **a defect was found,
recorded accurately where it was found, and the note that quotes the figure was
not updated.** The margin correction landed in `NO-TIER-EXPERIMENT.md` and not
`DEVELOPMENT-PLAN.md`; the denominator correction landed in `DEVELOPMENT-PLAN.md`
§Phase 4b and not `ADJUDICATION-EXPERIMENT.md` §Scaling or §Phase 4 step 5; the
stratum-B defect landed in `adjudicate-10-no-packet.R`'s comments and not in the
note that publishes the sample design. Finding 3 is the same thing inside a
single file.

Practice 1's remedy covers this precisely and is not yet applied: had the margin,
the layer-0 timing and the tier shares been *printed at point of use* rather than
typed into two notes each, a correction would have reached every consumer at
once. `adjudicate-18-layer-costs.R` is the right instrument and it already
exists — findings 1, 2 and 9 are all figures that *could* be printed by it and
are not.

One eighth catalogue entry comes out of this sweep — finding 2, `FZ_SEC = 521`.
An earlier version of this file proposed two more and **both were overstated**;
they are withdrawn and reclassified above. That the longest-standing finding in
this audit is one of its own is the honest note to end on: the practice that
catches a plausible wrong number is the same whether the number is in a research
note or in the audit of one, and reading output — a peer's as well as my own —
is what caught it both times.

`PLAUSIBLE-WRONG-NUMBERS.md` is not edited here, as instructed.
