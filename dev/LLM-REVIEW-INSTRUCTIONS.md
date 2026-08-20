# Reviewing 990-PF grant recipients against the IRS Business Master File

You are deciding, for each grant, which IRS Business Master File (BMF)
organization received it — or that none of the candidates offered is the
recipient.

Each case gives you the grant as the foundation filed it, and up to five BMF
candidates that a record-linkage cascade surfaced. The cascade could not decide
between them; that is why the case is here.

---

## The one thing to get right

**`NONE` is a correct and common answer.** In a labelled sample of these cases,
**24 of 82 had no correct candidate in the list**. The cascade surfaces
candidates by name similarity, and a plausible-looking name in the right state
is frequently a different organization.

You are not being scored on how many you resolve. A confident wrong EIN is worse
than `NONE`, because accepted matches are never reviewed again while `NONE`
cases go to a search queue. When the evidence does not single out one candidate,
say so.

---

## What you are given

**The grant, as filed:**

| field | meaning |
|---|---|
| `recip_name` | recipient name the foundation typed. Often abbreviated, truncated, misspelled, or a DBA |
| `recip_street`, `recip_city`, `recip_state`, `recip_zip5` | address as filed — may be the recipient's HQ, a program site, a lockbox, or the foundation's own address |
| `grant_purpose` | Part XIV column (d). Roughly a third is filler (`GENERAL`, `GOS`, `UNRESTRICTED`) |
| `grant_amount`, `grant_year` | size and year |
| `recip_status_raw` | what the filer called the recipient's tax status. Unreliable — it describes the *beneficiary*, not always the payee |

**The filing foundation** (`fdn_*`): name, state, NTEE code and definition.
Useful context — a health funder's unnamed grantee is more likely a clinic than
a ballet company — but weak evidence on its own. Foundations fund outside their
own sector constantly.

**Each candidate** (`cand_*`, `CAND_*`): BMF legal name, city, state, ZIP, NTEE
code and definition, NTEEv2 subsector, IRS activity text, subsection, ruling
year, assets, revenue, plus the linkage signals `score`, `name_sim`, `geo_zip5`,
`geo_state`, and which pass surfaced it.

**Each candidate's own words** (`cand_mission`, `cand_prog`, `cand_ntee_text`) -
the Form 990 Part III mission statement and program service descriptions, and the
NTEEv2 description for the code. **Read these first.** They are the single most
informative field in the packet: on 56 cases that name and address could not
close, they resolved 45. Most often what decides a case is a support organization
stating its parent outright - "IS THE SUPPORTING AFFILIATE OF EAGLE RANCH, INC.",
"TO SERVE AS A FUNDRAISING AND SUPPORT ORGANIZATION FOR THE KANSAS FOODBANK
WAREHOUSE, INC." - which tells you both that this candidate is the arm *and* what
the operating entity is called. Roughly 43% of candidates have this text; when it
is absent the fields are blank, which is not evidence either way.

---

## How to decide

Work in this order. Stop as soon as one step is decisive.

### 1. Does the name identify the same organization?

Not "is it similar" — *is it the same body*. Common traps:

* **Abbreviations and acronyms are usually fine.** `NJOP` = `National Jewish
  Outreach Program`; `MS Center for Public Policy` = `Mississippi Center for
  Public Policy`.
* **A shared generic head is not a match.** `CONGREGATION AGUDATH ISRAEL` and
  `CONGREGATION ADAT ISRAEL` are two congregations. `FIRST BAPTIST CHURCH OF
  SALEM` is not `... OF SALINE`. Ignore the shared prefix and compare what is
  left.
* **A chapter is not its parent.** `Boys & Girls Club of Salem` is not `Boys &
  Girls Clubs of America`. `Habitat for Humanity NYC` is not `Habitat for
  Humanity International`.
* **A DBA can belong to a quite different entity.** A campus ministry may carry a
  university's name as its DBA. Check the BMF *legal* name, not just the display
  name.

### 2. Does the address corroborate it?

An exact ZIP5 match is strong. A city match within the same state is moderate. A
shared city *name* across different states is worth nothing — Patterson LA and
Patterson NC are different places.

Two situations where a mismatched address is **not** disqualifying:

* The filed address is a **lockbox or gift-processing centre** (`PO Box`,
  `... GIFT PROCESSING`) — it says nothing about where the recipient is.
* The BMF holds a **national headquarters** while the grant went to a local
  address. Common for large national charities.

And one where it is decisive: if city and ZIP both match but the state does not,
the filer typed the state wrong. Treat that as a match.

### 3. Does what the organization *does* fit?

Use `CAND_ntee_code_definition` and `CAND_activity_code_definitions` against the
recipient name and grant purpose. This is what separates same-name, same-ZIP
candidates:

* `BOCA RATON COMM HOSP` → the candidate whose activity text reads `Hospital`,
  not the one that reads `Christianity`.
* `SUMMIT COUNTY HISTORICAL SOCIETY` → NTEE `Historical Societies`, not
  `Business promotion`.
* A grant purpose of `Educational Scholarships` fits a scholarship fund, not a
  labor union.

Treat a *contradiction* as strong evidence against, and agreement as moderate
evidence for. `UNDEFINED` NTEE means no information, not disagreement.

### 4. Foundation arm vs operating entity

