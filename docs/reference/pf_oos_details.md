# Detail levels that can never appear in the BMF

The BMF lists **US** exempt organizations, so only foreign geography is
truly disqualifying: an organization in London or Cape Town has no BMF
row whatever its tax status.

## Usage

``` r
pf_oos_details()
```

## Value

A character vector of `recipient_type_detail` values.

## Details

`individual` and `government` are deliberately **not** here, though an
earlier version of this package did exclude them. Auditing 100
out-of-sample cases showed the exclusion was wrong 24% of the time,
because column (c) reports the status of the grant's **beneficiary**
while the check is written to the **payee**. A foundation paying a named
student's tuition codes the grant `I`, and the payee is a university
that is plainly in the BMF; filers also code ordinary 501(c)(3)s as
`GOV` when they are university- or school-adjacent. Both are now carried
as flags (`flag_individual`, `flag_government`) and matched anyway. See
`dev/AUDIT-FINDINGS.md`.
