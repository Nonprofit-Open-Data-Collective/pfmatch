# A tiered reference: cheap DB first, escalate the residue

**Verdict: don't.** Not because the mechanism is unsound — it is sound, and more
so than expected — but because the arithmetic does not work and the safety flag
it depends on cannot be built accurately enough.

Measured 2026-08-21 on 1,000 identities against both references.
`dev/probe-tiered-reference.R`, `dev/probe-yes-caution-flag.R`,
`dev/build-label-frame.R`. Cascade mechanics: `dev/CASCADE.md`.

---

## 1. The mechanism is sound

Two things had to be true and both are.

**The base score is reference-independent.** `score = 0.60·name + 0.40·geo`,
computed from the query/candidate pair alone. Nothing consults corpus
statistics. So scores from two disparate reference DBs are directly comparable,
and merging scored pairs then re-running `np_select()` / `np_tier()` over the
union is legitimate rather than an approximation.

**reclin2 partitions cleanly.** `pair_blocking()` is per-reference,
`compare_pairs()` is per-pair; the frames `rbind` and re-select.

The cascade already *is* this pattern one level down: `np_cascade()` drops
YES-resolved queries from the pending set so each successive pass sees only the
residue. Extending it from passes to references is the same idea.

### Two terms that do depend on the reference

* **Blocking** — `max_ref_freq` / `min_pair_idf` prune token blocks by
  reference-wide document frequency. Affects recall, not comparability. Benign
  for merging.
* **The distinctive-name promotion** — floors the score to 0.90 when name
  similarity ≥ 0.95 **and `name_freq ≤ 3` counted in the reference**. A hard
  threshold on a corpus statistic. Measured: of 956 winning pairs with a
  `name_freq` on both sides, 879 are rare on the small reference, and **54 (6%)
  stop being rare on the big one**. Median `name_freq` is 1 either way, so this
  is a margin effect, not a wholesale shift — but the direction is unfavourable:
  **a smaller reference makes more names look rare, so it promotes more and
  auto-accepts more**, which is precisely the wrong bias for a stage whose job is
  banking early wins.

## 2. Escalation pays

| small → big | n |
|---|---:|
| MAYBE → **YES** | 47 |
| NO → **YES** | **36** |
| MAYBE → MAYBE | 140 |
| NO → NO | 145 |
| NO → MAYBE | 15 |
| MAYBE → NO | 6 |

Of 389 queries the small reference could not settle as YES, the big one settles
**83 (21%)**.

The 36 `NO → YES` are the strongest result in this memo and are discussed in §5:
grants whose recipient is simply absent from the active BMF, reachable only via
the legacy and alias rows.

## 3. Banking an early YES is not free

| | n | share |
|---|---:|---:|
| YES on the small reference | 569 | |
| big reference agrees, same EIN | 553 | 97.2% |
| **big reference picks a different EIN** | **16** | **2.8%** |
| ...and rates it YES there | 4 | |

The 16 are not noise. They are arm/operating pairs:

```
BOSTON CHILDRENS HEART FOUNDATION   ->  BOSTON CHILDREN HOSPITAL
BEMIDJI STATE UNIVERSITY ALUMNI     ->  Bemidji State University
GILCREASE MUSEUM MANAGEMENT         ->  GILCREASE MUSEUM ENDOWMENT
UNIVERSITY OF KENTUCKY RESEARCH FDN ->  UNIVERSITY OF KENTUCKY
REGIS HIGH SCHOOL PROPERTY          ->  REGIS HIGH SCHOOL
TEXAS CHILDRENS HOSPITAL            ->  TEXAS CHILDRENS HOSPITAL FOUNDATION
```

**The small reference does not contain the sibling**, so the cascade never sees
a contest, matches confidently to whichever member it has, and auto-accepts. Add
the sibling and 12 of the 16 fall to MAYBE.

A tiered design would therefore bank the operating-arm cases at high confidence
*because* the cheap reference is too thin to show the ambiguity — reintroducing,
upstream, the exact failure mode `R/dyads.R` exists to fix.

## 4. The safety flag does not work, and the arithmetic does not either

A flag rescues the design if it catches those 16 while sparing the 553. It must
be computable from the **small run alone** — a flag needing the big reference has
already paid the cost it was meant to avoid.

| flag | risky caught | safe wrongly flagged | total escalated |
|---|---:|---:|---:|
| `arm_name` — winning name has a support suffix | 3/16 (19%) | 75 (13.6%) | 13.7% |
| `sibling` — winning EIN is in a substitutable dyad | 3/16 (19%) | 93 (16.8%) | 16.9% |
| `promo` — score sits exactly on the 0.90 floor | 2/16 (12%) | 85 (15.4%) | 15.3% |
| `rare` — `name_freq ≤ 3` | 12/16 (75%) | 524 (**94.8%**) | 94.2% |
| `arm_name OR sibling` | 6/16 (38%) | 155 (28.0%) | 28.3% |
| **`arm_name OR sibling OR promo`** | **8/16 (50%)** | 214 (38.7%) | **39.0%** |

The best combination catches **half** the risky cases while escalating **39%** of
all YES. `rare` has the recall but no specificity at all.

### Why the flag is weak, stated plainly

The risky cases are risky *because the small reference lacks the sibling*. A flag
computed from the small run is being asked to detect the absence of something it
cannot see. `sibling` is the only flag carrying outside information — and it is
bounded by disclosure coverage: the dyad table holds only pairs that appear in a
filing, and 273 of 752 known arm pairs have no filing at all
(`dev/DYAD-FINDINGS.md` §2). `TEXAS CHILDRENS HOSPITAL` / `... FOUNDATION` is
not a disclosed dyad, so the lookup misses it.

