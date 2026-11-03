# Making two frames comparable before anything compares them

**Plan, 2026-11-03.** Written because three separate failures in the last two
days turned out to be one failure, and because the fix the instinct reaches for
("add the three columns back") is half right for a reason worth writing down.

Everything below was read off this machine today. No value here is quoted from
an earlier note; `dev/NPNORMALIZE.md` is an example of what happens when they
are (see §6).

---

## 1. The one failure, in three costumes

Each of these cost real time this week. They are the same defect.

**(a) A joined id that named a different organisation.** Two runs of the same
grant population were joined on `grant_id`. The ids were positions in each
run's own dedup output, so `R10000` was *Childrens Guardian* in one and
*CONGREGATION ATERES YESHAYA* in the other. The join succeeded, returned
plausible numbers, and every number was a base rate. Fixed at source:
`grant_id` is now `pf_identity_id()`, a hash of the identity's own dedup key
(`PFI-0d7dba2aa34fdadd`), and `pf_read_truth()` refuses a file whose ids match
`^R[0-9]+$`.

**(b) A run that cannot be asked what built it.** Measured today:

```
data-dev/TRI-V2-MATCH-20261025-prestack.rds   -> NO run stamp
data-dev/TRI-V2-MATCH.rds                    -> normalizer v1-5e901add4a04a5d6
                                                ref_rows 3,880,431  ref_cols 41
```

The October run records nothing — not its normalizer, not its reference, not
its config. So no difference between the two runs can be attributed to
anything. This one is not retroactively fixable; it is the argument for the
rest of the plan.

**(c) A reference bundle that silently changed shape.** `dev/REF-REBUILD.log`
(Oct 26) verified `recovery keys name_acro, name_pre present`.
`dev/REF-REBUILD-20261103.log` verifies rows, stamp, `name_freq` and
`token_idf` — and does not mention them, because they are not there. The Nov-3
run paid for it in the open:

```
  built stage-4 reference keys once (197.5 s)
```

That line is absent from the Oct-25 log, and the line has existed in
`R/batch.R` since the first commit, so its absence is evidence: the Oct bundle
had the keys and the current one does not.

**Why.** `pf_reference()` adds them before it saves
([R/pipeline.R:190-196](../R/pipeline.R)):

```r
ref <- pf_build_reference(bmf, active_col = active_col)
if (recovery) ref$reference <- pf_add_recovery_keys(ref$reference)
...
saveRDS(ref, cache, compress = FALSE)
```

The Nov-2 rebuild did not go through that path. Its own log says what it held
in memory — `reference, name_freq, token_idf, ref_index, normalizer, timing` —
which is `pf_build_reference()`'s return value, not `pf_reference()`'s. An
ad-hoc script called the builder and `saveRDS()` directly, skipping one line.
**That script is not in the repo**, so the current reference is also not
reproducible.

---

## 2. On "we should add those three columns back"

Right, and worth doing — but not as a correctness fix, and the distinction
decides where the check goes.

The three are `name_acro`, `name_pre`, `name_is_acro`, and they are a *pure
function of `name_key`* ([R/recover.R:101-115](../R/recover.R)). Nothing is
lost by rebuilding them, which is why `pf_run_batches()` quietly does, and why
the run stamp is computed **after** they are added, deliberately:

> Built AFTER the recovery keys, so a reference that arrives with them and one
> that gains them here stamp the same: the two produce identical results and a
> stamp that separated them would refuse a legitimate resume.

So the 197.5 seconds is the whole direct cost, and `ref_cols 41` in the Nov-3
stamp is 38-on-disk plus the 3 added in flight. **A correction to what I told
you earlier:** I described that as "the Oct-25 reference carried 41 columns
against the current 38". It is one reference counted at two moments of the same
Nov-3 run. The between-run reference difference is real (§1c) but 41-vs-38 was
never the evidence for it.

What the missing columns actually cost is the thing worth fixing: **the saved
bundle stopped being a complete input and nothing noticed.** Any caller that
reads `REF-augmented.rds` and does not go through `pf_run_batches()` or
`pf_match_grants()` now runs `D1-acronym` and `D2-prefix` against columns that
do not exist. So: put them back (§4 step 2) *and* add the check that would have
caught their absence (§4 step 1). The check is the durable half.

---

