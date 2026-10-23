# Order the members of an operating/arm cluster

Returns the two EINs in best-guess order. The default policy is
**operating entity first**, switching to the arm when the grant purpose
names a restricted gift — a scholarship, an endowment, a capital
campaign — because those are legally the arm's job.

## Usage

``` r
pf_arm_order(
  cluster,
  purpose = NULL,
  policy = c("purpose", "operating"),
  sa_status = NULL
)
```

## Arguments

- cluster:

  Output of
  [`pf_cluster_arms()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_cluster_arms.md).

- purpose:

  Character vector of grant purposes, aligned to `cluster` rows.

- policy:

  `"purpose"` (default) or `"operating"` for the flat rule.

- sa_status:

  Optional output of
  [`pf_schedule_a_status()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_schedule_a_status.md).
  When given, any arm ticking Schedule A line 5 is ordered first
  regardless of purpose.

## Value

`cluster` with `first_ein`, `second_ein` and `order_reason` added.

## What is and is not established

On 15 adjudicated cases containing a co-located arm pair, the operating
entity was the recipient 9 times (60%, 95% CI 32–84%) and the arm 6
times. The purpose-conditional rule scores 67%, the flat rule 60%, and
**the current cascade ranks the correct member first only 27% of the
time**. The last of those is the finding that justifies acting: the
existing behaviour is anti-correlated with the answer, and either policy
is a large improvement. The 60-versus-67 gap is one case wide and
settles nothing — only one adjudicated case had a restricted-gift
purpose. Do not read the conditional rule as validated; it is the
hypothesis a larger labelling round should test.
