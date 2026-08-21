# The dyad table, measured inside a full cascade

**704 MAYBE grants become YES, nothing moves into NO, and 99% of the collapsed
pairs are co-located bodies with an identical name core.** The mechanism is that
`np_tier()` demotes a YES to MAYBE whenever the margin to the runner-up falls
under `min_margin`; when the runner-up is the same body, that demotion was
always an artefact. Median margin on collapsed grants goes **0.000 → 0.140**.

Shipped as `R/dyads.R` with 41 tests in `tests/testthat/test-dyads.R`.
Table at `data-dev/PF-DYADS.rds` / `.csv`. Scripts: `dev/build-dyads.R`,
`dev/sweep-dyad-rules.R`, `dev/test-dyad-cascade.R`,
`dev/check-dyad-promotions.R`, `dev/check-dyad-residual.R`,
`dev/diagnose-dyad-fanout.R`. Logs alongside each.

Background and the decision not to build clusters: `dev/CLUSTER-FINDINGS.md`.

---

## 1. The rule, and why the first one was wrong

The first build classed every Schedule A line 12 edge as substitutable. It
produced an EIN with **905 substitutable partners** — the *YMCA Retirement
Fund*, a 509(a)(3) that supports 907 local YMCAs. SparkJoy Foundation supports
408 unrelated Maine charities, Vitalyst Health 406, Ascension Health 253.

"X is a supporting organization of Y" is **not an exclusive relation**, and only
an exclusive one licenses substitution. A grant reported to `Bangor YMCA` is not
interchangeable with a retirement fund. 43% of Schedule A edges come from a
supporter naming more than ten organisations:

| supporter fan-out | edges | share |
|---|---:|---:|
| 1 | 25,133 | 32% |
| 2 | 5,980 | 8% |
| 3–5 | 7,310 | 9% |
| 6–10 | 6,184 | 8% |
| 11–50 | 16,962 | 22% |
| 51+ | 16,298 | 21% |

The mirror-image failure is the federated sibling. An identical name core
catches 337 chapters of `ALPHA LAMBDA DELTA`, 214 South Carolina Masonic lodges,
and 150-odd `VOLUNTEERS OF AMERICA` affiliates. Siblings are not substitutes —
that is `pf_group_siblings()` territory.

Both failures are **degree**. A body with an arm has one to three of them;
anything with fifty is a network. `substitutable` therefore requires all of:

1. a Schedule A edge whose supporter names ≤ `max_fanout` (3) organisations,
   **or** an identical name core in the same state;
2. both parties sharing a subsection code — a c(3) and a c(4) are not
   substitutes for a private foundation's grant, whatever Schedule R says;
3. neither party exceeding `max_degree` (5) substitutable partners afterwards.

### The sweep

| rule | pairs | max degree | EINs deg>10 | MAYBE top-2 reached |
|---|---:|---:|---:|---:|
| A. Sch A edge or name core | 129,645 | **905** | 3,567 | 1,183 |
| B. + fan-out ≤ 3 | 90,587 | 319 | 2,322 | 1,163 |
| C. + name core needs same state | 40,605 | 289 | 577 | 1,158 |
| **D. + degree cap 5 (shipped)** | **29,238** | **5** | **0** | **1,055** |
| E. + degree cap 3 | 26,480 | 3 | 0 | 984 |
| F. name core + same city only | 8,536 | 289 | 379 | 895 |

89% of the naive rule's reach at 1/180th of its worst-case degree. **The
adjudicated 100 returns identical numbers for all six rules**, so this is chosen
on graph safety, not on labels — stated plainly because it is a real limit on
what has been established.

The cap removes exactly what it should: `ALPHA LAMBDA DELTA` (289),
`ANCIENT FREE MASONS OF SOUTH CAROLINA` (214), a dozen `VOLUNTEERS OF AMERICA`
affiliates (135–156 each).

## 2. The table

