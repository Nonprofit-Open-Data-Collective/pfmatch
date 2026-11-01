<div id="main" class="col-md-9" role="main">

# Name and address variants

How recipient names and addresses actually vary in the 990-PF filings,
which of those variations the pipeline already absorbs, and which ones
decide whether a grant resolves to an EIN.

Everything here is computed from `pf_variants`: 5,410 pairs of recipient
renderings filed at the same street and ZIP, across 4,291 addresses. In
each pair the cascade resolved one rendering (`YES`) and returned
`MAYBE` on the other. They come from the 50,000-case triangulation run
over population `cb3c78ff0f1a9546`.

<div class="section level2">

## Read this first: these pairs survived normalization

The pairs are not a random sample of variation. They are the residue.

Before any pass runs, `npmatch::np_normalize()` has already uppercased,
dropped a leading `THE`, rewritten `&` as `AND`, expanded `FDN` to
`FOUNDATION` and contracted USPS street suffixes; `pf_dedup()` has then
collapsed renderings sharing an identity key into a single recipient. So
a pair that differs *only* in a way the pipeline handles never reaches
the comparator as two things and never appears here.

What that buys: the table is a regression corpus. Every row is a live
case that reached the comparator and split. Tighten the normalizer and
specific rows should move; the rows recorded as already closed should
stay closed.

What it costs: `pf_variants` tells you nothing about variation the
normalizer already fixes. For that, compare the `*_differs` columns (the
filed text) against the `*_key_equal` columns (what the normalizer made
of it).

|                                              | pairs | share  |
|:---------------------------------------------|:------|:-------|
| ZIP5 agrees inside the pair                  | 5,410 | 100.0% |
| filed street text differs                    | 88    | 1.6%   |
| …but the normalized street key agrees        | 9     | 10.2%  |
| normalized name keys agree anyway            | 46    | 0.9%   |
| blocking intact (ZIP5 and state both usable) | 5,390 | 99.6%  |

ZIP5 agrees in every pair because the group is *defined* by
street-plus-ZIP5, which is also why this table cannot be used to study
ZIP variation.

</div>

<div class="section level2">

## It is not ground truth

The triangulation verdicts are silver, `confidence = "low"`, and
unadjudicated. Writing the anchor’s EIN onto every other rendering at
the address is the assumption under test, not a fact.

So `expected_same_org` is `TRUE` on 20 rows — where the two names are
the same string under a documented cosmetic transformation at an
identical address — and `NA`, never `FALSE`, on the other 5,390. Two
examples of why a string test cannot decide it:

-   `US OLYMPIC AND PARALYMPIC FOUNDATION` and `USOC` share no tokens
    and are the same family of organization.
-   `MARINE CORPS UNIVERSITY FOUNDATION` and
    `MARINE CORP SCHOLARSHIP FUND` share a distinctive token and are two
    different charities.

`label_basis` records which rows are waiting for a human.

</div>

<div class="section level2">

## Name variants

| class                  | pairs | share | median edit distance | median token Jaccard | name keys agree |
|:-----------------------|:------|:------|---------------------:|---------------------:|----------------:|
| different name         | 4,080 | 75.4% |                 23.0 |                 0.00 |               1 |
| token added or dropped | 595   | 11.0% |                 15.0 |                 0.50 |               1 |
| truncation             | 428   | 7.9%  |                 19.5 |                 0.50 |              23 |
| partial token overlap  | 274   | 5.1%  |                 12.0 |                 0.50 |               4 |
| leading THE            | 14    | 0.3%  |                  4.0 |                 0.75 |              14 |
| typo                   | 8     | 0.1%  |                  1.0 |                 0.60 |               0 |
| abbreviation           | 4     | 0.1%  |                  7.0 |                 0.60 |               3 |
| spacing or punctuation | 4     | 0.1%  |                  1.0 |                 0.49 |               0 |
| corporate suffix       | 2     | 0.0%  |                  4.0 |                 0.50 |               0 |
| identical normalized   | 1     | 0.0%  |                  0.0 |                 1.00 |               0 |

The cosmetic classes everyone expects to dominate are almost absent, and
that is the normalizer working: it has already closed them upstream.
What is left is dominated by names that are genuinely different strings.

