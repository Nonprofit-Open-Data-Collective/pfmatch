<div id="main" class="col-md-9" role="main">

# Matching against your own YES tier

A completed run has resolved hundreds of thousands of grants. The
obvious next question is whether that output is itself a database: take
the cases cleared `YES`, treat them as the thing to match against, and
see whether new cases clear.

The answer is yes, with a specific shape and a specific limit. It adds
about a point to the clear rate on the benchmark, it is nearly free to
build, and it cannot discover an organisation it does not already
contain. This article covers what the mechanism is, where in the
workflow it runs, what it is worth, and what its measured precision is –
which, for half the recoveries, is still unknown.

`vignette("matching-dictionaries")` puts this pass beside the
alternatives it competes with – the active BMF, the augmented BMF, and
matchdb’s published tiers – and is the article to read when choosing
*which* database to run against. This one is about the YES tier alone.

<div class="section level2">

## 1. Two things the question could mean

| reading                              | keyed on                                                   | built by                                   | verdict                                                |
|:-------------------------------------|:-----------------------------------------------------------|:-------------------------------------------|:-------------------------------------------------------|
| The BMF rows of the EINs you cleared | the BMF’s registered legal name and mailing address        | subsetting the production reference bundle | a diagnostic: it can only remove competitors           |
| The grant renderings you cleared     | the recipient name and address **as the filer wrote them** | `pf_grant_dictionary()`                    | the one that ships: it adds keys the BMF does not have |

Both were measured, and the difference between them is the whole result.
The first can only ever *remove competitors* – every row in it is
already in the production reference, so it reaches no EIN the full
reference could not. The second introduces keys the BMF does not hold at
all, because filers do not write registered legal names.

Section 2 reports the first, briefly, because it is a useful diagnostic
and because it is what the question usually means. Sections 3 onward are
the mechanism that ships.

A note on the word *tier*, which this project overloads. A **match
tier** is YES / MAYBE / NO, the cascade’s verdict on one grant. A
**matchdb tier** is a published, pre-compiled reference. “The YES tier
as a dictionary” means the first kind.

</div>

<div class="section level2">

## 2. The subset reference, and what a subset can do

Take every EIN the benchmark’s augmented-BMF arm cleared `YES` – 2,979
identities over 2,813 distinct EINs – and carve their BMF rows out of
the production bundle: 9,253 rows, 0.2385% of 3,880,431. Carved rather
than rebuilt, so the keys are byte-identical and the comparison measures
competition rather than normalization.

Re-matching the benchmark’s own 4,748 in-scope rows against it:

| full reference | no candidate | YES   | MAYBE | NO  |
|:---------------|:-------------|:------|:------|:----|
| YES (2,979)    | 5            | 2,963 | 3     | 8   |
| MAYBE (1,044)  | 642          | 35    | 83    | 284 |
| NO (725)       | 565          | 2     | 3     | 155 |

Full-reference tier (rows) against mini-reference tier (columns)

**The result worth having is 35 MAYBE to YES**, and in 17 of them
(48.6%) the subset clears to the same EIN the full reference already
held as its own top candidate. On those the production reference had the
right answer and the margin gate would not release it, because
competitors kept the margin tight. That is 1.6% of the MAYBE tier, and
it is direct support for the reference-side duplicate finding – 15.9% of
the MAYBE tie band is two BMF rows carrying one name for one body. The
other 18 clear to a different EIN, or the full reference had no
candidate at all; a subset cannot know better than the full reference,
so those are for hand review, not adoption.

Two findings come free with it, and both are worth keeping.

**Shrinking a reference is not monotone.** 16 of the 2,979 full-YES rows
(0.5%) stop clearing against the subset – 11 drop to MAYBE or NO, 5 find
no candidate – and 1 clears to a different EIN. Removing rows changes
name frequencies and candidate sets, not just the candidate pool.

**Running it over fresh grants measures coverage, not accuracy.** 50,000
fresh grant rows against the same 9,253-row subset:

