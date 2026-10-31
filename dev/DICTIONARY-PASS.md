# The grant-side dictionary pass

**Built and measured 2026-10-31.** `pf_grant_dictionary()` and
`pf_recover_from_dictionary()` in `R/dictionary.R`; experiments in
`dev/experiment-head-reference.R`, `dev/experiment-grant-dictionary.R` and
`dev/experiment-dictionary-curve.R`; raw results in
`dev/EXP-HEAD-REFERENCE.log`.

## The idea, and the asymmetry behind it

Foundations write recipient names by a convention of their own; the BMF carries
the registered legal name. So a grant the BMF cannot clear may still match a
grant that already cleared. Measured over the 312,306 cleared rows of the
triangulation run that hold both strings:

| | share |
|---|---:|
| a cleared row hits another cleared **grant** rendering exactly | **94.06%** |
| ...hits its own **BMF** name exactly | 47.16% |
| ...grant-exact but **not** BMF-exact | **48.12%** |
| neither | 4.72% |

On *fuzzy* distance the grant side is marginally **worse** — median 0.960 to
the nearest other rendering against 0.967 to the BMF name, and only 31.7% of
distinct renderings are closer to a grant than to the BMF. The advantage is in
**frequency, not similarity**: a common rendering repeats, so an arriving grant
often hits an existing one exactly. It shows up as exact-key recall, not as
better fuzzy matching, and that distinction governs everything below.

Where it pays hardest is the acronym and colloquial name, which the legal name
does not resemble at all:

```
THE YARD                  nearest grant 0.933   BMF 0.000
USO                                     0.789       0.000
THE ARC                                 0.927       0.423
```

## What the pass does, and the one rule that matters

`pf_grant_dictionary()` turns matched grant rows into a reference keyed on the
filer-written name and address. `pf_recover_from_dictionary()` runs the cascade
over what the BMF left unresolved and applies an acceptance rule.

**It is a supplement, never a reference.** A dictionary from one run holds the
EINs that run resolved — 31,721 against the BMF's ~1.9M — and reproduces only
26.7% of the BMF's own YES rows. It runs after the cascade, on what the cascade
could not clear.

**Every EIN in it came from this pipeline**, so resolving against it propagates
the pipeline's own decisions, errors included. That is what `accept` is for.
The default, `"agree"`, promotes a row only where the dictionary's EIN is the
one the BMF already held as its own top candidate — recoverable all along, with
the margin gate refusing to release it. Everything else goes to a queue rather
than into the status frame.

Measured end to end on the benchmark (recipient-identity unit, 4,683):

| | accepted | clear rate | queued |
|---|---:|---|---:|
| `accept = "agree"` | 42 | 61.18% → **62.08%** (+0.90) | 64 |
| `accept = "all"` | 106 | 61.18% → 63.44% (+2.26) | 0 |

The disagreements are the **known affiliate failure**, not a new one — an
organisation against its own foundation or alumni fund, a chapter network
picking the wrong chapter (`YALE UNIVERSITY` → `YALE UNIVERSITY ALUMNI FUND`,
`ANY BABY CAN` → a different chapter). `dev/AFFILIATION-FINDINGS.md` and the
dyad work are about exactly this, so the queue lands in work already underway.

Keying on the name alone does not work and the margin is not close: 727 of
63,310 bare name keys carry more than one EIN, `HABITAT FOR HUMANITY` with 39.
Adding ZIP5 takes that to **0 of 66,425**. The guard that drops an ambiguous
`(name, zip5)` is kept even though real data never trips it, because a silent
collision there attaches one organisation's EIN to another's grants.

## Does it get better at scale? The curve says no, in rate terms

