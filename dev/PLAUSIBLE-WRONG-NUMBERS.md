# Plausible wrong numbers

Written 2026-11-01, after the fourth one. Tracked as issue #15.

The dominant defect class on this project is not a crash. It is a number that
is wrong and looks right. Seven have been caught so far; none of them stopped a
run, every one of them would have been published, and four of the seven made
the pipeline look *better* than it was.

This note exists because the fourth one was found the same way as the first
three — by chance, while reading output for another reason — and because the
instances have a common shape that can be defended against deliberately.

## The catalogue

| | reported | true | why it read as fine |
|---|---|---|---|
| 1 | deep-arm cost, 25% low | `adj_cost()` charged input + output only | `usage.input_tokens` **excludes** cached tokens, so the sum looks complete |
| 2 | deep-arm cost, 66% low | `C_DEEP` hand-copied from a log printing cache *reads*, not *writes* | a search turn re-caches a growing prefix: 537,198 write tokens at \$5.00/MTok, 40% of that arm's bill |
| 3 | 0.90 recovers **7** of 33; margin **+0.002**; **1** false offer | 6; **−0.004**; **0** | computed with an approximate normalizer standing in for `np_normalize()`, and with the placeholder filter in a different state than the prose described |
| 4 | **159** identities moved | **28** | baseline read from `pf_status()`, comparison from the result frame — two conventions for "no candidate" |
| 5 | "Opus recoverable: **0 of 91**" | 33 of 91 | `merge(suffixes=)` renames only *shared* columns, so `a$ein_in_ref` was `NULL` and `sum(NULL %in% TRUE)` is `0` |
| 6 | a false-positive-risk table over **91** cases | 57 | filtered `bmf_expectation != "IN_BMF"`, a level that does not exist — so the test matched everything, including the true recoveries |
| 7 | an empty stratum | 91 rows | filtered `stratum == "A"`; the label is `A-estimation` |

Numbers 1 and 2 are recorded in `dev/ADJUDICATION-EXPERIMENT.md` §"Two cost
corrections". Numbers 3 and 4 are in `dev/NO-TIER-EXPERIMENT.md` §9. Number 5
carries an in-code note at `dev/adjudicate-15-no-arms.R:87`. Numbers 6 and 7
are recorded here for the first time.

## Why this class is harder than a crash

**A crash stops the run. A wrong number gets committed.** Every one of these
produced a well-formed table that rendered, passed review and read as a result.

**Four of the seven flattered the pipeline** (1, 2, 3, 4). That is the
dangerous subset, because a figure showing the work going well invites less
scrutiny than one showing it going badly. Number 4 is the clearest case: a
regression reporting 159 identities moved where 28 had does not look broken, it
looks like the pass is doing more than it is. Numbers 5 and 6 ran the other way
and were caught quickly *because* they looked bad — 5 within minutes, since an
arm recovering nothing at all is not a believable result.

**The language helps them along.** Most of these are R behaving as documented:

* `sum(NULL %in% TRUE)` is `0`, not an error — a mistyped column name becomes a
  zero count (5)
* `x != "LEVEL_THAT_DOES_NOT_EXIST"` is `TRUE` for every row — a filter on a
  misremembered level silently selects everything (6)
* `d$typo` is `NULL`, not an error (5)
* `merge(suffixes=)` renames only the columns both frames carry (5)
* a factor comparison against a wrong label yields an empty frame, not a
  complaint (7)

None of these is a bug in R. All of them convert a typo into a plausible
number instead of a stack trace.

**Two conventions for one concept is the other mechanism** (1, 2, 4). Tokens
vs tokens-plus-cache; `pf_status()`'s tier vs the result frame's tier. Both
sides of each pair are correct for their own purpose. The defect appears only
where the two meet, which is exactly where nobody is looking.

## What catches them

Ordered by how much each has actually caught here, not by how good it sounds.

**1. Compute every published figure; retype none.** Number 2 happened because a
constant was copied from a run log. `dev/adjudicate-18-layer-costs.R` exists so
that the layer-cost figures in `dev/DEVELOPMENT-PLAN.md` §"Phase 4b" cannot
drift from the runs they describe — it prints all of them, with its inputs
cited at point of use. A figure that cannot be re-derived by running a file is
a figure nobody can check.

**2. Assert the column, don't read it.** `stopifnot(!is.null(a$ein_in_ref_o))`
at `dev/adjudicate-15-no-arms.R:92` converts the silent `NULL` of number 5
into a stop. One line, and it is the only reason that join is trustworthy now.

**3. Assert the level before filtering on it.** Numbers 6 and 7 are the same
mistake in two directions — a filter against a label that does not exist,
matching everything or nothing. `stopifnot(all(x %in% known_levels))` or a
printed `table()` of the column before use catches both.

**4. Read the denominator.** Number 6 was caught by nothing cleverer than
noticing that a table of "the cases the BMF should not hold" had 91 rows when
that population is 57. The denominator is the cheapest integrity check
available and it is free on every table.

**5. Name the convention on both sides of a comparison.** Number 4's fix is one
sentence of code and ten of comment: both sides now read the result frame, and
`dev/adjudicate-16-fuzzy-regress.R` says why. Where two representations of the
same quantity exist, a comparison has to state which it uses.

**6. Re-check a guard independently of the guarded code.** `pf_fuzzy_recover()`
asserts that no YES identity moved; the regression script re-derives the same
check from the two result frames. A guard that only the guarded code tests is
not a guard.

**7. Prefer a measurement that can come out wrong.** The margin column in §9
goes to **−0.004**, and that negative number is the finding — the cutoff sits
*below* the collision it was supposed to clear. Had the column been defined as
`max(0, ...)` or phrased as "comfortable / tight", the 0.85 arm would have read
as merely tight rather than inverted. A metric that cannot embarrass the design
will not.

**8. Ask whether the number flatters, and look harder when it does.** This is
the weakest of the eight because it is a habit rather than a mechanism, but it
is the one that would have caught number 4 on the first run instead of the
second.

## What this does not claim

Seven instances over one project is not a base rate, and nothing here says how
many remain uncaught — by construction, that is the one number this note
cannot provide. The honest summary is narrower: **every defect of this class
found so far was found by reading output, not by a test failing**, and the
practices above are an attempt to shorten that gap rather than a demonstration
that it has closed.

Two classes of figure in this repo remain unguarded by any of the eight and
should be read with that in mind:

* **Corpus projections.** The Phase 4b dollar figures multiply a
  4,868-identity benchmark by roughly 940. The 3.72x dedup collapse underneath
  them is measured rather than extrapolated — an earlier 1.8x estimate from a
  100k sample was wrong by a factor of two — but the tier shares are an
  assumption the full run will test.
* **Anything measured once.** The accuracy denominators behind the adjudication
  recommendations are 27 and 91 cases. The *ordering* of the arms is the claim;
  the size of each gap is not.

See also `dev/CODE-AUDIT.md` for defects of the ordinary kind, and
`dev/BASELINE-2026-10C/MANIFEST.md` for what the benchmark does and does not
measure.