|                                                    |                            |
|:---------------------------------------------------|:---------------------------|
| fresh grant rows matched                           | 50,000                     |
| identities                                         | 40,977                     |
| YES                                                | 1,546 (3.77%)              |
| MAYBE                                              | 734 (1.79%)                |
| NO                                                 | 38,697 (94.44%)            |
| time                                               | 6.2 min (0.009 s/identity) |
| precision control: 400 mini-YES re-matched in full |                            |
| … full reference also YES, same EIN                | 352 (88.0%)                |
| … full reference clears a different EIN            | 16                         |
| … full reference does not clear at all             | 32                         |

So 3.77% of fresh identities go to one of these 2,813 organisations –
about 29x enrichment over uniform, since 2,813 is 0.13% of roughly 2.19M
distinct recipient names, but far less concentrated than the headline
recipients suggest. And the precision control says not to quote 3.77% as
accuracy: 88.0% survive contest against the full reference, so about
3.3% is the contest-surviving figure.

The conclusion: new YES cases do surface, but they are **new grants to
organisations already resolved, not new organisations**. A subset
reference cannot discover an EIN it does not contain. The finding worth
keeping is the 17 competition-blocked cases, and the way to pursue those
is the reference-side duplicate work, not a bigger batch.

</div>

<div class="section level2">

## 3. The mechanism that ships: a grant-side dictionary

Everything above keyed on the BMF’s own strings. The asymmetry that
makes the YES tier worth keeping is that **filers do not write those
strings**. Foundations write recipient names by a convention of their
own; the BMF carries the registered legal name. So a grant the BMF
cannot clear may still match a grant that already cleared.

Over the 312,306 cleared rows of the triangulation run that hold both
strings:

| a cleared row…                                   | n       | share  |
|:-------------------------------------------------|:--------|:-------|
| hits another cleared **grant** rendering exactly | 293,742 | 94.06% |
| hits its own **BMF** name exactly                | 147,290 | 47.16% |
| grant-exact but **not** BMF-exact                | 150,286 | 48.12% |
| BMF-exact but not grant-exact                    | 3,834   | 1.23%  |
| neither                                          | 14,730  | 4.72%  |

94% of cleared rows are *exactly* some other cleared rendering of the
same organisation, against 47% identical to the BMF name – and nearly
half are grant-exact while not BMF-exact. That is the gain, and it is a
gain of **frequency, not similarity**: on fuzzy distance the grant side
is marginally *worse* (median 0.960 to the nearest other rendering
against 0.967 to the BMF name, and only 31.7% of distinct renderings are
closer to a grant than to the BMF). A common rendering repeats, so an
arriving grant often hits an existing one exactly. It shows up as
exact-key recall, and that distinction governs everything below.

Where it pays hardest is the acronym and the colloquial name, which the
legal name does not resemble at all – similarity to the nearest other
grant rendering against similarity to the BMF name:

| rendering | nearest grant | BMF   |
|:----------|:--------------|:------|
| THE YARD  | 0.933         | 0.000 |
| USO       | 0.789         | 0.000 |
| THE ARC   | 0.927         | 0.423 |

<div class="section level3">

### The key must include the address

Keying on the name alone does not work, and the margin is not close:

| key              | distinct keys | carrying \>1 EIN | worst                           |
|:-----------------|:--------------|:-----------------|:--------------------------------|
| bare name key    | 63,310        | 727 (1.15%)      | `HABITAT FOR HUMANITY`, 39 EINs |
| (name key, ZIP5) | 66,425        | 0 (0.00%)        | none                            |

`RONALD MCDONALD HOUSE` carries 31 EINs on a bare name key and
`BIG BROTHERS BIG SISTERS` 29. Adding ZIP5 takes the ambiguity to zero.
`pf_grant_dictionary()` still drops any `(name_key, zip5)` that resolves
to more than one EIN rather than guessing, and reports the count in the
`ambiguous_dropped` attribute – real data never trips it, but a silent
collision there would attach one organisation’s EIN to another’s grants,
which is the one failure this must not have.

</div>

<div class="section level3">

### What it costs to build

|                                    |         |
|:-----------------------------------|:--------|
| cleared grant rows in              | 369,260 |
| distinct (rendering, address, EIN) | 88,750  |
| EINs                               | 31,722  |
| ambiguous keys dropped             | 0       |
| build time                         | 24.4 s  |
| size on disk                       | 63.9 MB |
| read back                          | 0.9 s   |