`name keys agree` is the column to watch. Where it is non-zero the
normalizer *did* close the name difference and the two renderings still
reached the comparator separately — covered in “A seam” below.

<div class="section level3">

### Exemplars

Six per class, from the `curated` subset.

**different name**

| resolved (YES)                         | unresolved (MAYBE)             | name key agrees | edit dist | jaccard | YES score | MAYBE score |
|:---------------------------------------|:-------------------------------|:----------------|----------:|--------:|----------:|:------------|
| ALLIED ARTS COUNCIL OF ST JOSEPH       | ARTS FUND                      | FALSE           |        25 |   0.143 |      0.98 | 0.720       |
| DANIELLES ANIMAL SAFE HAVEN INC        | ANIMAL RESCUE                  | FALSE           |        22 |   0.167 |      0.98 | 0.720       |
| JEWISH COMMUNITY FEDERATION - EAST BAY | BERKLEY HIGH HOLIDAYS SERVICES | FALSE           |        31 |   0.000 |      0.98 | 0.780       |
| ALLIANCE FRANCAISE DE MILWAUKEE        | BIG BROTHERS BIG SISTERS       | FALSE           |        25 |   0.000 |      0.98 | 0.720       |

**token added or dropped**

| resolved (YES)                       | unresolved (MAYBE)                               | name key agrees | edit dist | jaccard | YES score | MAYBE score |
|:-------------------------------------|:-------------------------------------------------|:----------------|----------:|--------:|----------:|:------------|
| BOY SCOUTS OF AMERICA                | GNFC - Boy Scouts of America                     | FALSE           |         5 |   0.800 |      0.98 | 0.760       |
| COMO FRIENDS                         | COMO ZOO AND CONSERVATORY SOCIETY - COMO FRIENDS | FALSE           |        34 |   0.333 |      0.98 | 0.780       |
| COVER HOME REPAIR                    | COVER                                            | FALSE           |        12 |   0.333 |      0.98 | 0.720       |
| The Humane Society of Broward County | BROWARD HUMANE SOCIETY                           | FALSE           |        25 |   0.500 |      0.98 | 0.751       |

**truncation**

| resolved (YES)                                        | unresolved (MAYBE)           | name key agrees | edit dist | jaccard | YES score | MAYBE score |
|:------------------------------------------------------|:-----------------------------|:----------------|----------:|--------:|----------:|:------------|
| CORNERSTONE CHRISTIAN SCHOOL AND EDUCATIONAL SERVICES | CORNERSTONE CHRISTIAN SCHOOL | FALSE           |        25 |   0.500 |      0.98 | 0.720       |
| FRIENDS OF YOUTH SERVICES AND PALM BEACH COUNTY INC   | FRIENDS OF YOUTH SERVICES    | FALSE           |        26 |   0.444 |      0.98 | 0.720       |
| FAITH CHURCH ST LOUISCOM INC                          | FAITH CHURCH                 | FALSE           |        16 |   0.400 |      0.98 | 0.720       |
| COLLEGE BOUND ST LOUIS                                | College Bound                | FALSE           |         9 |   0.500 |      0.98 | 0.720       |

**partial token overlap**

| resolved (YES)                           | unresolved (MAYBE)                   | name key agrees | edit dist | jaccard | YES score | MAYBE score |
|:-----------------------------------------|:-------------------------------------|:----------------|----------:|--------:|----------:|:------------|
| MOON TOWNSHIP LIBRARY FRIENDS            | MOON TOWNSHIP PUBLIC LIBRARY         | FALSE           |        13 |   0.600 |      0.98 | 0.980       |
| DELTA PHI EPSILON EDUCATIONAL FOUNDATION | DELTA UPSILON EDUCATIONAL FOUNDATION | FALSE           |         5 |   0.500 |      0.98 | 0.720       |
| A BETTER WISCONSIN INSTITUTE             | A BETTER WISCONSIN TOGETHER          | FALSE           |         8 |   0.600 |      0.98 | 0.980       |
| ALLIED ARTS COUNCIL OF ST JOSEPH         | ALLIES ARTS OF ST JOSEPH             | FALSE           |         9 |   0.571 |      0.98 | 0.760       |

**leading THE**

