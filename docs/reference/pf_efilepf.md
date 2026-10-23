# 990-PF Part XV grants paid, direct from the NCCS e-file extracts

The grant file this project has matched against since the beginning is a
GTDC Data Mart extract (`2025_08_29_All_Years_990PFPart14Grants3A.csv`,
12,559,051 rows, tax years 2008-2024). This module rebuilds the same
table from the NCCS e-file extracts instead, which is the upstream
source and is both larger and fresher.

## Usage

``` r
pf_efilepf_years()

pf_efilepf_table()

pf_efilepf_dir()
```

## Why rebuild

Measured against the inventory the bucket publishes alongside the data:

|                         |                |               |
|-------------------------|----------------|---------------|
| source                  | rows           | tax years     |
| GTDC `Part14Grants3A`   | 12,559,051     | 2008-2024     |
| **e-file `PF-P15-T01`** | **17,560,767** | **2009-2025** |

That is 5.0M more grant rows (+40%) and an additional year. The e-file
extract is also regenerated continuously, so a rebuild is reproducible
on demand rather than pinned to whenever the Data Mart extract was cut.

## Which version, and the trap

**Use `efilepf_v3_1`.** `efilepf_v2_3` exists in the same bucket and
carries the same `PF-*` table family, but its published row inventory
reports **zero** rows for `PF-P15-T01` in every year — the grants-paid
table is not populated there. This is the same shape of trap as
`efile_v2_1` vs `efile_v2_2` for Schedule I (see
[`pf_schedi_url()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_schedi_url.md)),
where the superseded extract carried the right schema and a tenth of the
rows. Always check `COUNT-OF-ROWS-BY-TABLE-AND-FORMTYPE-*.CSV` before
trusting a version.

## Part XIV or Part XV

The GTDC file is named "Part14" and this table "P15". They are the same
schedule: grants and contributions **paid** during the year. The IRS
renumbered the 990-PF supplementary-information part, and the e-file
extracts follow the current numbering. `PF-P15-T01` is the repeating
grant-level table; `PF-P15-T00` is the one-row-per-return parent;
`PF-P15-T02` is grants *approved for future payment*, which is a
different population and is **not** what this project matches.

## 2025 drops the recipient-status column

`PF_15_G_PAID_RECIP_STAT` – the GTDC `SIGOCPYRFSTA`, "foundation status
of recipient" – is present every year 2009-2024 and **absent from
2025**. One column removed; the other 29 are identical. The IRS revised
Form 990-PF and dropped that box from Part XV line 3, so this is
permanent and 2026 onward will not have it either.

It matters more than a missing field normally would, because
[`pf_standardize_status()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_standardize_status.md)
reads it and it is the only input to the scope decision. Measured rather
than assumed: with the column absent every row classifies as
`other_unknown` and **`in_scope` stays `TRUE`**, because the
recipient-type filter flags individuals and government bodies rather
than dropping them and only a foreign address removes a row. So 2025
grants are matched normally; what is lost is the ability to *crosstab*
them by recipient type, and any such breakdown must exclude 2025 or
report it separately rather than showing a year that is 100%
`other_unknown` and letting a reader conclude the data is broken.

## Column naming

[`pf_efilepf_build()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_efilepf_build.md)
emits the **GTDC column names**, not the e-file ones. That is
deliberate:
[`pf_prepare_grants()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_prepare_grants.md)
reads `SIGOCPYRBNBN1`, `SIGOCPYRFSTA` and friends by name, as do the
recipient-type and scope rules, so emitting the historical schema means
the entire downstream pipeline, every benchmark and every frozen
artifact keeps working untouched.
[`pf_efilepf_map()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_efilepf_map.md)
is the mapping, exported so the translation is auditable rather than
buried.
