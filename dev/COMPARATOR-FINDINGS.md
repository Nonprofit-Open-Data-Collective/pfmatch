# The Jaro-Winkler generic-head problem: measured, and not worth fixing

The promotion-floor audit left one error unexplained by the IDF gate:
`CONGREGATION AGUDATH ISRAEL` matched to `CONGREGATION ADAT ISRAEL`, two
different congregations, at JW **0.978**. The hypothesis was that a long shared
generic head ("CONGREGATION ", 13 identical leading characters) inflates
Jaro-Winkler past the 0.95 promotion bar. Stripping the head drops it to 0.936,
so the hypothesis is correct.

Whether it is worth fixing is a different question, and the answer is no.

## 1. A real evaluation set, not two hand-picked cases

Two labelled sets, both cheap and both honest:

* **Negatives** — pairs of **distinct BMF EINs**, same state, JW ≥ 0.95. Different
  EIN means different registered organization, by construction. 340 collected.
  They are exactly the failure mode: `MYMICHIGAN MEDICAL CENTER STANDISH` vs
  `... SAGINAW`, `SPIRITUAL ASSEMBLY OF THE BAHAIS OF DE...` vs `... OF AM...`,
  `MINISTERIAL ASSOCIATION OF PAWNEE COUNTY` vs `... OF ANTHONY`.
* **Positives** — accepted grant→BMF matches from the YES tier whose **ZIP5
  agrees exactly**, so the name match is corroborated by something other than the
  name. 1,897 collected.

## 2. Token-level disagreement separates them — on paper

| feature | negatives (median) | positives (median) |
|---|---:|---:|
| `jw` | 0.963 | 1.000 |
| `jw_tail` (head stripped) | 0.578 | 0.879 |
| IDF-weighted token agreement | 0.520 | 1.000 |
| IDF of disagreeing tokens | 17.7 | 0.0 |

`idf_disagree ≤ 15` blocks 61% of negatives while losing 4% of positives — about
2.8 negatives per positive lost. Promising enough to test live.

## 3. A bug in my own feature, worth recording

Applied to the 121 live promoted pairs, the gate initially demoted obviously
correct matches with enormous scores — `YOUTH WITH A MISSION` vs
`Youth With A Mission` at 66.8, `University of Texas at Austin` vs
`University Of Texas At Austin` at 55.1.

Cause: I compared `name_key_x` / `name_key_y`, the **primary** name keys. But
`np_compare()` scores the full name/DBA/division cross-product and keeps the
best, recording the versions that actually matched in `name_x` / `name_y`. For
that record the BMF *legal* name is `Y W A M METRO` — the acronym — while the DBA
is `Youth With A Mission`. The match is correct and was made on the DBA; my
feature was reading strings the comparator had already rejected.

**Anything that post-processes npmatch pairs must use `name_x` / `name_y`, not
`name_key_x` / `name_key_y`.** Using the wrong pair would have demoted 17 correct
matches.

## 4. With the right strings, the gate stops paying

| rule | demoted | known-wrong caught | known-right lost |
|---|---:|---:|---:|
| `dis_concat > 20` | 2 | 1 of 5 | 0 of 11 |
| `dis_concat > 12` | 5 | **1 of 5** | 0 of 11 |
| `dis_concat > 8` | 6 | 1 of 5 | 1 of 11 |

It catches **one** of the five known errors, and four of its five demotions are
wrong:

| demoted | matched to | verdict |
|---|---|---|
| `NOVO CENTER FOR MARINE SCIENCE` | `NOYO CENTER FOR MARINE SCIENCE` | one-letter typo, same org |
| `CONGREGATION AGUDATH ISRAEL` | `CONGREGATION ADAT ISRAEL` | **correctly caught** |
| `Sisters of St Francis` | `Sisters Of St Francis` | identical |
| `Help Hygiene` | `HELPHYGIENE` | de-spacing, same org |
| `COVERED BRIDGE RIVER JAXX BASEBALL` | `COVERED BRIDGE RIVERJAXX BASEBALL` | de-spacing, same org |

My concat- and typo-awareness was not robust enough to protect the de-spacing
cases even after being written specifically to do so.

## 5. Why the other four errors are invisible to this feature

`COMMUNITY CHURCH`, `CHRIST CHURCH`, `HOUSE OF HOPE` and `1` all score
`dis_concat = 0` — because the two names are **identical**. There is no name
disagreement to detect. The error is that an identical *generic* name matched a
different organization, which is exactly what `distinct_name_min_idf` (already
shipped) catches.

So the two failure modes are cleanly separated, and only one of them is worth
code:

| failure mode | n of 5 | fix |
|---|---:|---|
| generic name, identical strings | 4 | `distinct_name_min_idf = 10` — **shipped** |
| different names, shared generic head | 1 | this gate — **not worth it** |

## 6. Recommendation

**Do not change the comparator.** The remaining error affects roughly 1 in 121
promoted pairs — about 0.03% of the YES tier — and every gate that catches it
costs four correct matches. The IDF gate already handles 4 of the 5 known errors
at a cost of one questionable demotion.

If this is revisited, the direction that looked strongest was `jw_tail`
(head-stripped Jaro-Winkler: negatives 0.578 vs positives 0.879 on the hard
band). It was not pursued because it needs care around exact matches, where
stripping the shared head leaves nothing to compare — and on this evidence the
prize is one case per 5,000 grants.