## 3. The normalizer did move between the two runs — correcting the C2 log

`dev/C2-DBA-ANY-20261103.log` §1 says "Nothing here is attributable to the
normalizer." That is wrong, and `dev/REF-REBUILD.log` already said so in
writing before I wrote it:

> BASELINE-2026-10B and the triangulation run (population cb3c78ff0f1a9546,
> dev/TRI-V2-BUILD.log) were matched against the old bundle. [...] a rerun will
> not reproduce them and should not be expected to.

`np_signature_history()`, read today, dates the move:

| signature | release | what moved |
|---|---|---|
| `v1-6dcb298522cc5118` | npmatch 0.1.0.9000 | pre-split; the bundle the **Oct-25 run** matched against (built 2026-08-21) |
| `v1-3e7b9f9d59bbb19e` | npnormalize 0.1.0 | the Oct-26 rebuild |
| `v1-6d90b52d8b781673` | 0.1.2 | BUILDING became a unit designator |
| `v1-592912060053c4c3` | 0.1.3 | most specific unit kept; house number a whole token |
| `v1-1179714ce1e9d31f` | 0.1.4 | `street_has_box`, box gate anchored |
| `v1-533f186c123357cf` | 0.1.5 | a lettered box is a box |
| `v1-d49b18cc81ab79fb` | 0.1.6 | long-tail box spellings, `is_mail_only`, `mail_key` |
| `v1-59c6e84c5f38e9f5` | 0.1.7 | hyphenated house number; eleven FOUNDATION spellings fold |
| `v1-5e901add4a04a5d6` | 0.1.8 | lone compass letter; **0.1.9 reports it too** |

Eight signatures between the two runs. And the direct evidence, from the two
build logs, on an **identical** input:

```
extracted 596,539 grant rows for 36,366 keys     (both runs)
population id: cb3c78ff0f1a9546                  (both runs)
identities to match:  91,690   (Oct-25)
identities to match:  91,008   (Nov-3)
```

682 identities fewer, 0.74%. The dedup key is built from `name_key` and
`street_key`, so only the normalizer can do that.

**This hands §4 of the C2 log a testable hypothesis it did not have.** The
promotion needs `name_freq <= 3` — the normalized primary name must be rare in
the reference. Folding spellings together makes names *less* rare, and the
distinct-name count has fallen at every rebuild:

```
2,797,423  (Aug-21 bundle, the one Oct-25 used)
2,797,111  (Oct-26 rebuild)
2,796,717  (Nov-2 rebuild, current)
```

0.1.7 folding eleven spellings of FOUNDATION is exactly the shape of change
that pushes a name from `name_freq = 3` to `name_freq = 4` and withdraws the
promotion. Untested — but it is a mechanism, and `distinct_name_main_only` and
the `name_ver` columns (both dating from 2026-08-20) were not.

---

## 4. The plan

Each step ends in a check, and no step depends on a rerun of the match.

### Step 1 — a schema contract, checked before the frames meet

`pf_check_reference()` already guards the normalizer signature
([R/match.R:234](../R/match.R)) and stops on a mismatch. It does not look at
columns. Add `pf_check_schema(x, passes)`, in `pf_validate_grants()`'s existing
idiom (one row per check, `PASS`/`WARN`/`FAIL`/`INFO`), which reads the column
names out of the pass specs themselves rather than a hand-kept list:

```r
> pf_check_schema(readRDS("data-dev/REF-augmented.rds"),
+                 passes = c(pf_staged_passes("lean"),
+                            pf_recovery_passes(state = TRUE)))

  check                        status  detail
  rows                         INFO    3,880,431
  normalizer stamp             PASS    v1-5e901add4a04a5d6 (npnormalize 0.1.8)
  A1-A5 key columns            PASS    name_key, dba_key, street_key, zip5, state
  B1-B2 token column           PASS    name_key
  D1-acronym  needs name_acro  FAIL    absent -- pf_add_recovery_keys() not applied
  D2-prefix   needs name_pre   FAIL    absent -- pf_add_recovery_keys() not applied
```

Two FAILs on today's bundle. That is the 197.5-second line, stated before the
run instead of during it. Wire it into `pf_run_batches()` beside
`pf_check_reference()`, at `warn` for a derived column (the run can repair it)
and `stop` for a source column (it cannot).

