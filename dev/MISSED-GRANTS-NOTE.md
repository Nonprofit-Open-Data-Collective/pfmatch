# Missed grants, cluster precision, and MAYBE adjudication: TY2021–2024 run

Dev note from the intermediaries project, 2026-11-26. It covers the full 990-PF TY2021–2024
run: 7,621,052 grant rows and 1,577,882 identities, with pfmatch `4cbb6a9` and matchdb
`active-observed`. Related notes: `REPRESENTATIVE-NAME-NOTE.md` (the representative-name
loss, and the rematch that fixed it) and `PLACEHOLDER-SIDEBAR-NOTE.md` (setting placeholder
rows aside before matching).

- Plan: `intermediaries/dev/missed-grants-plan.md`
- Scripts: `intermediaries/dev/pfmatch-run/00`–`08`
- Outputs: `~/Documents/GRANTFLOW/pfmatch-ty2021-2024/` (`out/`, `missed/`, `placeholder/`,
  `review/`, `second-pass/`)

## Headline

| | YES, share of rows | YES, share of dollars |
|---|---:|---:|
| As run (all rows) | 61.7% | 43.1% |
| + rematch on the most common name | 68.9% | 52.1% |
| …placeholder rows removed from the base | 69.1% | 68.5% |
| …matchable universe (placeholders, people, governments, foreign, OOS removed) | **77.0%** | **76.3%** |
| …if MAYBE were adjudicated (projected from 100 agent-reviewed cases) | ~87–89% | ~90–92% |

"YES" here means *matched*. It does not mean verified. Section 2 shows that a meaningful
share of YES in merged clusters is on the wrong EIN.

## 1. Why grants were missed (after the rematch)

Missed means NO or MAYBE. The breakdown below is by identity class (`05-missed-scan.R`;
people from `peopleparser::classify_names()`).

| Class | Identities | Grant rows | $B | Share of missed $ |
|---|---:|---:|---:|---:|
| placeholder | 7,467 | 22,613 | 113.2 | 52.8% |
| organisation (recoverable) | 473,060 | 1,567,345 | 76.4 | 35.7% |
| foreign | 32,052 | 85,212 | 14.3 | 6.7% |
| person | 324,804 | 567,002 | 7.2 | 3.4% |
| government | 26,914 | 82,127 | 3.1 | 1.4% |

- People are 38% of missed identities but only 3% of missed dollars. Most of them should be
  out of scope rather than NO.
- Of the organisation class, $50.8B is MAYBE and $25.6B is NO.

**Match rate by cluster size, matchable universe, share of grant rows:**

| Rows per identity | Identities | YES | MAYBE | NO | YES, share of $ |
|---|---:|---:|---:|---:|---:|
| 1 | 417,723 | 43.2% | 24.1% | 32.7% | 47.1% |
| 2–5 | 570,519 | 66.2% | 16.6% | 17.1% | 56.1% |
| 6–20 | 149,626 | 81.2% | 12.5% | 6.3% | 84.0% |
| 21–100 | 42,806 | 88.0% | 9.6% | 2.4% | 86.0% |
| 101–1,000 | 5,862 | 83.4% | 15.6% | 1.0% | 79.4% |
| >1,000 | 141 | 76.4% | 23.6% | 0.0% | 74.7% |

**By number of name variants:**

| Variants | YES, share of rows | NO, share of rows |
|---|---:|---:|
| 1 | 66.5% | 16.4% |
| 2 | 83.2% | 6.0% |
| 3–5 | 86.4% | 3.2% |
| 6+ | 82.2% | 1.2% |

Clusters match far better than singletons. That comes partly from frequency, since frequent
recipients are big and well known, and partly from the rematch. MAYBE rises again in the
largest clusters (23.6% for clusters over 1,000 rows). Those are multi-entity systems with
several EINs of the same name, which is where section 3's errors sit.

## 2. Cluster precision: 100 YES clusters reviewed by an agent

The sample is 100 YES identities with more than one name variant: 50 drawn from the 500
largest by dollars, and 50 at random from the other 148,964. Four agents reviewed 25 each.
They checked 44 of the 100 EINs on ProPublica or the web and judged the rest from their own
knowledge. Verdicts are in `review/cluster-verdicts-*.csv`.

| Stratum | Clusters wrong | 95% CI | Share of grant rows wrong | Share of $ wrong |
|---|---:|---|---:|---:|
| random (median 10 rows) | 5 / 50 = 10% | 3–22% | 23.6%* | 35.7%* |
| largest 500 (median 226 rows) | 10 / 50 = 20% | 10–34% | 25.8% | 10.4% |

\*The random-stratum shares of rows and dollars are dominated by one case: Planned Parenthood
Mar Monte, 241 of 269 wrong rows. Read the share of clusters as the estimate.

