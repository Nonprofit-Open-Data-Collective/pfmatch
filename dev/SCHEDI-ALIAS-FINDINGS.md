# Form 990 Schedule I as an alias source

**Verdict: yes, build this.** It is the largest single recall opportunity found so
far, it reaches failures no string metric can reach, and its error rate is
controllable by a dial that is already in the data.

`dev/AUDIT-FINDINGS.md` §1 concluded that the residual NO tier "needs an alias
source the BMF does not carry." Schedule I is that source.

---

## 1. What it is and why the register matches

Schedule I Part II is where a non-PF 990 filer lists every grant it made to a US
organization or government: recipient **name**, **address**, and **EIN**. That is
the same speech act as 990-PF Part XIV — a grantmaker writing down who it paid —
so the name representations are drawn from the same distribution as the queries
we are trying to match.

The BMF gives one *legal* name per EIN. Schedule I gives many *observed* names
per EIN, written by third parties who were looking at a cheque stub or a grant
agreement.

Built by `dev/build-schedi-db.R` from the NCCS `efile_v2_2` extracts, 2009-2024
(`~/Documents/grants`, 3.5 GB raw, 2.0 GB DuckDB):

| | |
|---|---|
| grant rows | **8,986,064** |
| filers | 17k (2010) rising to ~50k (2023) |
| rows with a well-formed 9-digit EIN | 8,377,563 (**93.2%**); 608,501 blank, **0 malformed** |
| alias rows, distinct `(ein, name, city, state, zip5)` | **2,454,949** |
| distinct EINs | **794,209** (~41% of the BMF — and the 41% that receives grants) |
| distinct normalized names | 1,464,115 |
| names mapping to exactly one EIN | 1,320,784 (**90.2%**) |

**Use `efile_v2_2`, not `efile_v2_1`.** Same schema plus a `RecipientTable`
column, but ~10x the rows at identical bytes-per-row (641k vs 66k grants in
2024). `v2_1` appears to be a partial or superseded extract.

---

## 2. Precision: corroboration is a clean dial

The test that had to pass first. On grants the cascade already resolved as YES —
where we have a confident answer to check against — does the alias table agree?

**9,417 YES grants have an exact alias hit. Overall agreement: 95.6%.**

And it decomposes almost perfectly along the number of *distinct filers* who
wrote that name for that EIN:

| corroboration | grants | agrees with the accepted EIN |
|---|---|---|
| 1 filer | 1,506 | 86.1% |
| 2-4 filers | 2,406 | 95.4% |
| 5-19 filers | 3,842 | **98.0%** |
| 20+ filers | 1,663 | **99.0%** |

That is the whole risk-management story in one table. `n_filers` is not a
heuristic — it is an independent-observation count, and it behaves like one.
82% of the 2.45M aliases are single-filer and therefore indistinguishable from
that filer's typo; the corroborated ~440k are as reliable as the BMF itself.

---

## 3. Recall: it reaches the tier nothing else reached

Exact normalized-name lookup against the 50k benchmark:

| tier | grants | alias hit | rate |
|---|---|---|---|
| YES | 25,436 | 9,417 | 37.0% |
| **NO** | 13,047 | **2,364** | **18.1%** |
| MAYBE | 10,898 | 2,349 | 21.6% |
| OOS | 291 | 9 | 3.1% |

The 37% on YES is itself the evidence for the register argument: more than a
third of *already-matched* recipient names appear verbatim in Schedule I.

Of the 2,364 NO-tier hits:

* 74.5% point at an EIN present in the BMF
* 66.9% are corroborated by more than one filer
* **52.2% satisfy both** — about **1,234 grants**, i.e. **9.5% of the NO tier**

NO is 22.8% of all grants, so the conservative estimate is **+2.2 points on the
overall match rate**, and the full alias hit rate would be roughly double that.
For comparison, the entire grant-purpose investigation was worth +1 grant in 63.

---

## 4. What it actually fixes

These are the NO-tier names the alias table resolves, with the filer count:

| as the foundation wrote it | BMF legal name | filers |
|---|---|---|
| `INJURED MARINE SEMPER FI FUND` | Semper Fi & Americas Fund | 115 |
| `SHATTERPROOF` | Shatterproof A Nonprofit | 68 |
| `NATIONAL CENTER FOR TRANSGENDER EQ…` | Advocates For Trans Equality Education F… | 66 |
| `USA FOR UNHCR` | United States Association For Unhcr | 65 |
| `MAZON A JEWISH RESPONSE TO HUNGER` | Mazon Inc A Jewish Response To Hunger | 64 |
| `VOTEORG` | Vote | 59 |
| `WORLD PEDIATRIC PROJECT` | World Pediatrics | 55 |
| `CAMP KESEM` | Camp Kesem National | 51 |
| `FOUNDATION FOR NATIONAL PROGRESS` | The Center For Investigative Reporting | 49 |
| `Lakeview Pantry` | Nourishing Hope | 45 |
| `Little Kids Rock` | Music Will | 42 |