| resolved (YES)                       | unresolved (MAYBE)               | name key agrees | edit dist | jaccard | YES score | MAYBE score |
|:-------------------------------------|:---------------------------------|:----------------|----------:|--------:|----------:|:------------|
| The Pasadena Educational Foundation  | Pasadena Educational Foundation  | TRUE            |         4 |   0.750 |      0.98 | 0.720       |
| THE JACKSONVILLE HUMANE SOCIETY      | JACKSONVILLE HUMANE SOCIETY      | TRUE            |         4 |   0.750 |      0.98 | 0.739       |
| THE WESTERN PENNSYLVANIA CONSERVANCY | WESTERN PENNSYLVANIA CONSERVANCY | TRUE            |         4 |   0.750 |      0.98 | 0.759       |
| THE ONESTAR FOUNDATION               | Onestar Foundation               | TRUE            |         4 |   0.667 |      0.98 | 0.720       |

**typo**

| resolved (YES)                          | unresolved (MAYBE)                       | name key agrees | edit dist | jaccard | YES score | MAYBE score |
|:----------------------------------------|:-----------------------------------------|:----------------|----------:|--------:|----------:|:------------|
| MUSEUM OF THE AMERICAN REVOLUTION       | MUESEUM OF THE AMERICAN REVOLUTION       | FALSE           |         1 |   0.667 |      0.98 | 0.760       |
| YOUNG WOMENS CHRISTIAN ASSO OF MISSOULA | YOUNG WOMENS CHRISTIAN ASSOC OF MISSOULA | FALSE           |         1 |   0.714 |      0.98 | 0.780       |
| LONG BEACH COMMUNITY FOUNDATION         | LONG BEACH COMMUNITY FOUNDATON           | FALSE           |         1 |   0.600 |      0.98 | 0.765       |
| YESHIVATH BETH YEHUDAH                  | Yeshiva Beth Yehudah                     | FALSE           |         2 |   0.500 |      0.96 | 0.960       |

**abbreviation**

| resolved (YES)                           | unresolved (MAYBE)                  | name key agrees | edit dist | jaccard | YES score | MAYBE score |
|:-----------------------------------------|:------------------------------------|:----------------|----------:|--------:|----------:|:------------|
| COMMUNITY FOUNDATION FOR LOUDOUN         | COMMUNITY FDN FOR LOUDOUN           | TRUE            |         7 |   0.600 |     0.980 | 0.780       |
| MEDICAL FOUNDATION OF NASHVILLE          | MEDICAL FDN OF NASHVILLE            | TRUE            |         7 |   0.600 |     0.960 | 0.780       |
| WHITE PLAINS HOSPITAL FDN                | WHITE PLAINS HOSPITAL FOUNDATION    | TRUE            |         7 |   0.600 |     0.960 | 0.733       |
| LOS GATOS HIGH NEW MILLENNIUM FOUNDATION | LOS GATOS HIGH NEW MILLENNIUM FOUND | FALSE           |         5 |   0.714 |     0.888 | 0.780       |

**spacing or punctuation**

| resolved (YES)                                | unresolved (MAYBE)                           | name key agrees | edit dist | jaccard | YES score | MAYBE score |
|:----------------------------------------------|:---------------------------------------------|:----------------|----------:|--------:|----------:|:------------|
| BOYS & GIRLS CLUB OF WASHINGTON COUNTY        | BoysGirls Club of Washington County          | FALSE           |         1 |   0.571 |     0.980 | 0.720       |
| US NAVAL ACADEMY                              | U S NAVAL ACADEMY                            | FALSE           |         1 |   0.400 |     0.960 | 0.902       |
| US Marshalls Museum                           | U S Marshalls Museum                         | FALSE           |         1 |   0.400 |     0.949 | 0.760       |
| HEALTH CARE FOUNDATION OF GREATER KANSAS CITY | HEALTHCARE FOUNDATION OF GREATER KANSAS CITY | FALSE           |         1 |   0.625 |     0.900 | 0.780       |

**corporate suffix**

| resolved (YES) | unresolved (MAYBE) | name key agrees | edit dist | jaccard | YES score | MAYBE score |
|:---------------|:-------------------|:----------------|----------:|--------:|----------:|:------------|
| BRAC USA       | BRAC               | FALSE           |         4 |     0.5 |      0.96 | 0.720       |
| CARE           | CARE USA           | FALSE           |         4 |     0.5 |      0.82 | 0.720       |

