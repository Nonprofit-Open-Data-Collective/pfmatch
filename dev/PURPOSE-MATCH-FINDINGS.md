# Does grant-purpose text surface the correct EIN? Measured.

`dev/PURPOSE-MATCH-DESIGN.md` proposed a design. This is what happened when it
was built and run against labeled cases. Several of its recommendations do not
survive contact with the data — §6 lists the corrections.

**Short version.** No, the text fields do not surface the correct answer in most
cases. Grant-purpose similarity is *precise but rarely applicable*: on the
adjudicated set it separates candidates on 50% of grants that have a contentful
purpose (so ~27% of all grants), and when it does separate them it picks the
right EIN 13 times out of 14. It is silent or tied on almost every case that
actually causes an error. Worth adding as a tie-band feature for roughly +2
grants in 28; not worth building a semantic pipeline around.

And an unexpected result: **whether a candidate files a Form 990 at all
discriminates better than anything in the text of that 990** (§4).

---

## 1. What was built

| script | what it does |
|---|---|
| `dev/build-990-text-wide.R` | 553,488 returns → one row per OBJECTID, mission + program_01..10 |
| `dev/purpose-enrich.R` | shared enrichment: NTEE reference text, 990 text per EIN, purpose stoplist |
| `dev/build-purpose-testset.R` | **gold** set from the 100 adjudicated MAYBE cases |
| `dev/build-purpose-testset-yes.R` | **silver** set from the YES tier |
| `dev/eval-purpose-sim.R` | the metrics and the read-out (`dev/EVAL-PURPOSE-SIM.log`) |
| `dev/probe-ntee-availability.R` | is NTEE present on the candidates that need it? |
| `dev/probe-text-presence.R` | how much of the signal is presence rather than content? |

| set | file | rows | grants | usable |
|---|---|---|---|---|
| gold | `data-dev/PURPOSE-TESTSET.csv` | 485 | 100 | 63 adjudicated, **29** with a contentful purpose, **6** where the correct EIN is not already rank 1 |
| silver | `data-dev/PURPOSE-TESTSET-YES.csv` | 5,372 | 2,819 | 794 with >1 candidate, 390 of those with a contentful purpose |

Both carry, per candidate: BMF NTEE code + definition + NTEEv2 subsector, IRS
activity text, the NTEE reference text (level 3–5 labels + category description
+ keywords, joined on NTEEv2 with a fallback to the legacy code — 89% joined),
the 990 Part III mission, and all program descriptions concatenated. Per grant
they carry the filing foundation's EIN, name, NTEE code and definition.

The gold set is small because that is all the adjudicated truth there is. The
silver set treats the accepted YES EIN as correct and the other top-5 candidates
as distractors; it is not hand-verified, and its distractors are easier, but it
is the same discrimination task at n in the hundreds rather than tens. Note that
**no YES grant has a runner-up inside the tie band** — the cascade is decisive
where it is confident, which is why silver can measure discrimination but cannot
measure re-ranking (its baseline top-1 is 1.000 by construction).

---

## 2. The foundation is a dead end as a text source

Three separate tests, all negative.

**It has no mission text to give.** 0.0% of the filing foundations in the gold
set have Form 990 Part III text — they file 990-PF, which has no Part III. There
is no foundation mission statement to join. The `fdn_mission` / `fdn_prog_all`
columns are in the test set and they are empty by construction.

**Its NTEE code says only that it is a foundation.** Across the 26,361 distinct
filing foundations in the 50k run: 57.0% carry an NTEE beginning `T`
(Philanthropy, Voluntarism & Grantmaking) — `T20` and `T22` alone are 40% — and
another 32% are `UNDEFINED` or absent from the BMF. Roughly 11% carry a
substantive program code.

**Measured, it has no signal.** On the gold set the correct candidate shares the
foundation's NTEE major group 2.8% of the time; the distractors, 4.5%. The
comparison points the wrong way and is indistinguishable from noise.

