# Benchmark notes — 990-PF grant recipients vs. IRS BMF

> **Historical, 2026-08-19. The rates below are obsolete — do not quote them.**
> The 54.9% YES here predates state blocking, the apostrophe fix, the augmented
> reference and the e-file rebuild; blocking ran with **no geographic key on any
> pass**, which is the single biggest difference. The current figure is 62.81%
> on the augmented reference — see `dev/BASELINE-2026-10B/MANIFEST.md`.
>
> What is still worth reading here: the cost profile (the token pass dominates,
> §5), the recipient-type gradient, the score-band corroboration table, and the
> cross-state analysis. Those are structural and have replicated; only the
> headline rates moved.

Reference: `bmf_2026_01_processed.csv`, 1,924,822 records.
Config: npmatch defaults (`hier` scoring, YES ≥ 0.78, MAYBE ≥ 0.65, margin ≥ 0.05).
Blocking: `pf_default_passes()` — **no geographic key on any pass**.

---

## 1. Outcomes, 5,000-grant sample

| outcome | n | share |
|---|---:|---:|
| YES | 2,746 | 54.9% |
| MAYBE | 995 | 19.9% |
| NO | 886 | 17.7% |
| OOS | 373 | 7.5% |

Match rate **on grants actually attempted** (excluding OOS): **59.3% YES,
80.9% YES+MAYBE**.

Out-of-sample breakdown: 241 individual, 51 government, 50 foreign address,
31 no recipient name.

### Outcome × recipient type

| recipient type | YES | MAYBE | NO | OOS | n | %YES of attempted | %YES+MAYBE |
|---|---:|---:|---:|---:|---:|---:|---:|
| nonprofit (public charity) | 2,296 | 781 | 610 | 20 | 3,707 | 62.3 | 83.5 |
| nonprofit (other) | 64 | 35 | 24 | 4 | 127 | 52.0 | 80.5 |
| foundation (pf) | 40 | 18 | 17 | 0 | 75 | 53.3 | 77.3 |
| individual | 0 | 0 | 0 | 241 | 241 | — | — |
| other/unknown | 346 | 161 | 235 | 108 | 850 | 46.6 | 68.3 |
| **all** | **2,746** | **995** | **886** | **373** | **5,000** | **59.3** | **80.9** |

The gradient is the expected one and is a useful validity check on the
standardizer: recipients the filer coded as public charities match best, and the
`other/unknown` bucket — blanks and junk text — matches worst, because it is
where the uncoded individuals and misc. non-organizations hide. `looks_personal`
fires on 18% of OOS rows and 5% of NO rows but only 0.7% of YES rows, which is
consistent with that reading.

---

## 2. Precision: where the YES tier is soft

YES is heavily concentrated at the top of the score range, and score band tracks
geographic agreement almost perfectly:

| score band | n YES | state agrees | ZIP5 agrees |
|---|---:|---:|---:|
| ≤ 0.83 | 35 (1.3%) | 88.6% | 0.0% |
| 0.83–0.90 | 525 (19%) | 100.0% | 20.8% |
| 0.90–0.95 | 226 (8%) | 100.0% | 98.2% |
| > 0.95 | 1,960 (71%) | 99.7% | 98.2% |

**94.9% of YES matches score ≥ 0.90 with full ZIP or street corroboration.**
Hand-checking a random 15 from that band found no errors.

The soft spot is the 35 matches at ≤ 0.83 — exact matches on short, generic
names where nothing but the name agrees ("PATH", "RUACH", "BRIGHT BEGINNINGS",
"SECOND CHANCES"). Most are still right, but this is where the false positives
live.

---

## 3. Geographic mismatch — the question the state-free run was for

Only **10 of 2,746 YES matches (0.4%)** disagree on state. Reading them
individually splits them cleanly in two:

**Score 0.96–0.98 (6 cases) — the 990-PF state field is simply wrong.**
City *and* ZIP agree exactly; only the two-letter state is off.

| recipient (as filed) | city / ZIP | BMF state | filed state |
|---|---|---|---|
| Student Mobilization Inc | Conway 72033 | AR | TX |
| Temple Bat Yahm | Newport Beach 92660 | CA | NY |
| Second Chance Rescue of Hardy | Hardy 72542 | AR | AZ |
| Harvesters — The Community Food Network | Kansas City 64129 | MO | KS |
| Congregation Khal Chasidim of Lawrence | Lawrence 11559 | NY | NJ |
| Mercy House Teen Challenge | Georgetown 39078 | MS | MO |

