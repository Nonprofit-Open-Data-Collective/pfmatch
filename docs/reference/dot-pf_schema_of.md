# Which schema does this frame use?

Which schema does this frame use?

## Usage

``` r
.pf_schema_of(g)
```

## Arguments

- g:

  A grant frame.

## Value

`"v2"`, `"gtdc"`, or `"mixed"` when columns of both appear, which
usually means two vintages were concatenated.
