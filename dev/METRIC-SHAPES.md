# Metrics that cannot come out wrong

Written 2026-11-01. Practice 7 of `dev/PLAUSIBLE-WRONG-NUMBERS.md` — "prefer a
measurement that can come out wrong" — applied to the repo's metrics other than
the one that already follows it.

The practice's worked example is the margin column in `dev/NO-TIER-EXPERIMENT.md`
§9. It is allowed to go negative, it reaches **−0.004**, and that negative number
*is* the finding: the 0.85 cutoff sits underneath the top personal-name collision
it was supposed to clear. Defined as `max(0, ...)`, or phrased as
"comfortable / tight", the same arm would have read as merely tight rather than
inverted. The conclusion the note draws is the premise here: **a metric that
cannot embarrass the design will not.**

§9 needs no change. What had never been done is asking the same question of
anything else — whether each metric is *capable* of returning a value that
contradicts the design it measures, or whether it is floored, clamped, bucketed
into adjectives, reported as a share whose denominator moves with the thing being
measured, or summarised on one side only.

A provenance audit of the repo's 96 numeric claims was the input, written the
same day under issue #15's proposal 3. Its Part 1 ranking (which figures sit
behind a recommendation *and* would flatter if wrong) is the same ranking this
work needed, and its Part 3 denominator ledger named three of the four changes
below before they were looked for.

> **Superseded 2026-11-01: the audit is on `origin` now, and a clone can see
> it.** `claude/figure-provenance-audit-50121f` was pushed at the user's
> instruction, with `main` through #34 merged into it, and is open as **PR #36**.
> It adds `dev/FIGURE-PROVENANCE.md` and this paragraph, which is the only thing
> the audit changes outside its own file.
>
> *This paragraph's first draft cited the branch head as `5bba437` and said the
> branch touched nothing but the audit's own file. The commit that added the
> paragraph falsified both — it became the new head, and it is the second file.
> Fixed by naming the branch and the PR, which do not move, instead of a SHA
> that does. Left on the record, and worth distinguishing from this box's own
> lesson: nothing external moved here. A claim about a branch, written in a
> commit to that branch, is only ever read after the commit lands, so it was
> never true at any instant after being recorded. The paragraphs below went
> stale because time passed; this was self-reference. A date fixes the first and
> cannot touch the second. The general form: an identifier that the act of
> recording changes cannot be used to record it — which is why naming the branch
> and the PR is the fix rather than a tidier style.*
>
> The two paragraphs below are left exactly as written, because this file's own
> standard is that a wrong claim is "worth recording rather than quietly
> repairing" — but read them as a record, not as current fact. Three of their
> statements are now false: that the branch "was never pushed to `origin`", that
> "there is nothing here to open", and that "none of it is on `origin` … it
> survives only in this working copy". Their history list also stops at
> `0d16fd1`, so it predates `bd1b59c` — the commit that corrected the audit's
> finding 4a, which is the framing this note's author supplied and then
> retracted. What still holds, and is worth keeping: `dev/FIGURE-PROVENANCE.md`
> has never existed on `main`, and the object-store point about worktrees is
> right.
>
> That this box went stale on the single fact it took most trouble over is a
> fourth instance of its own closing lesson, and the cleanest of them, because
> nobody was careless — the world moved underneath it. A claim about where a
> branch lives has a shelf life. That is a reason to date such a claim, not a
> reason to avoid making it.

> **That audit is not in this repository.** It was written as
> `dev/FIGURE-PROVENANCE.md` on a branch that was never pushed to `origin`, so
> there is nothing here to open and the three references to it in earlier drafts
> of this file were dangling citations — `dev/FIGURE-PROVENANCE.md` has never
> existed on `main`. That is **the audit's own finding 6** (a recommendation
> resting on `dev/GRANT-DOLLARS-FINDINGS.md`, "cited twice" and absent from the
> repo) reproduced by the note that cited the finding, which is worth recording
> rather than quietly repairing. Its substantive results that bear on the work
> below — the exposure ranking, the denominator ledger, findings 1, 2, 4 and 9
> — are restated here where they are used, so nothing in this file depends on
> reaching it.
>
> **A reader on this machine can nonetheless read it, and the first draft of
> this box wrongly said otherwise.** The sessions on this project work in
> `git worktree`s of one repository: `git rev-parse --git-common-dir` returns
> the same `.git` from each, so they share one object store, and a commit one
> session has made but not pushed is a reachable object from any of the others.
> The audit is `dev/FIGURE-PROVENANCE.md` on `claude/figure-provenance-audit-50121f`,
> whose history reads directly from here — `159f4b3` publishes it, `ecc8e9b`
> corrects its `Rscript` caveat, `0d16fd1` withdraws two of its catalogue
> candidates. **Unpushed is not unreachable when the sessions share a
> checkout.** What is true is narrower and still worth saying: none of it is on
> `origin`, so a clone cannot see it and it survives only in this working copy.
>
> This is the third unchecked claim about verifiability in this file's short
> history — after `Rscript` and the dangling citation itself — and the shortest
> to check of the three. The lesson is not about `git` but about the shape: a
> statement that something *cannot be verified* licenses every unverified
> verdict downstream, and is therefore the claim most worth spending a command
> on, not least.

