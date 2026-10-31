# Investigating 990-PF grant recipients the matcher could not find

A private foundation filed a Form 990-PF listing a grant it paid. An automated
cascade tried to find that recipient in the IRS Business Master File — the IRS
list of organizations recognized as tax-exempt — and failed. Either no record
resembled the filed name closely enough to be worth offering, or the best
record it found scored below the floor for review.

Your job is **not** to pick a record. It is to find out who this payee actually
is, and then say which of two things is true:

1. **The organization has an IRS exemption record and the matcher missed it.**
   The record exists; the cascade's name resolution failed to reach it.
2. **There is no record to find.** The payee is not the kind of entity the
   Business Master File contains, or it is an entity the file deliberately
   omits.

Those two outcomes call for completely different responses from the project, so
getting the split right matters more than getting any single EIN right.

## The one thing to get right

**An EIN you report must come from a source that actually states it.**

Do not derive an EIN from a name match, do not guess one from a similar
organization, and do not report an EIN because a candidate record shown to you
happens to carry a plausible name. If a source states the EIN — an IRS
exemption record, a ProPublica Nonprofit Explorer page, a Candid/GuideStar
profile, a state charity registry, an audited financial statement, the
organization's own Form 990 — report it and say where. Otherwise report no EIN
and say the search did not establish one.

A wrong EIN is worse than no EIN here. No EIN leaves a case open; a wrong EIN
closes it with a falsehood and will be counted as a recovered match.

## You cannot see the Business Master File, and you are not asked to

You have no access to the file itself. **Do not try to decide whether a
specific EIN is in it.** Report the EIN you found, and the pipeline will look it
up mechanically. That lookup is exact, on the EIN, and it is the one step in
this experiment that depends on no judgement at all — yours or anyone's.

What you *are* asked to judge is the prior question: **should a record exist?**
That is a question about the entity, not about the file, and it is answerable
from what you find:

- A US charity with its own IRS determination letter: a record should exist.
- A Boy Scout troop, a PTA unit, a Lions club, a parochial school under a
  diocese: these are usually **subordinates under a group exemption**, covered
  by a parent's ruling and not separately listed.
- A church, synagogue, mosque or temple: churches are exempt automatically and
  need not apply or file, so many are simply absent.
- A public school, school district, public library, city, county, state agency
  or tribal government: a governmental unit, not an exempt organization.
- An organization outside the United States: not in the file.
- A named fund, program, campaign, scholarship or event rather than a legal
  entity — "the Wish Book Fund", "the post-prom committee", a hospital's cancer
  center: no exemption of its own, and often no EIN at all.
- A natural person, or a business: not an exempt organization.

## What you are given

**The grant as filed.** The recipient name, street, city, state and ZIP as the
foundation typed them, the stated purpose, the amount, the tax year, and the
foundation's own "recipient status" text. All of it is uncontrolled free text
entered by a filer, so all of it can be wrong, abbreviated, truncated or
internally inconsistent.

**The filing foundation.** Who paid. This is useful context: a foundation
usually gives near where it sits and within a recognizable field, and a local
funder naming a short generic recipient name usually means the local
organization of that name rather than a national body.

**What the cascade did.** One of two things:

- *No candidate retrieved.* No blocking pass produced any record to score. This
  usually means the filed name shares no distinctive token with any record, or
  the name is so generic that nothing could be pruned to a usable set.
- *Near-misses, with their scores.* Records the cascade found and rejected,
  best first. **Read these carefully and skeptically.** They were rejected, so
  the prior is that they are wrong — but in prior audits of this tier the
  correct record had frequently already been offered and merely scored too low.
  A near-miss that is plainly the same organization written differently is a
  real finding, not a distraction.

A near-miss is also a trap. Any EIN you read off one of these rows is in the
reference by construction, so reporting it as if search had established it
makes the result circular. Hence `ein_source`: set it to `CANDIDATE` when the
EIN came off a row shown to you, and `WEB` only when an outside source stated
it. Both are useful. Conflating them is not.

## How to investigate

Search. On essentially every case, and before you conclude anything.

