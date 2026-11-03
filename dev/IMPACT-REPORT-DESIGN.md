# A report indexed by modification, not by metric

Design for the report asked for on 2026-11-03: one section per change made to the
workflow, each section saying what that change did to the process.

The existing `dev/PERFORMANCE-REPORT-20261103.md` is indexed by *metric* — tier
distribution, then accuracy, then what is unmeasured. That shape answers "how
good is the pipeline right now", and it keeps its job: it is the document that
says which figures are MEASURED, which populations they belong to, and how the
fixtures and reference points were built. Nothing below replaces it. What it
cannot answer is "what did changing the IDF floor do", because a change's effect
is a difference between two runs and that report describes one.

**Short answer: yes, and most of it is possible from artifacts the pipeline
already writes.** One stage of it is not, and §6 names the single code change
that unlocks it.

A note on the examples below. Every block showing a layout is a *shape*, and its
numbers are invented to show the shape — `< n >` where that is unambiguous, and
plausible-looking digits where a column needs a width. The only figures in this
document that were measured are the ones attributed to a source: the production
run's 91,008 identities, the 686,380 pairs of the unblocked pass, the 159-for-28
defect, and the 0-of-440 unlabelled template rows. The worked case in §5 borrows
its identity and address from COMPARABILITY-PLAN step 3 and invents its scores.

---

## 1. The funnel, which is what a modification acts on

A case can fail in four different places, and every modification acts on one or
two of them. Reporting a single clear rate per section hides which:

```
  surfaced     did blocking put ANY candidate in front of the scorer?
     |
  contained    is the right organisation among the candidates it put there?
     |
  ranked       does the scorer put that one first?
     |
  cleared      is its score above the accept threshold -> YES?
```

This decomposition is the spine of the report, because it separates changes that
are easy to confuse:

- Widening a blocking pass raises **surfaced** and **contained**, and can *lower*
  the share ranked first, because it adds competitors.
- Changing how IDF is computed acts on **ranked** and **cleared** — the candidate
  set is the same, the ordering inside it is not.
- Un-clustering PO boxes removes *cases*, so it changes the denominator of all
  four without any case changing behaviour. §3 is about that.
- Lowering a threshold moves **cleared** alone, and moves it in both directions
  at once — more true clears, more false ones.

A section that reports "YES went from 45.4% to 47.1%" has said almost nothing. A
section that reports that containment was flat and the gain is entirely at
`cleared` has said that the change bought clears without finding anything new,
which is the sentence a reader needs.

### What is measurable at each stage, on what population

| stage | metric | population it can be measured on |
|---|---|---|
| surfaced | `n_cand` per case; share with `n_cand > 0` | every in-scope identity |
| contained | truth EIN present anywhere in the list | only labelled cases |
| ranked | truth EIN at rank 1; in top 3; `margin`; `n_close` | only labelled cases |
| cleared | YES / MAYBE / NO rates; `score` distribution | every in-scope identity |

Two stages are measurable on everything and two are not, so **every section
carries two n's**, not one. For the production run those are 91,008 identities
and, at the moment, 172 labels in PF-TRUTH-V2.

And the labelled subset is not a sample of the corpus: every row of it came from
a cell the pipeline had already produced. Containment measured there is
containment on known-hard cases, which is a useful number and is not a corpus
number. The existing report's §6 says this about recall; it applies with the same
force to everything in the middle two rows above.

There is one quality metric that escapes this, and each section should carry it:
`pf_consistency()`. One organisation is written many ways across grants; grouped
by address, every rendering should get the same EIN whatever that EIN is.
Disagreement inside a group is a defect without any ground truth, so it is
measurable on the full population, in every configuration. It is necessary and
not sufficient — a configuration that answers every rendering identically and
wrongly scores perfectly — so it reads alongside the labelled numbers, never
instead of them.

---

## 2. What a "modification" is, and where the report gets it from

A section heading should not be a claim typed by whoever wrote the report. It
should be derived from the two artifacts being compared, so a section cannot
describe a change the artifacts do not show.

Two layers of modification exist, and they are recorded in different places:

**Run-level** — everything `.pf_run_stamp()` already captures on every
checkpoint and every result: `ref_rows`, `ref_cols`, `normalizer`, `passes`,
`config`, `method`, `recover`, `self_guard`, `dyads`, `dyad_config`. An IDF
change lives in `config` or in a pass's `min_pair_idf`; a new recovery pass
lives in `passes`; a collapse policy lives in `dyad_config`. `.pf_check_stamp()`
already knows how to name what differs between two stamps, down to the component,
using `all.equal()`. A `pf_stamp_diff(before, after)` is that logic returning the
difference instead of throwing it.

