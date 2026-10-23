# The e-file to GTDC column mapping

Named character vector: names are the **GTDC** columns the pipeline
reads, values are the **e-file** columns they come from. Exported so the
rebuild is auditable — every column in the output traces to exactly one
source column.

## Usage

``` r
pf_efilepf_map()
```

## Value

Named character vector, GTDC name -\> e-file name.

## Details

One field changes meaning for the better. `SIGOCAFFRFACO` (recipient
country) is present in the GTDC schema but empty throughout it, which is
why
[`pf_prepare_grants()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_prepare_grants.md)
detects foreign recipients from the address text instead. The e-file
source populates `PF_15_G_PAID_RECIP_ADDR_CNTR`, so the rebuilt file can
carry a real country and foreign detection can be revisited — measure
before changing the rule.
