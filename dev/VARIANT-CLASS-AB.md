# The augmented reference's gain is entirely the aliases

Measured 2026-08-21 for matchdb Phase 0c (`matchdb/dev/PROCESS.md` §4).
`dev/probe-variant-class-ab.R`, log `dev/AB-COMPARE.log`.

**Three conclusions.**

1. The augmented reference's YES gain comes **entirely from the Schedule I
   aliases**. The inactive-EIN tranche — 1.76M rows, most of the reference's
   size and most of its cost — is *negative* at the YES tier.
2. The §6b promotion defect is **real but small, and the fix is nearly free**:
   19 identities are auto-accepted on a promotion that fired on an alias row,
   and gating the promotion to legal names costs 2 net YES.
3. The variant-class axis is **strongly justified**. `matchdb/dev/PROCESS.md`
   §4 set the decision rule as "if aliases-gained is small and promotions-lost
   is large, the plan's priorities change." It is the opposite: aliases-gained
   is large (+199 net, 467 YES won on alias rows) and promotions-lost is 19.

## Design

Four arms, one query (the five 1k grant files, 4,800 identities in the union),
one config, one 11-pass cascade. Arms differ only in the reference.

| arm | reference | rows |
|---|---|---:|
| D | monthly active BMF | 1,924,822 |
| A | unified (active + inactive) | 3,687,435 |
| B | augmented unified | 3,880,431 |
| C | augmented, promotion gated to legal rows | 3,880,431 |

Arm D reproduces `dev/DETERMINISM-FINDINGS.md` exactly (2821 / 1006 / 906),
which is the check that the harness matches the established benchmark.

**No npmatch change was needed.** `attr(result, "pairs")` retains the scored
pairs frame including `.y`, the reference row index, so variant class is
recoverable after the fact. And arm C needed no new logic: the promotion
already gates on `name_ver_y == "MAIN"` via `distinct_name_main_only`, so
marking alias rows as anything else disables it for exactly those rows. That is
applied in a four-line wrapper around `.np_hier_score()` operating on a local
copy of `pairs`, so npmatch's own scoring runs unmodified and nothing leaks.
This is measurement only; no shipped default changed.

## Results

| arm | YES | MAYBE | NO | NONE |
|---|---:|---:|---:|---:|
| D monthly active | 2821 | 1006 | 906 | 67 |
| A unified | 2816 | 1108 | 850 | 26 |
| B augmented | 3015 | 1041 | 737 | 7 |
| C augmented, legal-gated | 3013 | 1035 | 745 | 7 |

`NONE` = no candidate pair was ever generated, which is distinct from a scored
`NO`. Arms do not share an identity set — a larger reference draws candidates
for more identities (4,733 on the monthly BMF, 4,793 on the augmented) — so
they are aligned on the union of `.id`.

### The published figure decomposes into three steps

```
D -> A  inactive EIN tranche          -5 YES   +102 MAYBE
A -> B  Schedule I aliases          +199 YES    -67 MAYBE
B -> C  legal-gated promotion         -2 YES     -6 MAYBE
------------------------------------------------------
D -> B  the reported comparison     +194 YES    +35 MAYBE
```

**The inactive tranche costs 5 YES and pushes ~102 identities into MAYBE.** It
is 1.76M of the 1.96M rows added between D and B — nearly all of the size, and
by `dev/REF-PERFORMANCE.md`'s scaling nearly all of the runtime — and it moves
the YES tier *backwards*. Whatever the augmented reference buys, none of it
comes from adding inactive EINs.

That is exactly the §6a mechanism: `np_name_freq()` is a raw count, so doubling
the reference pushes names past `distinct_name_maxfreq = 3` and switches off the
distinctive-name promotion that had been carrying them.

### Where the +199 comes from

```
+283  YES gained, won on an ALIAS row
  +3  YES gained, won on a LEGAL row      (blocking / geo side-effects)
 -87  YES lost
        19  attributable to name_freq inflation
        68  other
-----
+199  net
```

467 of arm B's 3015 YES are won on an alias row — about 15% of all accepted
matches. The net understates the aliases' role considerably, because they also
*displace* legal-row wins rather than only adding new ones.

### What legal-gating costs (§6b)

```
19  YES in B that are not YES in C
19  ... of which won on an ALIAS row
 0  ... of which won on a LEGAL row   (as expected: the gate only touches alias rows)
```

19 identities were auto-accepted on a promotion whose stated justification is
"this exact **legal** name is rare in the reference." Gating it costs **2 net
YES**, because 17 of the 19 have a legal-row alternative that clears YES on its
own.

**Eligibility is not dependence**, and the gap is large. 350 alias YES in arm C
satisfy the promotion predicate (`name_freq <= 3 & name_score >= 0.95`) yet none
was promoted — arm C excludes alias rows entirely — so all 350 cleared YES
unaided. Counting eligible pairs overstates the defect's reach by roughly 18x.
Only the 19 actually depended on the floor.

| arm | promotion-eligible YES | alias | legal |
|---|---:|---:|---:|
| A | 2292 | 0 | 2292 |
| B | 2440 | 370 | 2070 |
| C | 2435 | 350 | 2085 |

Note the two 19s in this document are different sets that coincide in size: one
is A→B YES lost to frequency inflation, the other is B→C YES lost to gating.

## What this changes

**Adopt the legal gate — but at a boundary, not now.** It removes 19
auto-accepts resting on a rule that was never validated for third-party names,
at a cost of 2 YES. Per `matchdb/dev/PROCESS.md` §2 Collision B, it moves the
YES/MAYBE boundary, so it lands either before threshold optimization begins or
after it concludes, never during. The measurement is banked; the change waits.

**Reconsider `bmf_inactive` in the default published spec.** `matchdb/dev/PLAN.md`
§7b proposes `unified-legal` and `unified-observed` as named tiers. On this
evidence the inactive tranche buys −5 YES for ~1.76M rows. It has real uses —
resolving defunct grantees, historical identity work — but it should not be the
default anyone gets without asking. An `active-observed` spec (active BMF +
aliases, ~2.1M rows) looks like the better default and was not in the proposed
set. Worth measuring directly before Phase 3 fixes the published tiers.

**The row budget (§8) should be justified by tier, not by rows.** Aliases are
193k rows for +199 YES; inactive EINs are 1.76M rows for −5. Reference growth is
not fungible, and a budget expressed only in rows would have rated these
identically.

## Caveats

**This is not the reference `REF-PERFORMANCE.md` benchmarked.** That document
reports +43 YES against an augmented reference of 3,891,187 rows.
`REF-augmented.rds` holds 3,880,431 and resolves — by row count, at 100% EIN
alignment — to `BMF-AUGMENTED-unified-fixed.csv`, a different artifact from the
3,891,187-row geocoded CSV behind the published number. Three near-identically
named augmented CSVs sit in `data-dev/` and the reference bundle records which
one it came from nowhere.

The probe therefore resolves provenance empirically and refuses to run if
nothing matches. The four arms remain internally comparable — one query, one
config, one pass set — but `D -> B` here is +194, not +43, and the two are not
the same experiment. This is the filename-as-provenance failure
`matchdb/dev/PLAN.md` §2 describes, encountered in the course of trying to
reproduce a number.

**Attribution of the 68 "other" losses is not established.** They are YES in A
and not YES in B without the frequency-inflation signature. Candidates include
an alias row outscoring the legal row and then failing a veto, and margin
compression from added near-ties. Not pursued here.

**One query set, one vintage.** 4,800 identities from the 1k benchmark. The
direction of these effects is clear; the magnitudes are specific to this sample.