**Population-level** — the modifications that change which cases exist at all.
Un-clustering PO boxes is one; so is dropping 25+-name addresses as fiscal
sponsors; so is deduplication. These are not in the run stamp, because they
happen before the run. They are recorded by `pf_population_id()` and
`pf_frame_id()`.

So a section header is generated, and looks like this:

```
## Modification 4 — IDF floor on the distinctive-name promotion

  population   cb3c78ff0f1a9546  ==  cb3c78ff0f1a9546        unchanged
  frame_id     89a2a597ed0ea128  ==  89a2a597ed0ea128        unchanged
  normalizer   v1-5e901add4a04a5d6  ==  v1-5e901add4a04a5d6   unchanged
  ref_rows     3,880,431  ==  3,880,431                      unchanged
  passes       identical (11 passes, lean + recovery)
  config       distinct_name_min_idf   absent -> 6.5          CHANGED
  dyad_config  identical

  one setting moved; population and reference are the same objects
```

That block is the section's warrant. When it shows two things moved, the section
says so and attributes nothing to either. When it shows the population moved,
§3 applies.

---

## 3. The accounting rule, without which every section lies

Two runs rarely cover the same cases. The modification may have changed the
population on purpose (PO-box un-clustering), or the runs may be of different
vintages, or a batch may have failed. A naive before/after table charges all of
that to the modification. The existing report documents a 17-point spread across
three tier sets "for reasons that have nothing to do with pipeline quality"; this
is the mechanism.

So every section reports **three populations, separately**:

```
  cases in both runs        < n >    <- the flow matrix is computed on THESE
  only in before            < n >    <- left the population; not an outcome change
  only in after             < n >    <- entered the population
```

and the flow matrix covers the intersection only:

```
                     after
  before      YES   MAYBE    NO     OOS  |  total
  YES      < n >   < n >   < n >   < n >  | < n >
  MAYBE    < n >   < n >   < n >   < n >  | < n >
  NO       < n >   < n >   < n >   < n >  | < n >
  OOS      < n >   < n >   < n >   < n >  | < n >
```

Three further rules, each closing a failure that has actually happened here:

1. **One convention on both sides.** `pf_status()` labels an identity with no
   candidate anywhere `NO`; the result frame omits it. Reading one side from each
   once reported 159 identities moved where 28 had. Both sides come through
   `pf_status()` or both through `pf_result_tiers()`, and the section says which.
2. **Join on a content-derived id or refuse.** Identity ids have been
   content-derived (`PFI-<16 hex>`) since 2026-11-03. Before that they were
   positional, so an id join across that boundary returns a base rate that looks
   like a result. A comparison whose two frames disagree on id shape must error
   with both shapes printed, per COMPARABILITY-PLAN step 4 — not fall back to a
   name join silently. Falling back on purpose, and labelling the section
   approximate, is allowed; falling back quietly is the defect.
3. **Net change is not the headline.** `MAYBE -> YES` of 900 against
   `YES -> MAYBE` of 850 is a net of 50 and a churn of 1,750. The churn is the
   interesting number and the net is the one that gets quoted, so both are
   printed and the net never appears alone.
4. **A tier that did not move is not an answer that did not change.** A case
   that stays `YES` and picks a different EIN is absent from every cell of the
   flow matrix and has changed its answer completely. These are counted on their
   own line, and they are the reason a section cannot call a modification inert
   from a flow matrix alone.

---

## 4. The metric block, per section

Computed on the intersection, for before and after, with the delta:

```
  SURFACED                         before     after    delta
    cases with >=1 candidate       < n >     < n >    < +n >
    mean candidates per case       < n >     < n >    < +n >
    median / p90                   < n >     < n >
    cases with >100 candidates     < n >     < n >     <- blocking too wide

  CONTAINED  (n = 172 labelled)
    truth EIN anywhere in list     < n >     < n >
    truth EIN in top 3             < n >     < n >
    truth EIN at rank 1            < n >     < n >
    contained but not rank 1       < n >     < n >     <- scorer's failures
    not contained at all           < n >     < n >     <- blocker's failures

  CLEARED  (n = every in-scope identity in the intersection)
    YES / MAYBE / NO / OOS         ...       ...
    first-stage clears (A1-A5)     < n >     < n >
    recovery clears (D1, D2)       < n >     < n >
    mean margin on YES             < n >     < n >
    mean n_close on MAYBE          < n >     < n >

  CONSISTENCY  (ground-truth-free, full population)
    groups with disagreement       < n >     < n >
```

