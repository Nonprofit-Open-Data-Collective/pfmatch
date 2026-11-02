<div id="main" class="col-md-9" role="main">

# Package index

<div class="section level2">

## Run the pipeline

<div class="section-desc">

End to end. `pf_run()` is the whole thing; the staged functions are the
same work with the seams exposed.

</div>

</div>

<div class="section level2">

-   `pf_pipeline` : End-to-end wrappers
-   `pf_run()` : Run the whole pipeline
-   `pf_run_batches()` : Run the cascade over a large grant file in
    checkpointed batches
-   `pf_link()` : Stage 3 — run the cascade and propagate to grant rows
-   `pf_batch_doc` : Stage 6 — checkpointed batch driver for the full
    grant file
-   `pf_batch_report()` : Summarize a batched run

</div>

<div class="section level2">

## Stage 1 — read and prepare grants

<div class="section-desc">

Parse Part XIV Table 3a, standardize the uncontrolled recipient-status
field, resolve the two-line recipient name, and decide what is in scope.

</div>

</div>

<div class="section level2">

-   `pf_prepare()` : Stage 1 — read, repair, scope, and collapse to
    identities
-   `pf_read_grants()` : Read and prepare the sample grant CSVs
-   `pf_prepare_grants()` : Prepare a raw 990-PF grants extract
-   `pf_recover_name_from_street()` : Recover a recipient name typed
    into the street field
-   `pf_recipient_type` : Standardize the 990-PF recipient
    foundation-status field (SIGOCPYRFSTA)
-   `pf_standardize_status()` : Standardize SIGOCPYRFSTA into recipient
    types
-   `pf_status_audit()` : Audit the standardization
-   `pf_schedule_a_status()` : Schedule A Part I public-charity status
    flags
-   `pf_is_placeholder()` : Flag grant rows whose recipient is a pointer
    to an attachment
-   `pf_placeholder_pattern()` : Patterns that mark a recipient name as
    a pointer rather than a name
-   `pf_attached` : Returns that do not report grants directly
-   `pf_attached_report()` : Report on returns that do not itemize their
    grants

</div>

<div class="section level2">

## Stage 2 — collapse to recipient identities

<div class="section-desc">

Repeated grant rows become one identity, so the cascade scores each
recipient once rather than once per grant.

</div>

</div>

<div class="section level2">

-   `pf_dedup_doc` : Collapse grant rows to distinct recipient
    identities
-   `pf_dedup()` : Deduplicate grant recipients
-   `pf_recipients()` : The distinct recipient frame to actually match
-   `pf_dedup_report()` : Report on a dedup run
-   `pf_propagate_matches()` : Propagate a match back from identities to
    grant rows
-   `pf_group_siblings()` : Federated siblings from the BMF group
    exemption

</div>

<div class="section level2">

## Stage 3 — the reference

<div class="section-desc">

Compile the BMF side: layers, name variants, enrichment text.

</div>

</div>

<div class="section level2">

-   `pf_reference()` : Stage 2 — the reference bundle
-   `pf_build_reference()` : Build the BMF reference once
-   `pf_check_reference()` : Refuse a reference bundle built by a
    different normalizer
-   `pf_bmf_augment()` : Append Schedule I alias rows to the BMF
-   `pf_collapse_reference()` : Collapse reference rows the matcher
    cannot tell apart
-   `pf_partition_reference()` `pf_route_queries()`
    `pf_run_partitioned()` : Partition the reference by state, and run
    the cascade over the partition
-   `pf_bmf_context()` : Build a compact BMF context table keyed by EIN
-   `pf_text` : Organization self-description text, keyed by EIN
-   `pf_build_org_text()` : Build the EIN -> self-description table
-   `pf_attach_missions()` : Attach an external mission table
-   `nteev2` : NTEE codes rendered as text
-   `pf_variants` : Name and address variants that survive normalization

</div>

<div class="section level2">

## Stage 4 — the matching cascade

<div class="section-desc">

The staged blocking passes and the match itself. See the cascade article
for what each pass does and which cases it clears.

</div>

</div>

<div class="section level2">

-   `pf_match` : Match 990-PF grant recipients to the BMF
-   `pf_match_grants()` : Run the grant-recipient match
-   `pf_staged_passes()` : Staged cascade: state-blocked bulk, then an
    unblocked residual sweep
-   `pf_recover` : Stage 4 — alias and repair passes
-   `pf_recovery_passes()` : Stage 4 recovery passes
-   `pf_add_recovery_keys()` : Add acronym and prefix recovery columns
    to a normalized frame
-   `pf_drop_self_matches()` : Never match a grant to the foundation
    that made it
-   `pf_status()` : Per-grant outcome frame
-   `pf_result_tiers()` : Tiers in the result-frame convention
-   `pf_crosstab()` : Outcome x recipient-type crosstab
-   `pf_geo_agreement()` : Geographic-agreement diagnostics

</div>

<div class="section level2">

## Character-level recovery

<div class="section-desc">

The one failure the cascade cannot see. Every blocking pass is an exact
match on a name, a token, an acronym or a prefix, so a single mistyped
letter in the one distinctive token leaves no key to block on and the
correct record is never retrieved at all — not scored and rejected,
never offered. Jaro-Winkler inside a ZIP5 block, on the residual only.
See the article on what lives outside the BMF.

</div>

</div>

