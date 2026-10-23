# The 1k benchmark is deterministic, and thread-independent

Checked 2026-08-21. **Conclusion: the 1k benchmark can serve as a phase gate.**
Two cold runs at the default thread count and a third at a single thread all
produce bit-identical output across all 24 columns.

This was matchdb's Phase 0a precondition (`matchdb/dev/PROCESS.md` §4). Every
later gate reduces to "the 1k benchmark is unchanged", and that criterion is only
falsifiable if the benchmark returns the same answer twice.

## Why it was in doubt

Two mechanisms could plausibly have made it vary:

* `data.table` runs the blocking joins multi-threaded, so candidate-pair row
  order is not guaranteed stable across runs.
* Selection breaks ties by first-row-wins — `.np_argmax_by()` uses
  `order(group, -score)` then `!duplicated()`, and `.np_overall_summary()` takes
  `ix[1]` among equal scores (`npmatch/R/select.R`).

Together those are the classic recipe for a verdict that moves between runs
without any code changing. On this benchmark they do not.

## Method

`dev/probe-determinism.R`, three runs in separate R processes, each loading the
same cached reference bundle (1,924,822 rows) and running the 11-pass staged
cascade with stage-4 recovery over the five 1k grant files.

Comparison is exact, not tolerant: every column compared with `identical()` after
sorting by `.id`. Determinism means bit-identical — a benchmark that is merely
close cannot gate an extraction that must not change behaviour.

| run | threads | match time | YES | MAYBE | NO | vs run 1 |
|---|---:|---:|---:|---:|---:|---|
| 1 | 7 | 452.1 s | 2821 | 1006 | 906 | baseline |
| 2 | 7 | 534.8 s | 2821 | 1006 | 906 | **24/24 columns identical** |
| 3 | **1** | 477.8 s | 2821 | 1006 | 906 | **24/24 columns identical** |

4,733 identities from 5,000 grant rows (4,920 in scope). Logs:
`DETERMINISM-RUN1.log`, `-RUN2.log`, `-RUN3.log`.

## What this establishes, and what it does not

**Established.** The cascade is deterministic across processes, and — the more
useful result — **independent of `data.table` thread count**. Run 3 at one thread
matched run 1 at seven exactly. Since thread count is the variable that actually
differs between machines, this is the property that matters for
`matchdb/dev/PROCESS.md` §3's requirement that a gate pass "on a machine that is
not the author's".

**Not established.** One machine, one R version (4.4.2), one platform, one
pinned reference bundle. Cross-platform determinism is untested and would be
worth a single confirming run when a second machine is available. Nothing here
suggests it is at risk — thread-independence is the stronger of the two
properties and it holds — but it has not been shown.

Note also that this pins the *benchmark*, not the *baseline*. Phase 0a still
needs a manifested baseline from a pinned `(npmatch, pfmatch)` commit pair; this
result only says such a baseline will be reproducible once taken.

## Incidental: the result object is 242 MB, and it need not be

Each `DET-RUN*.rds` is 242,434,747 bytes for a 4,733 x 24 frame — roughly 51 KB
per row. Run down while freezing the Phase 0a baseline, the cause is specific
and the fix is one line.

`as.data.frame()` does **not** drop a subclassed frame's attributes, and
`np_cascade()` attaches the full scored candidate-pair table to its result
(`attr(res, "pairs") <- union`, `npmatch/R/cascade.R`). So the "data frame" is:

| attribute | size |
|---|---:|
| `pairs` | **194.4 MB** |
| `config` | 0.2 MB |
| `profile`, `stages` | < 0.1 MB |
| the frame itself | ~3 MB |

Setting `attr(x, "pairs") <- NULL` before saving took the baseline outputs from
9.65 MB and 16.64 MB to **0.163 MB and 0.165 MB** compressed — 60x and 100x —
with the frame and the useful metadata (`config`, `profile`, `stages`) intact.

Not a defect: retaining the pairs is deliberate and `np_route()` needs them,
which is exactly why `dev/probe-variant-class-ab.R` could recover variant class
post-hoc without any npmatch change. But it means **anything that persists a
`pf_match` result is storing ~194 MB of candidate pairs by default**, and a
phase gate archiving one per run would cost a quarter-gigabyte each time. Strip
the attribute unless the pairs are the point.

The three scratch files were deleted after comparison; `data-dev/` is gitignored
and the probe reproduces them in about eight minutes each.

---

## Update 2026-08-22: reproducible, and now also order-independent

This memo established that the benchmark reproduces bit-for-bit across processes
and thread counts. Both remain true. What it could not see is how much of that
reproducibility depended on the *reference arriving in the same order every
time*.

Measured while validating state partitioning: with selection ties broken on
`.ein` instead of on row position, **498 of 4,733 identities (10.52%) report a
different EIN, and 0 change tier** — every one of the 498 a pair of candidates
scoring identically. So one reported EIN in ten rested on row order, and three
runs on one machine could never have detected it, because the row order was the
same all three times.

`npmatch@f14f1d9` fixes it and `BASELINE-2026-08` was re-frozen at revision 2
(`BASELINE-2026-08/MANIFEST.md`). The benchmark is now deterministic across
processes, thread counts, **and reference row order** — which is the property a
partitioned run actually needs.

The "not established" note below still stands on cross-platform determinism.
