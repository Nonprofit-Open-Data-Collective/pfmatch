# Standardize the 990-PF recipient foundation-status field (SIGOCPYRFSTA)

Form 990-PF Part XIV Table 3a, column (c) asks the filer for the
"foundation status of recipient". The IRS supplies no controlled
vocabulary, so the field is free text: across 155,000 sample grants it
carries ~1,400 distinct spellings of what are really a handful of
concepts. This module collapses that free text onto a five-level
standard, which is what decides whether a grant is even eligible to
appear in the IRS Business Master File.

## Why a rule cascade and not a lookup table

A lookup can only cover the spellings already seen. The rules below key
off the *concept* — an IRC section reference, the words "public
charity", the words "operating foundation" — so unseen spellings land in
the same bucket. Two normalizations do most of the work:

- **section collapsing** — `501(c)(3)`, `501C 3`, `501 C 3`, and `501c3`
  all become the single token `501C3`; likewise `509A1`, `170B1A`,
  `4942J3`. Without this, each spacing variant needs its own pattern.

- **de-spacing** — a second, space-free copy of the string is matched in
  parallel, so `PUB CHAR`, `PUBLIC CH`, and `OTHERPUBLICCHARITY` are all
  caught by one `PUBCHAR` / `PUBLICCH` pattern.

## Standard levels (`recipient_type`)

- `public_charity` — nonprofit, public charity (PC, 501(c)(3) with no
  foundation qualifier, 509(a)(1)-(3), church, school, hospital)

- `nonprofit_other` — nonprofit, other subsection or exempt-but-
  unspecified

- `foundation_pf` — private foundation, private operating foundation,
  exempt operating foundation

- `individual` — a natural person

- `other_unknown` — blank, N/A, government, foreign, and text that
  answers a different question ("PAID", "CASH", "VARIOUS", "ACTIVE")

## Detail levels (`recipient_type_detail`)

A finer split carried alongside the standard, because `other_unknown`
mixes cases that behave very differently: `government` and `foreign` can
never be in the BMF, while `blank` and `unrecognized` are usually
organizations the filer simply did not code. Only the detail level is
precise enough to drive the out-of-sample decision — see
[`pf_oos_details()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_oos_details.md).