**identical normalized**

| resolved (YES)                           | unresolved (MAYBE)                     | name key agrees | edit dist | jaccard | YES score | MAYBE score |
|:-----------------------------------------|:---------------------------------------|:----------------|----------:|--------:|----------:|:------------|
| BOYS & GIRLS CLUBS OF MANATEE COUNTY INC | BOYS GIRLS CLUBS OF MANATEE COUNTY INC | FALSE           |         0 |       1 |      0.98 | 0.780       |

</div>

</div>

<div class="section level2">

## Address variants

| class           | pairs | share | blocking still intact |
|:----------------|:------|:------|:----------------------|
| identical       | 4,278 | 79.1% | 100.0%                |
| zip4 differs    | 534   | 9.9%  | 99.6%                 |
| city differs    | 285   | 5.3%  | 99.3%                 |
| unit differs    | 229   | 4.2%  | 98.3%                 |
| street spelling | 72    | 1.3%  | 100.0%                |
| state differs   | 12    | 0.2%  | 0.0%                  |

<div class="section level3">

### The address is scored, but inside a group it is saturated

Blocking and scoring are separate layers and the address behaves
differently in each. `pf_staged_passes()` blocks on `name_key` or
`dba_key` crossed with `zip5` or `state`, and nothing else:

| pass            | criteria                            |
|:----------------|:------------------------------------|
| A1-name-zip5    | name + ZIP5 (exact)                 |
| A2-name-state   | name + state (exact)                |
| A3-name-dba     | name == dba, same state             |
| A4-dba-name     | dba == name, same state             |
| A5-dba-dba      | dba == dba, same state              |
| B1-token-state  | shared token, same state            |
| B2-token-concat | shared token + compound, same state |
| C1-name-any     | name == name, ANY state             |
| C2-dba-any      | name == dba, ANY state              |

So no pass *blocks* on street, unit or city. But scoring is a different
layer, and there the address carries real weight. pfmatch runs
`method = "hier"`, whose score is

    score = 0.6 * name_key_similarity + 0.4 * geo_score

and `geo_score` is the **maximum** over a tier ladder:

| geo term | weight | fires when                                                                                  |
|:---------|-------:|:--------------------------------------------------------------------------------------------|
| zip9     |   1.00 | ZIP+4 agrees                                                                                |
| unit     |   0.97 | the suite agrees, where it discriminates (a multi-tenant building, not a crowded mail drop) |
| street   |   0.95 | street number agrees AND normalized street key similarity \>= 0.9, not a PO box             |
| zip5     |   0.90 | ZIP5 agrees                                                                                 |
| pobox    |   0.90 | PO box number agrees                                                                        |
| zip3     |   0.55 | ZIP3 agrees (zeroed on a state conflict)                                                    |
| city     |   0.50 | city Jaro-Winkler, floored at jw_threshold (zeroed on a state conflict)                     |
| state    |   0.20 | state agrees                                                                                |

`street_key` — npmatch’s normalized street — is compared directly and is
worth 0.95, behind only ZIP+4 and the suite. The address normalizer is
very much in use.

The catch is the `max()`. Inside a triangulation group ZIP5 agrees by
construction, so `geo_score` is already at least 0.90 before the street
is considered, and a street hit can lift it only to 0.95. That is 0.05
of geo, 0.02 of the final score. City at 0.50 and state at 0.20 are
dominated outright and cannot bind at all while ZIP5 agrees.

So the address is not inert — it is **saturated**, and only in this
corpus. Outside it, wherever ZIP5 does *not* agree, `street_hit` is the
best geo term available and street normalization is carrying the match.
That is the opposite of what these pairs alone would suggest, and it is
why `pf_variants` is the wrong instrument for judging the address
comparator’s value.

Consequences that do hold here:

-   A city spelling difference — `FT LAUDERDALE` against
    `Fort Lauderdale` — cannot change the outcome while ZIP5 agrees,
    because the 0.50 city term is dominated by the 0.90 ZIP5 term. There
    are 290 such pairs, and blocking stays intact in all of them.
