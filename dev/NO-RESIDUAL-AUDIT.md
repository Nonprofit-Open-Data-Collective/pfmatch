# What is actually left in the NO residual

Internet audit of 100 identities drawn from the 592 that are **NO under both
references** — the part of the file the two-tier cascade cannot reach. Run
2026-10-22. Scripts: `dev/build-no-residual-audit.R`,
`dev/stratify-no-residual.R`, `dev/score-no-residual.R`. Verdicts:
`dev/no-residual-verdicts.csv`.

## Why this population and not the NO tier

The tier-1 NO tier is 15% of the file, but tier 2 recovers or surfaces a quarter
of it (67 → YES, 75 → MAYBE). Auditing it would measure a population the
cascade does not leave behind. The 592 NO→NO identities are what survives both
references, which is what "cannot be matched" has to mean once tier 2 exists.
They are 12.2% of the 4,869 identities.

## The headline

| | n of 100 | of the 592 |
|---|---:|---:|
| **recoverable in pfmatch** | **35** | **~207** |
| genuine floor | 59 | ~349 |
| unresolved | 6 | ~36 |

The recoverable part is worth **4.3 points** of clear rate. It is not a data
problem:

> **All 21 EINs established independently of the reference were present in
> *both* references.** Zero missing from the BMF. Zero missing from matchdb.

Independently matters here. Four more EINs were read off a reference near-miss
row, and those are in the reference by construction — counting them would make
the test circular, so they are excluded.

So the residual is a name-resolution problem, not an absence problem. The August
NO audit found 13 of 15 web-confirmed EINs already in the BMF; this run finds 21
of 21, on a harder population (NO under *both* references, not just tier-1 NO)
and against a reference twice the size. The finding was not an artifact of the
old active-only BMF, and widening the reference did not shrink the residual's
cause.

## How the residual divides

Adjudicated from the filed record, the web, and both references' near-misses:

| | n |
|---|---:|
| payee is a person | 42 |
| **a real organisation, missed** | **32** |
| no such organisation traceable | 9 |
| payee has no exemption of its own | 8 |
| exact name present, wrong place | 3 |
| unresolved | 6 |

"No exemption of its own" is the honest floor and it is structural: a parochial
school under an archdiocesan group ruling, a food pantry operating inside
Catholic Social Services, Shaw Cancer Center inside Vail Health, the Rainbow
PUSH Automotive Project inside the Citizenship Education Fund, a high-school
post-prom committee. There is no EIN to find. Two more are not charities at
all — a for-profit nursing facility and a county health district.

## Why the 32 recoverable cases were missed

| | n |
|---|---:|
| acronym or initialism | 6 |
| legal name differs from the filed name | 6 |
| dba or trade name | 5 |
| plain name, plain miss | 5 |
| truncated or abbreviated | 3 |
| typo in the filed name | 3 |
| event or programme named as the payee | 3 |
| filed state or city is wrong | 1 |

Nothing here is exotic. `CASA OF NJ` is Court Appointed Special Advocates of New
Jersey at the filed ZIP. `BOROUGHS COMMUNITY CENTER` is Burroughs Community
Center at the filed ZIP — one letter. `LIONS EYE DOUNDATION OF CA & NV` misspells
*Foundation*. `GIRLS INC` in Hagerstown is Girls Inc of Washington County at the
filed street address. `WISH BOOK 2020 FUND` is the San Jose Mercury News Wish
Book Fund with the campaign year appended, and the BMF near-miss was already
that exact organisation.

That last pattern recurs: in many of the 32 the reference row the scorer needed
was the one it already surfaced and rejected. `THISTLEBEND COTTAGE` → Thistlebend
Ministries. `SAAWTU USA` → SAAWTU America. `MIRACULOUS LOVE MINISTRIES` →
Miraculous Love International Ministries. `Donovan Bank Foundation` → Donovan
**and** Bank Foundation. These are not retrieval failures; the candidate was in
hand and scored too low.

## The reference often holds the right name AND the right city

A direct probe of the reference for 26 of the 67 cases
(`dev/no-residual-probe-output.txt`) goes further than the EIN lookup. It
searched by rare token pair rather than by blocking key, so it sees rows the
blocker never offered the scorer — and in several cases those rows carry both
the correct name and the correct city:

| filed | reference row found | EIN |
|---|---|---|
| `DANCE PLACE DC WHEEL PRODUCTIONS INC` (Washington DC) | `DC WHEEL PRODUCTIONS INC AKA DANCE PLACE` (Washington DC) | 52-1118504 |
| `The Salvation Army` (Birmingham AL) | `SALVATION ARMY BIRMINGHAM AREA COMMAND` (Birmingham AL) | 58-0660607 |
| `JUVENILE DIABETES RESEARCH FOUNDATION` (Atlanta GA) | `JUVENILE DIABETES RESEARCH FOUNDATION GA CHAPT` (Atlanta GA) | 23-1907729 |
| `MUSCULAR DYSTROPHY` (Boston MA) | `MUSCULAR DYSTROPHY ASSOCIATIONS OF AMERICA INC` (Boston MA) | 23-7148632 |
| `Cong Mesilas Hachessed` (Brooklyn NY) | `CONGREGATION MESILAS HACHESED` (Brooklyn NY) | 83-1272141 |
| `MIRACULOUS LOVE MINISTRIES` (Franklin TN) | `MIRACULOUS LOVE INTERNATION MINISTRIES` (Franklin TN) | 20-8092403 |

