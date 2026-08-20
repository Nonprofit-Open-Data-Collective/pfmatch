# The distinctive-name promotion floor, measured on 990-PF grants

npmatch's hierarchical score contains an override: if name similarity ≥ 0.95 and
the reference name occurs in at most `distinct_name_maxfreq` (3) records, the
pair's score is **floored** to 0.90 when the state agrees (0.72 when it does
not), regardless of what the address evidence said. 0.90 clears the 0.78
auto-accept gate on its own.

The code cites ~97% reliability, measured on the SAM/USASpending training set.
This is what it does on 990-PF grants.

## 1. What it carries

| | YES | MAYBE | NO |
|---|---:|---:|---:|
| promotion ON (default) | 2,814 | 1,037 | 1,069 |
| promotion OFF | 2,698 | 885 | 1,337 |

**121 YES matches (4.3% of the tier) exist only because of the floor**, and all
121 fall to **MAYBE, not NO**, when it is disabled — so the floor is not creating
recall out of nothing, it is deciding whether these get adjudicated or
auto-accepted.

Their evidence profile is stark:

| geo evidence on the floor-dependent pairs | n | share |
|---|---:|---:|
| ZIP5 exact | 0 | 0% |
| ZIP3 only | 4 | 3% |
| **state only** | **117** | **97%** |
| no geo at all | 0 | 0% |

So: an exact-ish name, a name that is rare in the BMF, the same state, and
nothing else.

## 2. Precision, hand-checked

Thirty were read by hand against name, city, state and ZIP. Roughly **25–26 look
correct**, 2 are clearly wrong, and 2–3 are doubtful — call it **~85%**, against
the ~97% the code claims from a different dataset. Still far above the level that
would justify removing the mechanism, but not what the comment promises.

Correct examples, and they are the reason to keep it: `KOINONIA ACADEMY`
(Princeton NJ → Plainfield NJ), `ATHOL MEMORIAL HOSPITAL` (Gardner → Athol MA),
`FRACTURED ATLAS` (Hartsdale → New York NY), `GIVEMN` (Minneapolis → St Paul MN),
`YAFFED` (New City → Brooklyn NY), `CASA OF CENTRAL TEXAS` (Austin → New
Braunfels TX). In each the grant address is a mailing address and the BMF holds
the headquarters — exactly the case the floor exists to rescue.

## 3. Two distinct failure modes, only one of which is the floor's fault

**(a) Generic but lexically unique.** `name_freq` counts how many records share
the exact string. `COMMUNITY CHURCH` is unique in the BMF — every other one is
"*Place* Community Church" — so it passes the gate while identifying nothing. A
Big Bear Lake CA grant was auto-accepted to a Fort Jones CA congregation 700
miles away. Same shape: `CHRIST CHURCH` Philadelphia → Beaver Springs PA,
`HOUSE OF HOPE` Stuart → Tallahassee FL, and a recipient literally named `1`.

**(b) High JW on genuinely different names.** `CONGREGATION AGUDATH ISRAEL` →
`CONGREGATION ADAT ISRAEL`, two different congregations. This is **not** a floor
problem:

| pair | JW |
|---|---:|
| `CONGREGATION AGUDATH ISRAEL` vs `CONGREGATION ADAT ISRAEL` | **0.978** |
| `AGUDATH ISRAEL` vs `ADAT ISRAEL` (head stripped) | 0.936 |
| `FIRST BAPTIST CHURCH OF SALEM` vs `... OF SALINE` | **0.980** |
| `BAPTIST SALEM` vs `BAPTIST SALINE` | 0.956 |

The pair clears the 0.95 bar only because `CONGREGATION ` is 13 identical leading
characters and Jaro-Winkler pays a prefix bonus on top. It would score 0.95+ with
the floor switched off entirely. Only 7 of 121 promoted pairs (6%) lead with a
common institutional word, so the ceiling on fixing this is small — and it
belongs to the comparator, not here.

## 4. The fix: gate on information, not just rarity

