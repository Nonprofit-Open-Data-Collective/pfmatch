# End-to-end wrappers

The granular functions in this package are deliberately small and
separately testable, which is right for development and wrong for use:
`dev/run-full-file.R` had to hand-assemble nine calls in the correct
order, and every caller reproduced that order. These wrappers name the
four stages and compose them.

## Details

Three levels of entry, from coarse to fine:

- [`pf_run()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_run.md):

  one call, grants in, results out.

- [`pf_prepare()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_prepare.md),
  [`pf_reference()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_reference.md),
  [`pf_link()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_link.md),
  [`pf_adjudicate()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_adjudicate.md):

  the four stages, for when you want to cache between them or vary one.

- everything else:

  the individual steps, unchanged.

The wrappers add no logic of their own — they order existing calls,
thread the cache paths, and time each stage. Anything a wrapper does
that you disagree with can be done by calling the stage functions
directly.
