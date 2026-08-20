# Audit of the NO, OOS, and MAYBE tiers

Three 100-case samples drawn from the 5,000-grant benchmark (seed 2026), examined
before acting on the six-step plan in `BENCHMARK-NOTES.md`. Reproduce with:

```bash
Rscript dev/build-audit-samples.R
Rscript dev/probe-no-cases.R
Rscript dev/summarize-audit.R
```

**Headline:** none of the three tiers means what its label suggests. NO is
overwhelmingly real nonprofits we failed to reach, OOS is 24% wrong, and MAYBE
contains a correct answer 63% of the time. Fixing the four defects below is worth
more than any threshold tuning.

---

## 1. NO — are these real nonprofits, and why did we surface nothing?

**Method.** Two independent checks. (a) An *oracle probe*: search the whole BMF
for records sharing the query's two rarest tokens and rank by name similarity —
deliberately using a different mechanism than the cascade's own blocking, so it
can find what blocking missed. (b) Internet search on the cases whose legitimacy
could not be settled from the BMF alone, then verify the resulting EIN against
the BMF.

**Result.** The oracle probe surfaced a plausible BMF candidate for **92 of 100**.
Of 20 organizations web-searched, **18 are legitimate nonprofits**; the two that
are not are `HJP SERVICES LLC` (a for-profit vendor) and `Biosorra` (no
organization found). Of 15 web-confirmed EINs checked against this BMF vintage,
**13 are present** — the reference contained them and the match failed.

| filed name | BMF legal name | why we missed it |
|---|---|---|
| `WYEP-FM` | Pittsburgh Community Broadcasting | call sign vs legal name — **zero shared tokens** |
| `Project Turnabout` | Reverence for Life and Concern for People | brand vs legal name — zero shared tokens |
| `WILDLIFE SAFARI` | Safari Game Search Foundation | DBA vs legal name |
| `Cleveland Angels` | Transformations by Austin Angels | group-exemption parent name |
| `CSCOE` | Catholic Schools Center of Excellence | acronym |
| `NJOP` | National Jewish Outreach Program | acronym |
| `MCFL-MCEE` | Council on Economic Education in Maryland | acronym + word order |
| `PVCC EDUCATIONAL FOUNDATION` | Piedmont Virginia Community College Educational Fdn | acronym |
| `F I N D` | Food in Need of Distribution | **spaced initialism — no token ≥2 chars survives** |
| `Frigid NYC` | Frigid New York | NYC ↔ NEW YORK |
| `ALAMA PUBLIC TELECOMM` | Alamo Public Telecommunications Council | typo + truncation |
| `OPERATIONS RESTORED WARRIOR` | Operation Restored Warrior | plural typo |
| `SPINA BIFIDA ASSOCIATION` | Spina Bifida Association of America | affiliate suffix |
| `ST JUDE'S CHILDREN'S RESEARCH HOSPITAL` | St Jude Childrens Research Hospital | **apostrophe (see §2)** |
| `ACE MENTOR PROGRAM OF AMERICA` | ACE Mentor Program of America (many chapters) | exact name, ~20 same-named chapters — selection, not blocking |

Only 7 of 100 produced no BMF candidate at all, and those are mostly individuals
miscoded as organizations (`JOSHUA ADLER`, `MACKENZE HEDDINGS`, `CYRUSBROWN`).

**Read:** the NO tier is not a wall of genuinely-absent organizations. It is
mostly a **name-resolution** problem — aliases, acronyms, and punctuation —
plus one outright bug.

---

## 2. The apostrophe bug — the single largest recoverable loss

`npmatch`'s `.np_basic_clean()` replaces punctuation with a **space**, while the
NCCS-processed BMF `org_name_join` has already **deleted** it. The two sides
collapse the possessive differently, so no possessive name can clear an exact
pass:

