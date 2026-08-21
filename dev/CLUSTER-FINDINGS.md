# A clustered EIN for grant matching: what linkid's dyad tables can and cannot do

**Short answer: build the table, but as *dyads*, not clusters, and do not expect it
to move the error rate much.** It dissolves 22% of the MAYBE tie band into
single-body decisions and gives an aggregation key that makes
"how much did this funder give to Eagle Ranch" answerable. It forgives 5 of 47
adjudicated errors. It cannot touch the largest population in the tie band,
which turns out not to be operating-vs-arm at all.

Scripts: `dev/cluster-01-build.R` … `dev/cluster-07-samename.R`.
Logs: `dev/CLUSTER-0*.log`. Artefacts: `data-dev/CLUSTER-*.rds`,
`data-dev/CLUSTER-TOP2.csv`, `data-dev/CLUSTER-GIANTS.csv`.

Source: `~/Documents/grants/linkid/out/full/dyad_supported_orgs.csv` (Sch A
Part I line 12g) and `dyad_related_exempt_orgs.csv` (Sch R Part II). The `dyad_`
variants carry `ego_ein`/`alter_ein` already normalised; the `efile_` variants
do **not** carry the filer EIN at all — only `OBJECTID` — so they are unusable
for pair extraction without a separate OID→EIN index. Use the dyad files.

---

## 1. What the pooled tables contain

| | Schedule A | Schedule R |
|---|---:|---:|
| rows, 2009–2024 | 517,414 | 6,311,547 |
| alter EIN present | 99.4% | 96.5% |

The 99.4% is a **selection effect, not a gain**. The raw 2022 table
(`inputs/SA-P01-T01-PUBLIC-CHARITY-STATUS-2022.CSV`) has 89,569 rows, of which
the 2022 build found the supported-org EIN blank on 49%. linkid's dyad table
holds 45,665 rows for 2022 — i.e. it emits a dyad only when both ends have an
EIN and simply drops the rest. Nothing was recovered; the missing half is still
missing, it is just no longer visible as a denominator. Do not read the 99.4% as
an improvement in the input.

Pooled and symmetrised: **566,653 distinct undirected EIN pairs over 174,496
EINs**, of which 78,109 carry a Schedule A direction (supporter → supported).
63% of pairs are seen in 5+ tax years, so the relation is stable, not noise.

## 2. Connected components are unsafe. This is the main design finding.

The obvious implementation — take the transitive closure and hand every EIN a
`cluster_id` — produces this:

| rule | edges | EINs | components | **largest** | % of EINs in components > 10 |
|---|---:|---:|---:|---:|---:|
| all pairs | 566,653 | 174,496 | 35,848 | **66,973** | 47.3% |
| same state | 248,789 | 98,203 | 25,867 | 2,149 | 34.3% |
| same city | 192,861 | 82,978 | 26,470 | 407 | 19.8% |
| same city + 2+ years | 182,617 | 77,450 | 25,105 | 294 | 18.3% |

The largest component under the naive rule holds **66,973 EINs across 56
states** — 38% of every EIN in the graph — chaining The Reinvestment Fund to the
Jewish Community Federation of San Francisco to Glacial Ridge Hospital
Foundation. A grant "correctly" matched to anything inside it would be
unfalsifiable.

Geography does not save it. The largest same-city component is 407 EINs in
Phoenix, merging Florence Crittenton Services of Arizona, the Arizona Medical
Association Foundation and Arizona's Children Association — three unrelated
bodies joined by intermediaries. Dallas gives 290 (Dallas Opera Foundation +
Methodist Hospitals of Dallas + Peruna Holdings), Pittsburgh 244, Philadelphia
225.

**Use direct edges only — a dyad table, no transitive closure.** Two candidates
are interchangeable if one filing names the other, full stop. Every number below
uses that rule; the union-find in `cluster-04-eval.R` is deliberately scoped to
the candidates inside a single grant, so it can never chain through an EIN that
is not itself a candidate.