The stronger version of the idea — use the foundation's *portfolio* of
already-matched grantees as an empirical prior — is also weak. Foundations with
≥5 confidently matched grantees spread across a median of **5 distinct NTEE major
groups**, with a top-group share of 0.333 against a 0.268 base rate; at ≥20
grantees it is 13 groups and 0.25. These are diversified givers, not thematic
ones.

Keep the foundation join for the review sheet (a reviewer wants to see who wrote
the check). Do not build a feature on it.

---

## 3. NTEE is missing precisely where it is needed

The design memo leaned on NTEE as the always-available signal. It is not.

`ntee_code_clean` is blank / `INVALID` / `UNDEFINED` / `Z99` for **33.5%** of the
1.92M BMF records, and — counterintuitively — the rate *rises* with organization
size:

| revenue | records | unusable NTEE |
|---|---|---|
| no revenue reported | 807,848 | 28.5% |
| < $100k | 180,570 | 27.5% |
| $100k – $1M | 249,146 | 32.6% |
| $1M – $10M | 94,920 | 40.5% |
| **> $10M** | 30,574 | **56.8%** |

Large organizations are exactly the ones that receive foundation grants, appear
repeatedly as candidates, and spawn foundation-arm ambiguities. Consequently:

| | gold | silver |
|---|---|---|
| **correct** candidate has unusable NTEE | 46.0% | 44.7% |
| distractor has unusable NTEE | 31.1% | 35.7% |
| grants where *no* candidate has a usable NTEE | 1.6% | 34.3% |
| grants where every usable NTEE is the same letter | 20.6% | — |

The correct candidate is *more* likely than the distractors to be missing the
code. This is visible directly in the hard cases: the right answer for `SIERRA
CLUB FOUNDATION`, `PLANNED PARENTHOOD FEDERATION OF AMERICA`, `BOCA RATON
REGIONAL HOSPITAL`, `SUMMIT CHARTER SCHOOL FOUNDATION`, and `BIG BROTHERS BIG
SISTERS LONE STAR` all read `INVALID`.

Measured as a feature, `has_ntee` has a pair AUC of **0.425** (gold) and 0.455
(silver) — below 0.5, i.e. weakly predictive of being *wrong*.

---

## 4. Presence beats content

The single most surprising result. Pair AUC — probability the correct candidate
scores above a distractor — on the gold set, 63 grants / 304 candidate rows:

| feature | pair AUC | top-1 when it separates | grants |
|---|---|---|---|
| `score` (name + geo, the existing cascade) | **0.861** | 0.783 | 60 |
| `text_len` — chars of mission + program text | **0.810** | 0.569 | 58 |
| `n_prog` — number of program services reported | 0.792 | 0.691 | 55 |
| `has_mission` | 0.744 | 0.860 | 50 |
| `has_program` / `files_990` | 0.742 | 0.769 | 52 |
| `cos_all` — TF-IDF cosine, purpose vs all org text | 0.674 | 0.733 | 15 |
| `cov_all` — IDF-weighted containment, all org text | 0.665 | **0.929** | 14 |
| `has_ntee` | 0.425 | 0.362 | 47 |

Silver agrees: `text_len` 0.778, `n_prog` 0.756, `has_program` 0.735, against
`cov_all` 0.636.

Reading it plainly: **the fact that a candidate filed a full Form 990 with
program descriptions is a better discriminator than any comparison of what those
descriptions say.** Real grant recipients are active filers; the same-named
distractors are frequently dormant shells, defunct chapters, or
group-exemption subordinates that file nothing.

Two cautions before anyone wires this in. It is a size-and-activity prior, so it
will systematically disfavour small real grantees — the kind a family foundation
gives $500 to — and that is a bias, not just a loss of recall. And it partly
overlaps whatever the name cascade already captures. It should be tested inside
the tie band and measured for what it demotes, not adopted on this AUC alone.

Restricting to grants where *every* candidate has 990 text — controlling presence
away — the content metrics fall to `cov_prog` 0.604 / `cov_all` 0.602 (silver,
158 grants). Content is worth roughly 0.10 of AUC above chance once presence is
held constant.

---

## 5. What the similarity metrics actually do

