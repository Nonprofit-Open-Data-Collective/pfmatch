<div id="main" class="col-md-9" role="main">

# Detail levels that can never appear in the BMF

<div class="ref-description section level2">

The BMF lists **US** exempt organizations, so only foreign geography is
truly disqualifying: an organization in London or Cape Town has no BMF
row whatever its tax status.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_oos_details()
```

</div>

</div>

<div class="section level2">

## Value

A character vector of `recipient_type_detail` values.

</div>

<div class="section level2">

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

</div>

</div>
