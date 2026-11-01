<div id="main" class="col-md-9" role="main">

# The distinct recipient frame to actually match

<div class="ref-description section level2">

One row per `recipient_uid`, choosing the **most complete**
representative of each cluster (longest name, then most address fields
populated) so the match runs against the best available spelling rather
than an arbitrary one.

</div>

<div class="section level2">

## Usage

<div class="sourceCode">

``` r
pf_recipients(grants)
```

</div>

</div>

<div class="section level2">

## Arguments

-   grants:

    Output of `pf_dedup()`.

</div>

<div class="section level2">

## Value

A data frame with one row per identity, carrying `recipient_uid` as the
match key.

</div>

</div>