-   A suite line could not separate two organizations in one building
    **when these pairs were cut**: `.np_hier_score()` had no unit term,
    and the `street_unit_full` weight profile that does carry one needs
    50% unit coverage against an actual 3.84%. npmatch has since added
    the `unit` rung above — so the mechanism now exists, gated on the
    suite discriminating at that address rather than merely being
    present. The pairs in this table predate it, which is why
    `pf_unit_evidence()` exists here at all. Its own parser has since
    been retired in favour of npmatch’s; see
    `dev/UNIT-UPSTREAM-SYNC.md`.
-   The **state** costs twice when wrong: it blocks stages A2–A5 and all
    of stage B, *and* a state conflict zeroes the city and ZIP3 geo
    terms. It disagrees in 20 pairs, all adjacent-letter filing errors:

| resolved (YES)                                     | state | unresolved (MAYBE)                                   | state |
|:---------------------------------------------------|:------|:-----------------------------------------------------|:------|
| AICE                                               | MO    | JDC                                                  | MD    |
| UK PHILANTHROPY                                    | NY    | UNIVERSITY OF KENTUCKY                               | KY    |
| FEATHER RIVER COLLEGE FOUNDATION                   | WA    | FEATHER RIVER COLLEGE - ELLEN HOLLIFIELD SCHOLARSHIP | CA    |
| ASSOCIATION OF BALTIMORE AREA GRANTMAKERS          | MD    | BALTIMORE COMMUNITY FOUNDATION INC                   | MA    |
| FREE ARTS FOR ABUSED CHILDREN OF NEW YORK CITY INC | NY    | MOTHERS2MOTHERS INTERNATIONAL INC                    | PA    |
| NEW VENTURE FUND                                   | DC    | HOPE & HEAL FUND                                     | CA    |

Since ZIP5 is present and agrees in every one of these pairs, a
ZIP5-to-state repair would fix them outright.

</div>

<div class="section level3">

### Where street normalization does pay

Not inside a group — by construction every pair already keyed to the
same street. It pays in *forming* groups at all. The filed street text
differs in 88 pairs here, and the normalizer reconciles 9 of them:

| filed (YES side)                 | filed (MAYBE side)              | normalized key            |
|:---------------------------------|:--------------------------------|:--------------------------|
| 4550 WEST 77TH STREETSUITE 200   | 4550 West 77th Street Suite 200 | 4550 W 77TH ST            |
| 1360 MISSION STSUITE 300         | 1360 MISSION ST SUITE 300       | 1360 MISSION ST           |
| 506 2ND AVESUITE 1400            | 506 2ND AVE SUITE 1400          | 506 2ND AVE               |
| 620 MOUNTAIN VILLAGE BLVD STE 2B | 620 MOUNTAIN VILLAGE BLVDSTE 2B | 620 MOUNTAIN VILLAGE BLVD |
| 6321 Porter RoadSuite 8          | 6321 PORTER ROAD SUITE 8        | 6321 PORTER RD            |
| 8 S MICHIGAN AVENUE SUITE 500    | 8 S MICHIGAN AVENUESUITE 500    | 8 S MICHIGAN AVE          |

A missing space before `SUITE`, `Street` against `ST`, `ROAD` against
`RD`. Measured over the whole corpus rather than these pairs,
normalizing the street collapses 528,862 of 2,326,459 distinct address
keys — 22.7% — and brings 58,815 addresses above the two-rendering
threshold that are currently split across spellings and so form no group
at all.

The caution: a normalizer that drops the secondary-unit designator to
achieve that will also merge `STE 100` with `STE 200`, which are
different tenants. Distinct units are rare at these addresses, so the
trade is probably worth making, but it is a trade.

</div>

<div class="section level3">

### The suite line as an adjudication tie-breaker

The one address fact that bears directly on a triangulated label is the
door. Two renderings at one street giving *different* suites are very
likely different organizations, so the anchor’s EIN should not be
written onto the candidate. When these pairs were cut the matcher could
not use this at all; npmatch has since given the hierarchical scorer a
`unit` rung (0.97) and annotates every candidate pair with `geo_unit`,
so the mechanism now exists there too. A reviewer still needs the
four-way reading below, which `geo_unit` does not give: it cannot
separate “one side filed nothing” from “neither did”.

