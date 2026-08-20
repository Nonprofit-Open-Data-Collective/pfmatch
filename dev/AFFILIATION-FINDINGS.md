# Operating entities and their fundraising arms: can we link them?

Yes, about half the time, and Schedule R does more of the work than Schedule A.
The larger result is that the cascade is currently **anti-correlated** with the
answer on these cases — it ranks the correct member of the pair first only 27%
of the time — so almost any stated policy is an improvement.

Shipped as `R/affiliation.R`. Scripts: `dev/build-arm-links.R`,
`dev/analyze-arm-clusters.R`, `dev/test-arm-ordering.R`.

---

## 1. Isolating the cases

An arm pair is two candidates for the same grant that share a **name core** —
the name with legal suffixes and any support marker stripped, so `EAGLE RANCH
FOUNDATION` and `Eagle Ranch` both reduce to `EAGLE RANCH` — where one carries a
support marker and the other does not, and **both sit in the same state**.

The geography gate matters. Without it, `CATHOLIC CHARITIES FOUNDATION` in
Spokane pairs with `CATHOLIC CHARITIES` in Jackson, Mississippi.

Over the 50k run, restricted to the MAYBE tier:

| | n | share of MAYBE |
|---|---:|---:|
| MAYBE grants | 10,575 | — |
| grants whose candidate list contains an arm pair (name only) | 1,647 | 15.6% |
| ...same state | 1,385 | **13.1%** |
| distinct EIN pairs | 927 | — |
| ...same state | 752 | — |
| ...same city | 688 | — |

And the cascade's current behaviour on them, which is the reason to care:

| the cascade ranks first | n |
|---|---:|
| the **arm** | 1,031 |
| the operating organization | 634 |

It prefers the arm 62% of the time, because `X FOUNDATION` is the longer, more
distinctive string and scores better against a filed name of `X`.

## 2. How often is the pair actually disclosed?

On the 927 name-detected pairs:

| source | pairs linked | rate |
|---|---:|---:|
| **Schedule A** Part I line 12 — the arm names the operating org | 271 | 29.2% |
| Schedule A, reverse direction | 5 | 0.5% |
| **Schedule R** Part II — either direction | 425 | 45.8% |
| BMF same group exemption number | 19 | 2.0% |
| **any of the above** | 457 | **49.3%** |

Schedule R alone catches 165 pairs Schedule A misses; Schedule A alone catches
16. **Schedule R is the better single source for this relation**, which is the
opposite of what the form structure suggests — Schedule A is the one *about*
supporting organizations.

The reason is coverage. Schedule A Part I line 12 only exists if the filer is a
509(a)(3) supporting organization filing a full 990, and even then the supported
organization's EIN is **blank on 49% of rows** (44,026 of 89,569 for 2022).
Schedule R has the related EIN on **97%** of rows and does not require
509(a)(3) status.

### Geography is a validity check, not just a filter

Disclosure rises monotonically as the pairing gets tighter, which is the
evidence that the gate is removing false pairs rather than true ones:

| subset | pairs | Schedule A | Schedule R | either |
|---|---:|---:|---:|---:|
| all | 927 | 30% | 46% | 49% |
| same state | 752 | 37% | 56% | 60% |
| same city | 688 | 39% | 60% | 64% |

### Why the rest are undisclosed

Of the 470 pairs with no link from any source, for **302 (64%) neither party
files Schedule A or Schedule R at all**. This is not missing data to be chased —
it is the population. Public universities and school districts file no 990;
990-EZ and 990-N filers produce no Schedule A Part I line 12 table; Schedule R is
only completed if the filer answered yes to Part IV line 34.

`WICHITA STATE UNIVERSITY FOUNDATION` / `Wichita State University` and
`OKLAHOMA STATE UNIVERSITY FOUNDATION` / `Oklahoma State University` are both in
the unlinked set, and no e-file disclosure will ever link them.

### The BMF affiliation fields are the wrong tool here

`affiliation_code` and `group_exemption_number` describe **group rulings** —
federated chapters — not parent/arm relationships. `0000` means *no group
ruling* and covers 1,521,340 of 1.92M BMF rows. Matching on the raw field
without excluding the sentinel produces a spurious **74%** link rate; the real
figure is **2.0%**.