`DENVER ART MUSEUM` and `DENVER ART MUSEUM FOUNDATION` are two EINs, often at the
same address. So are a university and its foundation, a hospital and its
foundation, a club and its charitable arm.

* Grant purpose mentioning an endowment, campaign, or scholarship fund →
  the **foundation** arm.
* Purpose mentioning programs, operations, or services → the **operating**
  entity.
* Activity text `Gifts grants or loans to other organizations` marks a
  grantmaking arm.
* **If the purpose does not distinguish them, answer `AMBIGUOUS`.** Do not guess.

---

## Output

One row per case:

| field | value |
|---|---|
| `grant_id` | as given |
| `verdict` | `MATCH` · `NONE` · `AMBIGUOUS` |
| `ein` | the chosen EIN if `MATCH`; blank otherwise |
| `confidence` | `high` · `medium` · `low` |
| `evidence_class` | `QUOTE` / `NTEE` / `INFER` / `NONE` - see below |
| `evidence` | the specific facts that decided it, <= 25 words. If `evidence_class` is `QUOTE`, this must contain the quoted sentence |
| `runner_up_ein` | if a second candidate was seriously considered |

**Verdicts:**

* `MATCH` — one candidate is the recipient. Name identifies the same body, and
  either the address corroborates or the name is distinctive enough not to need
  it.
* `AMBIGUOUS` — two or more candidates are genuinely plausible and the evidence
  does not separate them. Typically related entities. Put the best in `ein` and
  the other in `runner_up_ein`.
* `NONE` — no candidate is the recipient. Expect this often.

**Confidence:**

* `high` — you would defend this to a sceptic. Name and address both agree, or
  the name is unmistakable.
* `medium` — probably right, one piece of evidence is missing or weak.
* `low` — a lean, not a conclusion.

**Evidence class** records *what kind of fact* decided the case. It is the
confidence signal we actually calibrate against, because unlike a feeling it can
be audited by a third party:

* `QUOTE` - a verbatim sentence in a candidate's own 990 decides it. Put the
  sentence in `evidence`. This is the strongest class and about half of resolvable
  cases reach it.
* `NTEE` - the classification code alone decides it (e.g. the top pick is `B11`
  Single Organization Support and the runner-up is the operating school).
* `INFER` - no single string; you reasoned over the whole packet. Legitimate, but
  mark it honestly. These are the cases a second reviewer most often overturns.
* `NONE` - nothing in the packet bears on the question. Route to search.

Do not claim `QUOTE` without a quotable string. A verdict that claims `QUOTE` and
supplies no sentence will be rejected.

**Evidence** must cite what actually decided it. Good: `ZIP 90024 exact; NTEE
A51 Art Museums matches "Hammer Museum"`. Useless: `names are similar`.

---

## Worked examples

**MATCH, high.** Filed `Hammer Museum`, Los Angeles CA 90024. Candidate 1
`ARMAND HAMMER MUSEUM OF ART AND CULTURAL CENTER`, LA CA 90024, NTEE A51 Art
Museums. Candidate 2 `HAMMER MUSEUM`, Haines AK.
→ `MATCH`, ein candidate 1, high. `ZIP5 exact and NTEE A51 Art Museums; the exact-name candidate is in Alaska`.

**MATCH, high — wrong state filed.** Filed `Temple Bat Yahm`, Newport Beach
**NY** 92660. Candidate: same name, Newport Beach **CA** 92660.
→ `MATCH`, high. `City and ZIP exact; filed state is a typo`.

**NONE.** Filed `EVANGELICAL LUTHERAN CHURCH IN AMERICA`, Merrifield VA, address
`ELCA GIFT PROCESSING CENTER PO BOX`. All five candidates are local ELCA
congregations in NC, CA, WI.
→ `NONE`. `Address is a lockbox; national body is not among the candidates`.

**AMBIGUOUS.** Filed `Cincinnati Nature Center`, Milford OH 45150, purpose
`UNRESTRICTED DONATION`. Candidates: `CINCINNATI NATURE CENTER FOUNDATION` and
`CINCINNATI NATURE CENTER ASSOCIATION`, same ZIP.
→ `AMBIGUOUS`, best guess the Association, runner-up the Foundation.
`Foundation vs operating arm at one address; purpose does not distinguish`.

**NONE — despite a high score.** Filed `PLANNED PARENTHOOD FEDERATION OF
AMERICA`, DC PO box. Top candidate `PLANNED PARENTHOOD EXPOSED`, Kansas City KS,
NTEE B01 Alliance/Advocacy.
→ Check the rest of the list before answering. `PLANNED PARENTHOOD FEDERATION OF`
in New York is the same organization under a BMF name truncated mid-phrase —
that is `MATCH`. The top-scoring candidate is an *opposing* advocacy group.
Never accept rank 1 without reading the others.

---

## Calibration

Roughly **15% of the batch has a known answer**, mixed in and not marked. Your
accuracy on those is reported alongside your results and is the only evidence
that the rest can be trusted. Do not try to identify them — consistency is the
point.

For reference, from a hand-adjudicated sample of these cases: about **43% are
`MATCH` on the top candidate**, **12% are `MATCH` on a lower-ranked candidate**,
**16% are `AMBIGUOUS`**, and **29% are `NONE`**. If your output is 90% `MATCH`,
something has gone wrong.
