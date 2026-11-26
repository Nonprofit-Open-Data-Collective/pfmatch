# Detect placeholder rows before matching, and set them aside

Dev note from the intermediaries project, 2026-11-26. Measured on 7,621,052 990-PF grant
rows, TY2021–2024 ($473.2B), from the V2 corpus. The lexicon, detector and scan are in
`intermediaries/dev/placeholder/` and `intermediaries/dev/pfmatch-run/00-placeholder-scan.R`.
Outputs are in `~/Documents/GRANTFLOW/pfmatch-ty2021-2024/placeholder/`.

**Request:** add a step before `pf_prepare()` scoping. It should flag grant rows whose
"recipient" is a note rather than a payee, and keep those rows out of the cascade. They
should get `in_scope = FALSE` with an `oos_reason` category, so that they are counted but
not matched. pfmatch's `flag_placeholder` and its OOS rules miss most of them today: in this
run, nearly all placeholder dollars reached the cascade and ended as NO.

## 1. Why it matters: few rows, a quarter of the dollars

| | Rows | Share of rows | Dollars | Share of dollars |
|---|---:|---:|---:|---:|
| Placeholder rows (set aside) | 25,690 | 0.34% | $113.4B | **24.0%** |
| …of which drug patient-assistance foundations (21 filers) | — | — | $71.7B | 15.2% |
| Reference that names a real payee (matched on the remaining name) | 346 | — | $0.27B | — |

- These rows held 61% of all NO dollars in the first combine. Leaving them in scope makes
  every match rate weighted by dollars look 24 points worse than the matcher is, and they
  cannot be matched by construction.
- They are concentrated. The top 10 filers hold 72% of placeholder dollars, the top 25 hold
  81%, and the top 100 hold 88%.
- 7,653 foundations file at least one placeholder line.

**By category** (the sink column is the intermediaries system of accounts):

| Category | Rows | $B | Filers | Sink |
|---|---:|---:|---:|---|
| attachment_reference ("SEE ATTACHED", "STATEMENT 25", "AVAILABLE UPON REQUEST") | 11,856 | 55.96 | 3,630 | UNITEMIZED |
| aggregate_individuals ("INDIVIDUAL PATIENT PROGRAMS", "VARIOUS INDIVIDUALS", "STUDENT 3") | 2,149 | 43.77 | 632 | INDIV |
| aggregate_organisations ("VARIOUS CHARITIES", "GRANTS", "MISC") | 7,097 | 6.28 | 2,728 | UNITEMIZED |
| privacy_withheld (HIPAA notes, "NAMES WITHHELD") | 144 | 5.07 | 27 | INDIV |
| legal_note ("NA - SECTION 4948B") | 8 | 2.10 | 2 | UNITEMIZED |
| unknown_or_none (blank, "N/A", digits only, 1–2 characters) | 4,436 | 0.18 | 947 | UNITEMIZED |

## 2. The lexicon

There are 15 regex rules in `placeholder-lexicon.csv`. Each has a category, a sink, a scope
(`whole`, `prefix` or `anywhere`) and an example taken from the data. Rules apply in file
order to the normalized name (upper case, punctuation turned into spaces). The rules are
**structural on purpose**. Keyword rules fail because the keywords also name real recipients
that match YES:

| Would be wrong | Real recipient | Handled by |
|---|---|---|
| SCHOLARSHIP, STUDENTS | Scholarship America (884 rows YES), Students for Life | IND02 matches whole names only |
| ANONYMOUS | Alcoholics / Narcotics Anonymous | PRV02 matches whole names only |
| SEE | SEE International, Help Me See | REF01 needs SEE + a document word |
| STATEMENT, EXHIBIT | Statement Arts Inc, Exhibit Envoy | REF03 needs a label + a number or letter |
| MULTIPLE, OTHER, SMALL | Multiple Sclerosis Society, Other Side Academy | AGG01 opens only with VARIOUS / MISC / SUNDRY / ASSORTED |
| PATIENT ASSISTANCE | "Angelica Patient Assistance Program Inc" | IND01 is blocked when INC, FOUNDATION, FUND, … follow |
| N A | N A A C P Legal Defense Fund | UNK01 matches whole names only |

