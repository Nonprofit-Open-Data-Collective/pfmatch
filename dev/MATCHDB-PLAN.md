# matchdb — pointer

The disambiguation-database plan that started here has moved to its own
repository and is **authoritative there**:

* `matchdb/dev/PLAN.md` — architecture: the layer / variant-class / derived-column
  axes, the schema, the spec object and compile step, S3 distribution, expansion
  control, the package boundary, and the phase order.
* `matchdb/dev/PROCESS.md` — how the work is conducted: phase gates, the
  comparison normal form, cross-repo sequencing, open decisions.

This file is a pointer, not a copy. A second copy of a 500-line plan is exactly
the divergence problem matchdb exists to fix.

## What pfmatch still owns

Three items in Phase 0 are pfmatch work, and none of them depend on matchdb
being built:

**A live promotion-guard question.** `pf_bmf_augment()` (`R/schedi.R:239`) writes
Schedule I aliases into `org_name_join` — the column `np_map_bmf()` maps to
`name`. A cloned alias row therefore reads as `MAIN`, so the
`distinct_name_main_only` guard cannot tell an observed alias from an IRS legal
name, and a rare alias can be promoted to auto-accept under a rule validated only
on legal names.

It is not yet clear this is a *defect* — an alias corroborated by several
independent filers may deserve the promotion. The rule has simply never been
evaluated there.

**It is not currently measurable.** `pf_bmf_augment()` emits `row_source`,
`alias_n_filers` and `alias_last_year`, but `.np_canonicalize()`
(`npmatch/R/canonicalize.R:204`) subsets to exactly `np_fields` and none of the
three appear anywhere in npmatch. They are dropped before blocking. The
prerequisite is an npmatch change — add `variant_class` to `np_fields`,
defaulting to `NA` — after which the count is trivial.

**The +43 YES is unverified.** `dev/REF-PERFORMANCE.md` records the augmented
reference gaining +43 YES / +10 MAYBE over the monthly BMF on 1,000 identities.
That is a *net* figure. `np_name_freq()` is a raw count, so growing the reference
monotonically tightens the `distinct_name_maxfreq <= 3` promotion gate — aliases
are won and promotions are lost, and the two have never been separated. The
Phase 0c A/B separates them; see `matchdb/dev/PROCESS.md` §4.

**Sequencing.** Measuring is read-only and safe now. *Adopting* the fix moves the
YES/MAYBE boundary, so it must land either before threshold optimization begins
or after it concludes — never during.

## Measured evidence

`dev/probe-idf-atomize.R` / `IDF-ATOMIZE.log` and
`dev/probe-refbuild-cost.R` / `REFBUILD-COST.log` (committed in `daa4b03`) are
what the plan's performance claims rest on. Headline: a reference rebuild is
408 s, of which `np_normalize` is 66% and token IDF is 6% — IDF is not the lever.
