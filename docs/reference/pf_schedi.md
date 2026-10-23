# Form 990 Schedule I as an alias source for the BMF

Schedule I Part II is where a non-PF 990 filer lists every grant it made
to a US organization or government: recipient **name**, **address**, and
**EIN**. That is the same speech act as 990-PF Part XIV — a grantmaker
writing down who it paid — so the name representations come from the
same distribution as the queries we are trying to match. The BMF gives
one *legal* name per EIN; this gives many *observed* names.

## Why it earns its place

Measured on the 50k benchmark (`dev/SCHEDI-ALIAS-FINDINGS.md`):

- 95.6% agreement with the accepted EIN on grants the cascade already
  resolved confidently — and the error rate is a clean function of
  `n_filers`, the number of *distinct grantmakers* who wrote that
  spelling: 86.1% at one filer, 95.4% at 2-4, 98.0% at 5-19, 99.0% at
  20+.

- 18.1% of the NO tier gets a hit; roughly half of those are both
  BMF-present and multi-filer, worth about +2.2 points.

- It resolves rebrands (`Lakeview Pantry` -\> Nourishing Hope), mergers
  (`Foundation for National Progress` -\> Center for Investigative
  Reporting), and brand-vs-legal names (`USA FOR UNHCR`, `VOTEORG`) —
  none of which any string metric can reach.

## The trap this design avoids

Do **not** use the alias to assign an EIN, and do not block on it. If
the alias merely surfaces the BMF row for `Nourishing Hope` as a
candidate for the query `Lakeview Pantry`, the comparison step scores
those two names against each other, gets ~0, and the veto layer discards
the correct answer. The match is justified by the alias *observation*,
not by name similarity. So the alias name is written into the reference
as a row in its own right, and the existing `exact-name` pass resolves
it with no new comparison logic.
