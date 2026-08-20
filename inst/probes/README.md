# Probes

One-off measurement scripts. They are **not tests** — they need the real BMF and
the real 990 extracts, they take minutes to hours, and several of them exist to
record a *negative* result so it is not re-derived.

They are shipped so the evidence behind the design decisions is inspectable, not
because they run anywhere. Each one loads pfmatch with `devtools::load_all()`,
so run them from a source checkout, not from an installed copy.

| script | question it answered | written up in |
|---|---|---|
| `probe-ntee-availability.R` | is the NTEE code present on the candidates that need disambiguating? | `PURPOSE-MATCH-FINDINGS.md` §3 |
| `probe-text-presence.R` | how much discrimination is presence rather than content? | §4 |
| `probe-threshold-recall.R` | is purpose similarity better as a set signal than a rank signal? | §9 |
| `probe-purpose-blocksize.R` | could a purpose floor generate candidates? | §9 |
| `probe-additive-risk.R` | what does adding purpose to the linkage score cost? | §8 |
| `probe-presence-prior.R` | can the filing-presence features support a safe floor? | §10 |
| `probe-tiebreak-scope.R` | does the gain survive npmatch's `tie_high` gate? | §10 |
| `probe-no-cases.R` | are NO-tier recipients real organizations? | `AUDIT-FINDINGS.md` |
| `probe-ref-truncation.R` | is the BMF reference name truncated too? | `TRUNCATION-FINDINGS.md` |
| `probe-promotion-*.R` | where should the YES threshold sit? | `BENCHMARK-NOTES.md` |
| `probe-zip3-credit.R` | should partial ZIP agreement score? | `BENCHMARK-NOTES.md` |
| `compare-blocking.R` | state-blocked vs unblocked cascade | `SCALE-PLAN.md` |
| `compare-concat.R` | does compound-token blocking pay? | `SCALE-PLAN.md` |
| `compare-sweeps.R` | which residual sweep is worth its cost? | `SCALE-PLAN.md` |