### Step 2 — put the three columns back, through the package, with the script in the repo

Not a 24-minute rebuild: the columns are a function of `name_key`, so the
existing bundle can be completed in place.

```r
ref <- readRDS("data-dev/REF-augmented.rds")        # ~4 min, 2.66 GB
ref$reference <- pf_add_recovery_keys(ref$reference) # ~200 s
stopifnot(!is.null(ref$reference$name_acro))
saveRDS(ref, "data-dev/REF-augmented.rds", compress = FALSE)
# then re-read from disk and run Step 1's check against it
```

Two conditions on this, both learned from §1c:

* the script lives in `dev/`, committed, not in a scratchpad; and
* it verifies by **re-reading from disk**, which is what the Nov-3 rebuild log
  already does for the stamp (`VERIFY (re-read from disk -- the check that
  failed last time)`) and did not do for the columns.

### Step 3 — one standardized comparison frame, built before any sampling

This is your suggestion, and it is the right shape. Today every draw script
does its own joins against a 700 MB artifact, which is where (a) happened. Make
one narrow frame the only thing that is ever compared or sampled:

```r
pf_eval_frame(x)   # from a run artifact
#
# identity_id   PFI-0d7dba2aa34fdadd   the content hash -- the only join key
# recip_name    CANOE CREEK K8 PTA
# recip_city    ST CLOUD
# recip_state   MO
# ein           86-3264768
# tier          NO
# score         0.980
# match_pass    C2-dba-any
#
# attr(,"pf_frame")
#   population  cb3c78ff0f1a9546     the grant file
#   frame_id    89a2a597ed0ea128     this run's id -> name pairing
#   normalizer  v1-5e901add4a04a5d6 (npnormalize 0.1.8)
#   ref_rows    3,880,431
#   built       2026-11-03 02:14:08
```

Nothing in it is optional, and the three fingerprints already exist —
`pf_population_id()`, `pf_frame_id()`, `pf_identity_id()`. What is new is that
they travel together on one narrow frame, so a comparison has one thing to
check instead of four.

### Step 4 — a comparison that refuses rather than returns a base rate

```r
pf_compare_frames(oct, nov)
# Error: these frames are not comparable.
#   population  cb3c78ff0f1a9546  ==  cb3c78ff0f1a9546   OK
#   normalizer  (not recorded)    vs  v1-5e901add4a04a5d6
#   frame_id    (not recorded)    vs  89a2a597ed0ea128
#   id shape    ^R[0-9]+$         vs  ^PFI-[0-9a-f]{16}$
#   91,690 vs 91,008 identities; 0 of 91,008 ids present in both.
#
#   The left frame predates run stamping and is keyed by position, so an
#   id join would return base rates. To compare these two runs, join on
#   normalized name + city + state and call the result approximate.
```

Note the last line: the honest fallback, which is what finally produced the
real §5 numbers in the C2 log (85,350 in common, tier unchanged on 97.5%). A
refusal that offers no route gets worked around.

The rule: **matching population is not sufficient.** `pf_evaluate()` currently
enforces population only, and its error message still says "grant_id is
positional", which stopped being true today. It needs the frame check and the
message needs updating.

### Step 5 — sample from the validated frame, never from the artifact

`pf_truth_shards()` and `pf_round_sample()` take a `pf_eval_frame` only, and
`pf_write_shards()` carries `population`, `frame_id` and `normalizer` into the
shard header — two of the three already do. Then a labelled shard can always be
re-attached, and a draw made from an unstamped or mis-keyed frame is impossible
rather than merely discouraged.

### Step 6 — one function that reports the stack, replacing every hand-written table

```r
pf_stack()
#  package      installed   floor      source of floor
#  npnormalize  0.1.9       >= 0.1.9   npmatch DESCRIPTION      OK
#  npmatch      0.1.1.9000  >= 0.1.1   pfmatch DESCRIPTION      OK
#  matchdb      0.1.1.9000  >= 0.1.1   -                        OK
#  pfmatch      0.1.0       -          -
#
#  normalizer   v1-5e901add4a04a5d6 (npnormalize 0.1.8)
#  np_signature_stamp()  ABSENT from the installed npmatch -- PR #35 unmerged
#
#  artifacts whose stamp disagrees with the installed normalizer:
#    REF-active.rds                  (unstamped)
#    REF-augmented-collapsed.rds     (unstamped)
#    PF-VARIANTS                     v1-6dcb298522cc5118
```

