# Returns that do not report grants directly

Some 990-PF filers decline to itemize Part XIV Table 3a electronically.
They file a single row whose recipient name is a pointer —
`SEE ATTACHED SCHEDULE`, `SCHEDULE AVAILABLE UPON REQUEST`, `VARIOUS` —
carrying the full year's grant total.

## Details

These are not match failures and must not be counted as such. No amount
of record linkage resolves them, because there is no recipient name to
link. They need their own report so the dollars they represent are
visible rather than buried in the NO tier.

## The detail is not recoverable from the e-file

Eight such returns were fetched and inspected
(`dev/probe-attached-xml.R`, `dev/check-xml-attachments.R`). Every one
files **exactly one** `GrantOrContributionPdDurYrGrp` whose
`BusinessNameLine1Txt` is the placeholder text and whose `Amt` is the
whole total, and every one declares `binaryAttachmentCnt="0"`. No
supplemental block, no free-text field long enough to hold a grant list.
The itemization exists only on paper.

What the XML *does* give reliably is the filer EIN, tax year, and the
authoritative Part XIV totals — which is what this report carries.