Gold, 29 grants with a contentful purpose. `fires` = share of grants where the
metric produced a non-degenerate ordering (not all-zero, not all-tied); `top-1`
is conditional on firing.

| metric | pair AUC | fires | grants fired | top-1 | MRR |
|---|---|---|---|---|---|
| `ng4_all` char 4-gram, all text | 0.679 | 1.00 | 28 | 0.429 | 0.661 |
| `cos_all` TF-IDF cosine, all text | 0.674 | 0.54 | 15 | 0.733 | 0.867 |
| **`cov_all`** IDF containment, all text | 0.665 | 0.50 | 14 | **0.929** | **1.000** |
| `nb_major` naive-Bayes NTEE bridge | 0.644 | 0.93 | 13 | 0.538 | 0.718 |
| `cov_ntee` | 0.621 | 0.45 | 9 | 0.556 | 0.778 |
| `cov_mis` mission only | 0.536 | 0.38 | 9 | 0.556 | 0.815 |
| `cov_name` candidate name (control) | 0.533 | 0.07 | 2 | 1.000 | 1.000 |
| `cov_act` activity codes | 0.505 | 0.17 | 3 | 0.333 | 0.667 |
| baseline `score` | 0.861 | — | 60 | 0.783 | 0.946 |

Three things to read off this.

**IDF-weighted containment is the right functional form, and it is precise.**
`cov_all` has the best MRR of any metric (1.000 — when it separates candidates
at all, the correct one is always on top) and 0.929 top-1. The asymmetric
containment argument from the design memo holds up: it beats plain cosine on
ranking even though cosine's AUC is nominally higher.

**Character n-grams fire on everything and rank nothing.** `ng4_all` produces an
ordering on 100% of grants and gets 43% of them right — barely better than the
~25% you would get at random from five candidates. It is a similarity that is
always non-zero, which is exactly the failure mode flagged in the design memo for
dense scores. Do not use it as a ranker; keep it, if at all, as a morphology
assist inside the token match.

**Coverage, not discrimination, is the binding constraint.** The best metric is
undefined or tied on half the contentful-purpose grants — which are themselves
only 55% of grants. Compounded: ~27% of grants get any usable purpose signal.

Silver, 1,345 grants with a contentful purpose, tells the same story more
cheaply: `cov_all` 0.636 AUC / fires 0.54 / top-1 0.676 (210 grants);
`cov_prog` 0.598 / 0.61 / 0.713; `cov_ntee` **0.527**; `cov_name` **0.521**.

### The semantic bridge works, and it still does not help

A multinomial naive Bayes trained on 337,260 mission statements labeled with the
filer's own BMF NTEE major group predicts the code correctly:

| input | top-1 over 25 labels |
|---|---|
| full mission statement | 59.1% |
| first 3 content tokens | 48.7% |
| first 2 content tokens | 43.5% |
| majority class | 15.4% |

So text → NTEE is learnable, and truncating to purpose-statement length costs
about 15 points. But as a candidate feature `nb_major` reaches only 0.644 AUC
(gold) / 0.616 (silver), and **adding it to the name score makes things worse**:
top-1 goes 22/28 → 20/28 at w=0.2 and 17/28 at w=0.4. It confidently assigns a
sector to a two-word purpose and then penalizes correct candidates whose BMF code
disagrees with it. The failure is not the model; it is that the grant purpose
describes the *beneficiary program* while the NTEE code describes the
*organization's primary activity*, and these routinely differ.

### Combining with the existing score

Gold, contentful purpose, 28 grants with an unambiguous label:

| added feature | w = 0 | 0.05 | 0.10 | 0.20 | 0.40 |
|---|---|---|---|---|---|
| `cos_all` | 22/28 | **24/28** | 24/28 | 24/28 | 24/28 |
| `cov_all` | 22/28 | 23/28 | 23/28 | 23/28 | 23/28 |
| `cov_ntee` | 22/28 | 22/28 | 22/28 | 22/28 | 22/28 |
| `nb_major` | 22/28 | 22/28 | 22/28 | 20/28 | 17/28 |

