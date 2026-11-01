<div id="main" class="col-md-9" role="main">

# Stage 6 — checkpointed batch driver for the full grant file

<div class="ref-description section level2">

A 12.5M-row run is measured in tens of hours, so it cannot be a single
call that loses everything on an interrupt. This driver splits the work
into batches, writes each batch's result to disk as it completes, and
skips finished batches on restart.

</div>

<div class="section level2">

## What is computed once and shared

The BMF reference — read, normalize, name-frequency table, token IDF,
blocking index, and the stage-4 recovery keys — is a function of the
reference alone. It is built once and handed to every batch, which is
the difference between a 5-minute setup and a 5-minute setup *per
batch*.

</div>

<div class="section level2">

## Batching by identity, not by row

Batches are formed over deduplicated `recipient_uid` values from
`pf_dedup()`, so a cluster is never split across batches and every row
of a cluster inherits the one match computed for it (see
`pf_propagate_matches()`).

</div>

</div>
