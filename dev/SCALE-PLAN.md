# Scaling to the full grant file (~12.5M rows)

## The budget problem

At the measured 50k rate — 61 s of cascade per 1,000 in-scope grants — 12.5M
grants is **~8.8 days** of single-threaded matching. That is the constraint every
decision below answers to.

Cost is concentrated in one place. On the 50k run the four exact passes generated
408k candidate pairs and the single cross-state token pass generated **9.66M** —
96% of the work — to resolve 4,636 queries. Two levers attack it:

1. **Match fewer things.** Grants repeat: the same foundation funds the same
   charity every year, and thousands of foundations fund the same large
   charities. Matching distinct *recipient identities* rather than grant rows is
   pure win — no recall is lost, because rows in a cluster are the same
   organization by construction.
2. **Block on state for the bulk, sweep the residual unblocked.** 99.7% of YES
   matches agree on state, so state blocking costs almost nothing in recall *as
   long as* the non-matches get a second, unblocked pass. That is the user's
   proposal and the data supports it.

## Design principle: what may be eliminated, and what may not

`DEFINITE NO` and `OOS` are never looked at again, so they need a bar that a
sceptic would accept. Everything else that fails a stage becomes `RETRY` and
falls through to a looser stage; only after the last stage does an unresolved
case become `NO` — and `NO` means "queued for internet search", not "not a
nonprofit".

| terminal state | criterion | who sees it next |
|---|---|---|
| `YES` | exact/near-exact name **and** confirmed address, one clear winner | nobody — accepted |
| `MAYBE` | candidates surfaced, no clear winner | human / LLM adjudication |
| `NO` | survived every stage with no usable candidate | internet search |
| `DEFINITE NO` | no name **and** no address — nothing to match on | nobody |
| `OOS` | foreign address | nobody |

Note what is **not** grounds for elimination: an `I` or `GOV` code (24% of those
are organizations — see `AUDIT-FINDINGS.md`), a blank status field, or a
low-scoring candidate set.

## The cascade

Each stage emits `YES` / `MAYBE` / `RETRY`. Only `YES` is pruned from the pending
set; `MAYBE` keeps travelling so later stages can surface a better candidate, and
the best evidence across all stages is selected at the end.

| # | stage | blocking | cost | resolves |
|---|---|---|---|---|
| 0 | **Preprocess + dedup** | — | one-off | OOS, DEFINITE NO |
| 1 | **Deterministic exact** — name+zip5, name+city+state, name↔dba | state | very cheap | YES / RETRY |
| 2 | **Fuzzy in-state** — token IDF + JW within state | state | moderate | YES / MAYBE / RETRY |
| 3 | **Unblocked sweep** — cross-state token, residual only | none | expensive but small N | YES / MAYBE / RETRY |
| 4 | **Alias & repair** — acronym index, truncation prefix, name-in-street recovery | state, then none | cheap, tiny N | MAYBE / RETRY |
| 5 | **Semantic re-rank** — purpose vs NTEE / activity / mission | — | cheap | MAYBE → YES, or ranked MAYBE |
| — | residual | | | NO → internet search |

Stage 3 is where the state-typo cases live (6 of the 10 cross-state YES matches
in the benchmark were 990-PF state-field typos with matching city and ZIP), so
its YES bar must require address corroboration, not name alone.

Stage 5 is **re-ranking only, never candidate generation**. Purpose text is ~⅓
contentless (`GENERAL`, `GOS`, `UNRESTRICTED`) and generating candidates from it
would explode the pair count for little gain. Used inside the tie band it fixed
9 of 10 mis-ranked MAYBE cases in the audit.

## MEASURED (step 1 complete): dedup is NOT the main scale lever

I expected deduplication to be the dominant saving. **It is not.** Measured on
the 100k sample with an accumulation curve (`dev/measure-dedup.R`):

| sample n | exact collapse | fuzzy collapse |
|---:|---:|---:|
| 2,000 | 1.01x | 1.02x |
| 10,000 | 1.03x | 1.07x |
| 25,000 | 1.07x | 1.14x |
| 50,000 | 1.11x | 1.21x |
| 98,786 | 1.17x | 1.32x |

