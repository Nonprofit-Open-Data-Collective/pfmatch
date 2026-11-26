# The cluster representative is the longest name, and that loses whole clusters

Dev note from the intermediaries project (`Nonprofit-Open-Data-Collective/intermediaries`),
2026-11-26. Measured on the full TY2021–2024 990-PF run: pfmatch `4cbb6a9`, matchdb
`active-observed` (`9cc7b76e3e144a87`, normalizer `v1-5e901add4a04a5d6`), `pf_prepare(dedup =
"fuzzy")` at the default threshold of 0.92. Run scripts: `intermediaries/dev/pfmatch-run/`.
Run root: `~/Documents/GRANTFLOW/pfmatch-ty2021-2024/`.

**Request: change the default in `pf_recipients()`.** It should stop matching each cluster on
its longest name. Options are in section 3. The clusters themselves are not the problem. The
problem is that a cluster is matched on one name, and the default rule chooses a poor one.

---

## 1. What happens

`pf_dedup()` builds clusters that look right. `pf_recipients()` then picks **one**
representative row per cluster: the longest name first, then the row with the most address
fields filled in. Only that row goes through the cascade. `pf_propagate_matches()` copies its
result to every grant row in the cluster.

In a cluster of spelling variants, the longest name is nearly always the most decorated one.
Here are three real clusters from this run:

| Cluster (grant rows) | Most common name (rows) | Representative actually matched | Result |
|---|---|---|---|
| 1,986 | NEW VENTURE FUND (1,968) | NEW VENTURE FUND FOR PROJECT UNLOADED (1) | NO, score 0.38, name_sim 0 |
| 1,534 | HARVARD UNIVERSITY (1,351) | HARVARD UNIVERSITY (HARVARD GRADUATE SCHOOL OF EDUCATION) | NO, 0.36, best candidate HARVARD DEDICATED ENERGY LIMITED |
| 270 | SCHWAB CHARITABLE FUND (255) | SCHWAB CHARITABLE (DONOR ADVISED FUND) | NO, 0.36, best candidate CHARLES AND HELEN SCHWAB FOUNDATION |

In each case the most common spelling is an exact BMF name in the right state, and it
resolves in pass A when matched alone. Small clusters of the same organizations that kept the
plain spelling came back YES: 7 New Venture Fund identities, 8 Harvard and 9 Schwab. The same
pattern holds for Tides, The Nature Conservancy, CAF America, MIT, Massachusetts General
Hospital, the University of Chicago, and other large DAF sponsors and fiscal sponsors.

The `pf_dedup` documentation says a cluster buys recall because "a match found for any member
**propagates to every member**." That would hold only if more than one member were matched.
Since only the representative is matched, a cluster gains nothing from the variants it merged,
and one poor representative takes down every member.

## 2. How much it costs

| | Identities | Grant rows | Dollars |
|---|---:|---:|---:|
| All in-scope identities | 1,577,882 | 7.57M | $461B |
| Clusters with more than one normalized name variant | 224,751 | — | — |
| …whose representative is **not** the most common name | 119,177 | 3.09M | $177B |

The NO rate depends on whether the representative is the most common name:

| Multi-variant clusters | Grant rows NO | Grant rows MAYBE |
|---|---:|---:|
| representative = most common name | 7.5% | 11.9% |
| representative ≠ most common name | 16.6% | 20.1% |

Clusters whose representative is not the most common name hold **33% of all NO grant rows
and 26% of all NO dollars ($48B)**. The losses are concentrated in the largest clusters, which
are the frequent recipients, and therefore the hubs of any grant network built from these
matches. Losing a cluster costs far more than losing a singleton.

**Rematching on the most common name** (`intermediaries/dev/pfmatch-run/04-rematch-modal.R`):
the 43,993 such clusters that ended NO or MAYBE were matched again, under the same
`recipient_id`, with the representative rebuilt from the most common name. For ties, the row
with the most address fields, then the latest tax year.

- 300-identity smoke test: **41% improved**. 49 went NO → YES, 47 MAYBE → YES, 27 NO → MAYBE.
- The first 20,000 of the full set came back 28–29% YES on the rematch alone.
- **Full result** (43,993 identities, 105.8 min, 0.144 s per identity):

  | Old tier → new tier | Identities |
  |---|---:|
  | MAYBE → YES | 6,840 |
  | NO → YES | 5,804 |
  | NO → MAYBE | 3,904 |
  | MAYBE → MAYBE / NO → NO | 11,655 / 13,902 |
  | MAYBE → NO (old result kept) | 1,888 |

  **16,548 identities (38%) improved, 12,644 of them to YES. That moved 549,253 grant rows
  and $42.7B to YES.** Across all grant rows, YES went from 61.7% to 68.9% of rows and from
  43.1% to 52.1% of dollars, from this one change.

