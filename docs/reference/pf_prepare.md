# Stage 1 — read, repair, scope, and collapse to identities

Wraps
[`pf_read_grants()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_read_grants.md)
(which itself calls
[`pf_prepare_grants()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_prepare_grants.md),
and so
[`pf_standardize_status()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_standardize_status.md)),
then
[`pf_recover_name_from_street()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_recover_name_from_street.md),
[`pf_dedup()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_dedup.md),
and
[`pf_recipients()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_recipients.md).

Turns the raw GTDC 990-PF "grants paid during year" extract (Part XIV
Table 3a) into a frame npmatch can consume, and attaches the scope
decision.

## Usage

``` r
pf_prepare(
  grants,
  pattern = "grants.*[.]csv$",
  dedup = c("fuzzy", "exact", "none"),
  threshold = 0.92,
  verbose = TRUE
)
```

## Arguments

- grants:

  A directory of grant CSVs, a vector of file paths, or an already-read
  data frame.

- pattern:

  Regex selecting files when `grants` is a directory.

- dedup:

  `"fuzzy"` (default), `"exact"`, or `"none"`.

- threshold:

  Name-similarity threshold for fuzzy clustering.

- verbose:

  Print progress.

## Value

A list of class `pf_prepared` with `grants` (every row, scoped and
assigned a `recipient_uid`), `recipients` (one row per identity, in
scope), and `timing`.

## Details

The dedup step is the scale lever, not a nicety: grants repeat heavily,
and matching distinct recipient identities rather than grant rows
removes most of the work without removing recall. It also *adds* recall,
because a match found for any cluster member propagates to all of them.

## Name fields

The extract carries three recipient-name columns, and the data
dictionary is explicit about what they are:

- `SIGOCPYRPNAM` — "Name of Grantee — **Person**"

- `SIGOCPYRBNBN1` — "Name of Grantee — **Business** Line 1"

- `SIGOCPYRBNBN2` — "Name of Grantee — **Business** Line 2"

So `BNBN1` / `BNBN2` are a two-line **wrap of one name**, not a main
name and a DBA — line 2 exists because line 1 ran out of characters. In
the 5,000-row sample `PNAM` and `BNBN1` never co-occur (0 rows carry
both), so the recipient name is a straight coalesce of the two. `PNAM`
is *not* a reliable individual flag: filers routinely put organizations
in it ("World Central Kitchen", "Surfrider Foundation"), so scope is
decided from `SIGOCPYRFSTA` instead.

Line 2, when present, is one of four things, and each is handled
differently:

1.  a duplicate of line 1 — dropped

2.  a care-of / attention line ("ATTN LEGAL DEPARTMENT", "C/O JUDY
    AREANO") — dropped, it is address data in a name field

3.  an FBO beneficiary ("ROCKY MOUNTAIN COLLEGE FBO" + "ALYSSA
    PATTERSON") — dropped and the trailing `FBO` stripped from line 1,
    since the grantee of record is the college

4.  a genuine continuation ("MEMPHIS JEWISH HOME B'NAI B'RITH HOME &" +
    "HOSPITAL") — joined onto line 1 as an alternate name

The joined continuation is carried in npmatch's `dba` slot. That is a
deliberate reuse rather than a claim that it is a DBA: `np_compare()`
scores the full name/DBA cross-product and keeps the best, so putting
the untruncated name there lets a record match on either the truncated
line-1 form or the complete one, whichever the BMF happens to hold.