> **Correction, and an embarrassing one for a note about unverified figures.**
> The first two drafts of this file said `Rscript` "is not on this machine" and
> declined to report any computed figure on that basis. **That was wrong.** R
> 4.5.1 is installed at `C:\Program Files\R\R-4.5.1`, with `npmatch`
> 0.1.1.9000, `pfmatch`, `data.table` and `stringdist` all present — it is
> simply not on `PATH`, which is all the original check established:
>
> ```
> which Rscript   # → nothing, and I stopped there
> ```
>
> The provenance audit had recorded the same thing and this note inherited it
> without re-checking — the audit's own closing pattern, a claim propagating to
> the note that quotes it, applied to a claim about whether anything *could* be
> checked, which is worse than the figures it was used to excuse. Every "not
> run" statement below has been re-examined and the ones that were only true of
> `PATH` are now runs.
>
> **The inheritance is the point, not the other note's error.** That author
> found and corrected the same caveat independently, on their own branch, before
> this was raised with them; and since that branch is not in this repository
> (see above), nothing false on the subject is published anywhere a reader can
> reach. The failure recorded here is wholly this file's: it repeated a claim
> about the limits of verification without spending one command on it.

Status of each change, after the correction above:

* **Changes 3 and 4 are run here**, on the cached 1k match under R 4.5.1 /
  npmatch 0.1.1.9000, with the transcripts committed as
  `dev/PROMOTION-FLOOR-PROBE.log` and `dev/AB-IDF-GATE.log`. Every figure
  attributed to them below is in those logs. See "What the runs found".
* **Change 1's effect on the three reference arms is recomputed** from the exact
  counts `dev/BENCH-MD-REFERENCE.log` already prints — no re-run needed, and a
  re-run is still expensive (~37 GB, one process per arm). The ordering holds;
  the gap between the top two arms grows about fivefold; and one published
  figure outside `dev/` is affected.
* **Changes 2, 5 and 6 are not run.** Their figures are not claimed anywhere.

The sibling session running issue #15's proposal 3 reached several of these
first, independently, and two of its findings corrected this work rather than
the repo — the `main_only` diagnosis in change 3 and the false-alarm in change
4. Credited where they appear. Its figures were never adopted as published
values. `PROMOTION-FLOOR-FINDINGS.md` §1 and §5 are regenerated in **PR #28**,
that session's work; the run logged here agrees with it figure for figure and is
the artifact behind it.

---

## Changed

### 1. `dev/bench-md-reference.R` — the clear rate rewarded an arm for failing to retrieve

**Shape 3: a share whose denominator moves with the numerator.** Highest-exposure
change here, because the figure chose a default.

The script compared three references — the local augmented bundle, matchdb
`unified-observed`, and matchdb `active-observed` — and reported

```r
clear rate = 100 * tb[["YES"]] / nrow(res)
```

`nrow(res)` is the **result frame**. `R/report.R`'s own convention note says what
that means: an identity no blocking pass produced a pair for is *absent* from the
result frame rather than `NO`. The three arms are three different references, so
they do not retrieve for the same identities — and the arm that retrieves less
gets the smaller denominator. The share can rise while coverage falls. At the
limit, an arm that found a pair for half the file and cleared all of them reports
a 100% clear rate.

That is the one outcome a reference comparison has to be able to show, and the
metric's definition excluded it. The script's own header claimed
`active-observed` "won outright" on this benchmark and has been the default
since — a claim that turns out to be wrong on its own log, and is corrected
below along with the header.