`contained but not rank 1` against `not contained at all` is the line that says
whether to work on the blocker or the scorer next, and neither of the two
existing reports can produce it.

### Which variables changed

The user's question — did one address field move, or the DBA name? — is a
cell-level diff of the derived keys the cascade actually blocks and scores on,
not of the raw filing:

```
  column            cases differing    example
  name_key                       0
  dba_key                      418     "ST JUDE CHILDRENS RESEARCH HOSP ALSAC"
  street_unit_id             1,204     "STE 200" -> "200"
  name_acro                      0
  zip5                           0
```

This separates "the modification changed a key, which changed matching" from
"the modification changed matching with identical keys". The two call for
completely different follow-up, and a tier flow matrix alone cannot tell them
apart.

---

## 5. The case blocks, which is where the report becomes readable

Per section, four lists, each capped (20 shown, full set written to CSV beside
the report), **sampled deterministically** with a seed printed in the section so
two readers see the same cases:

- **Promotions** — MAYBE -> YES, and NO -> YES
- **Demotions** — YES -> MAYBE, and YES -> NO
- **Left NO** — NO -> anything
- **Arrived at NO** — anything -> NO

Each case prints once, with the before and after candidate lists side by side.
`pf_candidate_frame()` already produces exactly these fields, which is why this
part of the design is cheap: `grant_id`, `rank`, `is_top_pick`, `score`,
`name_sim`, `geo_zip5`, `geo_state`, `geo_city`, `geo_stnum`, `pass`,
`veto_soft`, `veto_soft_reason`, plus the filed recipient and the candidate's BMF
name and address.

```
  PFI-0d7dba2aa34fdadd   MAYBE -> YES          +0.031 score, margin 0.004 -> 0.058
  filed: CANOE CREEK K8 PTA | ST CLOUD, MO | 34769

                                                     before            after
  rank 1  86-3264768  CANOE CREEK K-8 PTA            0.949  B2      *  0.980  B2
  rank 2  59-1234567  CANOE CREEK ELEMENTARY PTA     0.945  B2         0.922  B2
  rank 3  —                                                            —
                                                     n_close 2         n_close 1

  why: distinct_name_min_idf withdrew the promotion from rank 2, whose
       distinctive token "ELEMENTARY" is below the floor. The candidate set did
       not change; the tie band collapsed from 2 to 1 and the margin cleared.
```

The `why:` line is the one part that cannot be generated, and it should be
written by hand for the 20 shown cases and left blank in the CSV. A generated
guess there would be the most dangerous text in the document — it reads like a
finding and is a heuristic. Where the mechanism is not understood, the honest
line is `why: not determined`.

Cases are chosen to be *diagnostic*, not representative, and the section says
which it is doing. Three selection rules, all deterministic:

1. the largest score movements in each direction
2. cases that crossed a threshold by less than 0.005 — the ones a re-run could
   flip back
3. cases whose `match_pass` changed, which is a different mechanism from a score
   change inside one pass

---

## 6. What this needs that does not exist

Three of the four funnel stages are computable from artifacts the pipeline writes
today. `pf_status()` carries, per case: `status`, `ein`, `bmf_name`, `score`,
`name_sim`, `margin`, `n_close`, `match_pass`, and the geographic agreement
flags. That covers **cleared** completely, and **ranked** partially through
`margin` and `n_close`.

**Surfaced and contained are not computable from any saved run.** The batch loop
discards the scored pairs at the end of every batch — `R/batch.R` says so
twice — because `pf_status()` keeps only the winning candidate. The full pair set
is genuinely too large to keep: one unblocked pass produced 686,380 pairs, and a
token-blocked query can return thousands of equal-scoring candidates for one
grant. So `n_cand` is unrecoverable, and the rank of the truth EIN is
unrecoverable, for every run already on disk. `pf_evaluate()` inherits this: it
compares the *chosen* EIN against `correct_ein`, so a case where the right
organisation was in the list and placed second is invisible to it — it looks
identical to a case where the right organisation was never surfaced at all.

