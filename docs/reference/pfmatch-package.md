# pfmatch: Match 990-PF Grant Recipients to the IRS Business Master File

Recovers recipient EINs for grants reported on Form 990-PF Part XIV
Table 3a. Standardizes the uncontrolled recipient-status field, resolves
the two-line recipient name, collapses repeated grant rows to distinct
recipient identities, and runs a staged, geography-aware blocking
cascade against the IRS Business Master File. The generic record-linkage
machinery - normalization, blocking, comparison, hierarchical scoring,
vetoes, and YES/MAYBE/NO tiering - is provided by 'npmatch'; this
package holds only what is specific to the 990-PF grant context.

## See also

Useful links:

- <https://nonprofit-open-data-collective.github.io/pfmatch>

- <https://github.com/Nonprofit-Open-Data-Collective/pfmatch>

- Report bugs at
  <https://github.com/Nonprofit-Open-Data-Collective/pfmatch/issues>

## Author

**Maintainer**: Jesse Lecy <jdlecy@gmail.com>
