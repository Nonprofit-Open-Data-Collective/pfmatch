<div id="main" class="col-md-9" role="main">

# What lives outside the BMF

An automated cascade either finds a grant recipient in the IRS Business
Master File or it does not. [Adjudicating the MAYBE
tier](https://nonprofit-open-data-collective.github.io/pfmatch/articles/adjudicating-maybe.md)
is about the cases where it found several candidates and could not
choose. This one is about the cases where it found nothing worth
offering — and the first thing to say is that most of them are not
matching failures at all.

**Of 91 randomly drawn NO identities, 53 are payees the Business Master
File could never contain.** Individuals collecting scholarships,
businesses, government bodies, foreign organisations, and placeholders
like `SEE SCHEDULE ATTACHED`. Only 33 are organisations the file should
list and the cascade missed. The honest floor — real bodies with no
exemption of their own — is 6.

<div class="section level2">

## The tier this is about

| status | identities | share of 4,903 | meaning                               |
|:-------|-----------:|:---------------|:--------------------------------------|
| YES    |       2979 | 60.76%         | accepted automatically                |
| MAYBE  |       1044 | 21.29%         | candidates surfaced, none decisive    |
| NO     |        845 | 17.23%         | nothing surfaced, or all of it vetoed |
| OOS    |         35 | 0.71%          | flagged out of sample before matching |

<div class="section level3">

### 845, not 725

The published baseline reports **725** NO. `pf_status()` reports
**845**, and the gap is the interesting part.

| shape                                       | identities | in the baseline’s denominator |
|:--------------------------------------------|-----------:|:------------------------------|
| retrieved something, scored below the floor |        725 | yes                           |
| no blocking pass produced any pair at all   |        120 | **no**                        |

`pf_status()` runs over every identity in the file. The tiered result
runs only over identities that got at least one scored candidate. 120
in-scope identities never reached the result frame because no blocking
pass produced any pair at all — and so the baseline’s denominator of
4,748 **excludes the cases retrieval failed on hardest**.

| denominator  |    n | what                                            | YES alone  |
|:-------------|-----:|:------------------------------------------------|:-----------|
| result frame | 4748 | identities with at least one scored candidate   | 62.74%     |
| in scope     | 4868 | every identity the cascade should have resolved | **61.20%** |
| whole file   | 4903 | every identity in the population file           | 60.76%     |

On the in-scope denominator the same run is 61.20%, not 62.74%. That is
not a defect in the arm; it is a statement about which figure answers
which question. A match rate cannot drop the grants its retrieval step
never reached. Everything below is reported against 4,868.

</div>

</div>

<div class="section level2">

## Why there is no *no-search* arm

The MAYBE experiment compared a cheap model, an expensive one, and the
expensive one with web search, because all three could answer its
question: the correct EIN was already in the candidate set 71% of the
time, so a reviewer confined to the packet had something real to decide.

Here it is not. A NO case has no candidate worth offering, so **when
there is an answer it is outside the packet 100% of the time.** A model
without search can only report that the filed name does not resemble the
records already rejected, which is what the cascade said. So every arm
on this tier has search.

An earlier version of this page went further and said no cheaper
strategy was benchmarked because none applied. That was two claims in
one sentence and only the first holds. A cheaper *model* with search
applies perfectly well; it had simply not been run.

<div class="section level3">

### It was run, and it reproduces the findings

Haiku 5.5 on the same 100 cases, through the same case renderer and the
same collection code — the arm is parameterised by model, not forked, so
the two arms cannot drift apart in anything but the model.

| arm       | recoverable | share | ci               | token cost / 100 | searches |
|:----------|:------------|:------|:-----------------|:-----------------|:---------|
| Opus 5.5  | 33 of 91    | 36.3% | \[27.1%, 46.5%\] | $6.69            | 319      |
| Haiku 5.5 | 30 of 91    | 33.0% | \[24.2%, 43.1%\] | **$1.31**        | 436      |

The overlap is near-total: **30 found by both arms, 3 by Opus only, none
by Haiku only.** All three Opus-only cases are `SALVATION ARMY`, where
Haiku identified the organisation and then declined to name an EIN — for
an ambiguous local corps against a national body that is the defensible
answer rather than a failure to search. And where both arms named an
EIN, **they named the same one 31 times out of 31.**

The taxonomy this page publishes survives the substitution:

| field             | agreement | kappa |
|:------------------|:----------|:------|
| `bmf_expectation` | 95.6%     | 0.909 |
| `outside_reason`  | 92.3%     | 0.864 |
| `entity_class`    | 86.8%     | 0.816 |
| `miss_hypothesis` | 80.2%     | 0.651 |

`entity_class` agrees exactly on the two classes that carry the headline
— `INDIVIDUAL` 39 and 39, `NONPROFIT` 27 and 27. `miss_hypothesis` is
the weakest, which is what the most speculative field in the schema
should do: it asks the model to guess *why* a match failed, the one
question it cannot check against a source. Both arms also flag the same
single reference absence, Commonwealth University of Pennsylvania. Two
independent runs agreeing on which one record the BMF is right to omit
is worth more than either run alone.

So the breakdowns below do not rest on the expensive model.

</div>

<div class="section level3">

### The saving is 5x, not 40x

Haiku 5.5 lists at $0.10/$0.50 per MTok against Opus 5.5’s $4/$20, which
invites an expectation of a 40-fold saving. The measured ratio is
**5.1x**, for two reasons that only show up once the run is instrumented
for them.

Haiku prices a request by its *whole prompt*, stepping to $0.50/$2.50
above 100K tokens, and **22 of the 100 cases crossed that step** — which
is what a web-search turn does. Banking the run’s totals against the
cheap rate would have reported about $0.46 and understated by nearly
three times. Second, the cheap arm ran **37% more searches**, and
searches are billed per use and are in neither figure.

That is the shape of the cost result on this tier: the cheap model is
clearly worth using, and the reason is not the number on the price list.

</div>

</div>

<div class="section level2">

## What a reviewer is given

The filed record — name, street, city, state, ZIP, stated purpose,
amount, tax year, and the foundation’s own recipient-status text, all
uncontrolled filer free text. The filing foundation, as context. And
then one of two things:

-   **no candidate retrieved** (12 of the 100 cases): nothing to show,
    the reviewer works from the filed record alone
-   **the rejected near-misses, with their scores** (88 cases): the
    records the cascade found and declined

The near-misses are shown deliberately. In the prior hand audit the
correct record had *already been offered* in most recoverable cases, so
hiding them would hide the dominant mechanism.

They are also a trap, and the schema is built around it. An EIN read off
a near-miss row is in the reference **by construction** — it got there
because the blocker pulled it out of the reference — so counting it as
evidence that the reference covers this tier is circular. Every verdict
therefore records whether its EIN came from the web or from a candidate
row, and the headline uses web-sourced EINs only.

As it happened, **all 34 EINs in the estimation stratum were web-sourced
and none was read off a candidate row**, so the guard had nothing to
exclude. That was not guaranteed; it is why it was built.

</div>

<div class="section level2">

## How much of the tier is recoverable

|                                  | n            | share     | 95% Wilson       |
|:---------------------------------|:-------------|:----------|:-----------------|
| an EIN was established at all    | 34 of 91     | 37.4%     |                  |
| and that EIN is in the reference | **33 of 91** | **36.3%** | \[27.1%, 46.5%\] |

That projects to **\~306 of the 845** NO identities, \[229, 393\].

“Recoverable” here means: the investigation established an EIN from an
outside source, and that EIN is in the reference. It is a mechanical
set-membership test — the model never saw the reference and was told so.
It is **not** a verified match: an EIN can be in the reference and still
belong to the wrong organisation. The head-to-head below is the only
check on that.

<div class="section level3">

### Is the right EIN already in the reference?

This is the question that decides whether the NO tier is a coverage
problem or a name problem.

|                    | in the reference                      |
|--------------------|---------------------------------------|
| estimation stratum | 33 of 34 — 97.1%                      |
| both strata        | **37 of 38 — 97.4%** \[86.5%, 99.5%\] |

The single exception is `COMMONWEALTH UNIV OF PENN`, EIN 23-2738930,
which the model classed `GOVERNMENT` — a Pennsylvania state university.
A governmental unit is not an exempt organisation, so the file is
**correct** to omit it.

**Zero genuine coverage gaps in 38 independently established EINs.** The
earlier audit found 21 of 21 on a narrower population; this confirms it
on the production tier at nearly double the n. Widening the reference
will not shrink this residual, because the reference already contains
it.

</div>

</div>

<div class="section level2">

## Why the cascade missed them

For the 37 recoverable cases, was the correct EIN ever put in front of
the scorer? Every scored pair is cached, so this is a lookup rather than
a replay of the blocker.

| cause                              | diagnosis                      | n   | share |
|:-----------------------------------|:-------------------------------|:----|:------|
| offered to the scorer and rejected | a scoring / threshold failure  | 26  | 70.3% |
| never offered at all               | a blocking / retrieval failure | 11  | 29.7% |

Where it *was* offered, the score the comparator gave the correct row
was a median of **0.360**, ranging 0.080 to 0.622, against a review
floor of 0.65. Only 2 of 26 reached even 0.60.

So the dominant failure is not retrieval. In 70% of recoverable cases
the right record was in hand and ranked far below the floor.

| hypothesis         | never offered | offered |
|:-------------------|--------------:|--------:|
| LEGAL_NAME_DIFFERS |             2 |       7 |
| TRUNCATED          |             1 |       6 |
| DBA_OR_TRADE_NAME  |             3 |       4 |
| PARENT_OR_CHAPTER  |             0 |       5 |
| ACRONYM            |             1 |       1 |
| GEOGRAPHY_WRONG    |             1 |       1 |
| PROGRAM_NAMED      |             1 |       1 |
| PLAIN_MISS         |             0 |       1 |
| TYPO               |             2 |       0 |

Two patterns are worth naming.

**A misspelling is never retrieved at all.** `THE WESMINSTER SCHOOL` and
`COCORDIA UNIVERSITY` scored *no* candidates — `n_cand = 0`,
`n_pairs = 0`. So did `THE PASSONISTS`, which the model filed under
`DBA_OR_TRADE_NAME` but which fails the same way (`PASSONISTS` against
`PASSIONIST`), making the real count **3 of 91 rather than 2**.

What carries this is the mechanism, not the sample: three cases could
not support the word “never” on their own. Every pass in the cascade is
exact equality — `name_key` or `dba_key` plus ZIP5 or state, a shared
name token within state, an exact name anywhere, initials, an
18-character prefix plus ZIP5 — and npmatch has no approximate
comparator at the blocking stage at all. A one-character edit in the one
distinctive token therefore leaves no key anywhere, while `SCHOOL` and
`UNIVERSITY` are pruned out as too frequent. No comparator can rescue a
case that never reaches it. This is the subject of the next section.

**`PARENT_OR_CHAPTER` is always retrieved and always underscored.** Four
of the five are `SALVATION ARMY` and `YOUNG LIFE` at 0.08 — a name that
cannot discriminate between hundreds of real records, where the
geography term correctly refuses to break the tie. These should *not* be
forced through: loosening there buys wrong EINs.

The two call for opposite fixes, which is why reporting them as one
“name resolution” number would be useless.

</div>

<div class="section level2">

## The one failure no reviewer can fix, and the cheapest fix in the package

Pursuing those three cases turned out to answer a larger question than
the one it was asked.

**The correct record is in the reference at the filed ZIP5.** Not merely
present — present in the block the cheapest pass in the whole cascade
already looks at:

| filed name              | the reference row, at the filed ZIP5                       | similarity |
|:------------------------|:-----------------------------------------------------------|:-----------|
| `THE WESMINSTER SCHOOL` | `THE WESTMINSTER SCHOOLS` 58-0566206, ATLANTA GA 30327     | 0.941      |
| `COCORDIA UNIVERSITY`   | `CONCORDIA UNIVERSITY` 39-0833608, Mequon WI 53097         | 0.924      |
| `THE PASSONISTS`        | `PASSIONIST MISSIONARIES INC` 22-2092362, JAMAICA NY 11432 | 0.857      |

Pass A1 blocks on name plus ZIP5 and misses each of them by one letter.

<div class="section level3">

### Why no adjudication pass can help, at any price

This is worth stating plainly because it is the natural next question.
Adjudication *ranks a candidate sheet*. For these cases the sheet is
empty, so Opus, Haiku or a human reading it sees nothing to choose
between. A cheaper adjudicator, a more expensive one and a
better-instructed one all return the same thing. The failure is upstream
of the stage.

Both search arms did recover them, because search goes outside the
packet. But paying a model to search the web for a missing letter is an
expensive answer to a question string distance answers for nothing.

</div>

<div class="section level3">

### Jaro-Winkler inside a ZIP5 block

`pf_fuzzy_candidates()` scores the filed `name_key` against the
reference rows sharing its ZIP5, falling back to city plus state where
that block is empty, and emits the best few above a cutoff. Blocking
first is what makes it free: the pools are small — median 477 reference
rows on this sample, largest 2,940 — and one pool takes microseconds
against the 223,151 candidates pass B2 generates on 5,000 grants.

It does not reimplement any decision. `npmatch::np_block()` returns
nothing but a frame of row indices, which `np_compare()` accepts
directly, so the pairs go through the same comparator, selector and
tiering as every exact pass and a fuzzy pair clears the same bar.

All three misspellings rank **first** in their own ZIP5 pool, at 0.941,
0.924 and 0.857.

</div>

<div class="section level3">

### The cutoff is set from the collision, not from the recall

Scoring all 91 cases against their ZIP5 pools gives both halves of the
trade-off at once:

| cutoff             | recovered of the 33 the BMF holds | false offers in the 57 it does not | margin to the nearest personal name |
|:-------------------|:----------------------------------|:-----------------------------------|:------------------------------------|
| 0.95               | 3                                 | 0                                  | 0.102                               |
| **0.90** (default) | **7**                             | 1, a placeholder                   | **0.052**                           |
| 0.85               | 11                                | 1, a placeholder                   | 0.002                               |

The default is **0.90**, and the reason is the right-hand column rather
than the left. At 0.85 four more identities are recovered, but the
highest-scoring personal name sits at **0.848** — `ALEXANDER SCHWEIG`
against `ALEXANDER GRAHAM BELL ASSOCIATION`. A one-point margin on 38
individuals is not a margin.

That near-collision is structural, not bad luck: Jaro-Winkler’s prefix
bonus is precisely what rewards a shared first name, so individuals —
43% of this tier — are the population this comparator is worst at
excluding. `skip_personal` keeps them out of the pool rather than
leaving the cutoff to catch them.

The single false offer across the 57 cases the BMF should not hold is
`SEE SCHEDULE ATTACHED` against `SEE SCHEDULE O` at 0.91: two
placeholders are near-identical strings describing nothing. The
placeholder filter removes it on both sides, which is one more reason
the pass does its own filtering rather than trusting a threshold.

</div>

<div class="section level3">

### What it is not limited to

It runs on the **residual**, which is every identity that has not
cleared YES — 845 NO *and* 1,044 MAYBE. “NO” is a tier assigned after
scoring, so it cannot be blocked on, and `np_cascade()` drops an
identity from its pending set only when a pass clears it to YES, which
is the same rule. So the pass changes the MAYBE tier too: it adds rows
to the adjudication queue and can change which row a MAYBE identity
holds.

The YES set is protected by construction rather than by a threshold — an
identity that has cleared is not in the residual, no pair is added to
it, and its selection cannot move. `pf_fuzzy_recover()` asserts that
instead of trusting it, and `dev/adjudicate-16-fuzzy-regress.R`
re-checks it independently.

</div>

</div>

<div class="section level2">

## What lives outside the BMF, and why

| entity_class       |   n | share | \~of 845 |
|:-------------------|----:|:------|---------:|
| INDIVIDUAL         |  39 | 42.9% |      362 |
| NONPROFIT          |  27 | 29.7% |      251 |
| FOREIGN            |   5 | 5.5%  |       46 |
| GOVERNMENT         |   5 | 5.5%  |       46 |
| GROUP_SUBORDINATE  |   5 | 5.5%  |       46 |
| AGGREGATE          |   3 | 3.3%  |       28 |
| CHURCH             |   3 | 3.3%  |       28 |
| PROGRAM_OR_EVENT   |   2 | 2.2%  |       19 |
| FISCALLY_SPONSORED |   1 | 1.1%  |        9 |
| FOR_PROFIT         |   1 | 1.1%  |        9 |

Rolled up by whether a record should exist at all:

|                                             | n        | share     | 95% Wilson       |
|:--------------------------------------------|:---------|:----------|:-----------------|
| not an organisation the BMF could ever hold | 53 of 91 | **58.2%** | \[48.0%, 67.8%\] |
| a real body the BMF should list             | 33 of 91 | **36.3%** | \[27.1%, 46.5%\] |
| a real body with no exemption of its own    | 6 of 91  | 6.6%      | \[3.1%, 13.6%\]  |
| could not be identified at all              | 0 of 91  | 0.0%      |                  |

<div class="section level3">

### Not an organisation (58.2%)

The largest group in the tier by a wide margin. 39 individuals — almost
all scholarship payments to named students — plus 5 government bodies (a
high school, a public elementary school, a county fire and rescue
department, a state university, a university research institute), 5
foreign organisations (a Polish foundation, UNIDROIT, a UK charity, a BC
society, the ICRC), 3 aggregate placeholders, and 1 for-profit.

These reached the matching path, where they can only fail or match
something wrong. **They are a denominator problem, not a matching
problem.**

And the pipeline’s own signals largely did not catch them:

| signal                               | catches  | recall | false positives   |
|:-------------------------------------|:---------|:-------|:------------------|
| `looks_personal` is TRUE             | 11 of 39 | 28.2%  | **0 of 11**       |
| filed status code reads `individual` | 19 of 39 | 48.7%  | not measured here |

Every case `looks_personal` flagged really is an individual — 11 of 11,
no false positives — and it misses 28 of 39. A precise, low-recall flag
is the easy kind to fix: nothing needs to become more conservative, the
202-name given-name list simply has to get longer. Seven payees that are
not organisations at all are affirmatively coded `public_charity` by the
filed status field, which is why that field cannot be trusted on its
own.

</div>

<div class="section level3">

### A real body with no exemption of its own (6.6%)

The honest floor. Two churches (`SEVIER HEIGHTS BAPTIST CHURCH`,
`ST AGNES CHURCH`), which are exempt without applying and need not file;
a diocesan high school under a group ruling; one fiscally sponsored
project; and two named events. There is no EIN to find, so no amount of
matching recovers these.

At 6.6% this is **much smaller** than the prior audit’s 12-in-100
estimate for the same category. The floor is a few percent, not a tenth.

</div>

<div class="section level3">

### Could not be identified at all (0%)

Search identified something in every one of the 91 cases. The prior
audit, which searched 46 of its 67 adjudicated cases, had 10 “no such
organisation traceable”. With search applied to every case that category
disappears.

</div>

<div class="section level3">

### Why `entity_class` and `bmf_expectation` are separate fields

The `INTERNATIONAL COMMITTE OF THE RED CROSS` case earns the
distinction. The model classed it `FOREIGN`, which is right — it is
Swiss — and `bmf_expectation` `LISTED`, which is also right, because it
holds a US exemption record. The EIN it reported is in the reference.

Collapsing “what the entity is” into “should a record exist” would have
scored that case wrong whichever way it collapsed. A Scout troop is a
subordinate and is not listed; a Salvation Army area command is a
subordinate and is. They are different questions.

</div>

</div>

<div class="section level2">

## Does a human agree?

Almost everything above is the model’s judgement, so it needs a check
against something other than the model’s own confidence.

An earlier hand audit adjudicated 67 NO cases. Re-keyed on the filed
recipient name, 63 of them are still NO identities in this arm, so the
same arm was run over exactly those 63 and the two sides compared. Both
judged the same organisations from the same filed record; the only
difference is who judged.

| human’s class                   | model agreed |        |
|:--------------------------------|:-------------|:-------|
| not an organisation             | 11 of 11     | 100.0% |
| a real body the BMF should list | 30 of 34     | 88.2%  |
| no exemption of its own         | 5 of 6       | 83.3%  |
| could not be identified         | 3 of 8       | 37.5%  |

Overall **49 of 59 — 83.1%** \[71.5%, 90.5%\], Cohen’s kappa **0.724**.
Four cases the human marked unclear are excluded; a non-answer cannot
agree or disagree with anything.

Three of the ten disagreements exist only because this comparison maps
the human’s “geography unclear” verdict to *recoverable*. All three are
churches. Dropping that hedge gives 87.5% and kappa 0.795 — the figure
above keeps the conservative reading.

<div class="section level3">

### The one class they diverge on is the reassuring part

37.5% on “could not be identified” looks alarming until the cases are
read. Of the 8 the human could not trace, the model agreed on exactly 3
— and those 3 are precisely the ones where it reported **low confidence
and named no organisation**.

On the other 5 it found something at medium or high confidence.
`DOCKS TO DOORWAYS` is a Belgrade Lakes Association campaign, and the
filed street field literally reads
`PO Box 551 Belgrade Lakes Associati[on]`. `AMERICAN SHRINE ASSOCIATES`
sits at the Basilica of the National Shrine’s address.
`505 Main Street Canton` is not a name at all, it is a street address,
and the depot there is run by a food pantry.

**The model’s confidence tracks the disagreement exactly**: where it
says low it agrees the case is untraceable, and where it says medium or
high it found what the human could not. That is the opposite of the
pattern the [MAYBE search
arm](https://nonprofit-open-data-collective.github.io/pfmatch/articles/adjudicating-maybe.md)
showed, where confidence rose while accuracy fell. Here confidence is
worth routing on.

</div>

<div class="section level3">

### On the EIN itself, which needs no vocabulary mapping

Both sides name an EIN on 24 cases and give **the same nine digits on 23
— 95.8%**. The exception is `The Salvation Army`: the model gives the
Illinois corporation, the human the Southern territory. Both EINs are
real; which is correct depends on which corporation received the money.

The model named an EIN on 11 cases where the human could not, and **all
11 are in the reference** — 5 of them cases the human had already called
a real organisation without being able to produce its number.

The human named one where the model declined:
`Hamilton Co Gen Hlt Dist`. It is a county health district, the model
called it government, and that EIN is the one human EIN *not* in the
reference. The model was right to refuse it.

</div>

<div class="section level3">

### Both sides land in the same place

|       | recoverable, of the same 63 |
|-------|----------------------------:|
| human |                  34 — 54.0% |
| model |                  35 — 55.6% |

|       | independently established EINs in the reference |
|-------|-------------------------------------------------|
| model | **33 of 33 — 100%**                             |
| human | 24 of 25 — 96.0%                                |

Neither side found a single genuine coverage gap.

</div>

</div>

<div class="section level2">

## Where that leaves the match rate

| numerator                          | on 4,868 in scope |
|:-----------------------------------|:------------------|
| YES alone                          | 61.20%            |
| YES + recovered NO                 | 67.49%            |
| YES + cleared MAYBE                | 77.11%            |
| YES + cleared MAYBE + recovered NO | **83.40%**        |

Recovering the NO tier is worth **+6.29 points**. But dropping the
payees that are not organisations the file could ever hold — \~492
identities, taking the denominator from 4,868 to 4,376 — moves YES alone
from 61.20% to **68.08%**, a gain of **+6.88 points**, while matching
precisely nothing.

The scope correction is worth more than the recovery. Only one of the
two is a matching improvement; the other is a statement about which
grants were ever answerable. Both should be reported, and neither should
be quietly folded into a headline.

</div>

<div class="section level2">

## What this does not establish

-   **Recoverability is not accuracy.** 36.3% of the tier has an EIN
    that exists in the reference. Whether it is the *correct* EIN rests
    on the head-to-head above and on the model’s own confidence, not on
    the set-membership test.
-   **The taxonomy is a model’s judgement.** The mechanical parts — is
    the EIN in the reference, was it ever offered, what did it score —
    are not. The split between them is deliberate and the two should not
    be quoted with equal confidence.
-   **One adjudicator on each side.** The human labels come from a
    single pass with no blind second review, and the model ran once at
    one effort level. Neither is a consensus.
-   **`UNCERTAIN` was barely used.** One case of 100. A reviewer that
    almost never declines is either very well calibrated or is resolving
    ambiguity it should be surfacing; 100 cases cannot separate those.
-   **The 120 never-scored identities are 12 cases in this sample.**
    Their composition is reported with everything else, but a 12-case
    subset supports no claim of its own.
-   **Search cost is not in the token figure.** $0.0669 per case in
    tokens for Opus and $0.0131 for Haiku, plus 3.2 and 4.4 web searches
    per case billed separately. No ratio to the MAYBE arms is quoted:
    those were computed on that experiment’s own runs, some logged
    before the cache-write accounting was corrected.
-   **Two models agreeing is not two models being right.** The arms
    match on 31 of 31 EINs and on the single reference absence, which is
    evidence against independent error, not against *shared* error. Both
    were given the same instructions and both read the same web.
-   **The misspelling class is three cases.** The fix below is validated
    on 3 of 91, and what carries it is the mechanism — every blocking
    pass is exact equality — not the sample size. Its 0.90 cutoff is set
    from 91 cases and 38 personal names, which is enough to see the
    collision and not enough to price it precisely.

</div>

<div class="section level2">

## Reproducing

    PFMATCH_DIR=. Rscript dev/adjudicate-10-no-packet.R    # re-runs the match, ~30 min
    Rscript dev/adjudicate-11-no-search.R
    Rscript dev/adjudicate-12-no-score.R

    PF_NO_SET=cal Rscript dev/adjudicate-10-no-packet.R    # the human head-to-head
    PF_NO_SET=cal Rscript dev/adjudicate-11-no-search.R
    Rscript dev/adjudicate-14-no-calib.R

    PF_NO_MODEL=claude-haiku-5-5 PF_NO_TAG=-haiku Rscript dev/adjudicate-11-no-search.R
    PF_NO_TAG=-haiku Rscript dev/adjudicate-12-no-score.R  # the cheap arm
    Rscript dev/adjudicate-15-no-arms.R                    # Haiku vs Opus

    Rscript dev/adjudicate-16-fuzzy-regress.R              # the fuzzy pass, full file

The packet stage gates every identity’s tier against `BASELINE-2026-10C`
and stops on any drift, because a sample drawn from a drifted run does
not describe the baseline’s NO tier and its recovery could not be added
to the baseline’s match rate. It also re-checks that it drew the same
100 ids as the cached packet, so a rebuild cannot silently leave
collected verdicts keyed to different case text.

Design, full read-out and the taxonomy definitions are in
`dev/NO-TIER-EXPERIMENT.md`; the reviewer’s instructions are
`dev/LLM-NO-INSTRUCTIONS.md`.

</div>

</div>
