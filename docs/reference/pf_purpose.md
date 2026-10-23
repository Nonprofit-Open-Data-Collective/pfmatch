# Grant purpose as a tiebreak signal

Part XIV column (d), `SIGOCPYPOGOC`, asks the filer what the grant was
for. This module turns that free text into a comparison against the
recipient's own self-description and uses it to break ties the name
cascade could not.

## Why a tiebreak and not a score

Measured on 63 adjudicated MAYBE grants and 794 YES grants
(`dev/PURPOSE-MATCH-FINDINGS.md`):

- The purpose is contentless 58.9% of the time (median 2 words), and
  when it has content the comparison still separates candidates on only
  half of grants. It is silent far more often than it is wrong.

- Added to the linkage score across all pairs it is a net loss on grants
  that were already right (−14 of 794 at w = 0.4), and it would shift
  the score distribution the YES/MAYBE/NO thresholds are tuned against.

- Confined to the tie band it gains without losing, and the weight stops
  mattering — which is the signature of a tiebreak rather than a score
  term. So it is implemented as one, and the weight disappears.

The measured gain is small and rests on few cases: +1 grant of 61 at
npmatch's own gates, +3 if the `tie_high` gate is dropped. It is
therefore **off by default**; see
[`pf_purpose_tiebreak()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_purpose_tiebreak.md).
