# The k=8 deal, superseded 2026-11-03

Not a round in progress. Every truth template here was empty when it was
replaced, so no labelling was lost.

Kept for one reason: this deal is the evidence for the imbalance that
`pf_truth_shards()` now deals around, and that figure is cited in
`R/shards.R`, `dev/ADJUDICATION-PREREQS.md` and the roxygen for
`pf_truth_shards()`. It is **not reproducible from its seed any more** --
the overlap is dealt rather than sampled now, so `seed 20261103, k 8,
overlap 0.10` gives a different assignment under the current code. The key
here is the only record.

What it shows (`SHARD-KEY.csv`, overlap cases per shard):

    shard    1   2   3   4   5   6   7   8
    cases    7  15  11  10  12  10   9   6

Against an expectation of 10, and against `pf_labeler_agreement()`'s
`min_n = 20` -- so every per-labeler cell would have come back
`usable = FALSE`.

Superseded by `data-dev/round-stage1` (k = 5, overlap = 0.15); see
`dev/ADJ-ROUND-STAGE1-REDEAL-20261103.log`.
