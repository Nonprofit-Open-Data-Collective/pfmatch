# A funder NTEE profile, gated by entropy and persistence

The design is right and it fixes a real flaw in the earlier test. It cannot be
validated in the current dev sample, and the reason is the same random-grant
sampling defect found in `dev/FEATURE-ENGINEERING.md` §4. There is also a
structural limit worth knowing before building it: a sector prior cannot touch
the failure mode that actually dominates.

Scripts: `dev/test-funder-profile.R`, `dev/test-funder-profile2.R`.
Output: `data-dev/FUNDER-PROFILES.csv`.

---

## 1. Why the gate is the right idea

`dev/PURPOSE-MATCH-FINDINGS.md` §2 rejected a crude version of this: across all
foundations with ≥5 matched grantees the top NTEE major group holds 0.333 of
grants against a 0.268 base rate, so "these are diversified givers, not thematic
ones."

That was an **unconditional average**, and averaging over diversified funders
tells you nothing about whether a *concentrated* funder's profile predicts. The
entropy gate is exactly the missing conditional. The earlier finding does not
refute this proposal; it was answering a different question.

## 2. But the concentration is at chance

The earlier comparison was also unfair to the null. A funder drawing k grantees
at random from the population NTEE distribution has an expected top-group share
far above the population base rate when k is small — with 5 draws you *will* see
a modal group around 0.40 no matter what. Comparing 0.333 to 0.145 is not a
comparison.

Simulating the correct null (4,000 draws per k from the observed major-group
distribution):

| portfolio size k | funders | observed median top-share | null median | null p95 | above chance? |
|---:|---:|---:|---:|---:|---|
| 3 | 252 | 0.333 | 0.333 | 0.667 | no |
| 5 | 39 | 0.400 | 0.400 | 0.600 | no |
| 7 | 16 | 0.286 | 0.286 | 0.429 | no |
| 10 | 6 | 0.350 | 0.200 | 0.400 | no |
| 15 | 5 | 0.267 | 0.200 | 0.333 | no |

The observed median **equals the null median** at every size where there are
enough funders to look. Per-funder, against each funder's own size-matched null:

| | genuinely concentrated |
|---|---:|
| portfolios ≥ 5 grants | 19 of 173 (**11%**) |
| portfolios ≥ 10 grants | 5 of 67 (**7%**) |

Against 5% expected by construction at a p95 threshold. So there is a real
excess, but it is small — roughly **6 points above chance**. A gate would fire on
about one funder in ten among those with a usable portfolio, not on the majority.

That is not a reason to abandon it. It is a reason to size the expected payoff
honestly before building it.

## 3. The sample cannot answer the question

| | n | share |
|---|---:|---:|
| YES-matched grants (50k run) | 23,774 | — |
| ...with a usable NTEE major group | 12,097 | 51% |
| foundations with ≥1 usable matched grantee | 8,120 | 100% |
| ...with ≥3 | 507 | 6.2% |
| ...with ≥5 | 173 | **2.1%** |
| ...with ≥10 | 67 | 0.8% |
| **...with ≥5 AND normalised entropy ≤ 0.5** | **3** | **0.04%** |

And on the evaluation side, of 388 adjudicated candidate rows, only **9 grants**
have a filer carrying ≥3 matched grantees elsewhere in the sample; 4 grants at
≥5. There is no test to run.

Two things compound here. The dev file draws random *grants*, so portfolios
arrive shredded — median 1 grant per filer. And NTEE is usable on only 51% of
matched grantees, so a 5-grantee profile needs roughly 10 matched grants behind
it.

### Persistence is arithmetically forced to zero

| | |
|---|---:|
| funders with grants in ≥2 tax years | 1,397 |
| median grants per funder-year | **1** |
| funder-years holding exactly one grant | **92%** |
| median year-over-year grantee Jaccard | 0.000 |
| funders with ≥3 grants in a typical year | 42 |
| ...share showing any repeat grantee | 14% |

A funder-year with one grant can only overlap the next year if that single
grantee repeats. The 0.000 is a property of the sample, not of philanthropy.
Persistence is **untested**, not disproven.

## 4. The structural limit: a sector prior cannot fix the dominant error

Even a perfectly concentrated funder gives a prior over *sector*. That only
separates candidates that differ in sector — and the failure mode that dominates
the MAYBE tier does not.

`EAGLE RANCH` and `EAGLE RANCH FOUNDATION`. `KANSAS FOOD BANK WAREHOUSE` and
`KANSAS FOOD BANK FOUNDATION`. `DALLAS ARBORETUM AND BOTANICAL SOCIETY` and
`DALLAS ARBORETUM FOUNDATION`. These pairs sit in the same sector by
construction — the arm exists to fund the operating entity. A funder profile is
silent on every one of them.

This is the same wall that stopped `nb_major` (`dev/PURPOSE-MATCH-FINDINGS.md`
§5): sector features are undefined or tied on 20.6% of gold grants outright, and
on the hard cases they are tied because the candidates are *relatives*.

## 5. What is worth building anyway, and in what order

The proposal has several components with different prospects. Ranked:

| component | prospect | why |
|---|---|---|
| **entropy / concentration score per funder** | **build** | cheap, and it is the gate everything else needs. Compute it against a size-matched null, not a flat threshold — §2 shows a raw threshold would mislabel most funders. |
| **modal industry / major group** | build | trivial once the profile exists |
| **union of funded codes at L1 / L2 / L2+L3 / full** | build | the multi-granularity list is the right shape: L1 (industry) will be far better populated than L4, and a coarse hit is worth more than a missing fine one |
| **persistence (year-over-year grantee overlap)** | **defer to real data** | untestable here; likely the strongest of the set at full scale, since a repeat grantee is a near-certain identity link |
| **union of division/subdivision text, tokenised** | defer | duplicates the mission-text similarity already measured at +2 grants in 28, and inherits its 50%-fires ceiling |
| **blocking candidates on NTEE match** | **do not** | NTEE is unusable on 33.5% of BMF rows and *more* often missing on large organisations. Blocking on it would silently drop real grantees. Rank, never block. |

The last row matters most. Everything measured on this project says NTEE fails
asymmetrically — `dev/PURPOSE-MATCH-FINDINGS.md` §3 found `has_ntee` has a pair
AUC of 0.425, i.e. weakly predictive of being **wrong**, because the correct
candidate is *more* likely than the distractors to be missing the code. A gate
built on it would cost recall on exactly the large, real grantees the project
cares about.

## 6. Prerequisite

None of this is testable until the dev sample is drawn as **all grants from a
random sample of filers** rather than random grants. That single change makes
funder profiles, entropy, persistence, and funder-repeat all computable at once,
at the same row count and cost. It is now the highest-leverage open item in
`dev/PACKAGE-PLAN.md`.

A reasonable target: 2,000 filers with their complete Part XIV tables. At a
median of roughly 20 grants per filer that is ~40k grants — comparable to the
current 50k file — but with intact portfolios and multiple years per filer.
