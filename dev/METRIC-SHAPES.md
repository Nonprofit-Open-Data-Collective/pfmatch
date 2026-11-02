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

`dev/FIGURE-PROVENANCE.md` was the input. Its Part 1 ranking (which figures sit
behind a recommendation *and* would flatter if wrong) is the same ranking this
work needed, and its Part 3 denominator ledger named three of the four changes
below before they were looked for.

**Nothing was run.** `Rscript` is not on this machine, so no figure in this file
is recomputed and none is claimed to be. Every change is the metric *definition*
in the script that computes it; the commands to re-derive the figures are given
per change. The only verification performed was a paren/brace/quote balance check
over the edited files — which is not an R parse, let alone a run.

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
metric's definition excluded it. The script's own header says `active-observed`
"won outright" on this benchmark and is the default since.

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
rate falls. The precedent is exact: on `BASELINE-2026-10C` the same two bases are
4,748 and 4,868, and the same YES count reads 62.74% or 61.20% depending on
which is used. The gap is not uniform across arms — it is larger for the arm
that retrieves less — so **the ordering of the three arms can change, and the
"won outright" verdict is not re-established here.** It was reached on the
result-frame reading.

*To re-derive:* one arm per process (the augmented bundle alone peaks near 37 GB).

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

**Now:** the delta is decomposed, and the decomposition is an identity rather
than an approximation:

```
clear2 − clear1  =  ΔYES / n2                      ← the matching term
                 +  YES1 · (n1 − n2) / (n1 · n2)   ← the denominator term
```

Both terms print, `stopifnot()` checks that they sum to the headline (practice 6
— a guard that only the guarded code tests is not a guard), and the script says
so out loud when the denominator term is the larger of the two, or when the
headline rose while the matching term went *negative*. That last case is the one
the single difference could not produce and the decomposition can.

**No published figure moves.** The headline delta is unchanged; two terms are
printed under it. The limit is stated in the output: these are saved benchmark
frames and the in-scope count is not in them, so both `clear` columns remain
result-frame shares. The decomposition separates the population move from the
matching move; it cannot recover the retrieval failures neither base counts.

*To re-derive:* `Rscript dev/compare-baselines.R` (reads two committed `.rds`
files; cheap).

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

**No published figure moves;** this note publishes none of this script's figures,
and `dev/PURPOSE-MATCH-FINDINGS.md` was not reached by the provenance audit.

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

**Nothing was run, so no change is verified to execute.** The changes are
syntactically balanced and the identities in them are checked by `stopifnot()`
at run time, which is not the same as having run. `compare-baselines`,
`ab-idf-gate` and `probe-promotion-floor` are cheap and read committed `.rds`
files; `bench-md-reference` needs ~37 GB and one process per arm;
`measure-recovery` runs two full matches; `probe-threshold-recall` reads two
committed test sets. Run the cheap ones first.

**One change can move a conclusion and is not re-established.** Change 1 lowers
every arm's clear rate, by an amount that is larger for the arm that retrieves
less, and `active-observed` became the default by winning on the old reading.
Re-running all three arms is the only way to know whether it still wins. That
possibility is the practice working as intended — but it is an open question
this file leaves open, not a result.

**The audit's forward-looking pattern is not addressed here.**
`dev/FIGURE-PROVENANCE.md` closes on the observation that a correction reaches
the note where it was found and not the notes that quote the figure, and that
practice 1's remedy — print the figure at point of use — would fix it. Change 1
takes one step in that direction by attaching the in-scope base to the saved
artifact, so a downstream consumer can re-derive the right denominator instead of
the convenient one. The rest of that work is practice 1's, not practice 7's.

See also `dev/PLAUSIBLE-WRONG-NUMBERS.md` for the catalogue and the eight
practices, `dev/FIGURE-PROVENANCE.md` for where the published figures come from,
`dev/assert-lib.R` for practices 2–4 as code, and `R/report.R`'s
`pf_result_tiers()` for practice 5's seam.