**Score 0.80 (4 cases) — genuine false positives.** A common name matched in
another state with no address corroboration: "First Presbyterian Church" IA →
NC, "Patterson Volunteer Fire Department" LA → NC, "Bristow Community Center"
OK → IN, "Unbound" MO → KS (this last one is probably right — Unbound is
headquartered in Kansas City, KS).

**Implication for blocking.** Genuine cross-state matching is contributing
almost nothing on the YES tier: the six real cross-state hits are all recoverable
from city+ZIP, and the four that are not are errors. A state block would cost
~0.1% recall and remove a false-positive channel — but the MAYBE tier tells a
different story (68% state agreement, i.e. ~320 cross-state MAYBEs), so block
only after those are adjudicated, not before.

---

## 4. Runtime

Matching only. BMF read/normalize/index (~5 min, cached to a 1.3 GB RDS) and
grant preparation are excluded.

| set | in-scope grants | candidates generated | cascade | per 1,000 |
|---|---:|---:|---:|---:|
| 5k | 4,627 | 921,866 | 218 s | 47 s |
| 50k | 47,225 | 10,070,450 | 2,900 s (48 min) | 61 s |

Scaling is close to linear with a mild penalty (47 → 61 s per 1,000) as the token
pass grows: 4,627 in-scope grants generate 880k candidate pairs, 47,225 generate
9.66M. Extrapolating, the full-file run is bounded by the token pass, and the
dedup step in §6 below is the cheapest way to cut it.

### 50k results

| outcome | n | share |
|---|---:|---:|
| YES | 24,771 | 49.5% |
| MAYBE | 11,040 | 22.1% |
| NO | 11,414 | 22.8% |
| OOS | 2,775 | 5.5% |

**52.5% YES, 75.8% YES+MAYBE on attempted grants** — a few points below the 5,000
-grant sample (59.3% / 80.9%), so treat the smaller sample as mildly optimistic.
The type gradient and the geography finding both replicate: public charities
match best (56.5% YES) and `other/unknown` worst (39.2%), and **99.7% of YES
matches agree on state** (vs 68.2% of MAYBE), the same split seen at 5k.

Cost is dominated by the last pass. The four exact passes generate 41,106
candidate pairs between them and resolve 2,275 queries; `token-any` then
generates **880,760** pairs — 96% of all candidate pairs — to resolve a further
476. Residual pruning is doing its job (only the 2,335 unresolved queries enter
the token pass), but the token pass still costs roughly 20× the exact passes per
query resolved.

---

## 5. Where the misses are

**Recall ceiling from acronyms and short names.** 72 queries generated *zero*
candidates from any pass: `OMSI`, `LVOY`, `PRE4CLE`, `JDRF INTERNATIONAL`,
`HHM HEALTH INC`, `OPB FOUNDATION`, `CDGA FOUNDATION`. Acronyms share no token
with the spelled-out BMF name and are too short for the IDF pass. npmatch has
acronym-aware token overlap in `np_compare()`, but it only runs on pairs that
blocking already surfaced — and here nothing surfaces.

**Scoring misses, not blocking misses.** Several NO cases *did* surface the
right candidate and then scored it below the review floor:
`TUNNELS TO TOWERS FOUNDATION` → `STEPHEN SILLER TUNNEL TO TOWERS FOUNDATION`
(0.38), `CRU (FAMILY LIFE MINISTRIES)` → `JOURNEY FAMILY LIFE MINISTRIES`
(0.53), `THE NATURE CONSERVANCY OF TENNESSEE` → `NATURE CONSERVANCY` (0.52).
The best-candidate score across all NO rows has a median of 0.36 and a 3rd
quartile of 0.53, so the review floor at 0.65 is leaving a real tail unexamined.

**Field truncation in the source.** `SIGOCPYRPNAM` is hard-capped at 35
characters and `SIGOCPYRFAAL1` (street) at 35 — 6.1% of non-empty `PNAM` values
sit exactly at the cap and are therefore cut off mid-name. `SIGOCPYRBNBN1` is
not capped (max observed 75), which is why the two-line business-name wrap
exists at all. A truncated query name can never clear an exact-name pass.

---

## 6. Suggested next steps, in order of expected return

1. **A prefix pass for truncated names.** Block on the first *n* characters of
   `name_key` when the source name sits at the 35-character cap. This is a
   990-PF field-width artifact, so it belongs in `pfmatch` rather than
   `npmatch`.
2. **Adjudicate a sample of the MAYBE tier** (995 cases) to calibrate the
   thresholds. The 0.83–0.90 band is 525 YES matches with 100% state agreement
   but only 21% ZIP agreement — that is the band whose true precision is least
   known.