**A reference with a payee name.** "FIDELITY CHARITABLE - SEE ATTACHMENT A" and "LINDA VISTA
FOUNDATION SEE ATTACHED" name a real payee. The detector cuts off the reference and returns
`category = reference_with_name` with the payee in `residual`. Those rows stay in scope and
are matched on the residual name. A residual counts only if it is not a list word ("LIST",
"NAMES", "501C3 ORG", "DETAILS") and is not made up only of generic words ("THE FOUNDATION",
"COMMUNITY", "CASH GRANTS").

## 3. Validation: flagged rows that pfmatch matched YES

| Category | Rows | Matched YES | Share YES |
|---|---:|---:|---:|
| attachment_reference | 11,856 | 4 | 0.03% |
| aggregate_organisations | 7,097 | 26 | 0.37% |
| unknown_or_none | 4,436 | 93 | 2.10% |
| aggregate_individuals | 2,149 | 52 | 2.42% |
| privacy_withheld | 144 | 0 | 0 |
| legal_note | 8 | 0 | 0 |
| reference_with_name (not set aside) | 346 | 10 | 2.9% |
| *peopleparser-only "placeholder" (not used)* | 332 | 122 | **36.8%** |

- Most of the flagged rows that matched YES are pfmatch false positives, not detector
  errors. Examples: "GIFT", "CHARITY", "OTHERS", "X", "2164" and blank names all came back
  YES, which these placeholders should never be.
- The real detector misses are names of the form "INDIANA UNIVERSITY VARIOUS STUDENTS" and
  "SUNY CORTLAND FBO VARIOUS INDIVIDUALS", where the institution is the payee. A reference
  with a payee name should extend to `<ORG> (FBO) VARIOUS <people>`.
- peopleparser's `classify_names()` "placeholder" type was built for officer lists. On
  grantee names it flags real organisations ("NO ONE LEFT BEHIND", "THE TRUSTEES"), so it is
  reported but not used.
- Blank names with a street address sometimes matched YES (16 rows). pfmatch's
  `name_from_street` may be recovering them. Blank names should be set aside only when the
  address is blank too.

## 4. Where the lists are (agent test on 6 large placeholder filers)

The itemized list usually exists, but outside the e-file XML.

| Foundation | Where | Usable |
|---|---|---|
| Wyss | the foundation's own posted 990-PF (text PDF), and IRS full-return PDFs | yes; 2022 reconciles to $163,338,595 |
| Howard G. Buffett | IRS full-return PDF 2024, pp. 34–52 (scanned) | needs OCR; reconciles; no 2023 PDF |
| Bezos Family | IRS full-return PDF 2023, "Attachment C" (scanned) | needs OCR; reconciles |
| Schusterman | 2023 PDF has only expenditure-responsibility statements; 2022 not checked | unresolved |
| Wells Fargo | not in the published PDFs for 2021–2023; the 2024 e-file is itemized | no |
| Musk | "SEE ATTACHMENT A" lines are **real single stock grants** (Fidelity Charitable; Musk's Texas school charity) | not placeholders |

The IRS bulk 990 PDF releases (mirrored by ProPublica) are the only systematic source of the
binary attachment. A recovery pipeline would:

1. find the attachment pages by page size;
2. OCR them;
3. reconcile the OCR'd total against the placeholder amount;
4. only then add the rows.

This is worth doing only for the top filers that are not patient-assistance programmes. The
top 100 cover 88% of placeholder dollars, and the 21 patient-assistance programmes are
in-kind drugs given to people, with no organisation list to recover.

The Musk case shows a limit of the lexicon. A reference attached to a generic word ("THE
FOUNDATION - SEE ATTACHMENT A") can still be a single real grant. The amount is real, but
the payee can't be named from the row, so UNITEMIZED is the right sink for now.

## 5. Proposed change in pfmatch

1. Add `pf_detect_placeholders()`, a port of `detect-placeholders.R` with the lexicon in
   `inst/extdata/`. Call it in `pf_prepare_grants()` before scoping. Set `in_scope = FALSE`,
   `oos_reason = "placeholder:<category>"`, and keep `rule_id` and `sink`.
2. For `reference_with_name`, replace `recip_name` with the residual before dedup, and keep
   the original in `recip_name_filed`.
3. Report placeholder rows and dollars in `pf_report()` as a separate line, not inside NO.
   Compute dollar-weighted rates over the in-scope universe.
4. Add a fixture test for the false-positive table in section 2: every "real recipient" row
   must stay in scope.