`name_freq` measures **lexical** rarity. What the promotion actually needs is
**identifying power**. Summed token IDF measures that directly, and npmatch
already computes `np_token_idf()` and already plumbs it into `np_compare()`.

Implemented as `distinct_name_min_idf` (default **10**):

* `np_compare()` now emits a `name_idf` column — the summed IDF of the reference
  name's content tokens — alongside the existing `name_freq`.
* `.np_hier_score()` requires `name_idf >= distinct_name_min_idf` for promotion.
* Pairs with no `name_idf` (callers that do not pass `token_idf`) are **not**
  gated, so existing behaviour is preserved. `0` disables it.

At threshold 10 the gate demotes **5 of 121**, and **4 are the errors above**:

| demoted | IDF | → matched to | verdict |
|---|---:|---|---|
| `1` | 0.0 | `1`, Boonton NJ | junk |
| `COMMUNITY CHURCH` | 6.0 | Fort Jones CA | wrong |
| `CHRIST CHURCH` | 7.2 | Beaver Springs PA | wrong |
| `HOUSE OF HOPE` | 9.6 | Tallahassee FL | wrong |
| `THE CENTER FOR MICHIGAN` | 9.2 | Detroit MI | probably correct |

One likely-correct match moves to MAYBE, where it is still adjudicated. Nothing
is lost.

### Why not a higher threshold

Tempting, but wrong. `CONGREGATION AGUDATH ISRAEL` — one of the two clear errors
— has IDF **24.2**, *higher* than correct matches like `TIDES CENTER` (13.9),
`KOINONIA ACADEMY` (14.0), `YAFFED` (14.5) and `GIVEMN` (14.5). Raising the gate
to 25 catches both errors but demotes **96 of 121**, including every one of those.
IDF cannot separate failure mode (b), and pretending otherwise would trade 4
fixes for ~80 unnecessary demotions.

| min IDF | kept | demoted | known-wrong caught |
|---:|---:|---:|---:|
| 0 (off) | 121 | 0 | 0 of 2 |
| **10** | **116** | **5** | **1 of 2** |
| 20 | 62 | 59 | 1 of 2 |
| 25 | 25 | 96 | 2 of 2 |

## 5. Recommendation

* **Keep the floor.** It carries 121 matches at ~85% precision, and without it
  they go to the adjudication queue rather than disappearing.
* **Ship `distinct_name_min_idf = 10`.** Cheap, targeted, four errors removed for
  one questionable demotion, and it is off for any caller that does not supply
  `token_idf`.
* **Do not raise the threshold** to chase the second failure mode. That is a
  Jaro-Winkler prefix-bonus problem on shared generic heads, affects 6% of
  promoted pairs, and needs a comparator change rather than a gate.
* **The 97% figure in the comment should be re-stated as dataset-specific.** It
  measures ~85% here.

---

# CORRECTION: the IDF gate was the wrong fix. The real defect is DBA promotion.

§4 above shipped `distinct_name_min_idf` on the strength of a probe showing it
demoted 5 of 121 promoted matches, 4 of them errors. **A clean A/B on the live
pipeline showed it moves 2 cases, net zero.** The probe was wrong in a specific
and instructive way.

## What the probe got wrong

It computed the name's IDF from the **query** name (`recip_name`). The shipped
code computes it from the **reference** name key, which is what `name_freq`
measures. And the reference legal names behind those errors are not generic at
all:

| query | reference *legal* name | name_idf |
|---|---|---:|
| `COMMUNITY CHURCH` | `FORT JONES COMMUNITY CHURCH` | 20.2 |
| `CHRIST CHURCH` | `CHRIST CHURCH OF BEAVER SPRINGS` | 29.4 |
| `HOUSE OF HOPE` | `HOUSE OF HOPE COMMUNITY DEVE…` | 17.6 |
| `1` | `SLOVAK GYMNASTIC UNION SOKOL…` | 37.3 |

All four sail through an IDF gate, because on the reference side they *are*
informative.

