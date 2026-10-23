# IDF-weighted containment of a purpose in a document

The share of the purpose's information content that is present in the
organization's text: \$\$ \mathrm{cov}(q,d) = \sum\_{t \in q \cap d}
\mathrm{idf}(t) \\/\\ \sum\_{t \in q} \mathrm{idf}(t) \$\$

## Usage

``` r
pf_purpose_coverage(purpose, doc, idf)
```

## Arguments

- purpose, doc:

  Character vectors, recycled to common length.

- idf:

  Named numeric of token IDF weights (see
  [`pf_build_org_text()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_build_org_text.md)).

## Value

A numeric vector in `[0, 1]`, with `NA` where undefined.

## Details

Asymmetric on purpose. The query is two words and the document can be
five thousand, so a symmetric measure (cosine, Jaccard) is near zero for
every pair and cannot rank them; containment asks only how much of the
*query* is accounted for, and is insensitive to document length. `NA`
when the purpose has no content tokens or the document is empty — never
0, because a zero is evidence against and this is an absence of
evidence.