**566,653 pairs over 174,496 EINs. 29,238 substitutable (5.2%), 537,415
related.** Max substitutable degree 5, mean 1.23.

| reason | pairs |
|---|---:|
| `exclusive_support` | 25,806 |
| `same_name_core+same_state` | 1,820 |
| `exclusive_support+same_name_core` | 1,612 |

| kept out of `substitutable` because | pairs |
|---|---:|
| `disclosed_related` (a bare Sch R edge) | 433,418 |
| same name core, different state | 47,009 |
| support relation not exclusive | 42,822 |
| demoted: degree > 5 | 11,367 |
| demoted: subsection mismatch | 2,799 |

Sanity check against the 752 same-state arm pairs `pf_cluster_arms()` found by
name alone: of the 479 that have any disclosure, **411 (86%) are
`substitutable`**. The other 273 have no filing at all and are simply absent —
**the dyad table classifies disclosed pairs, it does not invent them.** Name-only
pairs remain `pf_cluster_arms()`'s job, and the two are complements.

## 3. What it does to the cascade

Collapse happens **before selection**: the losing member is removed from the
scored pair set and `np_select()` / `np_tier()` re-run. Rewriting the pick
afterwards leaves the tier where it was and measures nothing.

| variant | grants merged | candidates removed | picks changed | MAYBE → YES |
|---|---:|---:|---:|---:|
| substitutable, **operating-first** | 1,657 | 2,099 | 349 | **+704** |
| substitutable, keep-top | 1,657 | 2,099 | 311 | +398 |
| substitutable, arm-first | 1,657 | 2,099 | 558 | +258 |
| substitutable **+ related** | 2,575 | 4,713 | 539 | +983 |

**NO is unchanged in every substitutable variant.** Every tier change is inside
a collapsed grant.

### The related variant is the one that reports the better number

+983 against +704 — 279 more grants leaving the review queue. It gets there by
merging pairs like these:

```
Mayo Clinic Health System-Fairmont  / Mayo Clinic Health System-Lake City
Mass General Hospital Corp          / Mass General Brigham Population Hlth
DANA FARBER CANCER INSTITUTE        / DANA FARBER CANCER CARE NETWORK
AMERICAN CIVIL LIBERTIES UNION      / ACLU FOUNDATION
MOVEMENT STRATEGY CENTER            / MOVEMENT STRATEGY CENTER ACTION FUND
WORLD FOUNDATION FOR GIRL GUIDES    / GIRL SCOUTS OF THE USA
```

Different hospitals; a c(3) and its c(4). 918 grants are collapsed under
related-too that are not under substitutable-only. **The unsafe variant is the
one that flatters the metric**, which is the argument for the split in one line.

## 4. The promotions audit

704 auto-accepts is the risk surface, not the win: a YES leaves the review queue,
so a wrongly merged pair manufactures false confidence — worse than leaving the
grant in MAYBE.

| | |
|---|---:|
| same city | 698 (99%) |
| disclosed in 5+ tax years | 611 (87%) |
| identical name core | 595 (85%) |
| share 2+ content tokens | 666 (95%) |
| **share no content token** | **4 (0.6%)** |

All four of the no-shared-token promotions are correct: three are
`CARENET` / `CARE NET FOUNDATION` (the same name, one space), and the fourth is
`Meals On Wheels` / `PETER CARDELLA SENIOR CITIZEN CENTER`, a genuine exclusive
support relation in one city.

Typical promotions are unambiguous: `CENTRA HEALTH` / `CENTRA HEALTH FOUNDATION`,
`NEBRASKA HUMANE SOCIETY` / `NEBRASKA HUMANE SOCIETY FOUNDATION`,
`VALLEY HOSPITAL` / `VALLEY HOSPITAL FOUNDATION`.