A single-point measurement understates the full file badly, because a 0.8%
sample rarely catches two grants to the same recipient. Fitting `log K ~ log n`
gives a slope of 0.93 (fuzzy), extrapolating to **~1.8x collapse at 12.5M rows**
— roughly 7.1M distinct identities. That is a 125x extrapolation beyond the
measured range and should be confirmed on a real pass, but the direction is
clear: **dedup buys under 2x, and the problem needs ~20x.**

| approach | identities | projected runtime |
|---|---:|---:|
| no dedup | 12,500,000 | 213 h |
| exact dedup (extrapolated) | 9,048,164 | 154 h |
| fuzzy dedup (extrapolated) | 7,055,124 | 120 h |

**So state blocking has to do the heavy lifting**, not dedup. The token pass is
96% of the cost and currently compares against all 1.9M BMF records; blocking it
to one state cuts that pool by roughly 10-20x (less than 50x, because CA/NY/TX
are heavily over-represented on both sides). 120 h ÷ ~10 is a tractable overnight
job; that is the combination to aim for.

Dedup stays in the plan, but for the **second** reason rather than the first:
cluster propagation is a recall gain that costs nothing once clusters exist, and
it is the cheapest recall available.

## Deduplication — implemented, and the trap it walks into

Two levels, cheapest first:

**Exact dedup** on the normalized key `(name_key, street_key, zip5)`. A hash
group-by; collapses annual repeat grants and multi-foundation giving to the same
large charities.

**Fuzzy dedup** among the *surviving distinct keys only* (a much smaller set),
blocked by `zip5` (falling back to `state`), clustering names by Jaro-Winkler.
This absorbs `ST JUDE'S` / `ST JUDES` / `ST JUDE CHILDRENS RESEARCH HOSP`.

The payoff is bigger than the arithmetic suggests. Because a cluster is one
organization by construction, **a match found for any member propagates to every
member**. A hard variant (truncated, misspelled, acronymic) inherits the EIN
found for an easy variant in the same cluster. That is a recall gain, not just a
cost saving — and it is the cheapest recall we can buy.

### The trap: npmatch's `name_key` cannot be the identity key

The first implementation merged `UNIVERSITY OF MASSACHUSETTS AMHERST` with
`UNIVERSITY OF MASSACHUSETTS AMHERST FOUNDATION`. The cause is not the fuzzy
threshold — it is that npmatch's `name_key` **strips `FOUNDATION` as a legal
suffix**, so the two names are already identical before any comparison happens.
Exact dedup alone would have merged them.

That is correct behaviour for *matching* (both should be candidates) and wrong
for *identity* (they are two EINs). Merging them locks one EIN across every row
in the cluster — an unrecoverable error, and precisely the foundation-vs-operating
ambiguity the MAYBE audit found in 7 of 100 cases.

`pf_dedup()` therefore builds its own identity key that splits the suffix list in
two:

* **corporate** suffixes — `INC`, `CORP`, `LLC`, `LTD`, ... — stripped. Same
  entity in a different wrapper.
* **affiliate** suffixes — `FOUNDATION`, `FUND`, `TRUST`, `ASSOCIATION`,
  `ENDOWMENT`, `ALUMNI`, `FRIENDS`, ... — **retained**, and a difference in the
  affiliate-suffix set vetoes a fuzzy join outright.

Verified: `American Heart Association` / `... Inc` merge; `Denver Art Museum` /
`... Foundation`, `Sierra Club` / `... Foundation`, and `UMass Amherst` / `...
Foundation` all stay apart. Fuzzy clustering also carries npmatch's hard veto
predicates, so `Local 32` never merges with `Local 45`, nor `First` with
`Second`.

Result on 98,786 in-scope rows: 74,671 identities, 85.8% singletons, largest
cluster 201 rows (`ST JUDE'S CHILDREN'S RESEARCH HOSP` and its spelling
variants). Spot-checking the ten largest found no over-merges.

## Maximizing cheap matches, minimizing false negatives

The two goals pull in different directions and the cascade separates them:

- **Cheap matches** come from stages 1-2 under state blocking, over deduplicated
  identities. This is where the volume is and it should stay conservative: a YES
  here must be exact-name-plus-address.
- **Recall** comes from never terminating early. Concretely: prune only `YES`;
  keep `MAYBE` alive through later stages; let `RETRY` fall all the way through;
  and make `DEFINITE NO` provable rather than inferred.