Nearly free, in other words, and it reads back in under a second. At
full scale the pass is roughly 12 hours single-stream against roughly
186 hours for the cascade it supplements. Its real cost is not compute;
it is the queue in section 6.

</div>

</div>

<div class="section level2">

## 4. Where it runs in the workflow

**After the cascade, on what the cascade could not clear, and never
instead of it.** `pf_recover_from_dictionary()` enforces that by only
ever retrying rows whose status is not `YES`.

    pf_prepare()        read, standardize, resolve the two-line name
      pf_dedup()        collapse grant rows to recipient identities
    pf_reference()      the database: matchdb active-observed by default
    pf_link()           the staged blocking cascade -> YES / MAYBE / NO
      |
      |--- YES rows ------> pf_grant_dictionary()      build from the cleared tier
      |                             |
      '--- MAYBE + NO ------> pf_recover_from_dictionary()
                                    |
                                    |--> corroborated: status becomes YES
                                    '--> uncorroborated: the `queue` attribute
    pf_adjudicate()     the MAYBE sheet, and now the queue beside it

In code, after a run:

<div id="cb2" class="sourceCode">

``` r
run  <- pf_run(grants, dir = "data-dev/batches")

# 1. the dictionary, from this run's own YES tier. A list carrying $grants is
#    accepted, so `pf_grant_dictionary(run)` works too.
dict <- pf_grant_dictionary(run$grants, keep = "YES")

#    `exclude` is for the case where the rows you are about to match are rows
#    the dictionary was built from -- a benchmark re-run, say. Without it the
#    dictionary answers those queries with themselves.
#      pf_grant_dictionary(run$grants, exclude = benchmark_ids,
#                          key_col = "grant_id")

# 2. retry only what did not clear, and adopt only what the BMF corroborates
out  <- pf_recover_from_dictionary(run$status, dict, run$recipients,
                                   accept = "agree")

attr(out, "counts")   # retried / dict_yes / agreeing / accepted
attr(out, "queue")    # the uncorroborated claims, for adjudication
```

</div>

Three details of placement are deliberate.

**It is a supplement, not a reference.** A dictionary from one run holds
the EINs that run resolved – 31,721 against the BMF’s roughly 1.9M
organisations – and reproduces only 794 of the augmented BMF’s 2,979 YES
rows, 26.7%. Run as a reference it is strictly worse, and 37 BMF-YES
rows clear to a *different* EIN against it. It belongs after the cascade
or nowhere.

**`keep = "YES"` is the default for a reason.** A dictionary seeded from
MAYBE would propagate exactly the decisions that are in doubt.

**Statistics are not borrowed silently.** The IDF of roughly 90k filer
renderings is not the IDF of 3.88M BMF names, and which one is right is
an open question. `stats = "dictionary"` computes name frequency and
token IDF over the dictionary itself; passing a reference bundle borrows
its tables instead. The argument exists so the two effects are never
confounded.

It is **not yet wired into `pf_run()`**. The step on record is to add it
as an optional stage after the cascade, off by default, with the queue
surfaced beside the MAYBE sheet rather than merged into it; until then
it is an explicit call, as above.

</div>

<div class="section level2">

## 5. What it is worth

On the cases the BMF left unresolved, as exact-key recall. The unit here
is the benchmark’s in-scope **grant row** (4,748 of them: 2,979 YES,
1,044 MAYBE, 725 NO):

[TABLE]

End to end through the package API, on the same population at the
**recipient-identity** unit (4,683 identities, of which the BMF run
cleared 2,865), after a full augmented-BMF run. The two tables are two
units, not two answers – that is why the counts differ:

[TABLE]

1,818 unresolved identities were retried and 106 cleared. 42 of those
agreed with the EIN the BMF reference had already surfaced as its own
top candidate – recoverable all along, with the margin gate refusing to
release them.

The honest framing of +0.90 points: it is below the “every remaining
lever moves less than 1% of grants” bar the project set for itself, and
the trustworthy half only just reaches it. What makes it worth running
anyway is the absolute count at scale. Roughly 37% of 17.25M grant rows
go unresolved, so one point of clear rate is on the order of **170,000
grants** – a large number from a rate that does not move.