**Now:** the base is `length(m$in_scope)` — a property of the grant file,
identical across arms, unmoved by how well any of them retrieves. An `ABSENT`
row is printed with its count and share, the result-frame reading is printed
beside the in-scope one, and the **gap between them is printed as a number**,
because that gap *is* the coverage the arm lost. `pf_result_tiers()` (PR #23) is
used on the result-frame side so the convention is named at the call site rather
than arrived at by reaching into `x$result`. The in-scope ids and the no-pair ids
are attached to the saved `.rds` as attributes, so the base travels with the
artifact — saving the frame alone is what let the result-frame denominator be
re-derived downstream and the in-scope one not.

**Which direction the figures move: down, for every arm.** The in-scope base is
larger than the result frame by exactly the no-pair count, so each arm's clear
rate falls.

This one was settled after the first draft of this note, without a re-run.
`dev/BENCH-MD-REFERENCE.log` prints exact YES counts and per-arm result-frame
identities, not just rounded shares, and that is enough to recompute both
readings. (Spotted and recomputed by the sibling session running issue #15's
proposal 3; the counts below were re-checked against the log here.)

| arm | result frame | in-scope base | change | no pair |
|---|---:|---:|---:|---:|
| `unified-observed` | 63.91% | 62.45% | −1.46 | 111 |
| `active-observed` | 63.80% | 61.96% | −1.85 | 141 |
| `augmented` | 62.77% | 61.24% | −1.53 | 119 |

From `2981/4749`, `3040/4757`, `3016/4727` in the log, on the 4,868 in-scope
identities of the `efv2_1k` population (4,903 grants less 35 OOS; the log prints
`nrow(grants)` = 4,903, not the in-scope count, so 4,868 comes from
`NO-TIER-EXPERIMENT.md` §denominator and is the one number here not read off
this log).

**The mechanism is confirmed and the ordering holds.** `active-observed` loses
the most, −1.85 points, because it has the most absences — which is the effect
the change exists to expose. But `unified > active > augmented` on both
readings, and that is robust rather than lucky: all three arms share one fixed
base, so the ordering on it is just the ordering of the YES counts.

**What moves is the gap, by about five times.** On the result frame
`unified-observed` leads `active-observed` by **0.10** points — but those two
shares stand on 4,757 and 4,727, so `active-observed`'s smaller denominator is
masking part of the difference. On a shared base the gap is `24/N`, about
**0.49** points (0.4930 on 4,868, 0.4895 on 4,903 — invariant to the choice).
This is the shape-3 defect operating on a *difference between two arms* rather
than on one arm's level, which is the form it is hardest to see.

**One correction to the first draft of this note, and to the script's own
header.** Both said `active-observed` "won outright" on this benchmark and that
the fix might unseat it. It did not win outright: on the log it is **second** on
clear rate and **last** on YES+MAYBE (83.8% against 86.4% and 84.6%). What it
wins is time — 11.5 min against 28.7 — and PR #12 chose it on exactly that:
`unified-observed` buys its extra point for two and a half times the match time,
~275 hours at full corpus scale. **So the default is not in question.** The
"won outright" phrase was in the script header before this work and the first
draft inherited it rather than checking it — which is the audit's own forward
pattern, a claim left standing in the file where nobody re-reads it.

**But the figure it feeds is published outside `dev/`.** The 0.1-point gap is in
`R/pipeline.R`'s roxygen ("for two and a half times the match time and +0.1
point") and in `vignettes/matching-dictionaries.Rmd` at four places, including
the 62.8 / 63.9 / 63.8 clear-rate table and "0.1 point for 275 hours". Under
the base this change adopts those become 61.2 / 62.5 / 62.0 and ~0.49. The
275-hour argument is untouched; the tradeoff *sentence* understates the recall
it gives up by about five times.

**Not corrected here.** `R/`, `tests/` and `man/` are out of scope by
instruction and the vignette is shipped material whose rebuild is the
maintainer's call. Recorded as the one downstream edit this work identifies and
does not make.

*To re-derive from scratch:* one arm per process (the augmented bundle alone
peaks near 37 GB).

```bash
for ARM in augmented unified-observed active-observed; do MD_ARM=$ARM Rscript dev/bench-md-reference.R; done
```

### 2. `dev/compare-baselines.R` — a difference of two shares on two different denominators

**Shape 3 again, in its purest form.** This compares `BASELINE-2026-10` (v1,
undeduplicated) against `-10B` (v2, deduplicated), and the identity count is the
thing that moved between them — the script says so itself, in prose, at the
bottom. It then reported `clear %+.2f points` as a single difference, which is
not a measurement of matching: dropping fewer identities raises it exactly as
readily as matching more of them.

**The first attempt** decomposed the delta algebraically:

```
clear2 − clear1  =  ΔYES / n2                      ← labelled "the matching term"
                 +  YES1 · (n1 − n2) / (n1 · n2)   ← labelled "the denominator term"
```

An exact identity, `stopifnot()`-checked against the headline — and the label on
the first term is wrong, which is the subject of the withdrawal below. **`ΔYES`
is a change in a count over a population that also changed**, so it is not a
matching measurement at all, and no amount of checking the *arithmetic* would
have caught that. Practice 6 verifies that two terms sum to a third; it has
nothing to say about whether either term means what it is called.

**What the script does now:** holds the identity set fixed and compares the same
identities in both baselines, which measures matching directly, and reports
composition — who left, who arrived, and how each cleared — beside it.

> ## WITHDRAWN. This change's published finding was a false alarm, and it was
> the loudest thing in this note.
>
> Earlier drafts called this "the largest finding in the note" and reported:
>
> > The v1 → v2 population change cost 1.3–1.45 points of matching, and the
> > shrinking denominator gave back 86–87% of it. The published headline is
> > −0.17 and −0.21 — seven times smaller than the move underneath.
>
> **There was no matching loss.** The decomposition
> `Δclear = ΔYES/n₂ + YES₁·Δn/(n₁·n₂)` is algebraically exact, and the label on
> the first term was wrong. `ΔYES` is the change in the YES **count**, which
> mixes matching with *which identities are present* — so when the population
> changes, that term absorbs the composition effect and reports it as matching.
>
> The frames carry `.id`, so the matching move is directly measurable: hold the
> identity set fixed and compare the same identities in both baselines.
>
> ```
> active     clear -0.17 pt   MATCHING on the 4,481 both hold: 56.97% -> 56.77%  -0.20 pt
>                             COMPOSITION: 299 left (57.9%), 206 arrived (58.7%)
> augmented  clear -0.21 pt   MATCHING on the 4,598 both hold: 62.88% -> 62.92%  +0.04 pt
>                             COMPOSITION: 244 left (65.6%), 150 arrived (59.3%)
> ```
>
> Matching moved **−0.20** and **+0.04**. `BASELINE-2026-10B/MANIFEST.md`'s
> published −0.17 / −0.21 are accurate summaries and its sentence "the direction
> is the expected one rather than a regression" is correct — `augmented`'s
> matching slightly *improved*. Nothing was masked and nothing needed carrying
> into that note.
>
> A second error was stacked under the first: the population change is not a
> clean removal. **299 identities leave and 206 arrive** in `active`, 244 and 150
> in `augmented`, because v2 re-keys some — so the reasoning that "93 rows left"
> was also false, and the net identity count understates how much moved.
>
> **This is the defect this note had already diagnosed, one file over.** A
> metric that raises a *false* alarm is as bad as one that cannot alarm, because
> it teaches the reader to skip the line — written here about
> `ab-idf-gate.R`'s `YES gained (should be 0)`, then rebuilt in this change,
> believed, promoted to the headline finding, and flagged to a peer as the figure
> most wanting a second reader. Practice 7 asks for a measurement that can come
> out wrong. It does not excuse the *alarming* direction from needing a second
> instrument, and there was none on this one for three rounds.
>
> `compare-baselines.R` now measures matching on the intersection, and its
> warning fires on a measured divergence between the matching move and the
> headline rather than on a mislabelled term. On the committed run it reports no
> masking, correctly. The withdrawn figures are in `git log -p`.

**Run: `dev/COMPARE-BASELINES.log`.** What the change is actually worth, after
the withdrawal above: the headline delta is unchanged, and underneath it the
matching move and the composition effect are now separated and measured rather
than inferred. That is a real improvement on a single difference — a reader can
see that `augmented`'s matching held while its population moved — it is simply
not a finding about the pipeline. The denominator for both `clear` columns
remains the result frame, so neither reading recovers the retrieval failures
neither base counts.

*To re-derive:* `Rscript dev/compare-baselines.R` (reads four committed `.rds`
files; seconds).

### 3. `dev/probe-promotion-floor.R` — a recovery count with no column for what it cost

**Shape 4: a one-sided summary.** This is the script behind
`dev/PROMOTION-FLOOR-FINDINGS.md` §1 and audit finding 4.

Section 1 reported one number — "YES matches that exist ONLY because of the
floor: N" — which counts what the floor won and nothing it cost. The floor could
not come out of this script looking worse than neutral. §9's cutoff table is the
contrast: it carries `recovered` *and* `false offers` *and* `margin`, which is
why it was able to show the inversion.

Three companion measurements now print beside it, each **whether or not it is
zero** — a column that appears only when it fires cannot be read as evidence
that it was measured:

* **the reverse direction** — identities YES only with the floor *off*. A score
  floor is a `pmax` and cannot lower a pair's score, but it can change which
  pair `np_select()` picks, and the selected pair's tier can then fall.
* **EIN churn** — identities YES under both settings but matched to a *different*
  EIN. The old count saw these as "no change". One of the two EINs is wrong and
  nothing downstream can tell which, so the floor re-pointing a cleared match is
  a cost even where the tier is unmoved. `dev/compare-blocking.R` has carried
  this column all along ("EIN disagreements where both say YES"); this script did
  not.
* **gross against net** — the dependency count printed next to the net tier
  deltas it must reconcile with, with an explicit complaint when they disagree.
  A `pmax` floor can only add YES, so the net YES move *is* the gross count.
  This is the check that **121-against-116** needed: the audit found §1 publishing
  121 where its own table shows a net move of 116, most likely pairs against
  identities, with neither named. The output now states that `dep` counts
  identities (`pf_status()` rows) and that a pair count over the same set is
  larger and not interchangeable.

Two more defects of the catalogue's own kind were in the same block and are
fixed with it:

* `match()` returns `NA` for an id the other arm does not carry, `"YES" & NA` is
  `NA`, and `which()` drops `NA` — so an identity that fell out of one arm's
  status frame was **silently excluded from the count** rather than registered
  as a change. Both arms rescore the same stored pairs, so the id sets must be
  identical; that is now asserted rather than assumed.
* the share was quoted as `dep / YES_with_the_floor`. That denominator moves with
  the setting under test. Both bases now print, rather than whichever is smaller.

**Direction:** `dev/PROMOTION-FLOOR-FINDINGS.md` §1's 121 and 4.3% are not
corrected here — correcting them needs the run. What the script will now report
is the same gain with its cost beside it, so the *recommendation* can move even
where the gain does not. The note's §5 "Recommendation" is in any case already
retracted by its own CORRECTION below it (audit finding 3), which this change
does not touch.

*To re-derive:* `Rscript dev/probe-promotion-floor.R` — needs
`data-dev/PF-MATCH-RESULT-1k.rds`, rescores stored pairs, no re-blocking.

### 4. `dev/measure-recovery.R` and `dev/ab-idf-gate.R` — the same missing column

**Shape 4.** `measure-recovery.R` was better than §3's script to start with: it
already reported `YES -> lost` and the candidate and time cost. What neither it
nor `ab-idf-gate.R` reported was **EIN churn** — an identity YES before and
after, on a different EIN. A status comparison reads that as no change, and
stage 4 can generate a candidate that outscores the one the lean cascade
accepted.

This matters most for `ab-idf-gate.R`, because
`PROMOTION-FLOOR-FINDINGS.md`'s CORRECTION turned on this script reporting that
`distinct_name_min_idf = 10` "moves 2 cases, net zero" — and **net zero on a
status comparison is not net zero on the EINs.** That distinction was never
measured. The disposition it drove (`distinct_name_min_idf = 0`, disabled) may
well survive; the evidence behind it was one-sided.

Also in both: the `match()`/`NA` guard from §3, `need_rows()` on the shared
identity count, and `need_vocab()` on `pf_status_levels()`.

And in `measure-recovery.R`, the NO-tier share is now explicitly denominated on
the **before** count, stated in the output line. Denominating it after the pass
shrinks the base by exactly the recoveries, which inflates the share — shape 3
hiding inside a shape-4 script.

*To re-derive:* `Rscript dev/measure-recovery.R` (runs two full matches, not
cheap); `Rscript dev/ab-idf-gate.R` (rescores stored pairs, cheap).

### 5. `dev/adjudicate-03-score.R` — a clamped normal interval, and three hard-coded plus signs

**Shape 1: a clamped quantity, where the overshoot is the finding.**

`poststrat()` computes the tie-adjusted clearance behind
`ADJUDICATION-EXPERIMENT.md` §Q1's "tie-adjusted 70.7%" and "738 of 1,044 cases
(CI 620–855)" — a figure the audit places behind the Phase 4 go-ahead. It is a
**normal** interval, not Wilson: the post-stratified estimator is a weighted sum
and has no Wilson form. A normal interval on small strata can run outside [0,1],
and `max(0, ...)` / `min(1, ...)` absorbed that silently.

An interval that needed clamping is an interval whose approximation has failed,
and the clamped version reads as tighter and better behaved than the measurement
is. The raw bounds are now carried alongside and the caller says, in the output,
when they differ — and says what the clamp means: a statement about *n*, not
about the clearance rate.

**The published figures do not move.** At the published estimate the clamp does
not bite (0.707 − 1.96·se ≈ 0.594 > 0), so this changes what the script *can*
report, not what it currently reports. That is the point of the practice.

Separately, three format strings hard-coded a `+` where the quantity can be
negative, which renders a negative as `+-0.50` and reads as a typo rather than
as a finding. Fixed to `%+`:

| site | quantity | why it can be negative |
|---|---|---|
| `adjudicate-03-score.R` | clear-rate delta and its CI | the CI bound, once unclamped |
| `adjudicate-04-ablation.R` | search's cost premium over no-search | **this ablation exists to ask whether search earns its cost** |
| `measure-recovery.R` | stage 4's candidate and time cost | an extra pass is not guaranteed to cost time |
| `probe-shard-rss.R` | working-set delta after a step | memory can fall across a step |

`measure-recovery.R`'s candidate count needed a helper rather than a format flag:
`%+s` is not a valid R format, so the sign is built around `format(abs(x))` to
keep `big.mark`.

### 6. `dev/probe-threshold-recall.R` — a best-arm pick with no companion column

**Shape 4, mild.** `safe_floor()` is a `which.max(prune_rate)` over the floors
meeting a recall target, and the read-out gave the winning floor's prune rate
alone. `recall >= 0.95` is satisfied by 0.951 and by 1.000 alike, and a floor
that only just clears the target is a different recommendation from one that
clears it with room. The realised recall, its distance above the target, and the
mean candidates kept now print beside the prune rate.

`need_cols()` and `need_rows(min = 1L)` added to `load_set()`: four filters run
in it, each can empty the frame, and an empty one gives a sweep of `NaN` recalls
and zero prune rates that prints as a table rather than failing — catalogue
defect 7's shape.

**Run: `dev/THRESHOLD-RECALL.log`.** No published figure moves — this note
publishes none of this script's figures, and `dev/PURPOSE-MATCH-FINDINGS.md` was
not reached by the provenance audit. The companion column pays anyway, in three
ways that the prune rate alone could not show:

```
recall >= 1.00 : best floor t=0.550 prunes 65.2% at recall 1.000 (0.000 above target), keeping 2.39/grant
recall >= 0.99 : best floor t=0.550 prunes 65.2% at recall 1.000 (0.010 above target), keeping 2.39/grant
recall >= 0.95 : best floor t=0.650 prunes 78.6% at recall 0.964 (0.014 above target), keeping 1.82/grant
...
recall >= 0.99 : best floor t=0.000 prunes  0.1% at recall 0.997 (0.007 above target), keeping 4.22/grant
```

* The **1.00 and 0.99 rows are the same floor** (`t = 0.550`, recall 1.000).
  Two rows that look like two operating points are one. The realised-recall
  column is what says so.
* The 0.95 row clears its target by **0.014** — a floor that barely makes it,
  reported identically to one that clears with room.
* On the silver set the "best floor" is **`t = 0.000` pruning 0.1%**, i.e. no
  pruning at all. "Best floor prunes 0.1%" reads as a result; `t = 0.000` beside
  it reads as what it is.

Twenty of the thirty target rows print `NOT ACHIEVABLE`, which was already the
honest form and is why this change ranked last.

---

## What the runs found

Changes 3 and 4 were run on the cached 1k match under R 4.5.1 / npmatch
**0.1.1.9000**, transcripts committed as `dev/PROMOTION-FLOOR-PROBE.log` and
`dev/AB-IDF-GATE.log`. Recorded here because a redefinition that is never run is
a proposal, not a measurement — and because what came back is not what was
predicted. The two runs cross-check: `probe-promotion-floor`'s floor-on arm and
`ab-idf-gate`'s `min_idf = 0` arm are the same configuration and both report
2,821 / 1,006 / 1,093.

### The EIN-churn hypothesis is disconfirmed. Twice.

Changes 3 and 4 both rest on the reasoning that a status comparison records an
identity re-pointed to a different EIN as "no change", and that this hidden cost
was what the one-sided counts were missing. Measured:

| script | EIN churn |
|---|---:|
| `probe-promotion-floor.R` | **0** of 2,712 |
| `ab-idf-gate.R` | **0** of 2,820 |

The columns stay. A zero that was measured and a quantity nobody looked at print
identically in a note and differently in a log, and the second is what these
scripts are for. But the reasoning in the commit message was wrong: churn is not
where the missing cost lives, and this note should not imply it was vindicated.

### `ab-idf-gate.R`: the gross-against-net line found it instead, and the assertion was wrong

```
min_idf 0  : YES 2821  MAYBE 1006  NO 1093
min_idf 10 : YES 2822  MAYBE  986  NO 1112
demoted 1   gained 2   net +1 YES
```

Two results, and the second corrects this work rather than the repo.

**`PROMOTION-FLOOR-FINDINGS.md`'s "moves 2 cases, net zero" does not
reproduce.** The net is **+1**. That figure is what shipped
`distinct_name_min_idf = 0`, and it does not balance on the status comparison
the CORRECTION used.

**But `gained` was never a defect indicator, and asserting that it was is a
defect of its own.** The original line read `YES gained (should be 0)` and change
4 kept that framing, adding "non-zero … is a selection move or a defect". The
invariant is simply false. The gate removes pairs; `np_tier()` demotes on the
**margin to the runner-up** — `R/dyads.R`'s "Collapse before selection" section
says so, and `R/match.R:287` records a case of it — so removing a runner-up
*raises* the winner's margin and can carry it MAYBE → YES. A gain is expected
behaviour.

This is practice 7 failing in the opposite direction, and worth naming as such:
a metric that reports a **false** alarm is as bad as one that cannot alarm,
because it teaches the reader to skip the line. The script now asserts the
invariant that is true — no gained identity's *score* rose, which a veto cannot
cause — prints the margins beside it, and `stopifnot()`s the score condition
rather than the gain. **The assertion holds and the margins show the
mechanism:**

```
                           name    was score_off score_on margin_off margin_on
                OHIO FOUNDATION  MAYBE       0.9    0.888          0     0.068
 FAMILY AND CHILDREN'S ASSOCIAT  MAYBE       0.9    0.820          0     0.140
```

`margin_off` is **exactly 0** in both — ties — and the **score falls**. Falling
is the right signature and flat would have been the suspicious one: once the
floored pair is vetoed a *different* pair wins, scoring slightly lower but
carrying a real margin. Flat would mean the same pair survived and only its
runner-up left. (I predicted flat; the sibling session's run showed otherwise
and this one confirms it.)

Both of those identities also appear among the **six the floor costs** in change
3 below. One tie-driven selection mechanism, observed from either side of the
floor, in two scripts that were changed for unrelated reasons.

### `probe-promotion-floor.R`: the cost column paid

```
gained 109   cost 6   net +103 = 109 - 6        (reconciles)
all 109 fall to MAYBE (YES 0  MAYBE 109  NO 0  OOS 0)
geo on the floor-dependent pairs: state only 108, ZIP3 only 1
```

**Six YES identities exist only with the floor off** — selection moves, exactly
what a `pmax` can cause. `PROMOTION-FLOOR-FINDINGS.md` §5 reads "Keep the floor.
It carries 121 matches at ~85% precision" and has no slot for them, because the
metric it rests on could only count wins. The net is **+103**, not +121.

**The note's qualitative claim survives.** All 109 fall to MAYBE, so the floor
is deciding what gets adjudicated rather than creating recall from nothing.

**And the published figures were stale: 121 and 4.3% against 109 and
3.9%/4.0%**, with both tier arms moved (2,821 / 2,718 against the note's
2,814 / 2,698). "4.3% of the tier" was also denominated on the YES count the
floor itself inflates — this note's shape 3, appearing in a published note
rather than in code. So the audit's "121 pairs or 116 identities?" had a third
answer: neither reproduced.

**The cause is configuration, not drift and not an error.** §1 was measured
before `distinct_name_main_only`, the gate the CORRECTION below it introduces
and which `np_config()` now defaults to `TRUE` — verified here. Two things pin
it down, and this is the sibling session's diagnosis, reached from the first:

* the CORRECTION's own `main_only` row, **2,821 / 1,006 / 1,093**, reproduces
  **exactly**, which rules out version drift — drift would have moved it too;
* every tier table in the note, in the CORRECTION, and in both runs here sums
  to **4,920**, which rules out a population change.

A stable population plus a reproducing control row leaves the config default.
**So the old §1 was not wrong; it was unlabelled** — correct for a pipeline that
no longer exists. The defect was a missing configuration and version line, not
the arithmetic. That is a better diagnosis than the first draft of this note
reached, and it is worth recording that the first draft's "drift or original
error, cannot tell" was a failure to look for the control row that was eighty
lines further down the same file.

**§1 and §5 are regenerated in PR #28**, by the sibling session, which reached
the `main_only` diagnosis first. That PR removes the `STALE` box #25 put there
as a holding action — which is the right end for a flag: it existed to make the
figure unquotable while neither session could re-run it, and it is retired by
the fix rather than left standing beside it.

The regeneration was also done independently here, from
`dev/PROMOTION-FLOOR-PROBE.log`, and **the two agree figure for figure** —
2,821 / 1,006 / 1,093 and 2,718 / 901 / 1,301, gained 109, cost 6, net +103,
churn 0, state-only 108 of 109. That duplicate prose is not committed; #28 owns
the note. What this branch contributes instead is the **run log #28 does not
have**: that PR's §1 cites "npmatch 0.1.1.9000" with no artifact behind it, and
practice 1's standard is that a figure which cannot be re-derived by running a
file is a figure nobody can check. `dev/PROMOTION-FLOOR-PROBE.log` is that file.

### What this exchange says about the practice

The scorecard, counting the withdrawal:

| | |
|---|---|
| **confirmed, consequential** | change 1's denominator — moved three published figures and a shipped vignette |
| **confirmed where not expected** | change 3's cost column — 6 against a published 0 |
| **disconfirmed twice** | EIN churn, 0 of 2,712 and 0 of 2,820 |
| **false alarm** ×2 | `ab-idf-gate`'s `gained`, and change 2's `MASKED` — the second promoted to this note's headline finding before it was checked |

Every row but the first needed a run. One shape in four paid; two of the four
produced an alarm that was wrong rather than a value that was wrong.

**That ratio is the result, and it cuts against the practice as this note first
stated it.** "Prefer a measurement that can come out wrong" is sound, and
incomplete in a way this note demonstrated twice at its own expense: a
measurement that can come out wrong can come out wrong *in the alarming
direction*, and an alarm is exactly the output nobody audits, because it reads
as the metric working. Both false alarms here were believed on sight — one of
them after this very file had written the paragraph explaining why that is a
defect. The missing half of practice 7 is that **a new alarm needs a second
instrument before it is published**, and the cheapest second instrument is
usually the one that holds the population fixed.

The reasoning offered for three of the six changes turned out wrong — churn
twice, masking once — while the changes themselves mostly stand. That is a
reasonable outcome for a first pass and a poor one to have published without
running, which was the original sin and is corrected in the box at the top.

---

## Considered and left alone

Saying so with the reason is the result in these cases. Several are the practice
already applied, and those are worth naming because they are the models the
changes above copied.

| metric | shape it has | why no change |
|---|---|---|
| **`adjudicate-17-fuzzy-cutoff.R` margin** | 1 — unclamped | The model. `margin := cutoff - top` with no floor, both `recovered` and `false_offers` columns, and the personal-name scan run at `skip_personal = FALSE` on purpose so the hazard is not measured through its own mitigation. Nothing to generalise *to* here. |
| **Wilson intervals** (`adjudicate-03`, `-04`, `-06`, `-12`, `-14`, `-15`) | 1 — looks clamped | `max(0, ...)` / `min(1, ...)` around a **Wilson** bound is belt-and-braces: Wilson is analytically inside [0,1] for `0 ≤ k ≤ n`, so the clamp cannot bite and cannot hide anything. Left alone, and the distinction is now stated in `adjudicate-03-score.R` beside the normal interval that genuinely needed it. |
| **`evaluate-arms.R` `clear = mean(tier == "YES")`** | 3 — result-frame base | Looks identical to change 1 and is sound here. The arms vary `jw_p` and `substring_p`, which are *scoring* parameters: they change pair scores, not which identities get a pair, so `nrow(result)` is constant across arms and the denominator does not move with the thing under test. The script also already carries `recall YES`, `recall Y+M`, `false clears` and "picked an EIN adjudication ruled out" — its header says in as many words that a clear rate alone "cannot separate recall from precision". The same expression is a defect in one script and sound in another; which it is depends on whether the knob moves blocking. |
| **`bench-substring-ab.R` clear rate** | 3 — result-frame base | Same reasoning: scoring-only arms, so the denominator is constant across them — the two arms whose counts are printed in the script both sum to 4,843 — and the *comparison* holds. The *level* is overstated against the in-scope base, by the same mechanism as change 1. Not changed because this script's figures support a comparison and are not quoted as levels; flagged here rather than silently fixed. |
| **`adjudicate-03-score.R` projection onto 4,748** | wrong base, fixed base | This is audit **finding 9** — `62.74% → 78.28%` on the result frame where the project holds 4,868 in scope. It is a provenance correction, not a metric shape: the denominator is a literal and does not move with the numerator. Left to the fix pass rather than changed here, so the correction lands once and in one place. |
| **`adjudicate-12-no-score.R` cleaned denominator** | 3 — deliberately shrunk | The honest form of the shape: it shrinks the base on purpose (dropping NO-tier payees the BMF could never hold), prints **both** bases, and labels the uncleaned one as "from scope alone, matching nothing". Already the practice. |
| **`probe-determinism.R` PASS/FAIL** | 2 — bucketed | Determinism genuinely is binary — the header says "exact equality, not tolerance", and a benchmark that is merely close cannot gate anything. On failure it prints the differing columns with cell counts, so the magnitude is not discarded. |
| **`adjudicate-preflight.R` PASS/FAIL** | 2 — bucketed | Reachability and schema checks. There is no continuous quantity underneath to lose. |
| **`adjudicate-03-score.R` `mband` cut** | 2 — bucketed margin | The margin is the *stratifier* for an agreement rate, not the reported metric, and the first band is `<=0`, so a negative margin is still visible as its own row. Bucketing is what makes the agreement rates readable at n=68. |
| **`cut()` distribution tables** (`build-dyads`, `build-group-index`, `diagnose-dyad-fanout`, `measure-persistence`, `probe-ntee-availability`, `cluster-02`, `probe-additive-risk`, `eval-schedi-alias`, …) | 2 — bucketed | Descriptive distributions, not pass/fail verdicts on a design decision. No threshold is being justified, so there is nothing for a bucket to flatter. |
| **`compare-blocking.R`** | 4 — would be | Already carries all three: recall cost, gain, and "EIN disagreements where both say YES". The source of change 4's missing column. |
| **`sweep-dyad-rules.R`** | 4 — would be | Already carries "already-right touched" as the false-alarm proxy, and says so: "a rule that touches many of them is asserting more than it knows." |
| **`adjudicate-16-fuzzy-regress.R`** | 3 — would be | Already denominates on `length(scope)` from `x$in_scope`, injects an `ABSENT` level so a no-pair identity shows as a non-movement rather than vanishing, guards it with `need_vocab()`, and names `yes_broken` and `llm_contradicted` beside `to_yes`. The source of change 1's pattern. |
| **`summarize-audit.R`, `adjudicate-12-no-score.R` `+%` formats** | 1 — would be | Their quantities are counts and shares that are structurally non-negative (`n_maybe × rate`, and a share on a base that can only shrink), so the hard-coded plus cannot mis-render. Left alone rather than changed for uniformity. |
| **`dev/adjudicate-18-layer-costs.R`** | — | Not touched. `FZ_SEC` is audit finding 2 and the fix pass owns it, along with the ~136 core-hour projection that follows. |
| **`pf_crosstab()`'s `pct_YES_of_attempted`** (`R/report.R`) | 3 | Out of scope by instruction. Worth a look by whoever next opens `R/`: `att <- out$n - out$OOS` is the right base for OOS but still counts only identities the status frame holds, and `pf_status()` reports a no-pair identity as `NO`, so this one is probably fine. Unverified. |

---

## What this does not claim

Six changes across nine scripts; fourteen more metrics considered and left as
they are, plus two named as out of scope. That is a sweep of the `dev/*.R`
metric and probe scripts the provenance audit's exposure ranking pointed at, not
of `dev/` — which holds **234** `.R` files, most of them never opened here. The
catalogue's closing sentence applies unchanged: nothing above says how many
unguarded metrics remain, and by construction that is the one number this file
cannot provide.

Two narrower limits are worth stating plainly:

**Five of the six changes are now run, with committed logs.** Changes 2, 3, 4
and 6 were run under R 4.5.1 / npmatch 0.1.1.9000 —
`dev/COMPARE-BASELINES.log`, `dev/PROMOTION-FLOOR-PROBE.log`,
`dev/AB-IDF-GATE.log`, `dev/THRESHOLD-RECALL.log` — and change 1's effect is
derived from the already-committed `dev/BENCH-MD-REFERENCE.log`.

**What is still unrun, and what that costs:**

* **Change 5** (`adjudicate-03-score.R`, `adjudicate-04-ablation.R`) needs the
  saved adjudication runs. Its claim — that the clamp does not currently bite —
  is arithmetic from the published CI and is stated as such, not as a run.
* **`measure-recovery.R`** from change 4 runs two full matches and is the one
  genuinely expensive script here. Its EIN-churn column is therefore the one
  that remains *unmeasured*, as against the two measured at zero.
* **Change 1's three reference arms** were not re-run (~37 GB, one process per
  arm); the ordering was settled from the committed log instead.