Three distinct failure classes, none reachable by string comparison:

* **Rebrands** — Lakeview Pantry → Nourishing Hope, Little Kids Rock → Music Will.
* **Mergers** — Foundation for National Progress → Center for Investigative
  Reporting; National Center for Transgender Equality → Advocates for Trans
  Equality.
* **Brand vs legal name** — USA for UNHCR, VOTEORG, Camp Kesem.

No normalization, acronym index, or fuzzy threshold gets from `Lakeview Pantry`
to `Nourishing Hope`. The only route is the observation that 45 other
grantmakers used the old name for that EIN.

---

## 5. How to wire it in — and the trap

**Do not use the alias to assign an EIN directly.** Use it to add *names* to the
reference, and let the existing cascade do the rest.

The trap: if the alias is used as a blocking key that surfaces the BMF row for
`Nourishing Hope` as a candidate for the query `Lakeview Pantry`, the comparison
step then scores those two names against each other, gets ~0, and the veto layer
throws the candidate away. **The match is justified by the alias observation, not
by name similarity**, so the evidence has to travel with the candidate.

The clean way is already in npmatch. `np_compare()` scores the full name/DBA
cross-product and keeps the best, and the cascade already runs `exact-name-dba`,
`exact-dba-name`, and `exact-dba-dba` passes. So:

**Expand the reference with synthetic alias rows.** One row per
`(ein, alias_name)` above the corroboration threshold, carrying the BMF EIN and
the BMF's address, with `name` set to the alias. `Lakeview Pantry` then matches a
reference row whose name *is* `Lakeview Pantry`, on the existing `exact-name`
pass, and resolves to the right EIN. No new comparison logic, no new veto rules.

Sizing: ~440k corroborated aliases against 1.92M BMF rows is a ~23% reference
expansion — cheap, and it lands mostly on the cheap exact passes rather than the
expensive `token-any`.

Suggested gating, straight off §2:

| `n_filers` | precision | use |
|---|---|---|
| ≥ 5 | 98-99% | eligible for YES, same as a BMF name hit |
| 2-4 | 95.4% | eligible, but flag the provenance |
| 1 | 86.1% | candidate generation only — never auto-accept |

Carry `n_filers` and `alias_source` on the matched row so `pf_report()` can split
outcomes by provenance and the audit can be re-run on alias-sourced matches
specifically.

---

## 6. Open questions before building

* **The 25.5% of alias EINs not in the BMF.** Revoked, merged, or mis-keyed? The
  BMF in use is the active-only file, so some of these are probably legitimate
  organizations that have since been removed — which would make them evidence
  that the recipient is real but unmatchable, useful for the NO tier's triage
  rather than for matching.
* **Address as a second key.** Everything above uses name alone. The alias table
  carries city/state/zip5 and 93.4% of `(name, state, zip5)` keys are unique to
  one EIN; adding geography should raise the single-filer tier's precision
  materially. Untested.
* **Fuzzy alias matching.** Only exact normalized-name lookup was measured. The
  alias table would also work as a *token/IDF* blocking source, which should
  extend reach well past 18.1% of the NO tier.
* **Recency.** `first_year`/`last_year` are in the table but unused. A name last
  seen in 2011 is weaker evidence for a 2023 grant than one seen last year, and
  for rebrands the direction matters.
* **Self-dealing check.** Schedule I filers are themselves nonprofits; nothing
  currently prevents an alias row from being used to match a grant made by that
  same filer. Low risk, but the same guard as `pf_drop_self_matches()` applies.

---

## 6b. What the missing 35.2% of alias EINs actually is

35.2% of the 794,201 alias EINs (279,845) are in neither BMF vintage. Measured in
`dev/probe-schedi-ein-quality.R`; the answer is **mostly not data entry error**.

### Format errors: zero

| raw `SI_02_GRANT_US_ORG_EIN` | rows | share |
|---|---|---|
| exactly 9 digits | 8,377,563 | 93.2% |
| blank | 608,501 | 6.8% |
| **shorter than 9** | **0** | 0% |
| **longer than 9** | **0** | 0% |
| **containing a non-numeric character** | **0** | 0% |