</div>

<div class="section level2">

## 6. The acceptance rule, and why there is one

**Every EIN in the dictionary came from this pipeline.** Resolving
against it propagates the pipeline’s own decisions, errors included, so
it is a recall device whose precision is *inherited* rather than
established. That is what `accept` is for.

-   `"agree"` (default) promotes a row only where the dictionary’s EIN
    is the one the BMF run already held as its own top candidate. `NA`
    counts as a disagreement, not an agreement: a row the BMF could not
    name a candidate for has nothing to corroborate the dictionary.
-   `"all"` promotes every dictionary YES. For measurement, not
    production – its precision is the unknown that separates +0.90 from
    +2.26.
-   `"none"` annotates and promotes nothing.

The disagreements are not a new failure mode. They concentrate in the
known affiliate problem – an organisation against its own foundation or
alumni fund (`YALE UNIVERSITY` to `YALE UNIVERSITY ALUMNI FUND`), a
chapter network picking the wrong chapter (`ANY BABY CAN` to a different
chapter). That is the same population the dyad and affiliation work
addresses, so the queue lands in work already underway rather than
opening a new front.

Adjudicating one queue is the open step that matters: 64 uncorroborated
claims per 4,748 rows are the only way to turn an inherited precision
into a measured one. The route is the same adjudication the MAYBE tier
uses, described in `vignette("adjudicating-maybe")`.

</div>

<div class="section level2">

## 7. It does not get better with scale – in rate terms

The expectation was large gains once millions of cases have cleared: a
3M-row dictionary being a substantive database. That was tested
directly, with one fixed query set – the benchmark’s 1,769 unresolved
rows – against nested random dictionaries from 2% to 100% of the
369,160-row cleared pool.

[TABLE]

**A fifty-fold increase in dictionary rows roughly doubles the
recoveries**, 23 to 50, and the last doubling of the dictionary bought
two. Raw `dict YES` saturated outright: 126 at half the pool and 126 at
all of it.

The mechanism explains it. Recovery needs a cleared rendering *of the
same organisation*, so the quantity that matters is renderings per
organisation – and that grows logarithmically, 1.265 to 2.798 across a
fifty-fold increase in rows. The tenth foundation to write `USO` adds
nothing.

Two corollaries, and the first is easy to get backwards. The **rate**
saturates at about 1.05 points and is reached by half of a single run,
so more cleared data will not raise the percentage. But at full scale
the *query* side grows too – about 6.4M unresolved candidates rather
than 1,769 – so the absolute yield is large. Build it for the volume,
not for the percentage. And because the rate saturates so early, the
pass can be developed and tuned against a small dictionary without
waiting for a full run.

</div>

<div class="section level2">

## 8. What none of this establishes

**The precision of `accept = "all"`.** Unknown, and it is exactly the
difference between +0.90 and +2.26 points. The 64 queued cases per 4,748
rows are the measurement that would settle it.

**That the dictionary’s own YES rows are right.** They are the
pipeline’s output. Nothing in this pass validates them; it propagates
them.

**Which seed a production dictionary should use.** Three candidates, and
the choice is not obvious: the triangulation run’s cleared rows (what
was measured here, but drawn from multi-rendering addresses, so it
over-represents shared addresses and probably chapters – likely *why*
the disagreements skew to affiliates); a corpus-representative run’s
cleared rows; or the hand-adjudicated ground truth only, which is tiny
but carries no inherited error. The quantity to choose on is the
disagreement rate by seed.

**That the 3.77% coverage figure in section 2 is accuracy.** It is not;
88% of it survives contest.

</div>

<div class="section level2">

## Reproducing

<div id="cb3" class="sourceCode">

``` r
# the subset-reference arms of section 2
#   PFMATCH_DIR=. PF_EXP_ARM=R Rscript dev/experiment-head-reference.R
#   PFMATCH_DIR=. PF_EXP_ARM=C Rscript dev/experiment-head-reference.R
#
# the pass, end to end through the package API
#   Rscript dev/experiment-grant-dictionary.R
#
# the scaling curve of section 7
#   Rscript dev/experiment-dictionary-curve.R
```

</div>

</div>

</div>
