<div id="main" class="col-md-9" role="main">

# Recover unresolved grants against a grant-side dictionary

<div class="ref-description section level2">

Runs the cascade over the rows a BMF run could not clear, against a
dictionary from `pf_grant_dictionary()`, and applies an acceptance rule.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_recover_from_dictionary(
  status,
  dict,
  recipients,
  accept = c("agree", "all", "none"),
  passes = c(pf_staged_passes("lean", concat = TRUE), pf_recovery_passes(state = TRUE)),
  verbose = TRUE
)
```

</div>

</div>

<div class="section level2">

## Arguments

-   status:

    Status frame from `pf_run_batches()` or `pf_match_grants()`,
    carrying `grant_id`, `status` and `ein`.

-   dict:

    A bundle from `pf_grant_dictionary()`.

-   recipients:

    The prepared recipient frame the run was matched from.

-   accept:

    `"agree"`, `"all"` or `"none"`.

-   passes:

    Pass list for the dictionary run.

-   verbose:

    Print the recovery counts.

</div>

<div class="section level2">

## Value

`status` with `dict_status`, `dict_ein`, `dict_score` and `dict_agrees`
added, `status` and `ein` updated on accepted rows, and `recovered`
flagging them. The non-accepted dictionary YES rows are on the `queue`
attribute; `attr(, "counts")` carries the tally.

</div>

<div class="section level2">

## The acceptance rule

`accept = "agree"` (the default) promotes a row only when the
dictionary's EIN is the one the BMF run already held as its own top
candidate. Those were recoverable all along and the margin gate would
not release them — 40.9% of the recoveries measured on the benchmark.
The rest are a *new claim* from a reference whose labels this pipeline
produced, so they go to the queue attribute rather than into the status
frame. `accept = "all"` promotes every dictionary YES and is for
measurement, not production; `accept = "none"` annotates and promotes
nothing.

</div>

<div class="section level2">

## See also

<div class="dont-index">

`pf_grant_dictionary()`

</div>

</div>

</div>
