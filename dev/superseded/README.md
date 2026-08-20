# Superseded

`semantic.R` / `eval-semantic.R` were written in the 2026-08-19 session as
"stage 5" of `SCALE-PLAN.md`: compare grant purpose against the BMF's NTEE and
activity text, use it to re-rank tied candidates. They measured **net +1 of 63**
adjudicated cases.

They are superseded by `R/purpose.R` + `R/text.R` and
`dev/PURPOSE-MATCH-FINDINGS.md`, which do the same job with much better
evidence: real Form 990 Part III mission and program text (not just NTEE
proxies), measured coverage on all 1.92M BMF records, a 794-grant silver set in
addition to the 63-case gold set, and a proper tie-band-only design in which the
weight correctly drops out.

Both lines of work reached the same conclusion independently — the text signal is
precise but rarely applicable, worth roughly +2 grants in 28, and belongs in the
tie band rather than the score. Keep `purpose.R`; these files are retained only
so the earlier measurement is not lost.