+2 grants in 28, flat across two orders of magnitude of weight (the metric is
mostly deciding ties, so its scale barely matters), and nothing demoted. On 28
cases that is one standard error — directionally right, not established.

### Why it fails on the hard cases

Of the 6 gold grants where the correct EIN is not already rank 1, the purpose
signal is silent or tied on 5:

* `REACHING HIGHER TOGETHER CAMPAIGN` (Santa Barbara Cottage Hospital
  Foundation) — a campaign name, no domain content; every candidate scores 0.
* `IN SUPPORT OF THE FIREWORKS PICNIC` (Sigma Gamma Association) — no candidate
  has any text; all zero.
* `TO FURTHER ONE OR MORE OF THE EXEMPT PURPOSES OF THE CHARITY` (Planned
  Parenthood) — pure boilerplate; all zero.
* `EDUCATION` (Summit Charter School Foundation) — `cov_all` = 1.00 for **all
  five** candidates, four of which are unrelated charter schools.
* `YOUTH DEVELOPMENT` (Boys & Girls Club of Salem) — `cov_all` = 1.00 for four
  of five, including three Boys & Girls Clubs in other states.

This is structural, not a tuning problem. The two dominant ambiguity classes the
audit identified — **foundation arm vs operating entity** and
**group-exemption subordinates** — are precisely the cases where both entities
legitimately do the same thing. A purpose that describes the shared activity
cannot separate them. `SUMMIT CHARTER SCHOOL` and `SUMMIT CHARTER SCHOOL
FOUNDATION` are both about education, and so is `MOT CHARTER SCHOOL`.

The one case where it helps is `BIG BROTHERS BIG SISTERS LONE STAR`: purpose
`SUPPORT FOR CHILDREN ACTIVITIES AND EDUCATION` scores 0.57 on the correct
operating entity and 0.00 on the `T30` foundation arm at rank 1 — the design
memo's predicted use case, working exactly once in six.

---

## 6. Corrections to `PURPOSE-MATCH-DESIGN.md`

| § | claim | verdict |
|---|---|---|
| §2 | IDF-weighted containment is the right functional form, not cosine or Jaccard | **holds** — best MRR (1.000) and top-1 (0.929) of any metric |
| §2 | char n-grams as a morphology backstop | **partly wrong** — fires on 100% of grants and ranks at 0.429; it adds noise, not recall. Keep only inside the token match, never as a ranker |
| §3a | bridge through NTEE — "cheap, explainable, build this first" | **overstated**. 85% vocabulary reachability did not translate: `cov_ntee` AUC 0.527 (silver). NTEE is unusable on 33.5% of the BMF, 56.8% above $10M revenue, and is missing *more often on the correct candidate* than on the distractors (§3) |
| §3a | train purpose→NTEE on the 553k mission corpus | **works as a model, fails as a feature** — 59.1% top-1 on missions, but adding it to the score costs 2–5 grants in 28 |
| §3b | escalate to embeddings if lexical falls short | **do not** — content adds ~0.10 AUC over presence alone; a denser similarity is unlikely to change that, and it would make the always-fires / never-ranks problem worse |
| §4 | per-field scores beat one concatenated block | **contradicted on the numbers**. `_all` beats every single field on both sets, because the binding constraint is coverage, not dilution. The availability-mask reasoning still stands — it is *why* the union wins — but implement it as one text union with an availability count, not four weighted scores |
| §5 | keep the candidate name out of the comparison text | **holds** — `cov_name` AUC 0.533/0.521, fires on 7–8% of grants |
| new | the filing foundation as a second text source | **dead** (§2) |
| new | presence of a 990 filing beats its content | **strongest single finding** (§4) |

---

## 7. Recommendation

**Add `cov_all` as a tie-band feature and stop there.** One IDF-weighted
containment score of the grant purpose against the union of the candidate's NTEE
text, activity text, mission, and program descriptions; `NA` when the purpose is
boilerplate or the candidate has no text; applied only where name and geography
have already failed to separate candidates; never able to admit a candidate the
cascade did not produce. Expected value is around +2 grants in 28 on the MAYBE
tier — worth having, given it demotes nothing, and roughly an order of magnitude
less than adjudicating the MAYBE tier at all (+11 to +14 points, per
`AUDIT-FINDINGS.md`).