### The arithmetic

Using the measured 128 vs 279 s per 1,000 identities:

| | s per 1,000 |
|---|---:|
| single pass, big reference only | **279** |
| tiered: everything through small | 128 |
| ...plus 64% escalated to big | 178 |
| **tiered total** | **306** |

**Tiering is 10% slower**, before counting the engineering. Once 39% of YES
escalate on top of all MAYBE and NO, roughly two-thirds of queries pay both
passes. The small pass stops being a filter and becomes an overhead.

## 5. The valuable finding is a different one

The 36 `NO → YES` grants are recipients the active BMF **cannot reach at any
threshold** — `THE ROTARY FOUNDATION INC`, `AMERICAN CANCER SOCIETY`,
`JEWISH NATIONAL FUND INC`, `PHILLIPS ACADEMY ANDOVER`, `HOUSTON SPCA` — found
only through the legacy and alias rows, most at scores of 0.90–0.98.

**NO recall is the one thing the label set has never measured**
(`dev/OPTIMIZATION-PLAN.md` §0: every existing human label sits inside MAYBE).
These 36 are a ready-made NO stratum, and they are *pre-enriched* — each carries
the answer the bigger reference found, so a labeller is confirming or rejecting a
specific candidate rather than searching.

Folded into `data-dev/LABEL-FRAME-REFTIER.csv` (`dev/build-label-frame.R`):

| stratum | cases | what it answers |
|---|---:|---|
| `MAYBE_to_YES` | 47 | did more context resolve it, or just move it? |
| `NO_to_YES` | 36 | **what does the NO boundary cost?** |
| `YES_contested` | 16 | **is an auto-accept safe when a sibling exists?** |

`verdict` / `correct_ein` / `evidence` / `note` left blank for the labeller;
evidence classes as in `dev/ADJUDICATION-PLAN.md`, with `NONE` first-class.

Note the dyad column: only 1 of the 16 `YES_contested` pairs is a disclosed
`substitutable` dyad and 12 have no dyad at all — the same disclosure ceiling
that limits the flag limits any dyad-based rescue here.

## 6. What to do instead

1. **Run the augmented reference throughout.** It is 2.2x, not an order of
   magnitude, and Phase 1 fits in 81 h on 12 shards with it
   (`dev/REF-PERFORMANCE.md`). There is no cost problem to solve.
2. **Retain the top-K candidates per identity, including for YES.** This is the
   good half of the "review post hoc" idea — see §7.
3. **Label the 99-case frame.** It is the YES and NO strata the optimization
   plan is blocked on, already drawn and already enriched.

## 7. On retaining candidates and reviewing post hoc

Worth doing, but **it does not rescue tiering**, and the reason is worth being
precise about.

`pf_dyad_collapse()` resolves *within one grant's candidate list*. Retaining
candidates makes that replayable without re-running the cascade — genuinely
useful, because the batch checkpoints currently keep only the winner, so any
re-adjudication today means a full re-run.

But the 16 risky YES are wrong because **the sibling was never a candidate**. It
is not in the small reference at all. Retaining candidates from that run
preserves a list the right answer is absent from. Post-hoc dyad review cannot
recover what blocking never generated.

So: retain top-K (5 is enough — `pf_adjudicate()` already defaults to it) for
**all** tiers, at roughly 5 rows per identity instead of 1. At ~3M identities
that is ~15M rows, which is nothing next to the 12.5M-grant output, and it makes
adjudication, dyad policy changes and threshold sweeps replayable offline. Do it
for that reason — not as a tiering rescue.

### Whose Phase 2, and how narrow the change is

**`pfmatch` Phase 2** — "the development databases", `dev/DEVELOPMENT-PLAN.md`
§"Phase 2", writing `PF-{YES,MAYBE,NO,OOS}.parquet` and `PF-IDENTITIES.parquet`
to `~/Documents/grants/`. *Not* matchdb Phase 2, which is "Schedule I as
`observed`" (`matchdb/dev/PLAN.md` §11) and concerns the reference side only.
Both repos now number their phases and "the Phase 2 partitions" is ambiguous
between them; this is the pfmatch one. No part of it is matchdb work — candidate
pairs are match *output*, and matchdb's deliverable is the reference the match
ran against.

The change is narrower than "retain candidates" suggests, because two of the
three tier partitions already do:

| partition | today | change |
|---|---|---|
| `PF-MAYBE.parquet` | "with its full candidate set" | none |
| `PF-NO.parquet` | "with whatever candidates were surfaced" | none |
| `PF-YES.parquet` | "EIN, scores, match provenance" — **the winner only** | **carry the top-K candidate set** |

So the ask is one partition's schema, and it is the partition where retention
matters most, for the reason §3 measures: the 16 contested auto-accepts are YES
rows, and a YES row today keeps no record of what it beat. The Phase 2 exit
criterion is unaffected — reconciling to 12,559,051 counts identities, and only
columns per identity change.

Restating what retention does **not** buy, because it is easy to lose: the 16 are
wrong because the sibling was never a candidate. Keeping five candidates from a
run whose reference lacked the sibling preserves a list the answer is absent
from. Retention makes adjudication replayable; it does not make a thin reference
safe. That argument lives in `matchdb/dev/PLAN.md` §8a.