**The error shapes.** These are things to fix in pfmatch, not reviewer opinions. Almost
every case was confirmed against ProPublica.

1. **Sibling entity whose name contains the grantee's name, chosen by the token passes
   (B1/B2):**
   - ADL → ADL Professional Staff Association, a staff union (2,493 rows, $88.5M)
   - Columbia Business School → the CBS alumni club of NY
   - Philadelphia Museum of Art → its Women's Committee
   - Planned Parenthood Mar Monte → its 501(c)(4) advocacy arm
   - Semper K9 → Semper Fi Fund
   - Arizona State University Foundation → a fraternity colony
2. **The same mistake made by the exact passes (A1, score 0.98):**
   - McLean Hospital → its 501(c)(9) employee medical trust
   - Piedmont Healthcare Foundation → the hospital system

   A name plus ZIP does not separate entities that share a name and an address.
3. **Over-merge in fuzzy dedup:**
   - **"CINCINNATI …": 41 different organisations chained into one cluster** (Art Museum,
     Opera, Ballet, Shakespeare Company, Cincinnati Works, …). The shared leading city token
     carries Jaro-Winkler over 0.92, and transitive linking does the rest.
   - Georgetown University + Georgetown Ministry Center
   - Philadelphia Museum of Art + Mural Arts Advocates
   - St Louis Community College + its foundation
   - Enterprise Community Partners + Enterprise Community Development (the EIN went to the
     minority variant)
4. **Suggested fixes, in order of yield:**
   - **Dedup:** compare names after removing place tokens (city, county and state names) and
     generic org words, or require a token-overlap floor alongside Jaro-Winkler. Add a
     diameter check so clusters cannot chain: every member must clear the threshold against
     the cluster's most common name, not only against some other member.
   - **Cascade:** when the top candidate's name is a superset of the query, adding words like
     STAFF ASSOCIATION, ALUMNI CLUB, WOMENS COMMITTEE, AUXILIARY, GUILD, ADVOCATES, EMPLOYEE
     TRUST or FRATERNITY, require that it beat a candidate whose name equals the query, or
     downgrade it to MAYBE.
   - **Subsection:** only 1.0% of YES rows go to non-501(c)(3) EINs: (c)(4) 0.40%, (c)(6)
     0.18%, (c)(5) 0.14%, (c)(9) 0.01%. A rule that non-(c)(3) means MAYBE is cheap but
     small.
5. **The BMF name can be wrong.** In several cases the reference name for an EIN disagrees
   with ProPublica:
   - 75-6043842 is "TTU Health Sciences Center" in the BMF but Texas Tech Foundation on
     ProPublica.
   - 74-1587488 is "UT Dallas" in the BMF but the UT Foundation on ProPublica.
   - 52-1053406 is "Open Space Institute Land Trust" in the BMF but Open Space Institute Inc
     on ProPublica.

   An exact name match can therefore rest on a wrong name record. This is worth a matchdb
   check of `observed` names against the filer's own e-file header name.

## 3. MAYBE adjudication: 100 cases reviewed by an agent

There are 265,354 MAYBE identities (1,173,221 rows, $59.8B). The sample has the same strata
as section 2, and the 500 largest hold 55.5% of MAYBE dollars. Agents reviewed each surfaced
candidate (`review/maybe-verdicts-*.csv`, scored in `review/MAYBE-SCORED.csv`). **All 72 EINs
the agents proposed were checked against the BMF, and all 72 exist.**

| Outcome | Largest 500 | Random | Population, identities | Rows | Dollars |
|---|---:|---:|---:|---:|---:|
| candidate correct (ACCEPT) | 24 | 21 | 42% | 35.8% | 62.4% |
| candidate wrong, right EIN found | 20 | 7 | 14% | 32.7% | 26.8% |
| no EIN expected (government, public university, individual, foreign) | 5 | 10 | 20% | 17.4% | 8.7% |
| candidate wrong, EIN not found | 0 | 11 | 22% | 13.5% | 1.8% |
| ambiguous | 1 | 1 | 2% | 0.6% | 0.3% |

- **Adjudication recovers about 89% of MAYBE dollars** (62.4% + 26.8%) and about 69% of MAYBE
  rows.
- Accepting the candidate automatically would be **wrong in 38 of the 83 cases where an EIN
  should exist** (46%): 20 of 44 in the large stratum and 18 of 39 in the random one. This
  confirms `ADJUDICATION-PLAN.md`: there is no safe automatic rule.
- **Large MAYBE cases are mostly multi-entity systems with margin 0:**
  - MGH → its Nurses Alumnae Association
  - Memorial Sloan Kettering → the entity that files only a 990-T
  - Mayo → Mayo Clinic Hospital-Rochester
  - Juilliard → a legacy EIN
  - City of Hope → a small sibling
  - Children's Mercy Hospital ↔ its foundation, in the wrong direction

  "Margin 0 with ≥2 close candidates" is a useful flag for "choose among siblings". For that
  choice, the entity that files a 990 with the largest revenue is a strong prior.