Taking the better of two attempts can only add YES, so precision for the rematched YES rows
needs its own audit sample. In the smoke test there were also cases where the rematch chose a
different EIN, such as Habitat for Humanity International 58-2037200 versus 58-2125349. Those
cases need adjudication rather than being accepted automatically.

## 3. Alternatives, cheapest first

1. **Most common normalized name** (a one-line change to the ordering in `pf_recipients()`).
   Order by the frequency of the name within the cluster, then the number of address fields,
   then length. This fixes the decorated-name case at zero matching cost. It still fails when
   the most common spelling is itself abbreviated or misspelled, for example "HARVARD UNIV"
   winning in a small cluster.

2. **Strip decoration before choosing.** Score the names after removing parentheticals,
   "FOR PROJECT …", "C/O", "ATTN …" (rows like "CHDI FOUNDATION INC ATTN KEN SLUTSKY TAX EXEMPT
   IN…" also fail here), "- PROGRAM NAME" suffixes and similar. This is useful together with
   option 1, and npmatch's normalizer may already produce most of these tokens.

3. **Screen the variants against matchdb names** (suggested by J. Lecy). Before the cascade,
   fuzzy-match each cluster's *distinct normalized names* against matchdb's name dictionary,
   restricted to the cluster's state. Take the reference's name keys, or exact `name_key` hits
   plus Jaro-Winkler ≥ 0.92 within the state block. Any variant that has a valid candidate
   becomes a representative. This is cheap: a name-only lookup over distinct names, many fewer
   than identities, with no address or scoring work. It also turns dedup into a recall gain,
   which is what the `pf_dedup` documentation claims. Only multi-variant clusters need it, and they are
   14% of identities. The number of distinct names in them has not been counted yet. Clusters with no
   variant that hits are a strong NO or OOS signal in their own right.

4. **Run pass A on every variant, and the full cascade on one.** Run the exact-name passes
   (A1–A5) on every distinct variant in multi-variant clusters, and the full cascade only when
   none of them resolves. Pass A is the cheap part of the cascade, so this costs much less than
   running the full cascade on every variant, and it covers most of what option 3 would find.

5. **Try the top k variants and vote.** Match the k most frequent variants (k = 2–3) through
   the whole cascade. If they agree on an EIN, return it. If they disagree, use MAYBE, and treat
   the disagreement as a signal that the cluster was over-merged. The extra cost falls only on
   multi-variant clusters, at k× their matching time. It is the most robust option, and it also
   audits the dedup.

**Suggested default:** option 1, plus option 3 or 4 as a second pass for multi-variant
clusters that end NO or MAYBE. That is the shape of `04-rematch-modal.R`, but with the
screening moved inside `pf_link()`, so that it does not need a second reference load and a
second run. With options 3–5 the "any member propagates" property holds for real.

## 4. Related fixes

- **Benchmarks.** Check whether the benchmark frames are built from
  `pf_recipients()` output. If they sample grants and match them singly, they never see this
  failure, and the 57–63% clear rate overstates what a fuzzy-dedup production run delivers.
  In this run: 61.7% of grant rows were YES, but only **43.1% of dollars**, before the rematch.
- **Documentation.** `pf_recipients()` says it picks "the best available spelling". Change
  that when the rule changes, and correct the propagation claim in `pf_dedup_doc`.
- **Regression test.** Add a fixture cluster such as NEW VENTURE FUND × 50 plus one
  "NEW VENTURE FUND FOR PROJECT X" row, and assert that the representative is the common name
  and that the cluster resolves.
- **`dev/run-full-file.R`** uses the same path, so earlier production outputs have the same
  loss.

## 5. Other things seen in the same run (smaller)

- **Placeholder rows hold the dollars.** 61% of NO dollars ($112B) sit in 24,877 placeholder
  or aggregate rows: patient-assistance totals ("INDIVIDUAL PATIENT PROGRAMS", $19.8B in 12
  rows), "VARIOUS INDIVIDUALS", "SEE ATTACHED", HIPAA notes. `flag_placeholder` and the OOS
  rules let them through as in-scope NO. They should go out of scope, because they are not
  matchable, and they distort NO rates weighted by dollars.
- **Person-like names reach the cascade.** About half of the NO identities in the late chunks
  are person-like names, such as scholarship recipients, that stayed in scope. This is
  consistent with the known 24% OOS error rate.
- **Stale matchdb cache.** `md_reference(fetch = "missing")` never refreshes a local bundle
  whose spec hash is unchanged but which S3 has since republished under a new normalizer. The
  stale copy then fails the signature check, with a "republish it" message that points the
  wrong way. Comparing against the remote stamp, or refetching on a signature mismatch, would
  avoid this. That fix belongs in matchdb.