1. **Find the payee.** Search the filed name with the city or state. Look for
   the organization's own site, its IRS exemption record, or a directory entry
   (ProPublica Nonprofit Explorer, Candid/GuideStar, Charity Navigator, a state
   registry, a state corporate registry).
2. **Get the EIN from a source that states it.** This is the single most useful
   fact you can bring back, and it settles the case.
3. **Work out what kind of entity it is.** This is where the interesting
   answers are. A name that looks like a charity is often a chapter, a program,
   a fiscally sponsored project, a school district or a business. Confirm the
   relationship from a source rather than inferring it from the name's shape.
4. **Check the filed geography.** A filed state that contradicts the filed ZIP
   is common and is sometimes the entire reason the record was never retrieved.
5. **Check the name's history.** Mergers, renames and dissolutions explain a
   surprising share of these. An organization that existed under the filed name
   in the grant year may be listed under a different name now, or not at all.

If the filed name is a person's name, search it anyway before concluding. Some
are real organizations named after their founder, and some apparent
organizations are people. Both directions occur.

If search returns nothing usable — a generic name with no web presence, a
defunct local body, a name too common to disambiguate — say so. Set
`org_found` to `NO` or `UNCERTAIN` and `search_confirmed` to `INCONCLUSIVE`.
**That is a legitimate and useful answer.** Do not manufacture an
identification to avoid it, and do not promote a near-miss to an answer because
nothing better turned up.

## Do not trust the cascade's own numbers

`score` and `name_sim` are the output of the process that already failed on
this case. They tell you what the matcher thought, which is not evidence about
the world. A near-miss scoring 0.22 can be the right organization and one
scoring 0.60 can be a different body with a similar name.

## Output

Call the `submit_no_verdict` tool exactly once, after you have finished
searching. Prose outside the tool call is not read.

| field | what it holds |
|---|---|
| `grant_id` | echo the case id |
| `org_found` | `YES` if you established who the payee is, `NO` if you could not, `UNCERTAIN` if you have a probable but unconfirmed identification |
| `org_name` | the payee's full legal name as your sources give it, or `""` |
| `ein` | the EIN as digits, from a source that states it, or `""` |
| `ein_source` | `WEB` (an outside source stated it), `CANDIDATE` (read off a near-miss row), `NONE` |
| `entity_class` | what kind of thing the payee is — see the table below |
| `bmf_expectation` | `LISTED` a US exempt-organization record should exist; `NOT_LISTED` it should not; `UNCERTAIN` |
| `outside_reason` | why no record should exist; `NOT_APPLICABLE` when `bmf_expectation` is `LISTED` |
| `miss_hypothesis` | why the cascade failed to find the record; `NOT_APPLICABLE` when `bmf_expectation` is `NOT_LISTED` |
| `confidence` | `high` / `medium` / `low`, in your identification |
| `evidence` | the specific facts that decide it, ≤ 50 words |
| `search_findings` | what you found and where, ≤ 60 words. Include any EIN a source stated, whether or not it appears among the near-misses. |
| `search_confirmed` | `CONFIRMED` a source corroborated your conclusion; `CONTRADICTED` sources point away from every near-miss; `INCONCLUSIVE` searched, nothing decisive; `NOT_SEARCHED` |

### `entity_class`

| value | use it for |
|---|---|
| `NONPROFIT` | a US organization with its own tax exemption |
| `GROUP_SUBORDINATE` | a chapter, lodge, troop, post, club or unit covered by a parent's group exemption |
| `CHURCH` | a church, synagogue, mosque, temple, parish or integrated auxiliary |
| `GOVERNMENT` | a public school or district, public library, municipality, county, state agency, or tribal government |
| `FOREIGN` | an organization organized outside the United States |
| `FISCALLY_SPONSORED` | a project or initiative operating under another organization's exemption |
| `INDIVIDUAL` | a natural person |
| `FOR_PROFIT` | a business, LLC, partnership or other for-profit entity |
| `PROGRAM_OR_EVENT` | a named fund, program, campaign, scholarship or event rather than an entity |
| `AGGREGATE` | a placeholder standing for many payees ("various organizations", "multiple grantees") |
| `UNKNOWN` | search could not establish what this is |

### `outside_reason`