They are the right tool for the *other* clustering case, exposed as
`pf_group_siblings()`: 403,482 BMF rows across 4,000 genuine group rulings.
Siblings are not substitutes for one another, so that cluster is a **warning**
that the candidate list holds several interchangeable-looking chapters, not an
invitation to collapse them.

## 3. The joint ID table

`pf_cluster_arms()` emits one row per detected cluster with a stable
`joint_id`, both EINs, their ranks, and:

| evidence | direction | n |
|---|---|---:|
| NAME_GEO_ONLY | undirected | 301 |
| SCHED_A | arm_supports_op | 271 |
| SCHED_R | undirected | 164 |
| BMF_GROUP | undirected | 11 |
| SCHED_A | op_supports_arm | 5 |

**Schedule A is the only source that states direction, and it validates the name
heuristic: 271 of 276 pairs have the `... FOUNDATION` row as the supporter.**
The five exceptions are bodies legally named `... FOUNDATION` that are themselves
the operating entity. So `pf_is_arm()` can be trusted to say which member is the
arm even on the 301 pairs with no disclosure at all.

## 4. Ordering: which member received the grant?

Pooling every adjudicated case available — the 100-case MAYBE audit and the 56
text-enriched hard cases — 18 contain a co-located arm pair and 15 have an
adjudicated answer that is one of the two members.

| the recipient was | n | share |
|---|---:|---:|
| the **operating entity** | 9 | 60% |
| the fundraising arm | 6 | 40% |

| rule | accuracy on the 15 |
|---|---:|
| **the cascade today** | **27%** |
| flat "always the operating entity" | 60% (95% CI 32–84%) |
| purpose-conditional (arm if the purpose names a scholarship / endowment / capital campaign) | 67% |

Read this carefully. **The robust finding is the 27%** — the current ranking is
worse than a coin flip on this population, which is a systematic defect and not
sampling noise, since the mechanism is visible (the arm's longer name scores
higher) and the direction is confirmed on 1,031 of 1,665 unlabelled cases.

The 60-versus-67 comparison is **one case wide** and settles nothing. Only one
of the 15 adjudicated cases had a restricted-gift purpose. The purpose-conditional
rule matches the legal reality — a restricted gift is administered by the arm —
but it is a hypothesis to test with a larger labelling round, not a validated
rule. `pf_arm_order()` implements it and says so in its own documentation.

## 4b. Does the affiliation data beat plain name clustering? Mostly no

Section 3 reported counts, not gains. The gain test: over every candidate pair
inside a MAYBE grant (89,384 pairs), which pairs does each method reach?

| | pairs | grants |
|---|---:|---:|
| found by name+geo clustering | 2,229 | 1,452 |
| disclosed by Schedule A or R | 3,775 | 2,033 |
| both | 901 | 872 |
| **disclosed only** | 2,874 | 1,351 |
| name only, no disclosure | 1,328 | 702 |

At first reading that says disclosure nearly doubles coverage: 13.7% of MAYBE
grants from names, plus 12.8% only from disclosure, 24.1% combined. **That
reading is wrong**, because the name rule here is deliberately strict (exact
core equality plus an arm/non-arm split). Scoring the disclosure-only pairs on
stoplisted content-token overlap:

| shared content tokens | pairs | share |
|---|---:|---:|
| two or more - a looser name rule finds these | 2,345 | 82% |
| exactly one | 487 | 17% |
| none - no name rule could ever find them | 42 | 1% |

55% are full containment. **The honest increment over a generous name rule is
529 pairs across 279 grants - 2.6% of the MAYBE tier, not 12.8%.**

Those 279 are real and unreachable by string methods: acronyms and rebrands
(`JEWISH ADOPTION AND FOSTER CARE OPTIONS` and `JAFCO CHILDRENS FOUNDATION`,
`CHALLENGED ATHLETES` and `CAF PROPERTY`), and holding companies
(`NEW YORK UNIVERSITY SCHOOL OF LAW FOUNDATION` and `NYU LANGONE IPA`).

So the affiliation data earns its place on three things that are **not**
coverage:

1. **Direction.** Schedule A states which member is the arm, and confirms the
   name heuristic 271 times in 276. That is what licenses `pf_is_arm()` to be
   trusted on the 301 pairs with no disclosure at all - a name rule alone could
   not have established that.