`pf_unit_evidence()` compares the two lines. The parse is npmatch’s —
`pf_street_unit()` hands line 2 to `np_normalize()` and reads
`street_unit` back, so pfmatch reads a suite the same way the matcher
does. What is still pfmatch’s is the two rejections the field needs,
because it is not a unit field: it holds street continuations, city
names, PO boxes, and in one case a sequential counter written once per
grantee. The verdicts tabulated below were recorded under the normalizer
the corpus was built with; retiring the local parser moved 22 of the
5,410 pairs, every one traced in `dev/UNIT-UPSTREAM-SYNC.md`.

| evidence  | pairs | share | how to read it                                          |
|:----------|------:|:------|:--------------------------------------------------------|
| absent    |  5266 | 97.3% | neither side filed a parseable unit                     |
| one_sided |   108 | 2.0%  | one side did; silence is not disagreement               |
| agree     |    27 | 0.5%  | same door — NOT evidence of one organization, see below |
| conflict  |     9 | 0.2%  | different doors — the label is probably wrong           |

| anchor (YES)                       | unit               | candidate (MAYBE)                  | unit             |
|:-----------------------------------|:-------------------|:-----------------------------------|:-----------------|
| CITY GROWERS                       | 1105               | PRATT CENTER FOR COMMUNITY DEVELOP | 701              |
| Lankenau Medical Center Foundation | 340                | MAIN LINE HOSPICE                  | 100              |
| COURAGE WORLDWIDE                  | 433                | RRUFF - ROCKLIN RESIDENTS UNITE FO | 125              |
| AUTISM ALLIANCE OF MICHIGAN        | 520                | WOMEN OF TOMORROW                  | 155              |
| BALTIMORE ARCHITECTURE FOUNDATION  | STREET SUITE P-101 | JOHNS HOPKINS UNIVERSITYJOHNS HOPK | STREET SUITE 234 |
| LEUKEMIA & LYMPHOMA SOC            | SUITE 115          | KORE HAITI INC                     | SUITE 100        |
| WEIMARANER RESCUE OF NORTH TEXAS   | 184                | THOMAS JEFFERSON ALUMNI ASSOCIATIO | 150              |
| MCCOOK ECONOMIC DEVELOPMENT CORP   | STE 301            | MCCOOK COMMUNITY FOUNDATION        | RM 315           |
| CITY GROWERS                       | 1105               | DIEU DONN                          | 602              |

Two cautions, both measured rather than assumed.

**`agree` is not support.** Generic suites are shared by unrelated
tenants — `MIDDLE EAST CHILDRENS ALLIANCE` and `IRISH REPERTORY THEATER`
are both at Suite 100, `GLOBAL FUND FOR WOMEN` and
`THAKKER CHARITABLE TRUST` both at Suite 400 — a fiscal sponsor’s suite
is shared by everything it sponsors, and some values are not units at
all (`15219` is a Pittsburgh ZIP code on line 2). It is recorded for
completeness and carries nothing.

**`conflict` concentrates.** Over the whole triangulation run it fires
on 69 of 14,790 anchor/candidate pairs (0.47%), but one address produced
31 of them: a fellowship program writing `291 BROADWAY STE 1901`,
`STE 1902`, … one per individual grantee. Always read the raw columns,
never the flag alone. In the adjudication queue the flag lands on 121 of
58,680 rows, 26 of which sit in the zero-flag band — cases that looked
clean until the address was read.

</div>

</div>

<div class="section level2">

## What decides YES against MAYBE

| side               | median score | exact name+ZIP5 | token-blocked |
|:-------------------|-------------:|:----------------|:--------------|
| resolved (YES)     |         0.96 | 56.0%           | 19.8%         |
| unresolved (MAYBE) |         0.78 | 9.1%            | 53.2%         |

<div class="section level3">

### A seam: identity is keyed on one thing, blocking on another

`pf_dedup()` keys identity on `name_full` — deliberately, so that an
organization is not merged with its affiliate by a `name_key` that has
already thrown the affiliate suffix away. The cascade then blocks stage
A1 on `name_key` crossed with `zip5`. The two disagree, and 46 pairs
land in the gap: same normalized name key, same street key, same ZIP5,
two identities, two different tiers.

