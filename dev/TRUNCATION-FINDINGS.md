# Truncation-aware reference comparison: measured, and not worth building

I proposed this as the next lever after the MAYBE audit, on the strength of
candidates like `PLANNED PARENTHOOD FEDERATION OF` and `Boys And Girls Club Of
Greater La C` appearing in the audit output. The premise does not survive
measurement. This records what was checked, so it is not re-proposed.

## 1. Most of the "truncated" names were my own display width

The audit scripts printed candidate names with `substr(x, 1, 34)`. Checking the
BMF directly:

| audit showed | BMF actually holds |
|---|---|
| `Boys And Girls Club Of Greater La C` | `BOYS AND GIRLS CLUBS OF GREATER LA CROSSE INC` |
| `Northwest Ohio Hemophilia Foundatio` | `NORTHWEST OHIO HEMOPHILIA FOUNDATION` |

So several motivating examples were artifacts of my own reporting, not defects in
the reference.

## 2. The real BMF cap is 70 characters, and almost nothing hits it

`org_name_raw` runs to a maximum of **70** characters — not the 35 I assumed from
the 990-PF side. Records sitting at the cap: **1,495 of 1,924,822 (0.08%)**.

Genuine mid-phrase truncation, detected as a name ending in a dangling function
word (`... OF`, `... AND`, `... IN`): **3,873 records (0.20%)**.

Both are real — `PLANNED PARENTHOOD FEDERATION OF` (EIN 13-1644147) is truly
stored that way, at 32 characters, in both `org_name_raw` and `org_name_join`.
But at 0.2% of the reference this cannot be a meaningful recall lever.

## 3. Jaro-Winkler already handles it

Prefix truncation is the case JW is *best* at, because the Winkler boost rewards
a shared prefix:

| query | reference | JW | prefix-aligned JW |
|---|---|---:|---:|
| `PLANNED PARENTHOOD FEDERATION OF AMERICA` | `PLANNED PARENTHOOD FEDERATION OF` | **0.960** | 1.000 |
| `PLANNED PARENTHOOD FEDERATION OF AMERICA` | `PLANNED PARENTHOOD EXPOSED` | 0.883 | 0.929 |
| `COMMUNITY FOUNDATION OF WESTERN NORTH CAROLINA` | `COMMUNITY FOUNDATION OF WESTERN` | 0.935 | 1.000 |
| `EVANGELICAL LUTHERAN CHURCH IN AMERICA` | `EVANGELICAL LUTHERAN CHURCH IN AMER` | 0.995 | 1.000 |

A prefix-aligned comparator would raise these to 1.000 — but it raises the
*distractor* too (0.883 → 0.929), and JW already ranks the correct candidate
first. There is no ordering to fix.

## 4. So why did the Planned Parenthood cases fail?

Not on the name. Running the real comparator on `G002178`:

| rank | candidate | name_sim | score |
|---|---|---:|---:|
| 1 | PLANNED PARENTHOOD EXPOSED | 0.817 | **0.650** |
| 2 | PLANNED PARENTHOOD FEDERATION OF | **0.933** | 0.560 |

**Name similarity already favours the correct candidate.** The score inverts
because of the geo term: the filed address is a **lockbox** (`PO Box 97166,
Washington DC 20090`), which matches neither candidate's real location, and the
wrong one picked up geo credit the right one did not.

On `G001981` the mechanism is different again: the filed name is the bare
`PLANNED PARENTHOOD`, four candidates share ZIP 10038 and therefore identical geo
credit, and the correct one has the *lowest* name similarity of the four because
the query is generic. That is a **query-side** ambiguity, not reference
truncation.

**Conclusion: do not build truncation-aware reference comparison.** The defect is
0.2% prevalent, JW already orders it correctly, and the cases that motivated the
idea fail for unrelated reasons.

---

# What turned up instead: ZIP3 credit

Chasing the geo term surfaced a live issue. `np_default_geo_weights()` gives
`zip3 = 0.55` — above `city` (0.50) and 2.75x `state` (0.20) — for sharing a
3-digit ZIP prefix.

**A ZIP3 is a huge area.** Median BMF organizations per ZIP3 vs per ZIP5 differ
by more than an order of magnitude, yet ZIP3 carries 61% of ZIP5's credit.

**An exact name plus a shared ZIP3 auto-accepts:**
`0.6 x 1.0 + 0.4 x 0.55 = 0.82`, clearing the 0.78 gate with no real address
corroboration. **352 YES matches (12.5%) rest on ZIP3 as their strongest geo
evidence**, and the ones sitting at 0.78-0.82 include clear errors:

* `YMCA OF SAN FRANCISCO` (94108) → `PAC OF SAN FRANCISCO` (94127)
* `STAGES REPERTORY THEATRE` (77019) → `TEXAS REPERTORY THEATRE COMPANY` (77069)

## But lowering the weight is close to break-even

Sweeping `zip3` on the 5,000-grant sample:

| zip3 weight | YES | MAYBE | NO | YES→MAYBE |
|---:|---:|---:|---:|---:|
| 0.55 (default) | 2,814 | 1,037 | 1,069 | — |
| 0.50 | 2,808 | 1,042 | 1,070 | 6 |
| **0.44** | 2,798 | 1,052 | 1,070 | **16** |
| 0.30 | 2,798 | 1,039 | 1,083 | 16 |

Only **16** cases move, not 352 — because most ZIP3-only matches are held up by
the **distinctive-name promotion floor** (0.90 for a rare exact name), which is
applied by `pmax` *after* the geo score and is therefore untouched by the weight.

Of those 16, roughly 2 are the clear false positives above and the rest are
correct-but-generic (`SPAULDING REHAB HOSPITAL CORP` → itself, `Communities
United` → itself, `QUEERSPACE COLLECTIVE` → `QUEER SPACE COLLECTIVE`). They move
to MAYBE, so nothing is lost — but it is a queue cost for a precision gain of
about two cases per 5,000 grants.

**Recommendation: leave `zip3` at 0.55 for now.** The change is defensible but
too close to break-even to make on 5,000 grants and two hand-read errors. If it
is worth revisiting, the higher-leverage target is the **distinctive-name
promotion floor**, which is what actually carries most of these matches past the
gate — and which has never been measured on this dataset.
