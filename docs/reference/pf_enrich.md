# Enrich match results with BMF context for adjudication

A reviewer deciding between two candidate EINs needs more than a name
and a score. This module attaches, for every candidate, what the BMF
says the organization *does*, and, for every grant, what the
*foundation* does and what the grant was *for*. Purpose-to-mission
agreement is then usable as evidence.

## On "mission"

The BMF carries **no mission statement** — that text lives on Form 990
Part I / Part III, not in the master file. The BMF's mission proxies,
best to worst:

- `ntee_code_definition` — the NTEE classification in words
  ("Cemeteries", "Elementary & Secondary Schools"). Always populated,
  but ~1 in 4 records reads `UNDEFINED`.

- `nteev2_subsector` — the coarse sector (ART, EDU, HEL, HMS, REL ...).
  Useful for a same-sector / different-sector test even when the
  detailed code is undefined.

- `activity_code_definitions` — legacy IRS activity codes rendered as
  text ("Association or convention of churches; Other religious
  activities"). Genuinely mission-like, but only ~44% populated and
  frozen in the 1970s vocabulary.

Where a real mission statement is available from an e-file extract it
can be joined on `ein` via `mission` — see
[`pf_attach_missions()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_attach_missions.md).
