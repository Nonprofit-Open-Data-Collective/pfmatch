# Promoting three modules from pfmatch to npmatch

`dev/PACKAGE-PLAN.md` §2 identified three modules that are generic linkage
machinery sitting in pfmatch only because that is where they were first needed,
plus one defect in npmatch that this project surfaced. This is how to move them
without breaking either package.

**Do none of this until pfmatch packaging is finished and the `PF_SET=1k`
benchmark is confirmed byte-identical.** Moving code and drawing a package
boundary at the same time makes any regression untraceable.

---

## The rule being applied

Generic machinery — anything whose correctness does not depend on the query file
being 990-PF Part XIV — belongs in `npmatch`. Everything else stays here. The
test for "generic" is concrete: *would this be equally correct applied to SAM or
USASpending?* If yes, it belongs upstream, no matter which project paid to write
it.

---

## What moves, in order

Ordered by risk, lowest first. Each is a separate change with its own
verification. Do not batch them.

### 1. `pf_initials()` / `pf_add_recovery_keys()` → `np_initials()` / `np_recovery_keys()`

**Risk: low.** Pure functions over a normalized name column, no state, no
dependency on any pfmatch concept.

Acronym indexing and prefix keys are reference-side blocking devices. The
35-character `SIGOCPYRPNAM` truncation that *motivated* the prefix key is
990-PF-specific; the mechanism is not, and truncated names appear in every
administrative file. `pf_recovery_passes()` — the pass *specification* — is a
judgment call about this dataset and **stays in pfmatch**.

| moves | stays |
|---|---|
| `pf_initials()` | `pf_recovery_passes()` |
| `pf_add_recovery_keys()` | `pf_recover_name_from_street()` (990-PF field-swap repair) |

Verification: `np_initials()` output identical for the 1.92M BMF `name_key`
column before and after; `PF_SET=1k` unchanged.

### 2. `dedup.R` → `np_dedup()` / `np_identities()` / `np_propagate()`

**Risk: medium.** Larger surface, and the fuzzy path uses npmatch's veto
predicates already — which is itself evidence it belongs upstream.

Collapsing a query file to distinct identities and propagating a match across a
cluster applies to any repeated-query linkage problem. SAM and USASpending have
the same repetition and would get the same ~1.8× collapse.

What has to be generalized on the way: `pf_dedup()` currently keys on
`(name_key, street_key, zip5)` by name, and `pf_recipients()` picks the "most
complete" representative using 990-PF column names. Both need a column-mapping
argument rather than hard-coded names — npmatch already has `np_map_*()` for
exactly this, so follow that pattern.

Keep in pfmatch: nothing. The whole module moves, and pfmatch re-exports thin
wrappers if the current names are worth preserving for callers.

Verification: identity counts and collapse ratio identical on the 100k sample
(`dev/measure-dedup.R`); the over-merge guard still rejects the same
number/ordinal/direction cases; `PF_SET=1k` unchanged.

### 3. `batch.R` → `np_run_batches()`

**Risk: medium-high**, not because the code is hard but because it is the piece
a long run depends on, and a checkpoint-format change can strand an
in-progress run.

Checkpointed batching over a large query file is infrastructure with nothing
990-PF about it. But `pf_run_batches()` currently hard-codes the pfmatch stage
sequence — self-match guard, recovery passes — as `recover =` and `self_guard =`
flags. Upstream it must take a **list of post-processing hooks** instead, and
pfmatch supplies `pf_drop_self_matches()` as one of them. That inversion is the
actual work; the batching loop itself is a straight move.

Do this one last, and only when no long run is in flight. Bump the checkpoint
directory name so old and new checkpoints cannot be mixed.

Verification: a 25k-identity run resumed from checkpoints written by the old
code must produce identical output, or the checkpoint format must be
deliberately versioned and the old ones discarded.

---

## The npmatch defect this project found

Separate from the promotions, and worth more than all three.

`np_config()$tiebreak` accepts only the string `"name"`, and
`.np_overall_summary()` uses it to pick, among candidates within `tie_band` of
the top score, the one whose *full* name best matches the query. The intent is to
prefer an organization over its `FOUNDATION` / `ASSOCIATION` variant.

**On 990-PF data that assumption is a coin flip.** Of 61 contested adjudicated
grants, 36 have both a foundation arm and a plain entity among the candidates,
and the arm is the correct answer **52.8%** of the time — filers write the short
name for both. Measured as a tiebreak key it is net 0 at `tie_high = 0.95`, −1 at
0.90, and −2 with the gate removed (`dev/PURPOSE-MATCH-FINDINGS.md` §10).

The fix is not to change the default. It is to let `tiebreak` accept a
**function**:

```r
np_config(tiebreak = function(df, close) close[which.max(df$my_key[close])])
```

`.np_overall_summary()` then dispatches on `is.function(tiebreak)`, keeping
`"name"` as the default string for backward compatibility. That is a
~5-line, fully backward-compatible change, and it lets `pf_purpose_tiebreak()`
stop rewriting the result object after the fact — which is currently the ugliest
thing in pfmatch.

**Before changing the default for anyone**, check whether the name tiebreak is
also net-negative on SAM/USASpending. If it is, that is a real accuracy bug in
shared infrastructure and worth more than anything in this document. If it is
positive there, leave the default alone and let callers override.

---

## What must not move

* `recipient-type.R` — column (c) of Part XIV has no controlled vocabulary and
  the rule cascade encodes ~1,400 observed spellings of eight 990-PF concepts.
* `prepare.R` — the `PNAM` / `BNBN1` / `BNBN2` name-field logic is a 990-PF
  schema quirk, as is the line-2 four-way disambiguation.
* `selfmatch.R` — "a grant is a payment *from* the filer" is only true here.
  (The *mechanism*, excluding a forbidden EIN per query, is generic; if it is
  ever wanted upstream, promote the mechanism and keep the 990-PF policy here.)
* `purpose.R` / `text.R` — `SIGOCPYPOGOC` is a 990-PF field, and the Part III
  text join is specific to this problem's adjudication step.
* `report.R` — the YES / MAYBE / NO / OOS framing is shared with npmatch's
  tiering, but the *out-of-sample* concept (natural persons, governments,
  foreign orgs) is a 990-PF scope decision.

---

## Sequencing

1. Finish pfmatch packaging. Confirm `PF_SET=1k` byte-identical.
2. Promotion 1 (`initials` / recovery keys). Re-run both benchmarks.
3. Promotion 2 (`dedup`). Re-run both benchmarks.
4. The `tiebreak`-as-function change in npmatch — independent of 1-3, and can be
   done at any point. Rewrite `pf_purpose_tiebreak()` to use it.
5. Promotion 3 (`batch`), when no long run is in flight.

Each step re-runs **npmatch's own eval as well as** `PF_SET=1k`. A promotion that
improves pfmatch and regresses npmatch's SAM numbers has not succeeded; the whole
point of moving the code upstream is that it has to be right for both.