## 3. Pooling 2009–2024 buys almost nothing over 2022 alone

Measured on the same 927 name-detected arm pairs the affiliation module used:

| subset | pairs | 2022 (prior build) | pooled 2009–2024 | gain |
|---|---:|---:|---:|---:|
| all | 927 | 49% | **52%** | +3 pp |
| same state | 752 | 60% | **64%** | +4 pp |
| same city | 688 | 64% | **68%** | +4 pp |

39 pairs newly linked; 15 lost (the prior build also counted BMF group
exemption, which the dyad tables do not carry).

This confirms the ceiling in `AFFILIATION-FINDINGS.md` §2 is **structural, not a
vintage problem**. For 64% of unlinked pairs neither party files Schedule A or R
in *any* year — public universities, school districts, 990-EZ and 990-N filers.
Fifteen years of data does not create a filing that was never required.

So: recommendation 5 of `AFFILIATION-FINDINGS.md` ("refresh the link tables per
year; pooling should raise the 49%") is now **tested and largely negative**. Pool
anyway — it costs only disk and the EIN-completeness gain in §1 is real — but do
not budget any recall from it.

## 4. What it does to the cascade, at 50k scale

Top two candidates, directly disclosed as related:

| tier | grants | linked | | inside the tie band | linked | |
|---|---:|---:|---:|---:|---:|---:|
| MAYBE | 10,409 | 1,548 | 14.9% | 5,513 | 1,345 | **24.4%** |
| YES | 4,501 | 319 | 7.1% | — | — | — |
| NO | 9,399 | 349 | 3.7% | 6,380 | 329 | 5.2% |

Collapsing every directly-linked candidate inside the tie band:

| tier | grants w/ 2+ in band | mean candidates | mean groups after | tie fully dissolved |
|---|---:|---:|---:|---:|
| MAYBE | 5,517 | 2.89 | 2.52 | **1,224 (22.2%)** |
| NO | 6,380 | 3.89 | 3.73 | 285 (4.5%) |

**1,224 MAYBE grants stop being ties.** That is the concrete operational win: a
review queue item that reads "choose between two candidates" becomes "one body,
confirmed by a filing, pick a reporting convention."

Dollar exposure is modest — the MAYBE grants with a linked top two carry
**\$54.5M of \$2.37B (2.3%)** in the 50k sample. Median \$5,000 vs \$3,000 for
unlinked MAYBE grants, so these are slightly larger than typical but not where
the money is.

## 5. Where it fires, it is precise

Among the 2,216 linked top-two pairs:

| shared content tokens | pairs | share |
|---|---:|---:|
| 3+ | 953 | 43.0% |
| 2 | 932 | 42.1% |
| 1 | 306 | 13.8% |
| **none** | **25** | **1.1%** |

54% share an identical name core. Only 25 pairs share no content token, and
inspection says most of those are *correct* and unreachable any other way:
`NETWORK FOR TEACHING ENTREPRENEURSHIP` / `NFTE ENDOWMENT FUND`,
`AMERICAN CIVIL LIBERTIES UNION` / `ROGER BALDWIN FOUNDATION OF ACLU`,
`SIGHT SAVERS INTERNATIONAL` / `SIGHTSAVERS`,
`STAND UP TO CANCER` / `ENTERTAINMENT INDUSTRY FOUNDATION`.

Gating adds nothing, which is the useful result — the edge is already clean:

| gate | MAYBE | YES | NO | % of edges kept |
|---|---:|---:|---:|---:|
| edge only | 1,548 | 319 | 349 | 100% |
| edge + same state | 1,535 | 319 | 349 | 99% |
| edge + same city | 1,492 | 307 | 323 | 96% |
| edge + ≥1 shared token | 1,537 | 307 | 347 | 99% |
| edge + identical name core | 1,030 | 16 | 158 | 54% |

**Ship the ungated edge.** A same-state gate costs 1% and buys nothing measurable.

The one real hazard is hubs: 11.8% of linked top-two pairs involve an EIN with
degree ≥ 26 in the link graph — `SAINT VINCENTS FOUNDATION` (335),
`ALEXIAN BROTHERS HEALTH SYSTEM` (320), `ST JOSEPH HEALTH SYSTEM` (264). At
degree 1 this is harmless; it is only transitivity that turns a hub into a
67,000-EIN blob, which §2 already forbids.

## 6. The increment over the name rule already shipped

`pf_cluster_arms()` needs no disclosure data at all. On MAYBE top-two pairs:

| | grants | share of MAYBE |
|---|---:|---:|
| `pf_cluster_arms` rule (arm/non-arm split + same state) | 1,155 | 11.1% |
| generous name rule (same core + same state) | 2,148 | 20.6% |
| disclosed edge | 1,548 | 14.9% |
| union | 2,671 | 25.7% |
| **disclosure only — the honest increment** | **523** | **5.0%** |
| name only, no filing confirms it | 1,123 | 10.8% |

5.0% of the MAYBE tier, consistent with the 2.6% all-pairs figure in
`AFFILIATION-FINDINGS.md` §4b (higher here because the top-two basis is
narrower). The disclosure-only pairs are exactly the ones string methods cannot
reach — rebrands, acronyms, and system members:

```
Mayo Clinic Health System-Fairmont   / Mayo Clinic Health System-Lake City
DANA FARBER CANCER INSTITUTE         / DANA FARBER CANCER CARE NETWORK
J N PEW JR CHARITABLE                / PEW CHARITABLE TRUSTS
Mass General Hospital Corp           / Mass General Brigham Population Hlth
KOKUA KALIHI VALLEY COMPREHENSIVE FA / KALIHI VALLEY COMMUNITY FOUNDATION
FCS URBAN MINISTRIES                 / FCS COMMUNITY FINANCE
PLANNED PARENTHOOD GLOBAL            / PLANNED PARENTHOOD ACTION FUND
```

Note that several of these are pairs where "either counts" is **not** obviously
right — Mayo Fairmont and Mayo Lake City are different hospitals, and Planned
Parenthood Action Fund is a 501(c)(4). Relaxing the error definition across a
disclosed edge is not automatically safe; see §8.

## 7. On the adjudicated cases, the relaxation forgives 5 of 47 errors

Joined on the EINs stored in `AUDIT-MAYBE-100.csv` (**not** by rank — the
candidate ordering changed when the reference switched to the unified BMF, so a
rank join to the audit is invalid and produced spurious zeroes on the first
pass).

| verdict | n | top pick linked to the truth / runner-up |
|---|---:|---:|
| CORRECT_TOP | 53 | 11 (21%) — control group |
| NO_CORRECT | 24 | 0 — truth absent from the list, unreachable |
| AMBIGUOUS | 13 | 2 |
| CORRECT_DEEPER | 10 | 3 |

| | |
|---|---:|
| counted as an error today | 47 (47%) |
| forgiven by an "either member counts" rule | **5** |
| error rate after the relaxation | 42 (42%) |

The three CORRECT_DEEPER saves are real and are exactly the target case:
`BOYS AND GIRLS CLUB OF SALEM ... FOUNDATION` / the club,
`BIG BROTHERS BIG SISTERS LONE STAR` / its foundation,
`PLANNED PARENTHOOD GLOBAL` / `PLANNED PARENTHOOD FEDERATION`.

By failure mode, `foundation_vs_operating` is the only one where it works:
**4 of 7** cases have a linked top two. `group_subordinates` 0 of 5,
`related_entities` 0 of 2, `absent` 0 of 13.

21% of already-correct decisions (11 of 53) also have a linked runner-up. Those
stay correct under the relaxation, so there is no direct harm — but it means the
relaxation touches a fifth of the cases where the cascade needed no help, and
any headline accuracy gain will be smaller than the number of edges suggests.

## 8. The finding that changes the priority: AMBIGUOUS is mostly *one org, two EINs*

The 13 AMBIGUOUS cases look like the target population and are not. The largest
group is `group_subordinates`, and inspection shows it is two BMF rows carrying
the **same name for the same body**:

```
Purdue University                  / Purdue University
Texas State University             / Texas State University
Texas Tech University              / Texas Tech University
Univ Of North Carolina At Charlotte / Univ Of North Carolina At Charlotte
MEXICO MEDICAL MISSIONS            / MEXICO MEDICAL MISSIONS
```

**No affiliation disclosure can ever link an organisation to itself.** Sized
across the whole tie band:

| MAYBE top-two pairs, disjoint buckets | grants | share |
|---|---:|---:|
| neither | 6,993 | 67.2% |
| **same normalised name, two EINs** | **1,651** | **15.9%** |
| arm pair — name *and* disclosure agree | 851 | 8.2% |
| disclosure only | 516 | 5.0% |
| name only, unconfirmed | 398 | 3.8% |

The same-name population (15.9%) is **larger than everything the linked-EIN
table reaches (13.2%)**, and only 11% of it carries a disclosure edge. 45% of
those pairs are in the same city — `JOHNS HOPKINS UNIVERSITY` at two EINs,
`MEMORIAL SLOAN KETTERING CANCER CENTER` at two EINs, `VNA CARE NETWORK` at two
EINs — which is a reference-data problem, not a linkage problem. The other 45%
are in different states and are genuine namesakes or federated chapters, where
collapsing would be actively wrong.

## 9. What to do

> **Built. See `dev/DYAD-FINDINGS.md` for the module and its measurement.**
> Shipped as `R/dyads.R`. Two things below changed on contact with the data:
> the substitutability rule needed an *exclusivity* test (a bare Schedule A edge
> gave one EIN 905 substitutable partners — the YMCA Retirement Fund supports
> 907 local YMCAs), and the payoff is larger than §4 implies once the collapse
> runs *before* selection rather than after: **704 MAYBE grants become YES with
> no NO movement**, because `np_tier()` was demoting them on a margin measured
> against themselves.


1. **Build the dyad table, not a cluster table.** `pf_ein_dyads()` returning
   `(ein_a, ein_b, src, direction, n_years, first_year, last_year)`. No
   `cluster_id`, no connected components. §2 is the reason.
2. **Use it for three things, in this order of confidence:**
   - **Tie collapse.** 1,224 MAYBE grants (22.2% of the tie band) stop being
     ties. Highest-value, lowest-risk.
   - **Aggregation.** Report the dyad alongside the chosen EIN so that funder →
     recipient rollups are correct regardless of which member was picked. This
     is the use the data unambiguously supports.
   - **Confirmation.** Convert a name-shape guess into a filed fact for 8.2% of
     the MAYBE tier, and give the audit trail the form and year.
3. **Relax the error definition only where the dyad is a substitution, not
   merely a relation.** Sch A `supporter → supported` and an identical name core
   both qualify; a bare Sch R Part II edge does not — it links Mayo Fairmont to
   Mayo Lake City and Planned Parenthood Global to a c(4) Action Fund. Suggest
   two flags: `dyad_substitutable` (Sch A direction, or identical name core) vs
   `dyad_related` (everything else), and relax only on the first.
4. **Do not pool for recall.** §3. Pool for the `n_years` stability signal and
   for the handful of pairs disclosed in one year and not another, and state
   that the ceiling is non-filing. There is no EIN-completeness gain — §1.
5. **Chase the same-name population instead — it is bigger.** 15.9% of the MAYBE
   tier is two BMF rows with one name, 45% of them co-located. That is a
   reference-side dedup job (or a deliberate "which row is canonical" rule), and
   on this evidence it is worth more than the affiliation work.
6. **Do not expect a headline accuracy jump.** 47% → 42% on the adjudicated 100,
   with 24 of the 47 errors being cases where the truth is not in the candidate
   list at all. The linked-EIN table makes a class of decisions *legitimately
   unnecessary*; it does not make the cascade find more recipients.