| resolved (YES)                       | unresolved (MAYBE)               | shared name key                  | YES score | MAYBE score |
|:-------------------------------------|:---------------------------------|:---------------------------------|----------:|------------:|
| COMMUNITY FOUNDATION FOR LOUDOUN     | COMMUNITY FDN FOR LOUDOUN        | COMMUNITY FOUNDATION FOR LOUDOUN |      0.98 |       0.780 |
| CHILDREN’S HOME SOCIETY              | CHILDRENS HOME                   | CHILDRENS HOME                   |      0.98 |       0.680 |
| The Pasadena Educational Foundation  | Pasadena Educational Foundation  | PASADENA EDUCATIONAL             |      0.98 |       0.720 |
| THE JACKSONVILLE HUMANE SOCIETY      | JACKSONVILLE HUMANE SOCIETY      | JACKSONVILLE HUMANE              |      0.98 |       0.739 |
| THE WESTERN PENNSYLVANIA CONSERVANCY | WESTERN PENNSYLVANIA CONSERVANCY | WESTERN PENNSYLVANIA CONSERVANCY |      0.98 |       0.759 |
| THE ONESTAR FOUNDATION               | Onestar Foundation               | ONESTAR                          |      0.98 |       0.720 |

</div>

<div class="section level3">

### When the unresolved side has the better match

The most useful flag in the table. Triangulation writes the anchor’s EIN
onto the candidate as `correct_ein`. On 726 pairs (13.4%) the
candidate’s own match was *better* than the anchor’s — a higher score,
or an exact name-plus-ZIP5 hit against a token-blocked one. On those the
silver label runs against the system’s own evidence.

| anchor (YES)                          | score | pass           | candidate (MAYBE)                            | score | pass          |
|:--------------------------------------|------:|:---------------|:---------------------------------------------|------:|:--------------|
| FRIENDS OF SPL                        | 0.900 | D1-acronym     | Friends of the Scarsdale Library Inc         |  0.98 | A1-name-zip5  |
| CHILDREN’S HOME SOCIETY               | 0.900 | D1-acronym     | BOYS AND GIRLS CLUB OF MIAMI-DADE INC        |  0.90 | A2-name-state |
| REGENTS OF THE UNIVERSITY OF MINNES   | 0.900 | D1-acronym     | UNIVERSITY OF MN FOUNDATION                  |  0.90 | A2-name-state |
| BROWARD ALLIANCE INC (THE)            | 0.913 | B1-token-state | GREATER FORT LAUDERDALE ALLIANCE             |  0.98 | A1-name-zip5  |
| CENTRAL GWINNETT JROTC                | 0.905 | B1-token-state | PARENT BOOSTER USA INC                       |  0.98 | A1-name-zip5  |
| PRESTON HOLLOW ELEMENTARY SCHOOL FUND | 0.958 | B1-token-state | PTA TEXAS CONGRESS                           |  0.98 | A1-name-zip5  |
| FRIENDS OF HAYWOOD PUBLIC LIB         | 0.893 | B1-token-state | HAYWOOD COUNTY PUBLIC LIBRARY FOUNDATION INC |  0.98 | A1-name-zip5  |
| JENSEN BEACH COMMUNITY PLAYGROUND     | 0.876 | B1-token-state | PTA FLORIDA CONGRESS                         |  0.98 | A1-name-zip5  |

`BETHEL COLLEGE` against `BETHEL UNIVERSITY` is the shape to recognise:
a renamed organization, where the rendering being labelled wrong found
the better reference row. Filter on `b_outscores_a` before trusting a
triangulated label.

</div>

</div>

<div class="section level2">

## Using this as a regression corpus

The pairs carry both the raw filed strings and the keys `np_normalize()`
made of them, so the keys can be recomputed and compared.
`tests/testthat/test-variants.R` does exactly that, in two layers:

-   **Invariants** that must hold under any sane normalizer: a leading
    `THE` never decides a name key; streets differing only by suffix
    spelling or a missing space normalize together; streets recorded as
    genuinely different stay different; a city difference never breaks
    blocking.
-   **A pinned check** that every recorded key still reproduces, scoped
    to the `np_normalize_signature()` the fixture was built under
    (`v1-6dcb298522cc5118`). It skips when the normalizer moves, because
    an intentional improvement *should* move keys — and the skip message
    tells you to rebuild with `data-raw/make-pf-variants.R`.

To test a change, re-run the fixture build against the new normalizer
and diff the class table: cosmetic classes should shrink,
`name_key_equal` should grow, and no pair should move from a
different-street class into an agreeing one unless you meant it to.

</div>

</div>