3. **An acronym index on the reference side.** Index the initials of each BMF
   `name_key` as a synthetic token so `OMSI` can reach
   `OREGON MUSEUM OF SCIENCE AND INDUSTRY`.
4. **Then consider blocking.** Once MAYBE is adjudicated, a state block (with a
   ZIP3 or city escape hatch for the state-typo cases in §3) should cut the
   token pass sharply. Do not impose it before the MAYBE cross-state cases are
   understood.
5. **Deduplicate before matching.** Grant rows repeat recipients across
   foundations and years; matching distinct (name, address) tuples and joining
   back would cut the work substantially on the full file.

---

## Re-benchmark after the apostrophe fix + loosened scope (5,000 grants)

Two changes: `npmatch`'s `.np_basic_clean()` now deletes apostrophes instead of
spacing them, and `individual` / `government` are flagged rather than dropped
(only foreign geography is out of sample now).

| | before | after |
|---|---:|---:|
| YES | 2,746 (54.9%) | **2,819 (56.4%)** |
| MAYBE | 995 (19.9%) | 1,043 (20.9%) |
| NO | 886 (17.7%) | 1,058 (21.2%) |
| OOS | 373 (7.5%) | **80 (1.6%)** |
| in scope | 4,627 | 4,920 |

Read these together, not separately. The rate *on attempted grants* falls
(59.3% → 57.3% YES) purely because the denominator grew by 293 deliberately
harder cases — the individual- and government-coded grants that used to be
discarded unexamined. In absolute terms 73 more grants matched, and 293 that were
never looked at are now examined.

Where the gains came from:

* **Exact-name pass candidates 40,177 → 44,772 (+11%), YES from it 2,182 →
  2,267.** That is the apostrophe fix: possessive names now reach the cheapest
  pass instead of falling through to the token pass or missing entirely.
* **Individual-coded grants: 22 YES, 20 MAYBE of 241** (17.4% YES+MAYBE). Lower
  than the audit's 24% oracle estimate, as expected — the audit probe was
  deliberately unblocked and used containment matching the cascade does not.
* OOS fell from 7.5% to 1.6% of all grants: 50 foreign + 30 with neither a name
  nor an address.

---

## Staged cascade at 50k (production configuration)

`pf_staged_passes("lean")`, after the apostrophe fix and the loosened scope.

| outcome | n | share |
|---|---:|---:|
| YES | 25,436 | 50.9% |
| MAYBE | 10,898 | 21.8% |
| NO | 13,052 | 26.1% |
| OOS | 614 | 1.2% |

51.5% YES, 73.6% YES+MAYBE on attempted grants. Runtime **33.5 s per 1,000**
(baseline 61.4), from 5.29M candidate pairs (baseline 10.07M).

| recipient type | YES | MAYBE | NO | OOS | n | %YES attempted |
|---|---:|---:|---:|---:|---:|---:|
| nonprofit (public charity) | 20,224 | 7,908 | 6,942 | 117 | 35,191 | 57.7 |
| nonprofit (other) | 1,010 | 567 | 577 | 7 | 2,161 | 46.9 |
| foundation (pf) | 261 | 124 | 157 | 9 | 551 | 48.2 |
| individual | 95 | 107 | 1,602 | 0 | 1,804 | 5.3 |
| other/unknown | 3,846 | 2,192 | 3,774 | 481 | 10,293 | 39.2 |
| **all** | **25,436** | **10,898** | **13,052** | **614** | **50,000** | **51.5** |

The `individual` row is the scope change made visible: 202 of 1,804 resolve to a
BMF organization (11.2% YES+MAYBE), and the remaining 1,602 are now NO — queued
for internet search — instead of being discarded unexamined as they were before.

---

## Confirmed baseline, 2026-08-20 (5,000 grants)

All session fixes in: apostrophe normalization, loosened scope, staged `lean`
cascade, stage-4 recovery, self-match guard, city/ZIP3 state gating, and
`distinct_name_main_only`.

| outcome | n | share |
|---|---:|---:|
| YES | 2,821 | 56.4% |
| MAYBE | 1,006 | 20.1% |
| NO | 1,093 | 21.9% |
| OOS | 80 | 1.6% |

**57.3% YES, 77.8% YES+MAYBE on attempted grants.** Geographic agreement on YES:
99.8% state, 82.8% ZIP5 (up from 82.2%).

| recipient type | YES | MAYBE | NO | OOS | n | %YES attempted |
|---|---:|---:|---:|---:|---:|---:|
| nonprofit (public charity) | 2,329 | 759 | 600 | 19 | 3,707 | 63.2 |
| nonprofit (other) | 65 | 35 | 23 | 4 | 127 | 52.8 |
| foundation (pf) | 41 | 18 | 16 | 0 | 75 | 54.7 |
| individual | 22 | 20 | 199 | 0 | 241 | 9.1 |
| other/unknown | 364 | 174 | 255 | 57 | 850 | 45.9 |