- **Cluster propagation** is the highest-leverage recall move available, because
  it costs nothing extra once dedup exists.
- **The known name-resolution defects** (acronyms, aliases, truncation) are
  stage-4 work and are the difference between "not in the BMF" and "we could not
  spell it".

## Ordered execution

1. ~~**Dedup module + measurement**~~ — **done.** `R/dedup.R`, measured in
   `dev/measure-dedup.R`. Verdict: ~1.8x collapse at full scale, not the main
   lever; kept for cluster propagation. Identity-key trap found and fixed.
2. ~~**State-blocked stages 1-2**~~ — **done**, and the result was not what the
   plan predicted. See "Measured: state blocking" below.
3. Unblocked residual sweep (stage 3) and the YES bar for it.
4. Stage 4 alias/repair passes.
5. Stage 5 semantic re-rank; decide whether real mission text (990 Part I/III
   from the GTDC "990 Missions" dataset) is worth acquiring over BMF NTEE alone.
6. Full-file run with checkpointing.

---

## MEASURED (step 2 complete): state blocking, and where the cost really is

Four configurations on the same 5,000 grants (`dev/compare-sweeps.R`):

| config | candidates | secs | YES | MAYBE | NO | cand/YES |
|---|---:|---:|---:|---:|---:|---:|
| state-free baseline | 970,889 | 235.3 | 2,819 | 1,043 | 1,058 | 344 |
| staged, no sweep | 454,887 | 157.9 | 2,828 | 760 | 1,332 | 161 |
| **staged, lean sweep** | **482,710** | **159.3** | **2,832** | 1,007 | 1,081 | **170** |
| staged, full sweep | 1,169,090 | 294.2 | 2,832 | 1,053 | 1,035 | 413 |

**`lean` is the configuration to use: 1.48x faster, 2.0x fewer candidates, and
13 *more* YES matches than the state-free baseline.** It loses exactly one
baseline YES — `BRISTOW COMMUNITY CENTER` OK matched to Bristow **IN**, which
was a false positive, so that is a precision gain too.

### The unblocked token sweep does not pay for itself

The plan assumed stage C was the price of safety. It is not:

* `C3-token-any` generated **686,380 candidate pairs — 59% of the entire run —
  and produced ZERO additional YES matches.** Its only product is MAYBE
  candidates for adjudication (+46 over lean).
* The four YES matches stage C did contribute came from the cheap exact pass
  `C1`, and **three of the four are the known cross-state false positives**
  (`UNBOUND` MO→KS, `FIRST PRESBYTERIAN CHURCH` IA→NC, `PATTERSON VOLUNTEER FIRE
  DEPARTMENT` LA→NC) — common names matched in another state on city name alone.

The reason is that the residual reaching stage C is dominated by queries that
match *nothing anywhere*. Blocking earlier stages does not shrink it; those
queries simply fail in-state and then fail again cross-state, at full price.

### Why the genuine cross-state cases never needed a sweep

Pass `A1` blocks on **name + ZIP5 with no state key at all**. Every one of the
"the filer typed the wrong state" cases from the benchmark — Temple Bat Yahm,
Student Mobilization, Harvesters, Second Chance Rescue, Congregation Khal
Chasidim, Mercy House — has a correct city and ZIP, so `A1` catches them for
8,285 candidates total and 1,834 YES. That single pass is the most efficient in
the whole cascade (4.5 candidates per match) and it does the job the expensive
sweep was supposed to do.

### The remaining lever, and why it is declined

`B2-token-concat` (adjacent-token compounds) costs 223,151 candidates — 46% of
the lean cascade — for 48 YES. Dropping it is **1.93x faster**, but of those 48,
**40 fall to NO rather than MAYBE**: real, correct matches lost outright
(`DONORSCHOOSE`, `GEORGIA FORESTWATCH`, `CRITTERHOUSEKC`, `KIDSPAK`,
`WIPEDISEASES FOUNDATION`). Since the stated goal is maximising recall, `concat`
stays **on by default** and is exposed as `pf_staged_passes(concat = FALSE)` for
a fast first pass over the full file.

### Revised runtime projection

Over ~7.0M identities (12.5M grants after ~1.8x dedup):

