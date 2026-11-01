<div id="main" class="col-md-9" role="main">

# End-to-end wrappers

<div class="ref-description section level2">

The granular functions in this package are deliberately small and
separately testable, which is right for development and wrong for use:
`dev/run-full-file.R` had to hand-assemble nine calls in the correct
order, and every caller reproduced that order. These wrappers name the
four stages and compose them.

</div>

<div class="section level2">

## Details

Three levels of entry, from coarse to fine:

-   `pf_run()`:

    one call, grants in, results out.

-   `pf_prepare()`, `pf_reference()`, `pf_link()`, `pf_adjudicate()`:

    the four stages, for when you want to cache between them or vary
    one.

-   everything else:

    the individual steps, unchanged.

The wrappers add no logic of their own — they order existing calls,
thread the cache paths, and time each stage. Anything a wrapper does
that you disagree with can be done by calling the stage functions
directly.

</div>

</div>