NCCS validates the field upstream. A length check therefore returns a clean
null — and that is informative rather than disappointing: any error that survives
is a *valid-looking* nine-digit number, which no format rule can catch.

### It is governments and public universities

Schedule I covers grants to organizations **and governments**. State
universities, school districts and municipalities are exempt under §115 rather
than §501(c)(3), so they have EINs and receive enormous numbers of grants but
have no exempt-organization BMF row at all.

A crude government-name pattern fires on **11.9% of not-in-BMF aliases against a
2.7% base rate** — 4.4x enrichment. That understates it: the pattern misses
`George Mason University`, `Oregon Health & Science University` and `Auburn
University`, none of which contain "University of" or "State University".

The most-corroborated missing names are almost entirely public universities:

| name | filers |
|---|---|
| University of Washington | 312 |
| North Carolina State University | 170 |
| Arizona State University | 153 |
| University of Alabama at Birmingham | 153 |
| Colorado State University | 152 |

These are not errors, and they are not recoverable by better matching. They are
out of the BMF's scope by construction.

### Typos: real but rare

1,000 not-in-BMF aliases with a complete name and address, blocked on ZIP3 and
Jaro-Winkler matched against the unified BMF (median block 6,278 rows):

| best name similarity in block | cases |
|---|---|
| < 0.80 | 300 |
| 0.80–0.90 | 531 |
| 0.90–0.95 | 112 |
| ≥ 0.95 | **58 (5.8%)** |

Of those 58 strong matches under a *different* EIN, the digit distance splits
them cleanly: **19 (32.8%) differ by ≤ 2 digits** — genuine typos — while 34
differ by 6 or more, which is a coincidental same-name match rather than a
mis-keyed number (`Pine Lane Elementary`, `Ferris State University` — both
out-of-scope public entities whose fuzzy match found an unrelated namesake).

So the typo rate is roughly **5.8% × 32.8% ≈ 1.9% of not-in-BMF EINs**, or about
**0.7% of all alias EINs**. Confirmed examples:

| filed | actual | organization |
|---|---|---|
| `237231219` | `237241219` | East Michigan Environmental Action |
| `742408566` | `742408656` | Master Plan Ministries |
| `961690977` | `951690977` | Childrens Hospital Los Angeles |
| `710680803` | `710680830` | Northwest Arkansas Food Bank |

### A correction: the "leading zero rotation" is not real

Three of the 19 confirmed typos looked like a systematic digit rotation —
`020628872` → `206288720`, as though a leading zero had been dropped and the
number left-shifted. That looked mechanically repairable and was written up as
such. **Testing it against all 279,845 missing EINs does not support it:**

| test | hit rate |
|---|---|
| rotate left one digit lands on a real BMF EIN | 0.41% |
| rotate right one digit | 0.71% |
| either | 1.11% |
| **a random 9-digit number** | **0.35%** |

With 3.69M EINs in a 10^9 space, *any* number hits ~0.35% of the time, so
rotation is barely above chance. And only 3.0% of the rotate-left hits produce a
leading zero at all — the mechanism would require nearly all of them to. The
pattern was small-sample coincidence. Real rotation typos exist but are on the
order of 0.2% of alias EINs, far too rare to justify a repair pass.

### What follows for the pipeline

* **Do not build an EIN repair pass.** ~0.7% yield overall, and the repairs
  require a fuzzy name match that the cascade would have found anyway.
* **The 37,236 orphaned alias rows dropped in Stage 4 are correctly dropped** —
  they are mostly government entities with nothing in the BMF to attach to.
* **But those governments are real grant recipients**, funded by 990-PF filers
  too, and they are *unmatchable by construction* in a BMF-only design. Some
  share of the NO tier is therefore not a matching failure at all. That is worth
  quantifying, and it connects directly to `AUDIT-FINDINGS.md` §3 on the OOS
  flag: column (c) already mis-codes government recipients, and this is the same
  population arriving from the other direction.

---

## 7. Where this sits against everything else

| lever | measured worth |
|---|---|
| adjudicating the MAYBE tier | +11 to +14 points |
| **Schedule I alias table** | **~+2.2 points, conservatively** |
| OOS gating for `individual`/`government` | ~+1.5 points |
| apostrophe normalization | ~+1.3 points (done) |
| grant-purpose tiebreak | +1 grant of 63 |

Second only to adjudicating MAYBE, and unlike that one it is automatic.