Only one promotion is in the adjudicated 100: **G004576, `WAYNE MEMORIAL HEALTH
SYSTEM` / `WAYNE MEMORIAL HOSPITAL FOUNDATION`, adjudicated `AMBIGUOUS`** — a
case where the reviewer could not choose. Collapsing is the correct response to
that: it stops asking a question with no answer.

### Why operating-first beats keep-top, which is not what you would guess

Keep-top retains the highest score by construction, so it cannot lose on score —
yet it promotes 398 against operating-first's 704. `np_tier()` has a third gate:
`overall_veto_soft` demotes a YES regardless of score.

| | promotions |
|---|---:|
| kept candidate carries a soft veto | **0 (0%)** |
| dropped candidate carried a soft veto | **451 (64%)** |
| kept candidate scored lower than the dropped one | 24 (3%) |

The arm's name carries an extra qualifier the grant record does not, which trips
the soft veto; the operating entity's name matches cleanly. So operating-first
is systematically dropping the soft-vetoed candidate at almost no cost in score.

**Read this carefully.** It means the tier promotion is sound *whichever member
truly received the money*, because the claim being made is "these are one body."
It is **not** independent evidence that the operating entity is the right payee.
That question still rests on 15 adjudicated cases (60%, CI 32–84%), and it now
governs the **196 promotions (28%) where the reported EIN changed**.

## 5. The precision residual, and why it is smaller than it looks

30.8% of substitutable pairs share no content token — alarming until you
separate the table from what fires:

| | rate |
|---|---:|
| in the table | 9,019 / 29,238 = **30.8%** |
| among edges firing on 50k top-two pairs | 14 / 1,370 = **1.0%** |
| among the 704 promotions | 4 / 704 = **0.6%** |

Blocking does the filtering: two candidates for one query are already
name-similar. All the risk sits in `exclusive_support`; the name-core paths
cannot produce a zero by construction.

The 14 firing cases are mostly the reason to have disclosure at all —
`NETWORK FOR TEACHING ENTREPRENEURSHIP` / `NFTE ENDOWMENT FUND`,
`MUSEUM OF MODERN ART` / `MOMA AUXILIARIES`,
`MUSEUM OF NEBRASKA ART` / `MONA REAL ESTATE HOLDINGS`,
`CHALLENGED ATHLETES` / `CAF PROPERTY`. Acronyms and rebrands, unreachable by
any string method.

Extra gates priced on the exclusive-support path:

| gate | pairs kept | firing edges kept |
|---|---:|---:|
| as shipped | 29,238 (100%) | 1,370 |
| + shared token **or** same city | 24,359 (83%) | **1,370** |
| + require a shared token | 20,219 (69%) | 1,353 |
| + require same city | 12,824 (44%) | 1,327 |
| + shared token **and** same city | 8,684 (30%) | 1,310 |

`shared token OR same city` removes 4,879 table rows and loses **zero** firing
edges — free if a tidier table is wanted, but it buys nothing measurable here so
it is not the default. Requiring a shared token outright would delete the
NFTE / MoMA / CAF cases.

## 5b. Confirmed against the augmented unified reference

Everything above used the 50k `pf_match` built on the January monthly BMF
(1,924,822 rows). The package now matches against the augmented unified
reference (3,891,187 rows). Re-measured on 1,000 grants / 978 identities
(`dev/bench-dyad-1k.R`), with the predictions written down first:

| | prediction | result |
|---|---|---|
| 1 | promotions at a similar or higher rate than 6.5% of MAYBE | **9.5%** (19 of 200) |
| 2 | nothing pushed into NO | **0** in all three variants |
| 3 | adjudicated accuracy does not fall | **77% → 77%** (10 of 13) |

The dyad table was rebuilt on the unified BMF first
(`dev/build-dyads-unified.R`) and barely moved:

| | monthly | unified |
|---|---:|---:|
| BMF coverage of dyad EINs | 62.6% | **88.9%** |
| substitutable | 29,238 | **29,230** |
| max substitutable degree | 5 | 5 |

