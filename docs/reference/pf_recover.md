# Stage 4 — alias and repair passes

Stages A-C fail on names that are *spelled* differently from the BMF
rather than absent from it. The NO-tier audit found three recurring,
mechanical causes, and this module addresses each. Together they were
the single largest identified block of recoverable recall.

## Details

- **Acronyms**:

  `NJOP`, `CSCOE`, `OMSI`, `PVCC`. The BMF holds the spelled-out legal
  name, so query and reference share **no token at all** and blocking
  never surfaces the pair — 72 of 4,627 queries in the 5k benchmark
  generated zero candidates from any pass, mostly for this reason.

- **Truncation**:

  `SIGOCPYRPNAM` is hard-capped at 35 characters and 6.1% of non-empty
  values sit exactly at the cap, cut off mid-name
  (`MASSACHUSETTS SOCIETY FOR THE PREVENTION O`). A truncated name can
  never clear an exact pass.

- **Name typed into the street field**:

  `Society of Jesus NY Province` and `St Ignatius School` appear as
  street values on rows whose name field is blank. Rare, but pure
  garbage-in that is cheap to catch.