```
QUERY name_key             BMF name_key             equal?
SAINT LUKE S HOSPITAL   |  SAINT LUKES HOSPITAL   |  NO
BO S PLACE              |  BOS PLACE              |  NO
LEAH S HOPE             |  LEAHS HOPE             |  NO
ALLY S ALLIES           |  ALLYS ALLIES           |  NO
CHILDREN S MUSEUM OF NH |  CHILDRENS MUSEUM ...   |  NO
```

Measured over the 5,000-grant sample:

| filed name contains an apostrophe | YES | MAYBE | NO |
|---|---:|---:|---:|
| no (n=4,468) | **60.3%** | 21.6% | 18.1% |
| yes (n=159) | **32.7%** | 19.5% | 47.8% |

Testing the actual fix — delete the apostrophe rather than let it become a space
(`dev/test-apostrophe-fix.R`) — over the 159 apostrophe names in scope:

| | n | share |
|---|---:|---:|
| exact BMF `name_key` hit **today** | 7 | 4.4% |
| exact BMF `name_key` hit **with the fix** | 104 | 65.4% |
| **newly reachable by an exact-name pass** | **99** | |

Be careful reading that 99. The token pass already recovers many of them by
another route, so it is not 99 new matches. Their current outcomes:

| current tier of the 99 | n |
|---|---:|
| already YES (found via the token pass) | 39 |
| MAYBE | 19 |
| NO | 41 |

So the realistic gain is **~41 new matches and ~19 likely promotions** — about
**1.3% of in-scope grants and 4.6% of the NO tier** — plus a real efficiency win:
39 matches that currently cost a trip through the 880,760-pair token pass would
be settled by the cheapest exact pass instead.

The differential outcome rate is the symptom, not the whole measure of the fix:

| filed name contains an apostrophe | YES | MAYBE | NO |
|---|---:|---:|---:|
| no (n=4,468) | **60.3%** | 21.6% | 18.1% |
| yes (n=159) | **32.7%** | 19.5% | 47.8% |

This is a defect in the *interaction* between `npmatch`'s cleaner and the NCCS
BMF, not something specific to 990-PF data — it will be depressing the SAM match
rate too.

---

## 3. OOS — is the scope flag right?

**24 of 100 are misclassified**: a BMF organization plainly exists for them.

| oos_reason | n | misclassified | rate |
|---|---:|---:|---:|
| individual | 66 | 16 | 24% |
| government | 16 | 8 | 50% |
| foreign address | 11 | 0 | 0% |
| no recipient name | 7 | 0 | 0% |

**Root cause.** Column (c) of Part XIV asks for the *foundation status of the
recipient*, and filers answer it about the **beneficiary**, not the **payee**.
When a foundation pays tuition to a college for a named student, it codes `I`.
19 of the 24 misclassified grants have a scholarship/tuition/education purpose.

Examples flagged `I` that are unambiguously organizations, with the BMF row the
probe found:

```
IOWA CENTRAL COMMUNITY COLLEGE  -> Iowa Central Community College Foundation  23-7043863
STETSON UNIVERSITY              -> Stetson University                         59-0624416
HOFSTRA UNIV                    -> Hofstra University                         11-1630906
LUTHER COLLEGE                  -> Luther College                             42-0680466
EMMAUS BIBLE COLLEGE            -> Emmaus Bible College                       36-2270695
Mississippi State University    -> Mississippi State University Foundation    64-0410581
UW-STOUT                        -> UW-Stout Foundation and Alumni Association 39-6088094
```

The `government` bucket is worse in rate: `KENAN-FLAGLER BUSINESS SCHOOL
FOUNDATION` (56-0771850) and `COUNCIL OF SENIOR CENTERS DBA LIVEON NY`
(13-2967277) are ordinary 501(c)(3)s the filer coded `GOV`.

**What is correctly OOS:** all 11 foreign addresses, all 7 blank names, and the
genuine public entities — city parks departments, school districts, individual
public elementary and middle schools.

**Note on the university cases:** the BMF row is often the *foundation or alumni
arm* rather than the institution (`Iowa Central Community College Foundation`,
`Canyon Ridge High School Booster Club`, `Wesley Chapel Elementary PTO`). Whether
that is the right EIN depends on where the check actually went, so these should
be routed to MAYBE for adjudication, not auto-accepted.