**Do not build the NTEE bridge, the naive Bayes classifier, or the embedding
tier.** Each was tested; none earns its complexity.

**Test the presence prior next.** `text_len` / `n_prog` / `has_mission` outrank
every content metric by 0.10–0.15 AUC and are free to compute — the join is
already built. The open question is not whether they discriminate but what they
demote: they encode organization size, so they will penalize small real
grantees. Measure the tier movement in both directions before adopting.

**Get more truth.** Every conclusion above about *re-ranking* rests on 29 gold
grants, of which 6 are hard. The silver set has n but its baseline is 1.000 by
construction, so it can only measure discrimination. Adjudicating another 200–300
MAYBE cases would cost less than any of the modeling above and is the only thing
that would let these numbers carry weight.

---

## 8. Should the score simply be added to the linkage score, gated on length?

Measured in `dev/probe-additive-risk.R`. The gate is right and the gating
variable is wrong; the additive-to-the-global-score part is the risky half and
buys nothing a tie-band tiebreak does not.

### Length is the wrong gate

Character count is only loosely related to whether a purpose says anything.
Across the 855 distinct purposes in both test sets:

| purpose length | grants | contentful |
|---|---|---|
| ≤ 10 chars | 124 | 29.0% |
| 11–20 | 346 | 31.2% |
| 21–30 | 165 | 46.7% |
| 31–50 | 115 | 81.7% |
| 51–100 | 75 | 97.3% |
| > 100 | 30 | 100.0% |

The tails are where the errors live. **55 purposes of ≤12 characters are
contentful** — `SCHOLARSHIP`, `EDUCATION`, `Culture`, `YOUTH` — and a length gate
throws away the cheapest signal in the file. **23 purposes longer than 30
characters are contentless**: `TO SUPPORT THE MISSION OF THE ORGANIZATION`,
`A GRANT TO FURTHER THE DONEE'S EXEMPT PURPOSE`, `GENERAL DONATION TO SUPPORT
ORGANIZATION'S ACTIVITIES.` — long, fluent, and empty, and a length gate lets all
of them through.

Gate on **IDF mass after stoplisting**, not on length: does the purpose contain at
least one token that is not funding boilerplate? That is what
`purpose_contentful` computes, and it is what the length buckets above are
measured against. Build it as a rule cascade in the shape of
`pf_standardize_status()` — the boilerplate vocabulary is open-ended (`GOS`,
`As needed`, `Gen'l`, a check stub) and a fixed stoplist will keep leaking.

And note there is a *second* gate the proposal is missing, on the reference side:
the candidate must have text to compare against. Encoding "no text" as a zero
score silently converts the feature into an organization-size prior (§4).

### Additive across all pairs is a real, measurable cost

`score + w · cov_all`, content gate on, `NA` treated as neutral:

| set | scope | w=0.05 | w=0.10 | w=0.20 | w=0.40 |
|---|---|---|---|---|---|
| GOLD (61 contested grants, base 47) | all pairs | +1 | +1 | +1 | +1 |
| GOLD | margin ≤ 0.05 | +1 | +1 | +1 | +1 |
| **SILVER** (794 grants, all currently right) | **all pairs** | 0 | **−1** | **−2** | **−14** |
| SILVER | margin ≤ 0.05 | 0 | 0 | 0 | 0 |

`cos_all` gains more on gold (+2: three gained, one lost) and costs nothing on
silver at any weight — but only because its magnitudes are tiny, not because it
is safer in principle.

Two things fall out of this table.

**The tie band is what makes the feature free.** 39.3% of contested gold grants
have a top-2 margin ≤ 0.05; **0.0%** of silver grants do. The band cleanly
separates "the cascade is unsure" from "the cascade is settled," so restricting
to it keeps the entire gain and zeroes the entire loss. Applied across all pairs
instead, the same term reaches into 794 grants that were already right and, at
w=0.40, breaks 14 of them for no compensating gain.