The Dance Place row is the sharpest: the reference carries four alias rows on
that EIN, one of which is `DC WHEEL PRODUCTIONS INC AKA DANCE PLACE`, and the
filed name is almost exactly that string concatenated. The pipeline returned NO.

This narrows the diagnosis. It is not only that the right name is absent from
the candidate set — for these the right name **and** place are both present and
retrievable, so the failure sits in blocking or scoring, not in the reference and
not in the geography term. That is a stronger and more actionable claim than
"name resolution", and it is where the 4.3 points live.

## Two findings that are not about the residual

**1. The individual-payee flags miss half of what they should catch.** The
pipeline's own signals (`looks_personal`, `recipient_type`, the filed status
code) classified 28 of the 100 as individual payees. Adjudication puts the true
count at **42**. Fourteen named people — `JOEL BASS`, `BROOKLYN GARRISON-OSBORN`,
`JONES MAURICE`, `SMALL RANDALL`, `George Dupree` — were routed into the matching
path, where they can only ever fail or match something wrong.

This does not raise the clear rate; it cleans the denominator. Scoped to this
cell alone, ~249 of the 592 are individuals. Removing just those from the 4,869
moves the cascade's 69.0% to roughly **72.7%**. The real figure is higher still,
because the other cells were not sampled — and the August audit found the error
runs the other way too (the OOS flag was wrong 24% of the time, coding real
organisations as individuals). Both directions are broken, and neither has been
measured end to end.

**2. State blocking has a failure mode worth one point.** `EASTER SEAL SOCIETY OF
DEL-MAR` is filed as `NEW CASTLE PA 19720`. ZIP 19720 is New Castle,
*Delaware* — the filed state is simply wrong, and state blocking therefore never
offered the correct organisation. One case in 100. State blocking is a ~1.8x
throughput lever and worth keeping, but it should fall back to the ZIP when the
filed state and ZIP disagree, which is a cheap check.

Separately, three cases carry the **exact** filed name in the reference and still
score 0.60, below the 0.65 MAYBE floor, because the organisation is a common one
and the geography does not corroborate: `UNIVERSITY BAPTIST CHURCH`,
`ST BARTHOLOMEWS CHURCH`, `CHRIST CHURCH CATHEDRAL`. Two more —
`PLAYWORKS` and `UNIVERSITY BAPTIST CHURCH` — score 0.60 with *both references
agreeing on the EIN*. The 0.60 cap is the geography term doing its job on a
name that cannot discriminate, and these should not be forced through.

## What this says to do next

1. **Blocking and scoring, not reference coverage.** 6 acronyms, 6 legal-name
   divergences, 5 dba names, 3 truncations — 20 of 32 are one mechanism, and the
   probe above shows the reference already carries the alias row with the right
   city for at least six of them. matchdb's observed and dba variants are why
   tier 2 wins the cleared cell (`dev/CASCADE-STRATEGY.md` §3); here the variant
   was present and still did not clear. Start by replaying these 32 through
   `np_block` and `np_score` with the correct EIN known, and find out at which
   stage each one is lost — that is a cheap, decisive diagnostic and it has not
   been run.
2. **Fix the individual-payee flags before re-quoting any clear rate.** A
   denominator with 14% misrouted individuals understates every figure in the
   project, and the fix is independent of matching.
3. **Add the ZIP-vs-state fallback to blocking.**
4. **Do not raise the YES threshold or widen the geography term** to chase these.
   Five of the 100 are common names where the reference holds an exact string and
   the place does not corroborate; loosening there buys wrong EINs, which is the
   failure mode the cleared-cell adjudication already found tier 2 producing.

## Method and its limits

- 100 drawn with `set.seed(2026)` from the 592; no stratification before drawing.
- Strata assigned from the filed record *before* any searching, deliberately
  conservative: a case went to "individual" only on a person-shaped name **and**
  an individual-shaped signal, so borderline cases were searched rather than
  assumed away. Nine of them turned out to be people.
- 46 of the 67 cases were resolved by a dedicated web search; the other 21 rest
  on the filed record plus both references' near-misses being unambiguous
  (`Cong Mesilas Hachessed` → Congregation Mesilas Hachesed). They are marked
  `basis = reference` in the verdict file. Of the 32 REAL-ORG verdicts, 21 carry
  a web-established EIN, 4 an EIN read off a near-miss, and 7 no EIN at all.
- Reference presence was tested by exact EIN against both compiled references,
  not by name, so the "all 21 in both" result does not depend on any
  normalisation choice — and it uses only the 21 EINs whose source was outside
  the reference.
- Single adjudicator, no blind second pass. The August experience is that
  independent re-checking overturns a meaningful share of labels, so treat the
  32/59/6 split as having a few points of slack. The "all 21 EINs present in
  both references" result is the robust one — it is a mechanical lookup.