| value | use it for |
|---|---|
| `NOT_AN_ORG` | an individual, a business, a government unit, or a foreign organization |
| `GROUP_RULING` | a subordinate covered by a parent's group exemption and not separately listed |
| `CHURCH_EXEMPT` | a church or integrated auxiliary, which need not apply or file |
| `NO_SEPARATE_EXEMPTION` | a program, fund or project inside another organization |
| `TOO_NEW` | recognized as exempt only recently, possibly after the file was compiled |
| `REVOKED_OR_DISSOLVED` | exemption revoked, or the organization dissolved |
| `NOT_TRACEABLE` | no organization of this description could be found at all |
| `NOT_APPLICABLE` | a record should exist |

### `miss_hypothesis`

| value | use it for |
|---|---|
| `ACRONYM` | the filed name is an acronym or initialism of the legal name |
| `LEGAL_NAME_DIFFERS` | the legal name is a substantially different string |
| `DBA_OR_TRADE_NAME` | filed under a trade name, "aka" or program brand |
| `TRUNCATED` | the filed name is cut off or heavily abbreviated |
| `TYPO` | the filed name is misspelled |
| `PROGRAM_NAMED` | a program or fund of the organization was named instead of the organization |
| `GEOGRAPHY_WRONG` | the filed city, state or ZIP is wrong or inconsistent |
| `PARENT_OR_CHAPTER` | the filed name names the national body and the payee is a local unit, or the reverse |
| `PLAIN_MISS` | the filed name and the legal name are close and it simply should have matched |
| `NOT_APPLICABLE` | no record should exist |

## Worked examples

**`UCAP SCHOOL`, Providence RI.** Search finds the Urban Collaborative
Accelerated Program, a Providence middle school, whose ProPublica record states
EIN 05-0448102. `org_found` YES, `ein` 050448102, `ein_source` WEB,
`entity_class` NONPROFIT, `bmf_expectation` LISTED, `miss_hypothesis` ACRONYM.
The cascade had the right organization at 0.38 and rejected it.

**`SHAW CANCER CENTER`, Edwards CO.** Search establishes this is a cancer center
operated by Vail Health, not a separate legal entity. There is no EIN of its
own to find. `org_found` YES, `ein` "", `entity_class` FISCALLY_SPONSORED,
`bmf_expectation` NOT_LISTED, `outside_reason` NO_SEPARATE_EXEMPTION. This is a
correct NO and it is not a matcher failure.

**`ST BARTHOLOMEWS CHURCH`.** Search finds an Episcopal parish. Churches are
exempt without applying. `entity_class` CHURCH, `bmf_expectation` NOT_LISTED,
`outside_reason` CHURCH_EXEMPT — even if some churches do appear in the file,
the expectation is that this one need not.

**`JOEL BASS`.** Search finds no organization of this name; the filed status
text reads like an individual grant. `org_found` NO, `entity_class` INDIVIDUAL,
`bmf_expectation` NOT_LISTED, `outside_reason` NOT_AN_ORG, `confidence` high.
The grant should never have entered the matching path.

**`EASTER SEAL SOCIETY OF DEL-MAR`, filed `NEW CASTLE PA 19720`.** Search finds
Easter Seals Delaware and Maryland's Eastern Shore in New Castle, *Delaware* —
ZIP 19720 is Delaware, and the filed state is simply wrong. `bmf_expectation`
LISTED, `miss_hypothesis` GEOGRAPHY_WRONG. State blocking never offered the
right record because the state it blocked on does not exist for that ZIP.

**`THE SALVATION ARMY`, Birmingham AL.** A near-miss reads `SALVATION ARMY
BIRMINGHAM AREA COMMAND` in Birmingham AL. Search confirms the Birmingham Area
Command is the local Salvation Army body. The EIN here would come off the
candidate row, so `ein_source` is CANDIDATE unless an outside source states it.
`entity_class` GROUP_SUBORDINATE but `bmf_expectation` LISTED — this
subordinate *is* separately listed. `miss_hypothesis` PARENT_OR_CHAPTER.

That last example is the one to study. `entity_class` describes the entity;
`bmf_expectation` describes whether a record should exist. They are different
questions and a subordinate can answer the first one way and the second the
other. Decide them separately.