753 promoted, 761 demoted. Better coverage adds name-core matches and
subsection vetoes in near-equal measure, so the guards hold under a doubling of
reference coverage. That stability is a stronger result than a flat number: the
rule is not tuned to one reference vintage.

### The `related` variant now has a measured cost

| variant | YES | MAYBE | adjudicated accuracy |
|---|---:|---:|---:|
| baseline | 593 | 200 | 77% |
| operating-first | 612 | 181 | **77%** |
| keep-top | 609 | 184 | 77% |
| **+ related** | **620** | **173** | **54%** |

It promotes the most **and is the only variant that loses accuracy** — 10 of 13
correct down to 7. Until this run the case against collapsing `related` rested
on inspecting the pairs it merges. It now rests on a measurement. 13 cases, so
the magnitude is not established; the sign is, and it points the same way as
every qualitative check.

### Promotions on this reference

19 promotions, all of the expected shape:

```
COMMUNITY HOUSE ASSOCIATION   <- COMMUNITY HOUSE FOUNDATION
SAINT SEBASTIANS SCHOOL       <- SAINT SEBASTIANS SCHOOL FUND
CENTRA HEALTH                 <- CENTRA HEALTH FOUNDATION
PHOENIX CHILDRENS HOSPITAL    <- PHOENIX CHILDRENS HOSPITAL FOUNDATION
BOCA RATON REGIONAL HOSPITAL  <- BOCA RATON REGIONAL HOSPITAL FOUNDATION
```

34 identities collapsed, 7 reported EINs changed, and **15 collapsed without a
tier change** — the tie shrank but the grant stayed in MAYBE for some other
reason. That last number matters: collapsing is not a promotion machine, it
removes one specific artefact.

## 5c. The soft veto the collapse was defeating

`affiliate_suffix` is a **soft veto** that fires when a candidate's last token is
FOUNDATION / ENDOWMENT / AUXILIARY / BOOSTERS and the query lacks it. It is the
operating-arm problem in veto form, and a soft veto is npmatch's "do not
auto-accept this" signal — it caps the grant at MAYBE.

Dropping the arm dropped the veto with it. Measured on the 50k run:

| | grants |
|---|---:|
| promotions, no guard | 700 |
| ...where the **pick itself** was soft-vetoed | **71** |
| ...held only by the margin brake | 629 |

All 71 are pick-changed: the cascade ranked the arm first, `affiliate_suffix`
said don't accept it, and `policy = "operating"` overrode both. Those
auto-accepts rested on the ordering policy alone — 60% on 15 adjudicated cases —
against a score and a veto that both said otherwise.

`pf_dyad_config(keep_soft_veto = TRUE)`, on by default, carries the veto (and
its original reason) onto the surviving representative. Result: **629
promotions, exposure 0**, and a veto on the *kept* candidate still holds the
grant — 162 collapsed grants keep a soft-vetoed representative and 142 stay
MAYBE.

### Two predicates that were wrong, and what they cost

The guard has to fire on "the veto was **holding** this grant", and that has a
precise meaning. Two looser readings were tried and measured first:

| predicate | promotions | exposure |
|---|---:|---:|
| any dropped member vetoed | 249 | 0 |
| top of the band vetoed | 394 | 6 |
| **the pick itself vetoed** | **629** | **0** |

The first cost 451 grants to fix 71: in 380 of those the cascade had already
picked the un-vetoed operating entity, so the veto concerned a candidate that
was never going to be reported. The second leaked because **the band's top row
is not the pick** — `np_select()` resolves through `.np_overall_summary()` with
tiebreak rules, not by raw max score. Only reading `overall_veto_soft` off the
pre-collapse result gives 700 − 71 = 629 by construction.

### What this does not explain