**Fix:** stop treating `individual` and `government` as automatic OOS. Gate them
on the name instead — `looks_personal` already separates them well (it fires on
0.7% of YES rows but 18% of OOS rows). A grant coded `I` whose recipient name
carries an institutional token should be matched.

---

## 4. MAYBE — adjudicating 100 cases with NTEE, mission proxies, and purpose

Each case was reviewed with the top 5 candidates plus, for both the candidate and
the **filing foundation**: NTEE code and definition, NTEEv2 subsector, IRS
activity-code text, subsection, assets, and the foundation's state — joined by
`pf_candidate_frame()`. Verdicts are in `dev/maybe-verdicts.csv`.

| verdict | n |
|---|---:|
| top pick is correct | **53** |
| correct EIN present but mis-ranked | **10** |
| ambiguous among genuinely related EINs | 13 |
| no correct candidate in the top 5 | 24 |

**63 of 100 MAYBE cases contain the right answer in the top 5.** Projected over
the 995-case MAYBE tier, that lifts the match rate on attempted grants from
**59.3% to 70.7%** (accepting top picks) or **72.9%** (adjudicating the top 5).

### Is the BMF "mission" information useful? Yes — decisively so

The BMF carries **no mission statement**; the usable proxies are the NTEE
definition (always present, ~1 in 4 reads `UNDEFINED`), the NTEEv2 subsector, and
the legacy IRS **activity-code text**, which is only ~44% populated but is the
most mission-like field there is. Used together they were **decisive in 9 of the
10 mis-ranked cases (90%)** and confirmed a further 12 correct top picks.

The clearest wins:

- **`BOCA RATON COMM HOSP`** — five candidates tie at exactly 0.78 (same city,
  same ZIP) and the tiebreak picked *First Presbyterian Church*. The correct
  answer, `BOCA RATON REGIONAL HOSPITAL`, sits at rank 5 and is the only
  candidate whose activity code reads **"Hospital"**.
- **`SUMMIT COUNTY HISTORICAL SOCIETY`** — top pick was `SUMMIT COUNTY MEDICAL
  SOCIETY`; the correct one at rank 5 carries NTEE **A82 Historical Societies**.
- **`University of Washington`, purpose "Educational Scholarships"** — the top
  pick's NTEE is **J40 Labor Unions**. The UW *Foundation* (B11 Single
  Organization Support) is the right payee.
- **`Planned Parenthood Federation of America`** (twice in the sample) — the top
  pick is `PLANNED PARENTHOOD EXPOSED`, an **opposing advocacy organization**
  (NTEE B01). Name similarity alone cannot see this; NTEE and purpose can.
- **`THE NCTA FOUNDATION`** (Washington DC) — top pick was a Vermont
  racquet-sports club literally named `Ncta`. The correct `NCTA EDUCATION
  FOUNDATION` shares the DC ZIP and reads NTEE W80 Public Utilities.

### Is the grant purpose (`SIGOCPYPOGOC`) useful? Moderately

It is highly variable. Roughly a third is contentless (`GENERAL`, `CHARITABLE`,
`UNRESTRICTED`, `GOS`, `As needed`), and one entry was a check stub
(`05/23/23CHECK 130CHARITABLE PURPOSES`). But where it carries content it is
strong, and it is the **only** signal that separates a foundation arm from its
operating entity:

- `SUPPORT OF FOOD PANTRY IN GREEN COUNTY, WI` → confirms `GREEN COUNTY FOOD
  PANTRY` (NTEE K31) over four same-ZIP distractors.
- `Educational Scholarships` → favours the *Foundation*; `YOUTH DEVELOPMENT` →
  favours the *operating club*.
- `HANDICAP LIVING` → confirms `GIANT STEPS ILLINOIS` (NTEE B28 Specialized
  Education) over a same-named sports foundation in New York.

Treat it as a **tiebreak signal, not a scoring field**: match its content words
against the candidate's NTEE definition and activity text only when several
candidates are within the tie band.