2. **Confirmation.** It converts a name-shape guess into a filed fact for 64% of
   same-city pairs, which is what an audit trail needs.
3. **Knowing when to stop** - see the next section.

## 4c. Schedule A Part I line 5: the government-parent flag

Line 5 (`SA_01_PCSTAT_COLLEGE_BEN_X`, 170(b)(1)(A)(iv)) is *an organization
operated for the benefit of a college or university owned or operated by a
governmental unit*. It is a **status the filer declares about itself**, not an
inference, and it identifies exactly the population where no disclosure can ever
exist - because the parent is a government agency, not a related nonprofit.

| | n |
|---|---:|
| EINs ticking line 5 nationally (2022) | 2,105 |
| MAYBE-tier arms ticking line 5 | 115 |
| ...of which **no source could link to a parent** | **106 (92%)** |
| MAYBE grants holding a line-5 arm | 209 (2.0%) |

The sample is wall to wall: Wichita State, Missouri State, Buffalo State,
Sonoma State, North Texas, Florida State, Fitchburg State, Northern Michigan,
UW-La Crosse, Eastern Illinois, Toledo.

This resolves the puzzle in section 2. `WICHITA STATE UNIVERSITY FOUNDATION` and
`Wichita State University` is not a disclosure failure - there is nothing to
disclose. And it is the one place where the ordering question has a **legal**
answer rather than a statistical one: the university is a governmental unit and
does not hold the charitable gift, so the foundation received it. The cascade
currently ranks the arm first in 137 of these 209 grants - right by accident 66%
of the time, where it could be right by construction.

### Line 4 does not do the same job for hospitals

Line 4 (`MEDICAL_RSRCH_X`) sounds like the hospital analogue and is not. It is
for medical *research* organizations operated in conjunction with a hospital -
only **384 filers nationally**, and **zero** of the 927 MAYBE-tier arms tick it.
What the arms actually tick, of the 750 that file Schedule A:

| line | n | share of filers |
|---|---:|---:|
| 12 supporting organization | 324 | 43% |
| 5 government college benefit | 115 | 15% |
| 7 publicly supported | 51 | 7% |
| 3 hospital | 1 | 0% |
| 4 medical research | 0 | 0% |

An arm that is publicly supported in its own right ticks line 7 and discloses no
parent at all. That is the structural reason the linkage ceiling sits near 60%.

## 5. What to do

1. **Collapse the pair before selection, not after.** On 13% of MAYBE grants the
   runner-up is the same body as the top pick. Removing it from the tie band
   converts `MAYBE-because-two-candidates-tie` into a single-body decision, which
   is a materially easier review and a candidate for automation once the ordering
   policy is validated.
2. **Report the joint ID alongside the EIN.** For an analyst asking "how much did
   this foundation give to Eagle Ranch", the arm and the operating entity are the
   same answer. The joint ID makes that aggregation correct regardless of which
   EIN the linkage picked.
3. **Do not use `group_exemption_number` without excluding `0000`.**
4. **Label ~100 fresh arm-pair cases**, stratified to over-sample restricted-gift
   purposes, and settle the ordering policy. This is the cheapest remaining
   measurement with a real payoff: it governs ~13% of the MAYBE tier.
5. **Refresh the link tables per year.** Schedule A and R are filed annually; a
   pair disclosed in 2021 may be absent in 2022. Pooling several years should
   raise the 49% and costs only disk.

6. **Use line 5 as a hard rule, not a hint.** When a candidate ticks line 5 and
   the grant names the university, the foundation is the payee as a matter of
   law. 209 MAYBE grants in the 50k run; no labelling needed to justify it.
7. **Do not expect disclosure to expand coverage.** Its increment over a
   generous name rule is 2.6% of the tier. Budget it as a direction-and-audit
   feature, not a recall feature.

## 6. Incidental fix

`R/affiliation.R` would not run inside the installed package: pfmatch has
`data.table` under `Imports` but no `importFrom()` directive, so `cedta()` fails
and every `dt[, x := y]` inside a package function raises *"not data.table-aware"*.
This was already latent in `R/text.R`, `R/enrich.R` and `R/purpose.R`, and was
worked around once in `R/attached.R` by rewriting it in base R.
`.datatable.aware <- TRUE` is now declared in `R/pfmatch-package.R`, which fixes
it for the whole namespace.