### Against the session's opening baseline

| | opening | now | change |
|---|---:|---:|---:|
| YES | 2,746 | 2,821 | **+75** |
| OOS (discarded unexamined) | 373 | 80 | **-293** |
| in scope | 4,627 | 4,920 | +293 |
| YES+MAYBE on attempted | 80.9% | 77.8% | -3.1 pts |

The YES+MAYBE rate falls because the denominator grew by 293 deliberately harder
cases — the individual- and government-coded grants that used to be dropped
without being looked at. Those now return 42 YES+MAYBE and 199 NO, and the NO
rows are visible as internet-search candidates rather than silently gone.

Precision moved in the right direction throughout: the cross-state
false-positive channel is closed (city/ZIP3 now require state agreement), 13
DBA-justified promotions were demoted, and ZIP5 agreement on YES rose.

### Runtime from this run is NOT usable

It reported 762.9 s per 1,000 against 33.5 s per 1,000 measured at 50k — a 23x
discrepancy that is machine contention, not a regression. Several heavy analysis
scripts were running concurrently, each holding a 1.3 GB reference bundle and a
2.6 GB result object in memory. The outcome counts are unaffected (they match the
config A/B exactly, 2,821 YES), but **the timing from this run should be
ignored**; the clean figure remains the 50k measurement, which ran alone.

Lesson for future benchmarking: time the cascade on an otherwise idle machine, or
the number measures the machine rather than the code.

### The same mistake, repeated 2026-08-20

Recorded because the lesson above was already written down and did not prevent
it. While the full-file prepare job held a core and 20 GB for six hours, the
augmented reference was timed at **2,390 s per 1,000** on 98 queries and
**1,178 s per 1,000** on 980 — against the 33.5 s per 1,000 measured at 50k.
That is a ~25x discrepancy, the same magnitude and the same cause as the 23x
above. It was initially reported as a 60x performance regression in the
augmented reference. There was no regression.

Two further errors compounded it:

* **Comparing across batch sizes.** The 33.5 s per 1,000 was measured on
  25,000-query batches. A 98-query run pays the same per-batch fixed cost over
  250x fewer queries, so the per-1,000 figure is dominated by overhead. Solving
  the two-point line gives a fixed cost near 132 s and a marginal cost near
  1.04 s per query on this contaminated machine -- neither comparable to a
  production batch.
* **Timing the wrong configuration.** `pf_match_grants()` defaults to
  `pf_default_passes()`, the state-free baseline whose unblocked `token-any`
  sweep the scale work rejected. Production runs
  `pf_staged_passes("lean")` with state blocking. A direct caller gets the
  rejected configuration silently.

What survives from that session is the **relative** comparison, because both
references were timed back to back under identical load: on the same 98 queries
and the same production passes, the augmented reference cost 630 s against the
plain reference's 234 s -- **2.7x for 2.02x the rows**, near-linear -- while
returning 64 YES against 61 and 10 NO against 15.

**Rule, restated operationally:** no absolute timing is recorded unless
`Get-Process Rscript` shows nothing else running, and no per-1,000 figure is
compared across different batch sizes.

## 2026-10-22: the rule was broken again, and it coloured a conclusion

Every long-running job in the 2026-10-22 session shared the machine with an
unrelated 15-process job (`dev/partvii-panel/05-link.R` plus 14 parallel SOCK
workers, started 20:28:52) and, later, an R process from a separate matchdb
session. `Get-Process Rscript` was not checked before running anything.

No absolute timing from that session should be quoted. Specifically affected:
the ~40-minute reference probe, the ~15-minute token-IDF builds, and the
agreement-cell scan.

Worse than the lost timings, it coloured a diagnosis. `dev/scan-agreement-risk.R`
ran 90 minutes with no output and was written off as "the `by = seq_len(nrow(a))`
pattern is too slow". That pattern *is* slow and should be rewritten as two
vectorised joins — but the attribution was made without noticing the machine was
carrying a 15-worker job, so how much of the 90 minutes was the pattern and how
much was CPU starvation is unknown. The honest statement is that the scan's cost
was never measured.

**Addition to the rule:** check for foreign R processes before *and* after any
long run, and never diagnose a performance problem from wall-clock alone on a
shared machine. Identify processes by command line (`Get-CimInstance
Win32_Process`) rather than by count — most of the Rscript processes visible that
evening belonged to other sessions, and killing by name would have destroyed
someone else's work.
