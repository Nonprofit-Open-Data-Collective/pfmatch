<div id="main" class="col-md-9" role="main">

# Organization self-description text, keyed by EIN

<div class="ref-description section level2">

The BMF says what an organization *is* (NTEE code, activity codes); Form
990 Part III says what it *does* (mission, program service
accomplishments). This module assembles both into one table keyed by
EIN, so that a grant purpose can be compared against it.

</div>

<div class="section level2">

## Coverage, and why it is the binding constraint

Measured on the 1.92M-record BMF and the 553,488 tax-year-2022 Part III
returns:

-   NTEE code usable (not blank/`INVALID`/`UNDEFINED`/`Z99`) — 66.5%,
    and *worse* for large organizations: only 43% above $10M revenue.

-   Form 990 mission text — 27.1% of BMF EINs.

-   Form 990 program descriptions — 17.2%.

-   IRS activity-code text — 37.2%.

990-EZ filers (37% of returns) have a mission and never a program
description, so program coverage tracks organization size rather than
chance. See `dev/PURPOSE-MATCH-FINDINGS.md` for what that costs.

</div>

</div>