A `>=` floor cannot detect drift; only the signature can. This prints both and
makes the staleness of a quoted table impossible to miss.

---

## 5. Keeping npnormalize and npmatch in step — read today

**npnormalize** — `main`, clean, nothing unpushed, **no open PRs**, version
**0.1.9**, installed 0.1.9. In step. 0.1.9 changed no rule, so it reports
0.1.8's signature.

**matchdb** — `main`, clean, no open PRs, 0.1.1.9000 installed. Pins
`npnormalize (>= 0.1.8)`, `npmatch (>= 0.1.1)`. In step.

**npmatch** — this is where the work is.

* HEAD is `feat/signature-history-provenance`, two commits ahead of `main`,
  pushed, **open as PR #35**.
* **The installed npmatch does not have it.** `np_signature_stamp` is not in
  `getNamespaceExports("npmatch")`; the install is dated 2026-11-03 03:20 UTC
  and predates the branch.
* `main`'s DESCRIPTION pins `npnormalize (>= 0.1.8)`; the branch bumps it to
  `>= 0.1.9`. So **merging #35 also corrects the pin**, which is otherwise a
  release behind what is installed.
* **PR #36** adds GitHub Actions CI (`R CMD check` + a pkgdown build check),
  also open. Nothing upstream has CI today, which is why a pin can go stale
  without a failing build.

What #35 gives pfmatch is precisely the thing §1b lacked — a signature that
names its release instead of being an opaque hash:

```
v1-5e901add4a04a5d6
# normalizer: v1-5e901add4a04a5d6 (npnormalize 0.1.8)
# installed:  npnormalize 0.1.9
# stamped:    2026-11-03 04:00:00
```

**Order:** merge #36 first (so #35 merges against a branch with a check on it),
then #35; reinstall npmatch; confirm `np_normalize_signature()` is still
`v1-5e901add4a04a5d6` — it must be, since no rule moved, and if it moves that
is the finding. Then adopt `.np_sig_label()`'s "hash (package version)" form in
`pf_check_reference()`'s messages and in Step 6.

The doctrine `dev/PLACES-SYNC.md` already states, and the reason it exists:

> **Do not quote a normalizer signature. Read it.** [...] a published signature
> that never existed is worse than no signature at all, because that is exactly
> the value downstream callers stamp cached artifacts with.

---

## 6. Two documents that now carry wrong numbers

Fix these in the same pass, because both are read before the code is.

* **`dev/C2-DBA-ANY-20261103.log` §1** — replace "Nothing here is attributable
  to the normalizer" with §3 above, and strike the 41-vs-38 claim per §2. §§2-3
  of that log (what C2 matches: 457 of 458 at 0.600, `name_key` <= 4 chars on
  46.3%) are measured on the current frame alone and stand.
* **`dev/NPNORMALIZE.md`** — its "read off this machine today" table says
  npnormalize **0.1.6**, signature `v1-d49b18cc81ab79fb`, matchdb **not
  installed**. All three are wrong now (0.1.9, `v1-5e901add4a04a5d6`,
  0.1.1.9000). It is the clearest possible argument for Step 6: a table that
  has to be re-typed will be wrong within the week. Replace it with a
  `pf_stack()` call and its output.

---

## 7. Order of work

| | step | cost | why here |
|---|---|---|---|
| 1 | `pf_check_schema()` + tests | small | nothing else is safe to trust until a frame can be checked |
| 2 | complete `REF-augmented.rds`, script committed | ~10 min run | the one live defect |
| 3 | merge npmatch #36 then #35, reinstall, re-read signature | small | Step 6 wants `np_signature_stamp()`; the pin is stale |
| 4 | `pf_eval_frame()` + `pf_compare_frames()` | medium | the durable fix for §1a |
| 5 | repoint `pf_truth_shards()` / `pf_round_sample()` / `pf_evaluate()` | medium | closes the door the draw scripts walk through |
| 6 | `pf_stack()`, and rewrite the two stale tables | small | |
| 7 | test `name_freq` as C2's withdrawn `promote` condition | small | §3; the first real mechanism for that gap |

Steps 1-2 are independent of 3. Step 4 wants 1. Step 5 wants 4.