| config | s/1k | single-threaded | 16-way parallel |
|---|---:|---:|---:|
| state-free baseline | 47.8 | 93 h | 6 h |
| **staged lean** | **32.4** | **63 h** | **4 h** |
| staged lean, no concat | ~16.8 | ~33 h | ~2 h |

An overnight job with modest parallelism. Note the honest total: state blocking
delivered ~1.5x, not the 10-20x the plan hoped for, because the expensive pass is
driven by unmatchable queries rather than by reference size.

### Carried forward: a scoring defect this exposed

The surviving cross-state false positives all score exactly **0.80**, which is
`0.6 × name(1.0) + 0.4 × city(0.5)`. npmatch's hierarchical geo score credits a
**city-name match without requiring state agreement**, so "Patterson LA" earns
full city credit against "Patterson NC". Gating city (and ZIP3) credit on state
agreement would remove this false-positive channel entirely. That is an
`npmatch` scoring change, not a blocking change, so it belongs with the stage-5
work rather than here.

### 50k confirmation

The staged `lean` cascade re-run on the 50,000-grant file:

| | state-free baseline | staged lean |
|---|---:|---:|
| candidates | 10,070,450 | **5,294,623** |
| cascade | 2,900 s | **1,653 s** |
| **per 1,000 in-scope** | **61.4 s** | **33.5 s** |