### The two dominant ambiguity classes

**Foundation arm vs operating entity (7 cases).** `Denver Art Museum Foundation`
vs `Denver Art Museum`; `LiveOnNY Foundation` vs `LiveOnNY`; `Cincinnati Nature
Center Foundation` vs `Association`; `Big Brothers Big Sisters Lone Star
Foundation` vs `Lone Star`. Same name, same ZIP, tied scores. Only the grant
purpose distinguishes them, and even then a reviewer may reasonably disagree.

**Group-exemption subordinates (5 cases).** `PURDUE UNIVERSITY` returns five
identical names with five different EINs; `OHIO STATE UNIVERSITY` returns five —
**all of them 4-H clubs** (NTEE O52), with the OSU Foundation absent entirely;
`CONNECTICUT INSTITUTE FOR THE BLIND` returns five at one ZIP. The BMF's
`group_exemption_number` and `affiliation_code` fields — already imported by
`np_bmf_review_fields()` but not used in scoring — are the lever here.

### Two outright bugs surfaced

1. **Self-match.** `SIGMA GAMMA ASSOCATION`'s top pick was `SIGMA GAMMA
   FOUNDATION` — which is *the filing foundation itself*. A grant should never
   match the filer's own EIN. One-line guard, and `fdn_ein` is already in the
   candidate frame.
2. **Name typed into the wrong column.** One grant's recipient name is the single
   character `x`, with the real name (`Westford Conserv Trust`) typed into the
   street field.

---

## 5. Revised priorities

The original six-step plan still holds, but the audit reorders it and adds three
items.

**The dominant lever is not an algorithm change — it is adjudicating MAYBE at
all.** 63% of that tier contains the right answer, worth +11 to +14 points on the
match rate, which is more than every engineering fix below combined. Everything
else is second-order.

Ranked by measured return:

1. **Adjudicate the MAYBE tier** (§4), with NTEE / activity text / grant purpose
   in the sheet. `pf_candidate_frame()` already produces it. +11.4 points
   accepting top picks, +13.6 adjudicating the top 5.
2. **Add NTEE / activity-code agreement to the tiebreak** (§4). Fixes 9 of the 10
   mis-ranked cases, i.e. converts most of that +2.2 into something automatic.
   Apply it **only inside the tie band**, where name and geo have already failed
   to separate candidates — not as a general scoring term.
3. **Stop auto-OOS'ing `individual` and `government`; gate on the name instead**
   (§3). Recovers ~24% of a bucket that is 5.5-7.5% of all grants, so roughly
   +1.5 points, and it removes a systematic bias against scholarship grants.
4. **Fix the apostrophe/punctuation asymmetry** (§2). ~41 new matches and ~19
   promotions per 5,000 grants (~1.3 points), plus it moves 39 more off the
   expensive token pass. One-line change, and it improves `npmatch` generally.
5. **Guard against self-matches** (§4). Trivial, and currently produces confident
   nonsense.
6. **Acronym / initialism index on the reference side** (§1). Index BMF name
   initials as synthetic tokens, and lower `min_token_len` for names that are a
   spaced initialism (`F I N D`). This does *not* fix `WYEP-FM` or `Project
   Turnabout` — brand-vs-legal-name needs an alias source the BMF does not carry.
7. **A prefix pass for the 35-character `SIGOCPYRPNAM` truncation** (unchanged
   from the original plan).
8. **Use `group_exemption_number` / `affiliation_code` to collapse subordinates**
   before selection, rather than letting five identical names tie.
9. **Then** revisit thresholds and state blocking. Note the direction: with 63%
   of MAYBE recoverable, the tier is **under-accepting**, so tightening the YES
   threshold would be exactly the wrong move.

### What the audit did *not* find

No evidence that the YES tier is over-accepting. The earlier benchmark put 94.9%
of YES matches at score ≥0.90 with ZIP or street corroboration, and nothing in
these 300 cases contradicts that. The problems are all on the recall side.