<div class="section level2">

-   `pf_fuzzy_candidates()` : Candidate pairs from a near-miss name
    inside a geographic block
-   `pf_fuzzy_recover()` : Retry the unresolved residual with fuzzy
    candidates

</div>

<div class="section level2">

## Stage 5 — adjudication

<div class="section-desc">

Build the sheet a human or an LLM reviews. There is no safe automatic
acceptance of the MAYBE tier; see `dev/ADJUDICATION-PLAN.md`.

</div>

</div>

<div class="section level2">

-   `pf_adjudicate()` : Stage 4 — build the adjudication sheet
-   `pf_candidate_frame()` : Candidate-level adjudication frame
-   `pf_enrich` : Enrich match results with BMF context for adjudication
-   `pf_purpose` : Grant purpose as a tiebreak signal
-   `pf_purpose_tiebreak()` : Break near-ties on grant purpose and
    filing presence
-   `pf_purpose_is_contentful()` : Does the purpose say anything?
-   `pf_purpose_coverage()` : IDF-weighted containment of a purpose in a
    document
-   `pf_purpose_tokens()` : Tokenize purpose or organization text
-   `pf_street_unit()` : Parse the secondary-unit line into a comparable
    unit
-   `pf_unit_evidence()` : Compare two unit lines as adjudication
    evidence

</div>

<div class="section level2">

## Recovery against resolved grants

<div class="section-desc">

A supplement to the cascade, not a reference. Foundations write
recipient names consistently with each other and differently from the
BMF, so a grant the BMF cannot clear may match one that already cleared.
Runs after the cascade, on what it left unresolved, and promotes only
what the BMF’s own top candidate corroborates. See
`dev/EXP-HEAD-REFERENCE.log`.

</div>

</div>

<div class="section level2">

-   `pf_grant_dictionary()` : Build a dictionary of resolved grant
    renderings
-   `pf_recover_from_dictionary()` : Recover unresolved grants against a
    grant-side dictionary

</div>

<div class="section level2">

## Evaluation against ground truth

<div class="section-desc">

Score a configuration instead of arguing about its clear rate: a
clear-rate delta cannot separate recall from false accepts.

</div>

</div>

<div class="section level2">

-   `pf_evaluate()` : Score a run against ground truth
-   `pf_consistency()` : Consistency across renderings of one
    organisation
-   `pf_validate_grants()` : Validate a grant file
-   `pf_truth_schema()` : Ground-truth table columns
-   `pf_population_id()` : Fingerprint a grant population

</div>

<div class="section level2">

## Affiliates, dyads and sibling structure

<div class="section-desc">

Parent, chapter and auxiliary relationships — the dominant source of
wrong-but-plausible matches.

</div>

</div>

<div class="section level2">

-   `pf_affiliation` : Affiliated organizations: operating entities and
    their fundraising arms
-   `pf_build_affiliation_links()` : Build the EIN-to-EIN affiliation
    link table
-   `pf_dyads` : Disclosed EIN dyads: substitutable pairs and merely
    related ones
-   `pf_build_dyads()` : Build the dyad table
-   `pf_dyad_annotate()` : Attach dyad context to a match result
-   `pf_dyad_collapse()` : Collapse substitutable candidates before
    selection
-   `pf_dyad_config()` : Dyad collapse settings
-   `pf_dyad_lookup()` : Look up the dyad class for pairs of EINs
-   `pf_dyad_sources()` : Default locations of the linkid dyad extracts
-   `pf_dyad_summary()` : Summarise a dyad table
-   `pf_cluster_arms()` : Group a candidate list into operating/arm
    clusters
-   `pf_arm_core()` : The shared core of an organization name
-   `pf_arm_order()` : Order the members of an operating/arm cluster
-   `pf_is_arm()` : Is this name a fundraising or support arm?

</div>

<div class="section level2">

## Source data

<div class="section-desc">

Build the grant file from the NCCS e-file extracts, and Schedule I
aliases.

</div>

</div>

<div class="section level2">

-   `pf_efilepf_years()` `pf_efilepf_table()` `pf_efilepf_dir()` :
    990-PF Part XV grants paid, direct from the NCCS e-file extracts
-   `pf_efilepf_fetch()` : Fetch the 990-PF grants-paid extracts via
    panel990
-   `pf_efilepf_build()` : Build the rebuilt grant file from the
    downloaded extracts
-   `pf_efilepf_download()` : Download the e-file 990-PF grants-paid
    extracts
-   `pf_source_provenance()` : The release pfmatch would read, as
    panel990 resolves it
-   `pf_concordance_vars()` : The grants-paid variables, taken from
    concordance990
-   `pf_efilepf_dedup()` : Drop superseded and duplicate 990-PF filings,
    keeping every grant reported
-   `pf_grant_content_cols()` : Grant fields compared when deciding
    whether two filings are the same
-   `pf_efilepf_map()` : The e-file to GTDC column mapping
-   `pf_efilepf_url()` : URL for one year of the e-file 990-PF
    grants-paid extract
-   `pf_schedi` : Form 990 Schedule I as an alias source for the BMF
-   `pf_schedi_alias()` : Read the alias table, one row per (EIN, name)
-   `pf_schedi_build()` : Load the extracts into DuckDB and reduce them
    to an alias table
-   `pf_schedi_download()` : Download the Schedule I extracts

</div>

</div>