**The weight is meaningless, which is the tell.** Inside the tie band the result
is identical from w=0.05 to w=0.40. That is not robustness — it means the term is
never changing the *magnitude* of anything, only the *order* of near-equals. A
parameter with no effect over an eightfold range is a tiebreak wearing a score's
clothing. Implement it as a tiebreak and the parameter disappears.

Related trap: `cov_all` and `cos_all` are on incomparable scales — p90 of 1.000
vs 0.088, max 1.000 vs 0.403. A single `w` tuned on one is off by an order of
magnitude on the other, and any published weight is uninterpretable without the
metric's distribution attached.

### The threshold problem

`pf_report()`'s YES / MAYBE / NO split is driven by `np_config` thresholds and
`min_margin` against the score. Adding a term to that score shifts its
distribution and silently moves records across the tier boundaries — including
records the purpose feature never fired on, if `NA` is encoded as 0. Any additive
version therefore requires re-tuning the thresholds and re-running the benchmark
before its match rate is comparable to `BENCHMARK-NOTES.md`. A tiebreak applied
after selection changes no score and needs no re-tuning.

### Verdict

Not a bad instinct — the gating half is correct and necessary. But implement it
as an **ordered tiebreak inside the tie band**, not a term added to the linkage
score:

1. gate on IDF mass, not length (query side);
2. gate on the candidate having text at all (reference side) — `NA`, never 0;
3. apply only where the top-2 margin is inside the tie band;
4. break the tie on `cov_all` and leave the score untouched.

Same measured gain, no exposure on the 49.5% that already works, no threshold
re-tuning, and no weight to tune.

---

## 9. Is it better as a *set* signal than a *rank* signal?

A fair and important question, and the general instinct behind it is right:
a recall-first feature — one that reliably keeps the correct record *in* the
candidate set — is usually more robust than one that has to put it *on top*,
because a filter only has to be safe, not decisive. It is the standard shape of
a blocking or pruning stage.

It does not work here, and `dev/probe-threshold-recall.R` shows why in one line:
**this metric's failure mode is silence, not misordering.**

### The threshold sweep

Recall = share of grants where the correct candidate clears the floor.
Prune rate = share of distractors removed.

| metric | floor | recall | prune rate | mean candidates kept (of 5) |
|---|---|---|---|---|
| `cov_all` (gold) | 0 | 1.000 | 0.000 | 5.00 |
| | >0 | **0.536** | 0.768 | 1.46 |
| | 0.5 | 0.393 | 0.857 | 0.96 |
| `cov_all` (silver) | 0 | 1.000 | 0.000 | 4.22 |
| | >0 | **0.428** | 0.793 | 1.09 |
| | 0.5 | 0.238 | 0.927 | 0.47 |
| `cos_all` (silver) | >0 | 0.428 | 0.793 | 1.09 |
| | 0.1 | 0.159 | 0.937 | 0.36 |

The instant the floor rises above exact zero, recall of the correct candidate
falls off a cliff — to 0.536 on gold and 0.428 on silver — because **46–57% of
correct candidates score exactly zero**. There is no floor at which the feature
is both safe and useful:

    recall >= 1.00 with any pruning : NOT ACHIEVABLE
    recall >= 0.99 with any pruning : NOT ACHIEVABLE
    recall >= 0.95 with any pruning : NOT ACHIEVABLE

on both sets and both metrics. (Whether candidates with no text are kept or
dropped barely moves it: 1.000 → 0.997 at t=0.)

For contrast, here is what a feature that *is* a good filter looks like — the
existing linkage score, same sweep, same grants:

| floor | recall | prune rate |
|---|---|---|
| 0.75 | **1.000** | **89.0%** |
| 0.80 | 0.990 | 95.5% |
| 0.85 | 0.950 | 98.1% |

That is a safe floor: it removes nine distractors in ten and never drops the
truth. Purpose similarity has no equivalent point anywhere on its curve.

### Why the two uses need different properties

* **Ranking** needs the feature to be trustworthy *when it is high*. It may
  abstain freely — a zero simply means "do not reorder," and the name score
  decides as before.