The expectation was large gains once millions of cases have cleared — a 3M-row
dictionary being a substantive database to match against. Tested directly:
one fixed query set (the benchmark's 1,769 unresolved rows), nested random
dictionaries from 2% to 100% of the 369,160-row cleared pool.

| share | rows | renderings | EINs | dict YES | agreeing | points |
|---|---:|---:|---:|---:|---:|---:|
| 2% | 7,383 | 6,240 | 4,933 | 66 | 23 | 0.484 |
| 5% | 18,458 | 13,500 | 9,267 | 77 | 31 | 0.653 |
| 10% | 36,916 | 22,985 | 13,845 | 85 | 34 | 0.716 |
| 25% | 92,290 | 42,613 | 21,155 | 109 | 42 | 0.885 |
| 50% | 184,580 | 63,254 | 26,725 | **126** | 48 | 1.011 |
| 100% | 369,160 | 88,744 | 31,721 | **126** | 50 | 1.053 |

Marginal return, agreeing recoveries per 100,000 new dictionary rows:

```
72.23  ->  16.25  ->  14.45  ->  6.50  ->  1.08
```

**A fifty-fold increase in dictionary rows roughly doubles the recoveries**, 23
to 50, and the last doubling of the dictionary bought **two**. Raw `dict YES`
saturated outright: 126 at half the pool and 126 at all of it.

The mechanism explains it. Recovery needs a cleared rendering *of the same
organisation*, so the quantity that matters is renderings per organisation —
and that grows logarithmically:

| share | EINs | renderings | per EIN |
|---|---:|---:|---:|
| 2% | 4,933 | 6,240 | 1.265 |
| 25% | 21,155 | 42,613 | 2.014 |
| 100% | 31,721 | 88,744 | 2.798 |

Fifty times the rows for 2.2× the renderings per organisation. The tenth
foundation to write `USO` adds nothing.

### The distinction that matters, because the hypothesis is half right

The curve measures the **rate** on a fixed query set, and the rate saturates at
about **1.05 points**, reached by half of a single triangulation run. More
cleared data does not raise it.

But at full scale the *query* side grows too. Roughly 37% of 17.25M grant rows
go unresolved, so about 6.4M candidates rather than 1,769. One point of 17.25M
is on the order of **170,000 grants recovered** — a large absolute number from
a rate that never improves.

So: a 3M-case dictionary **is** substantive, and it will recover a lot of
grants. What it will not do is recover a larger *share* than a dictionary a
tenth its size. Build it for the volume, and do not expect the percentage to
move. The saturation also means the pass can be developed and tuned against a
small dictionary without waiting for a full run, which is the useful corollary.

## The step, and where it sits

Ordered. Steps 1 and 2 are done.

1. ~~Build `pf_grant_dictionary()` / `pf_recover_from_dictionary()` with the
   agreement rule and the ambiguity guard.~~ **Done**, 29 assertions in
   `tests/testthat/test-dictionary.R`.
2. ~~Measure the lift and the scaling curve.~~ **Done**, above.
3. **Adjudicate one queue.** The 64 uncorroborated claims per 4,748 rows are
   the only way to turn an inherited precision into a measured one. They are
   concentrated in the affiliate failure, so run them through the same
   adjudication the MAYBE tier uses rather than inventing a path —
   `dev/ADJUDICATION-PLAN.md`, and the LLM experiment now in
   `dev/ADJUDICATION-EXPERIMENT.md`. *Check:* a precision figure for
   `accept = "all"`, which is currently unknown and is the difference between
   +0.90 and +2.26 points.
4. **Wire it into `pf_run()`** as a stage after the cascade, off by default,
   with the queue surfaced beside the MAYBE sheet rather than merged into it.
   *Check:* `PF_SET=1k` reproduces the baseline exactly with the pass off.
5. **Decide what seeds the production dictionary.** Three options, and the
   choice is not obvious: the triangulation run's cleared rows (what was used
   here, but drawn from multi-rendering addresses, so it over-represents shared
   addresses and probably chapters — which is likely *why* the disagreements
   skew to affiliates); a corpus-representative run's cleared rows; or the
   hand-adjudicated ground truth only, which is tiny but carries no inherited
   error. *Check:* the disagreement rate by seed, since that is the quantity
   the seed should be chosen on.
6. **Re-measure after the full run**, not before. The curve says the rate will
   not move, so this is a confirmation rather than an experiment, and it costs
   nothing once the run exists.

### What this does not need

A bigger dictionary, before step 3. The curve is flat and the binding
constraint is the precision of the uncorroborated half, which is a labelling
problem rather than a data-volume one. That is the same conclusion
`dev/FEATURE-ENGINEERING.md` reached about the accept decision generally:
label-limited, not feature-limited.

## Published as an article

`vignettes/matching-dictionaries.Rmd` puts this pass beside the alternatives it
competes with — the active BMF, the augmented BMF, and matchdb's
`active-observed` and `unified-observed` tiers — on three axes: what each is
made of, what each is worth on the 1k benchmark, and what each costs in
wall-clock time. Two things the article establishes that this note did not:

* **matchdb's `active-observed` tier dominates the augmented BMF** on both axes
  at once — 11.5 min against 23.2 for the same 4,903 grants, for +1.0 point
  (`dev/BENCH-MD-REFERENCE.log`). The dictionary pass is additive on top of
  whichever reference runs, so that result does not compete with this one. It
  is now the default tier for `pf_reference()` and `pf_run()`, replacing
  `unified-observed`; the option `pfmatch.matchdb_tier` still overrides it.
* **Building the dictionary is nearly free**: 24.4 s from 369,260 cleared rows,
  63.9 MB on disk, 0.9 s to read back (`dev/DICT-TIMING.log`). At full scale the
  pass is ~12 h single-stream against ~186 h for the cascade it supplements. Its
  real cost is the ~62,700 queued cases, not the compute.
