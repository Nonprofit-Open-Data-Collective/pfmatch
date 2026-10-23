# Stage 6 — checkpointed batch driver for the full grant file

A 12.5M-row run is measured in tens of hours, so it cannot be a single
call that loses everything on an interrupt. This driver splits the work
into batches, writes each batch's result to disk as it completes, and
skips finished batches on restart.

## What is computed once and shared

The BMF reference — read, normalize, name-frequency table, token IDF,
blocking index, and the stage-4 recovery keys — is a function of the
reference alone. It is built once and handed to every batch, which is
the difference between a 5-minute setup and a 5-minute setup *per
batch*.

## Batching by identity, not by row

Batches are formed over deduplicated `recipient_uid` values from
[`pf_dedup()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_dedup.md),
so a cluster is never split across batches and every row of a cluster
inherits the one match computed for it (see
[`pf_propagate_matches()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_propagate_matches.md)).