* **Filtering** needs the feature to be trustworthy *when it is low*. A floor
  cannot distinguish "this candidate is wrong" from "I have no evidence," and
  purpose similarity is zero overwhelmingly for the second reason: the purpose
  was boilerplate, the candidate has no 990 text, or the shared vocabulary
  simply missed.

So the robustness argument inverts for this particular signal. Used as a ranker
it is a weak feature that is silent half the time. Used as a filter, that same
silence becomes an *active deletion of the correct answer*, half the time.

### The one high-end rule that does carry information

The asymmetric version — trust it only when it is high — does show real lift.
On silver, where a random candidate is correct 23.7% of the time:

| rule | rows | precision | grants where the high scorer is unique | precision there |
|---|---|---|---|---|
| `cov_all` ≥ 0.5 | 183 | 0.503 | 72 | **0.764** |
| `cov_all` ≥ 0.7 | 141 | 0.496 | 56 | **0.768** |
| `cov_all` ≥ 0.9 | 126 | 0.484 | 52 | 0.731 |

A uniquely high scorer is correct about three quarters of the time against a 24%
base rate — a genuine 3× lift. But note two things. It is still far below the
cascade's own accuracy on those grants (1.000 by construction on silver), so it
is not competitive as a standalone acceptance rule. And "uniquely highest" is a
*ranking* statement, not a threshold one. The information lives at the top of the
distribution, which is exactly where the tiebreak in §8 already reads it.

### And as a candidate generator it is hopeless

The strongest form of the question — could a purpose floor *surface* correct
matches the cascade never produced, and fix the NO tier? — fails on block size.
37.5% of contentful purposes are a single content token, and containment on one
token returns (`dev/probe-purpose-blocksize.R`, over the 545k organizations with
990 text):

| purpose token | grants using it | organizations matching | share of corpus |
|---|---|---|---|
| `COMMUNITY` | 1,175 | 140,701 | 25.8% |
| `EDUCATION` | 2,086 | 112,269 | 20.6% |
| `PROMOTE` | 403 | 72,088 | 13.2% |
| `SCHOOL` | 411 | 66,058 | 12.1% |
| `CHILDREN` | 571 | 61,711 | 11.3% |
| `YOUTH` | 461 | 46,986 | 8.6% |
| `SCHOLARSHIP` | 2,503 | 9,288 | 1.7% |

Median block over the twenty most common contentful tokens: **50,844
organizations**. `SCHOLARSHIP` is the tightest in the top twenty and still
returns 9,288. A generator that returns fifty thousand candidates at 43% recall
is worse on both axes than the name cascade it would supplement.

### Answer

No — as a set-membership signal it is strictly worse than as a rank signal, for
this feature. The intuition is sound and worth keeping for other features: it is
exactly the right test to apply, and it is the reason `score` is used the way it
is. Apply the same test to the presence features from §4 — `has_mission`,
`n_prog`, `text_len` are dense, never silent, and are the natural candidates for
a recall-first floor. That is the version of this idea worth measuring next, and
§10 measures it.

---

## 10. The presence features, tested the same way

`dev/probe-presence-prior.R`. The recall-first floor fails here too — for a
different and more interesting reason — but the tiebreak works, and works better
than purpose similarity does.

### A. There is no safe floor either

Best floor achieving each recall level, and what it prunes:

| feature | recall ≥1.00 | ≥0.99 | ≥0.95 | ≥0.90 |
|---|---|---|---|---|
| `has_mission` (gold) | — | — | — | t=1 : 55% |
| `text_len` (gold) | — | — | — | t=92.5 : 60% |
| `n_prog`, `has_program` (gold) | — | — | — | — |
| everything (silver) | — | — | — | — |

Purpose similarity failed as a filter because it is *silent* — zero meaning "no
evidence." Presence fails for the opposite and more stubborn reason: the zeros
are **real**. 184 of 794 correct candidates on silver (23.2%) genuinely have no
990 mission, and 233 (29.3%) no program text. Those are 990-N postcard filers and
small organizations that receive grants and file nothing describing themselves.
A floor set anywhere above zero deletes that whole population, and it is not a
tail — it is a quarter of the answer set.

