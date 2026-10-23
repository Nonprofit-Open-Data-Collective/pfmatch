# Affiliated organizations: operating entities and their fundraising arms

The single largest identified failure mode in the MAYBE tier is a
candidate list holding both an operating organization and its own
fundraising arm — `EAGLE RANCH` and `EAGLE RANCH FOUNDATION`,
`KANSAS FOOD BANK WAREHOUSE` and `KANSAS FOOD BANK FOUNDATION`. Two real
EINs, one body, and nothing in the name or the address separates them.
Measured on 15 adjudicated cases the cascade ranks the correct member
first **27%** of the time — worse than chance, because the arm's name is
usually the longer, more distinctive string and so scores better.

## Details

This module treats the pair as one entity. It builds an EIN-to-EIN link
table from three independent disclosures, groups co-located same-core
candidates under a joint id, and orders the members by a stated policy
rather than by a name score.

## The three sources, and what each actually covers

- Schedule A Part I line 12 (`SA-P01-T01`):

  A 509(a)(3) supporting organization lists the organizations it
  supports, by name and EIN. This is the only source that states
  **direction**, and on 276 pairs it agrees with the name heuristic (the
  `... FOUNDATION` row is the supporter) 271 times. It exists only for
  full-990 filers that are supporting organizations, and the
  supported-org EIN is blank on 49% of rows.

- Schedule R Part II (`SR-P02-T01`):

  Related tax-exempt organizations. Undirected in practice but far
  better populated — the related EIN is present on 97% of rows — and it
  covers pairs Schedule A never sees, because it does not require
  509(a)(3) status.

- BMF group exemption:

  **Not** the right tool for this relation. The `affiliation_code` and
  `group_exemption_number` fields describe group *rulings* — Lions
  Clubs, PTAs, BSA councils — i.e. federated siblings, not parent/arm
  pairs. `0000` means no group ruling and covers 1.52M of 1.92M BMF
  rows; treating it as a match key produces a spurious 74% link rate.
  Use it for the sibling case only, via
  [`pf_group_siblings()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_group_siblings.md).

On 927 name-detected pairs drawn from the MAYBE tier, Schedule A links
30%, Schedule R 46%, and either 49%. Restricted to pairs in the same
city those rise to 39% / 60% / 64% — the monotone rise being the
evidence that the geography gate removes false pairs rather than real
ones. The residual is mostly non-filing: for 64% of unlinked pairs
neither party files a schedule at all, which is what you would expect of
public universities, school districts and 990-EZ filers.