- **No EIN expected** is mostly government units the cascade paired with a same-town
  nonprofit: school boards → a booster club or Sav-A-Life, a public library → its Friends
  group, a town → its car show. Public universities are also here, though "no EIN" versus the
  university's foundation is a judgement call.
- Cost: the pfmatch NO-search adjudication arm measured about $0.03 per case. For 265k MAYBE
  identities that is about $8k; adjudicating only the 500 largest (55.5% of MAYBE dollars) is
  about $15. The agent test here ran on Claude subagents with web access, because no API key
  was set. Production should use the `adjudicate-1x` scripts.
- Caveat: the verdicts come from one model reviewer, and their own accuracy has not been
  measured. The 72 EINs are verified to exist, not verified to be right.

## 4. Second pass for the organisation class (name cleaning)

`06-org-second-pass.R`: the 500 largest organisation-class NO identities ($13.87B). It strips
ATTN / C/O / FBO tails, parentheticals, "- suffix" tails, project, campaign and year notes,
and splits compound names.

**Result:** cleaning changed 74 of the 500 names. 20 became YES (265 rows, **$1.16B**, 8.4% of
the targets' dollars). 10 became MAYBE ($0.16B). 44 stayed NO.

| Recovered | $M | Filed as | Cleaned to |
|---|---:|---|---|
| YES | 495.4 | CHDI Foundation Inc Attn Ken Slutsky Tax Exem… | CHDI FOUNDATION INC |
| YES | 391.9 | High Q Foundation Inc Attn Ken Slutsky… | HIGH Q FOUNDATION INC |
| YES | 119.5 | CHARTER FUND INC (DBA CHARTER SCHOOL GROWTH F… | CHARTER FUND INC |
| YES | 10.2 / 7.6 | SCHWAB CHARITABLE FUND (JUDY FRANCIS ZANKEL C… | SCHWAB CHARITABLE FUND |
| MAYBE | 27.6 | BLACKBAUD GIVING FUND - YOURCAUSE | BLACKBAUD GIVING FUND |

Taking "the longest part" of a compound name is often the wrong part.

| Still NO, $M | Filed as | Right payee |
|---:|---|---|
| 291.6 | DAF - STABLER CHARITABLE FUND | the DAF's sponsor, if one is named elsewhere |
| 57.1 | CHABOT FAMILY DAF - VANGUARD | **Vanguard Charitable** (the shorter part) |
| 25.0 | TCU - AWM SCHOOL OF MEDICINE | **TCU** (the first part) |
| 31.5 | BANK OF AMERICA CHARITABLE FUND - KYM'S ANGEL FUND | Bank of America Charitable Fund, a DAF sponsor; it may not be in the active tier |
| 37–41 a year | Nationwide Foundation 2021–2024 Grants | cleaned correctly but still NO; check whether this filer pays itself, or whether the recipient is missing from the reference |

**Rules for the cleaner:**

- Try **every part** of a compound name, not just the longest.
- When one part is a donor-advised fund ("… DAF", "… FAMILY FUND", "… CHARITABLE FUND") and
  another is a known DAF sponsor (Fidelity, Schwab, Vanguard, NPT, Morgan Stanley GIFT, BofA,
  the community foundations), the sponsor is the payee.

The yield is small next to the rematch ($1.16B against $42.7B), but it is cheap: 74
identities. A full run over all 473k organisation-class misses would probably recover a few
billion more.

## 5. Agent search for placeholder attachments

See `PLACEHOLDER-SIDEBAR-NOTE.md` §4. Lists exist in the scanned IRS full-return PDFs for
most large filers and need OCR. Wells Fargo's 2021–2023 lists are not public. Musk's "SEE
ATTACHMENT A" lines are real single grants.

## 6. Requests for pfmatch, in priority order

1. Choose the representative by the most common name (`REPRESENTATIVE-NAME-NOTE.md`): +$42.7B
   YES, measured.
2. Set placeholder rows aside before matching (`PLACEHOLDER-SIDEBAR-NOTE.md`): 24% of dollars
   leave the base.
3. Dedup chaining guard and place-token removal (§2.4): this is a precision fix, and it
   affects the largest clusters most.
4. Sibling-superset downgrade in B1/B2 and A1 (§2.4).
5. Put people, government and foreign recipients out of scope, rather than NO or MAYBE:
   people are 38% of missed identities.
6. MAYBE adjudication through the existing arm, largest dollars first, with the margin-0
   sibling prior (§3).
7. Report rates over the matchable universe and weighted by dollars, beside the share of
   identities.