Earlier notes here claimed the soft veto was why `operating` promoted more than
`keep-top` (+704 against +398). **It is not** — only 10% of promotions were
veto-held, which cannot account for a 306-grant gap. The "64% of dropped
candidates carried a soft veto" statistic describes the *dropped candidate*, not
what determined the tier: the arm frequently carried a veto while the pick was
already the operating entity, in which case the veto never affected the outcome.
The mechanism behind the policy gap is **unexplained** and should not be
asserted without measurement.

## 6. Bugs the exercise found

Recorded because each was invisible until something executed:

1. **`%chin%` was never imported.** `.datatable.aware <- TRUE` makes `:=` work
   but does not put data.table's infix operators on the package search path.
   Every `%chin%` in `R/dyads.R` failed whenever the caller had not attached
   data.table. Fixed with `@importFrom data.table %chin%`; this was latent for
   any future package code too.
2. **`max_band = Inf` coerced to `NA`** via `as.integer()`.
3. **The tie band was uncapped.** One grant has **4,609 candidates inside the
   band** — 10.6M pairwise comparisons — which hung the first cascade run.
   `max_band` now caps at 25 by score and reports what it drops (620 grants
   exceed it). Nothing below the top handful can affect selection.
4. Row identity in `pf_dyad_collapse()` was carried by position across a
   `setorder()`. Now carried in a `.rowid` column.
5. **`utils::modifyList()` was silently discarding the collapse's output.** The
   return was `modifyList(x, list(result = new))`; `modifyList` recurses
   whenever both values are lists, and **a data.frame is a list**, so instead of
   replacing the result it merged the new one column-by-column into the old
   object. The columns arrived, which is why nothing looked wrong, but every
   attribute set on the new frame was dropped — including the reduced pair set
   that `pf_dyad_collapse()` exists to produce. Tier counts stayed correct
   (computed from `pr1` before the assignment), so the promotion findings above
   are unaffected; but the returned object still carried the merged-away
   candidates, and `pf_candidate_frame()` builds the review sheet from that
   attribute, so a reviewer would have been shown a contender the collapse had
   already resolved. Now an explicit `.pf_setresult()`. The same pattern was in
   `pf_purpose_tiebreak()` — benign there, since it does not change `pairs`, but
   equally wrong.
6. The progress message reported `length(drop_key)` rather than rows actually
   removed, so it announced a drop that had not happened. That is what concealed
   (5): the message said "1 rows dropped" while the returned pair set still had
   both. Now `sum(!keep_rows)`.

(1) and (2) came from the unit tests, (3) from the cascade run, (4) from review,
(5) from a unit test written for something else entirely, and (6) from chasing
(5). Note the shape of (5) and (6): a wrong progress message hid a real defect
for as long as it was believed. **Instrument the thing that happened, not the
thing that was requested.**

## 7. What to do

1. **Ship `use = "substitutable"`, `policy = "operating"`, `rescore = TRUE`.**
   +704 YES, no NO movement, 99% co-located, 85% identical name core.
2. **Never ship `use = c("substitutable", "related")`.** It reports the better
   number by merging different hospitals and cross-subsection pairs. Keep
   `related` for `pf_dyad_annotate()`, which is context and a rollup key.
3. **Label the ordering policy — it is now the blocking item.** It controls 196
   changed EINs among the promotions and 446 promotions of difference between
   policies, on 15 adjudicated cases. This was recommendation 4 of
   `AFFILIATION-FINDINGS.md`; it has gone from cheap-and-worthwhile to
   load-bearing.
4. ~~**Re-run against the unified BMF.**~~ **Done — §5b.** Promotions 9.5% of
   MAYBE, no NO movement, accuracy flat. The dyad table is stable across the two
   references (29,230 against 29,238 substitutable).
5. **Report `dyad_id` alongside the EIN** regardless of the collapse, via
   `pf_dyad_annotate()`. Funder-to-recipient rollups are then correct whichever
   member was picked — the use this data unambiguously supports.
6. **Do not add a name gate to the exclusive-support path** without new
   evidence. It removes a third of the table and no firing edges.