No figure in this note is retyped from another session's run. Where the sibling
session reached a result first, the result is credited and the figure comes from
the log committed here.

**The conclusion that was at risk survived; a different one did not.** Change 1
lowers every arm's clear rate, most for the arm that retrieves least — and the
reference-tier ordering is unchanged, so the default stands. Worth stating as
plainly as the alternative would have been: the metric was redefined so that it
*could* contradict the design, and it did not. A practice that only ever
produces retractions is not being applied honestly. What did not survive is
`PROMOTION-FLOOR-FINDINGS.md`'s 121 and its costless recommendation, found by
change 3 and not predicted by it.

**Both published figures this work identified have since been corrected, by
other hands.** They are recorded here because the point of the exercise was to
find them, not to own them:

* **`PROMOTION-FLOOR-FINDINGS.md` §1 and §5** — regenerated in **#28**, with the
  `main_only` cause named; the run logs behind them cited in **#30**.
* **The 0.1-point reference-arm gap** in `R/pipeline.R`'s roxygen and
  `vignettes/matching-dictionaries.Rmd` — corrected in **#31**, which puts all
  three arms on the 4,868 in-scope base at 61.2 / 62.4 / 62.0 (YES+MAYBE
  82.6 / 84.4 / 81.3), takes unified-over-active from +0.1 to **+0.49** and
  augmented-to-active from +1.0 to **+0.72**, and rebuilds the site. Verified
  against `dev/BENCH-MD-REFERENCE.log` here: 2981, 3040 and 3016 over 4,868 give
  61.24%, 62.45% and 61.96%, and the two gaps follow. #31 also had to fix
  `_pkgdown.yml`, because `pf_result_tiers()` shipped unindexed in #23 and
  pkgdown would not build at all — a side effect of practice 5's accessor that
  nobody predicted.

So the shape-3 defect in change 1 moved three published figures and a shipped
vignette, and every one of them is now on one denominator.

**The audit's forward-looking pattern is not addressed here.** It closes on the
observation that a correction reaches the note where it was found and not the
notes that quote the figure, and that practice 1's remedy — print the figure at
point of use — would fix it. Change 1
takes one step in that direction by attaching the in-scope base to the saved
artifact, so a downstream consumer can re-derive the right denominator instead of
the convenient one. The rest of that work is practice 1's, not practice 7's.

See also `dev/PLAUSIBLE-WRONG-NUMBERS.md` for the catalogue and the eight
practices, `dev/assert-lib.R` for practices 2–4 as code, and `R/report.R`'s
`pf_result_tiers()` for practice 5's seam. The provenance audit this work was
built on is not in the repository — see the note under "Metrics that cannot come
out wrong" above.