**The change:** in the batch loop, at the point where the pairs still exist —
after the dyad collapse, immediately before `pf_status()` — write a second
checkpoint holding, per identity, the top *k* candidates (k = 5) by score, with
the `pf_candidate_frame()` signal columns and the derived query keys. Truncation
is what makes this affordable: 5 rows per identity instead of an unbounded
number. For the production run that is ~455,000 rows of about twenty columns
beside a 91,008-row status frame, and it must carry the same `pf_stamp`, so a
candidate slice can never be read against a status frame from different settings.

Keep the **total** candidate count as a scalar column on the status frame
(`n_cand`) rather than inferring it from a truncated slice, since the slice
cannot distinguish 5 candidates from 5,000 — which is exactly the blocking-too-
wide signal §4 wants.

This changes no result. It writes down something the run already computed and
currently throws away.

---

## 7. What the existing report keeps

`PERFORMANCE-REPORT-20261103.md` stays, with its scope narrowed to what it is
good at and its title saying so:

- the three statuses and why they cannot be mixed (§1)
- scope accounting (§2)
- how each fixture and reference point was built, and its population, grain,
  Wilson interval and MEASURED / PROJECTED / UNMEASURED tag (§3-5)
- the UNMEASURED register and its T-numbers (§6)
- the labelling round's state (§7)
- the defects bounding every figure (§8)
- provenance (§10)

Those are statements about *one* state of the world, and the impact report
depends on them: a section comparing two runs has to cite which population each
run covers, and that is what the performance report is for. The impact report
replaces none of it. It replaces §9, "What this report should become".

---

## 8. Build order

Each step is usable before the next exists.

1. **`pf_stamp_diff(a, b)`** — BUILT, `R/compare.R`. `.pf_check_stamp()`'s
   comparison logic returning the difference rather than throwing it. Generates
   the §2 header block from any stamped artifact on disk today. It decomposes a
   changed setting rather than reporting that it changed: a pass table diffs by
   pass name and then by argument (`B2-token / min_pair_idf: 4 -> 6.5`), a
   config by component (`distinct_name_min_idf: absent -> 6.5`), a column set by
   what was added and removed. When more than one setting moved it says so and
   says that no effect can be attributed to either from those two runs.
2. **`pf_compare_runs(before, after)`** — BUILT, `R/compare.R`. The §3
   population accounting, flow matrix, net-and-churn table and per-case moved
   frame, plus the three refusals.

   The design above said this depended on COMPARABILITY-PLAN step 3's
   standardized frame. It turned out not to: step 3 exists so that *sampling*
   draws from a validated frame, while a comparison needs only a content-derived
   join key and one convention on both sides — and both of those are checked
   here, on raw `pf_status()` frames, which is what is actually on disk. Putting
   the guard inside the comparison is also stricter than putting it upstream,
   because it cannot be bypassed by handing the function an unstandardized
   frame. Step 3 is still worth building, for sampling.
3. **Candidate retention** (§6) — the batch-loop change plus `n_cand`. Unlocks
   `surfaced`, and `contained` on labelled cases.
4. **`pf_candidate_diff(before, after, ids)`** — the §5 side-by-side blocks.
   `pf_candidate_frame()` already renders one side; this pairs two and computes
   the movement summary line.
5. **`pf_impact_report(pairs, mods)`** — assembly. Takes a list of
   (before, after, label) and emits the document.

Steps 1, 2 and 4 are reporting over existing data and cannot change a result.
Step 3 touches the batch loop, so it is the one that needs the full test suite
and a stamp-compatibility decision: a status frame gaining an `n_cand` column
changes `ref_cols`-adjacent expectations and will refuse to resume older
checkpoint directories. That refusal is correct and should be stated in the
commit, not worked around.

The first modification to document, once step 2 exists, is the one with two runs
already on disk: BASELINE-2026-10C reproducing exactly on 2026-11-02 with not one
identity moved. A section whose every delta is zero is the right first test of
the machinery, because any non-zero number in it is a bug in the report.

---

## 9. One thing this design cannot fix

Precision on the YES mass is still unmeasured, and a modification-indexed report
makes that gap *easier to overlook*, not harder: a section showing
`MAYBE -> YES` of 900 looks like 900 cases improved. Whether they are correct is
not in any artifact. Every section's `cleared` block therefore carries the
labelled-subset caveat inline, and the report's front matter states that no
section demonstrates a quality improvement until stage 1 of the labelling round
carries verdicts — 0 of 440 template rows do, counted on disk on 2026-11-03.

A modification that moves cases into YES and a modification that improves the
pipeline are the same table and not the same claim.