So the recall-first framing is dead for both feature families, and for
complementary reasons. It remains the right question to have asked; it just has
no affirmative answer in this data.

### B. As a tiebreak it works, and binary beats continuous

Reordering inside the tie band on the feature alone, no weight — gold, 61
contested grants, baseline 47 correct (0.770):

| tiebreak | gained | lost | net | top-1 |
|---|---|---|---|---|
| `text_len` | 7 | 4 | +3 | 0.820 |
| **`has_mission`** | 2 | **0** | **+2** | 0.803 |
| `cov_all` (purpose) | 1 | **0** | +1 | 0.787 |
| `has_program` | 2 | 2 | 0 | 0.770 |
| `n_prog` | 4 | 4 | 0 | 0.770 |

Silver: 0 gained, 0 lost for every feature at every band, because no silver grant
has a top-2 margin inside 0.05.

The pattern is worth noting. **The binary "does this organization file at all"
is safer than any continuous measure of how much it filed.** `text_len` and
`n_prog` gain more and lose more — they are measuring organization size, and size
overreaches: it starts picking the biggest same-named entity rather than the one
that actually files. `has_mission` asks the narrower question and gets it right
without collateral damage.

### C. Cascading them is the best of the lot

| tiebreak cascade | gained | lost | net | top-1 |
|---|---|---|---|---|
| `cov_all` → `has_mission` → `text_len` | 7 | 3 | +4 | 0.836 |
| **`cov_all` → `has_mission`** | 3 | **0** | **+3** | **0.820** |
| `has_mission` → `cov_all` | 3 | 0 | +3 | 0.820 |
| `text_len` alone | 7 | 4 | +3 | 0.820 |
| `has_mission` alone | 2 | 0 | +2 | 0.803 |
| `cov_all` alone | 1 | 0 | +1 | 0.787 |

`cov_all` → `has_mission` is the zero-loss optimum: 0.770 → **0.820** on the
contested set, +3 grants, nothing broken, and no effect at all on silver. The
order does not matter — the two orderings give identical results, meaning the two
signals never meaningfully disagree; they are covering different grants, which is
exactly why the cascade beats either alone. Appending `text_len` buys one more
grant and costs three, which is the point at which size starts overreaching
again.

### D. What it costs, and a correction

I flagged earlier that a presence prior would disfavour small grantees. Half
right, and the wrong half matters:

* **It is not biased against small grants.** Median grant amount is $5,000
  whether or not the correct candidate files a 990 (silver, identical; gold
  $5,000 vs $2,950 on n=4). Small foundations give small grants to organizations
  of every size, so grant amount does not proxy grantee size here.
* **It is biased against non-filing organizations**, which is a real and
  identifiable population: 23.2% of correct answers on silver. In **10.5% of
  silver grants (83 of 794) the correct candidate has no mission while a
  distractor does** — a presence tiebreak picks wrong in every one of those, if
  the band ever fires there. On gold it is 1 of 61 (1.6%). The tie band is what
  keeps this contained; widening it would expose the whole 10.5%.

One caveat on the gold measurement. The adjudicators saw `pf_candidate_frame()`
output, which carries BMF `asset_amount` and `revenue_amount` — correlated with
filing status, though not the 990 text itself. So a small circularity risk
remains on the gold set specifically. Silver has no such exposure, but its band
never fires, so it cannot confirm the gain.

### Revised recommendation

Replace §7's single-feature suggestion with a **two-key cascaded tiebreak inside
the tie band**: `cov_all`, then `has_mission`. No weights, no threshold
re-tuning, no exposure outside the band. Measured: +3 grants of 61 on the
adjudicated set with zero losses (0.770 → 0.820), and zero movement on the 794
YES grants.

That is still 13 grants moving on a 61-grant set. It is the right shape and the
magnitude is unestablished — which continues to point at the same conclusion as
§7: adjudicate more MAYBE cases before believing any of these numbers to a
decimal place.
