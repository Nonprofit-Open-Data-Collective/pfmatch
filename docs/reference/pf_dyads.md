# Disclosed EIN dyads: substitutable pairs and merely related ones

A grant reported to `EAGLE RANCH` may have been paid to
`EAGLE RANCH FOUNDATION`, and nothing in the name or the address decides
which. The cascade cannot resolve that and should not pretend to. This
module builds the table that lets it stop trying: one row per
**disclosed pair of EINs**, drawn from Schedule A Part I line 12g and
Schedule R Part II.

## Dyads, not clusters — the one design decision that matters

The obvious implementation is a transitive closure with a `cluster_id`
per component. Measured on the pooled 2009-2024 disclosures (566,653
pairs over 174,496 EINs), that produces a single component holding
**66,973 EINs across 56 states** — 38% of every EIN in the graph —
chaining The Reinvestment Fund to the Jewish Community Federation of San
Francisco to Glacial Ridge Hospital Foundation. A match "verified"
against a set that large is unfalsifiable.

A same-city gate does not fix it: the largest same-city component is 407
EINs in Phoenix, merging Florence Crittenton Services of Arizona, the
Arizona Medical Association Foundation and Arizona's Children
Association.

So this module emits **direct edges only**. Two EINs are in a dyad when
one filing names the other, and never because a third party names them
both.
[`pf_dyad_collapse()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_dyad_collapse.md)
enforces that by resolving groups only within the candidates of a single
grant. See `dev/CLUSTER-FINDINGS.md` §2.

## Substitutable versus related

A Schedule R Part II edge means *related*, which is much weaker than
*interchangeable*. It links `Mayo Clinic Health System-Fairmont` to
`Mayo Clinic Health System-Lake City` — two different hospitals — and
`PLANNED PARENTHOOD GLOBAL` to `PLANNED PARENTHOOD ACTION FUND`, which
is a 501(c)(4) and cannot receive the same grant. Relaxing an error
definition across those edges launders real errors into passes.

`dyad_class` therefore separates two things:

- `substitutable`:

  The arm exists to fund this one body, or carries its name. Three
  conditions, all measured: see *Why exclusivity is the test*.

- `related`:

  Every other disclosed edge. Useful for context and for flagging, never
  for relaxing a correctness test.

## Why exclusivity is the test

A first build classed every Schedule A edge as substitutable and
produced an EIN with **905 substitutable partners**: the *YMCA
Retirement Fund*, a 509(a)(3) that supports 907 local YMCAs. SparkJoy
Foundation supports 408 unrelated Maine charities, Vitalyst Health
Foundation 406, Ascension Health 253. A grant reported to `Bangor YMCA`
is not interchangeable with the retirement fund, so **a bare Schedule A
edge cannot license substitution** — 43% of Schedule A edges come from a
supporter with more than ten supportees.

The mirror-image failure is the federated sibling: an identical name
core catches 337 chapters of `ALPHA LAMBDA DELTA`, 214 South Carolina
Masonic lodges, and 150-odd `VOLUNTEERS OF AMERICA` affiliates. Siblings
are not substitutes either — that is
[`pf_group_siblings()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_group_siblings.md)
territory, and a warning rather than an invitation to merge.

Both failures are the same measurement: **degree**. A body with an arm
has one to three of them; anything with fifty is a network. So
`substitutable` requires all three of

1.  a Schedule A edge whose *supporter* names at most `max_fanout`
    organisations, **or** an identical name core in the same state;

2.  both parties sharing a subsection code — a 501(c)(3) and a 501(c)(4)
    are not substitutes for a private foundation's grant, whatever
    Schedule R says about them being related;

3.  neither party exceeding `max_degree` substitutable partners once the
    first two conditions are applied.

At the defaults this yields 29,238 substitutable pairs with a **maximum
degree of 5 and no EIN above it**, against 129,645 pairs and a maximum
of 905 for the naive rule, while retaining 89% of its reach into the
MAYBE tier (1,055 of 1,183 top-two pairs on the 50k run). The sweep is
`dev/sweep-dyad-rules.R`; the adjudicated 100 does not discriminate
between any of the six rules tried, so this is chosen on graph safety,
not on labels.

## What it is worth

On a 50,000-grant run, 14.9% of MAYBE grants have a directly disclosed
top two, rising to 24.4% inside the tie band, and collapsing dissolves
the tie entirely for 1,224 grants (22.2% of the MAYBE tie band). Where
the edge fires it is precise: 98.9% of linked top-two pairs share a
content token and 54% share an identical name core. Its increment over
the disclosure-free name rule in
[`pf_cluster_arms()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_cluster_arms.md)
is 5.0% of the MAYBE tier — this is a direction-and-confirmation
feature, not a recall feature.

Pooling fifteen years buys almost nothing over a single year (49% to 52%
of known arm pairs) because the ceiling is non-filing, not vintage. Pool
for the `n_years` stability signal, not for coverage.