**1.83x faster per unit of work** — better than the 1.48x seen at 5k, because the
in-state token pass scales better than the unblocked one (B1 used 2.14M
candidates where the baseline's cross-state token pass used 9.66M).

Two cautions on reading the rest of that table. First, the 50k baseline predates
the apostrophe fix and the scope change, so its YES count is **not** a clean
comparison — the clean blocking-only comparison is the 5k one above (2,819 →
2,832 YES). Second, `NO` rose from 11,414 to 13,052 while `OOS` fell from 2,775
to 614: that is the scope change working as intended. 1,602 of the new NO rows
are individual-coded grants that used to be discarded unexamined and are now
visible as internet-search candidates.

Outcome at 50k: **50.9% YES, 21.8% MAYBE, 26.1% NO, 1.2% OOS**; 51.5% YES and
73.6% YES+MAYBE on attempted grants. State agreement on YES holds at 99.8%.

### B2 gets worse with scale — revisit before the full run

At 5k, `B2-token-concat` cost 223k candidates for 48 YES (4,650 per match). At
50k it cost **2,709,785 candidates for 387 YES — 7,000 per match, and 51% of the
entire cascade.** Efficiency degrades as the file grows, because compound tokens
are rare and the pass mostly re-scans the same hard residual.

`B1` + `B2` together are 92% of all candidate pairs at 50k. Dropping `B2` would
roughly halve runtime again (~17 s/1k, ~33 h for the full file single-threaded),
at a cost of ~1.5% of matches of which ~83% fall to NO rather than MAYBE.

That trade looks different at 12.5M than at 5k and should be decided with a
measurement at 100k before committing, not assumed from the 5k result.

---

## MEASURED (step 4 complete): alias and repair passes

`R/recover.R` adds two blocking passes plus one data repair, appended after the
staged cascade and running only on its residual.

### D1 — acronym index

The BMF holds spelled-out legal names, so `NJOP` and `NATIONAL JEWISH OUTREACH
PROGRAM` share **no token at all** and blocking never surfaces the pair. The fix
is to inject each reference record's initials into its token string as synthetic
tokens, so ordinary IDF token blocking can find them.

Filers elide function words inconsistently, so one initialism per record is not
enough. Three tiers are generated and de-duplicated:

| tier | drops | `Food In Need Of Distribution` |
|---|---|---|
| `all` | nothing | `FINOD` |
| `core` | OF / THE / AND | **`FIND`** |
| `content` | all function words | `FND` |

The middle tier is not decoration: `F.I.N.D.` is that name with only "of"
dropped, and neither outer tier produces it. Adding it was what made `FIND`
reachable.

Initialisms are highly discriminating — **81.7% are unique to a single
organization**, median 1 record per initialism — so they carry high IDF and
justify a pair on their own, while the existing `max_ref_freq` / `min_pair_idf`
machinery prunes the common ones.

### D2 — truncation prefix

First cut keyed the 18-character prefix on **state** and produced exactly one
match in 5,000 grants: `AMERICAN ASSOCIATION OF PRO-LIFE OBSTETRICIANS` matched
to `AMERICAN ASSOCIATION OF ZOO KEEPERS`, which share that prefix. Re-keyed on
**ZIP5** instead — mirroring pass A1 — the false positive disappears.

The truncation flag also had to be corrected. The two name fields have different
width caps (`SIGOCPYRPNAM` 35 characters, `SIGOCPYRBNBN1` 75), and a single
35-character rule flagged **15%** of names as truncated. Per-field caps give
**1.0%**, with unambiguous examples (`GIRLS INCORPORATED OF WESTCHESTER C`,
`MULTIPLE MYELOMA RESEARCH FOUNDATIO`).

### Result on 5,000 grants

| | lean | lean + stage 4 |
|---|---:|---:|
| candidates | 482,841 | 562,192 |
| cascade | 200.3 s | 230.9 s |
| YES | 2,832 | **2,838** |
| MAYBE | 1,006 | **1,025** |
| NO | 1,082 | **1,057** |

**25 grants moved out of NO (6 to YES, 19 to MAYBE) — 2.3% of the tier — with
zero regressions**, for +16% candidates and +15% runtime. Per-pass cost: D1
79,292 candidates, D2 just 264.

The named audit failures are recovered: `CSCOE` → Catholic Schools Center of
Excellence, `NJOP` → National Jewish Outreach Program, `OPB FOUNDATION` →
Oregon Public Broadcasting, all with ZIP corroboration.

An unplanned benefit: the initials token also acts as a fuzzy blocking key for
near-miss spellings, which is where most of the six new YES matches came from —
`HOME FOR HEARTS` → `HOMES FOR HEARTS`, `DEFENDER OF WILDLIFE` → `DEFENDERS OF
WILDLIFE`, `Community Foundation For MS` → `COMMUNITY FOUNDATION FOR
MISSISSIPPI`, all ZIP-confirmed.

Acronym matches land in MAYBE rather than YES by design — an acronym is a lossy
encoding and npmatch caps such recoveries below the auto-accept threshold. That
is the correct outcome: they are exactly the cases a reviewer should see.

### What stage 4 does not fix

`MCEE` → `Council on Economic Education in Maryland` is unreachable: the filer
wrote the words in a different order (*Maryland* Council on Economic Education),
so no initialism of the BMF name produces it. Brand-vs-legal-name cases
(`WYEP-FM` → Pittsburgh Community Broadcasting, `Project Turnabout` → Reverence
for Life and Concern for People) are likewise out of reach — those need an alias
source the BMF does not carry.

### D3 — name typed into the street field

`pf_recover_name_from_street()` promotes the street value to the name when the
name is blank or a single-character placeholder and the street looks nothing
like a street. Fires on 2 rows per 5,000 (`Society of Jesus NY Province`,
`Westford Conserv Trust`). A correctness guard, not a recall lever.

---

## MEASURED: the B2 decision, settled at 100k

| | concat ON | concat OFF |
|---|---:|---:|
| candidates | 10,350,144 | 5,028,917 |
| cascade | 3,363 s | 1,545 s |
| YES | 50,980 | 50,191 |

Dropping B2 is **2.18x faster** for **-789 YES (1.55%)**, of which **584 fall to
NO** and 207 to MAYBE. The ratio is stable across scales (1.7% at 5k, 1.55% at
100k), so this is a real, predictable trade rather than sampling noise.

**Decision: keep B2 on.** At 12.5M rows the off setting would forfeit roughly
73,000 genuine matches — `SHEPHERD COMMUNITY CENTER` / `SHEPHERD COMMUNITY`,
`OPEN SKY POLICY INSTITUTE` / `OPENSKY POLICY INSTITUTE`, `COMMUNITY FOODBANK OF
NEW JERSEY` / `COMMUNITY FOOD BANK OF NEW JERSEY`. The stated goal is recall.
`pf_staged_passes(concat = FALSE)` remains available for a fast first pass.

---

## MEASURED (step 5): semantic re-ranking mostly does not work

**I over-claimed this one and the measurement corrected me.** The audit note said
"NTEE decisive in 9 of 10 mis-ranked cases". That was true of what a *human*
could do with the NTEE column in front of them. It is not what an automatic
text-overlap re-ranker can extract, and I conflated the two.

Evaluated against the 100 hand-adjudicated MAYBE cases (63 of which have a known
correct candidate, 53 already ranked first by npmatch):

| | correct of 63 | fixed | broken |
|---|---:|---:|---:|
| baseline (npmatch's pick) | 53 | — | — |
| + semantic re-rank | **54** | 2 | 1 |

**Net +1.** And identical across every weight (0.02–0.30) and tie band
(0.05–0.50) tested — the semantic term is either decisive or exactly zero, so
tuning it does nothing.

Three real bugs surfaced on the way, each worth recording:

1. **Wrong query side.** Comparing *purpose* against mission text scored ~0 for
   55% of rows; purpose is dominated by filler. The signal is in the **recipient
   name** (`BOCA RATON COMM HOSP` vs activity text `Hospital`). Fixing this took
   the NA rate from 55% to 6%.
2. **Stem length.** A 5-character stem gives `HOSP` vs `HOSPI` — no match. Four
   characters fixes the single most quotable case in the whole audit.
3. **Wrong baseline in the harness.** Tiebreaking on score rank silently
   overrode `np_select()`'s own high-tie rule (which uses full-name similarity),
   manufacturing five "broken" cases that had nothing to do with semantics — it
   was demoting `SIERRA CLUB FOUNDATION` back to `SIERRA CLUB`. The re-ranker now
   keys its tiebreak on `is_top_pick`.

### Why the other 8 cannot be fixed by re-ranking

The correct candidate is usually **far outside any sane tie band**:
`SUMMIT COUNTY HISTORICAL SOCIETY`'s correct match scores 0.38 against a top
candidate at 0.741. No tiebreak reaches that; only a scoring or blocking change
would. The rest need *structured* detectors rather than text similarity:

| case | what it actually needs |
|---|---|
| `SIGMA GAMMA` | self-match guard — **built, see below** |
| Planned Parenthood ×2 | truncation-aware comparison on the **reference** name |
| BBBS Lone Star, UW | foundation-arm detector (activity text "Gifts grants or loans to other organizations") |
| Summit County, NCTA | correct candidate scored far too low — scoring, not ranking |

**Superseded.** While this was being written, `R/purpose.R` + `R/text.R` and
`dev/PURPOSE-MATCH-FINDINGS.md` were built independently and cover the same
ground with much better evidence: real Form 990 Part III mission and program
text rather than NTEE proxies alone, measured coverage across all 1.92M BMF
records, and a 794-grant silver set alongside the 63-case gold set. They reach
the same verdict from a stronger position - precise but rarely applicable,
~+2 grants in 28, belongs in the tie band and not in the score.

**Use `pf_purpose_tiebreak()`.** The `semantic.R` / `eval-semantic.R` written
here have been moved to `dev/superseded/` so the earlier measurement is not
lost, but they should not be maintained. The three implementation bugs recorded
above are still worth knowing - any future text-comparison work can hit all
three.

### Self-match guard — small, and unambiguously right

`pf_drop_self_matches()`. A 990-PF grant is a payment *from* the filer, so the
filer's own EIN cannot be the recipient. Fires on 22 of 4,920 queries (0.4%):
fixes `SIGMA GAMMA ASSOCATION` exactly as the audit predicted, and removes three
YES matches that were foundations matched to themselves. Those three are a
**precision gain**, not a recall loss — they were wrong answers.

---

## MEASURED (step 6): checkpointed full-file driver

`pf_run_batches()` + `dev/run-full-file.R`. Batches over deduplicated identities
(never splitting a cluster), writes each batch to disk **only after it succeeds**,
and skips completed batches on restart. A failed batch leaves no checkpoint, so a
re-run retries exactly that batch. The reference bundle and the stage-4 recovery
keys are built once and shared across all batches.

Verified end to end on 5,000 grants in 4 batches, then verified resume by
deleting one checkpoint and re-running: only the missing batch recomputed, with
identical output.

```
per-GRANT-ROW outcome after cluster propagation
  YES    2,830  (56.6%)
  MAYBE  1,025  (20.5%)
  NO     1,065  (21.3%)
  OOS       80  ( 1.6%)
```

Run it with:

```bash
PF_GRANTS='^100k_grants\.csv$' PF_BATCH=25000 PF_OUT=data-dev/fullrun \
  Rscript dev/run-full-file.R
```