## The actual defect

If the reference legal name is `FORT JONES COMMUNITY CHURCH`, it cannot have
scored ≥ 0.95 against a query of `COMMUNITY CHURCH`. It did not. `np_compare()`
scores the full name/DBA/division cross-product and keeps the best, and
`name_ver_y` records which won:

| query | matched on | reference legal name |
|---|---|---|
| `COMMUNITY CHURCH` | **DBA** `Community Church` | `FORT JONES COMMUNITY CHURCH` |
| `CHRIST CHURCH` | **DBA** `Christ Church` | `CHRIST CHURCH OF BEAVER SPRINGS` |
| `1` | **DBA** `1` | `SLOVAK GYMNASTIC UNION SOKOL` |

So the promotion's justification — *this exact legal name is rare in the
reference, so trust an exact match on it* — was computed about a string that had
nothing to do with the match. A DBA is frequently a short generic trade name
whose rarity means nothing.

## The fix: `distinct_name_main_only` (default TRUE)

Promotion now requires the match to have been made on the **primary** name.

| config | YES | MAYBE | NO | known errors caught |
|---|---:|---:|---:|---:|
| neither gate | 2,834 | 1,028 | 1,058 | 0 of 3 |
| `min_idf = 10` only | 2,833 | 1,024 | 1,063 | **0 of 3** |
| **`main_only` only** | **2,821** | **1,006** | **1,093** | **3 of 3** |
| both | 2,822 | 986 | 1,112 | 3 of 3 |

It demotes **13** YES to MAYBE, all DBA matches, and the demotions are
overwhelmingly justified — in most the DBA belongs to a quite different legal
entity:

| query | DBA matched | legal entity | geography |
|---|---|---|---|
| `COMMUNITY CHURCH` | Community Church | FORT JONES COMMUNITY CHURCH | Big Bear Lake → Fort Jones |
| `CHRIST CHURCH` | Christ Church | CHRIST CHURCH OF BEAVER SPRINGS | Philadelphia → Beaver Springs |
| `1` | 1 | SLOVAK GYMNASTIC UNION SOKOL | Bridgeton → Boonton |
| `HOUSE OF HOPE` | House Of Hope | AJ HOPE | Stuart → Tallahassee |
| `CARING SOLUTIONS` | Caring Solutions | SERVICES BY DESIGN | Ballwin → St Louis |
| `Pregnancy Resource Center` | Pregnancy Resource Center | MOUNTAIN RIGHT TO LIFE | San Clemente → San Bernardino |
| `University of Texas at Austin` | University Of Texas At Austin | **CHI ALPHA ISFM CAMPUS MINISTRY** | Austin → Austin |
| `OHIO STATE UNIVERSITY FOUNDATION` | The Ohio State University | **CHI ALPHA CHRISTIAN FELLOWSHIP** | Columbus → Columbus |
| `YOUTH WITH A MISSION` | Youth With A Mission | Y W A M METRO | Orlando → Jupiter |

The two campus-ministry cases are the clearest illustration: a ministry *at* a
university carries the university's name as its DBA, and matching a grant to it
instead of the university is exactly the error the gate stops.

Two of the 13 look like real losses — `UJA-FEDERATION OF NEW YORK` → legal
`UNITED JEWISH APPEAL FEDERATION…` is the same organization, and `EMBRACE KIDS
FOUNDATION` may be a rebrand. Both land in MAYBE and are adjudicated, so nothing
disappears.

## Disposition

* **`distinct_name_main_only = TRUE`** — shipped as the default. Fixes 3 of the 5
  known errors.
* **`distinct_name_min_idf = 0`** — default changed to disabled. The mechanism is
  retained and documented, since the reasoning is sound and may suit a reference
  whose primary names *are* generic, but it does nothing here.
* `CONGREGATION AGUDATH ISRAEL` remains YES. That is the Jaro-Winkler
  generic-head case, deliberately not fixed — see `COMPARATOR-FINDINGS.md`.
