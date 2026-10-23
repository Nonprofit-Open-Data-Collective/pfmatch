# Package index

## Run the pipeline

End to end.
[`pf_run()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_run.md)
is the whole thing; the staged functions are the same work with the
seams exposed.

- [`pf_pipeline`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_pipeline.md)
  : End-to-end wrappers
- [`pf_run()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_run.md)
  : Run the whole pipeline
- [`pf_run_batches()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_run_batches.md)
  : Run the cascade over a large grant file in checkpointed batches
- [`pf_link()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_link.md)
  : Stage 3 — run the cascade and propagate to grant rows
- [`pf_batch_doc`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_batch_doc.md)
  : Stage 6 — checkpointed batch driver for the full grant file
- [`pf_batch_report()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_batch_report.md)
  : Summarize a batched run

## Stage 1 — read and prepare grants

Parse Part XIV Table 3a, standardize the uncontrolled recipient-status
field, resolve the two-line recipient name, and decide what is in scope.

- [`pf_prepare()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_prepare.md)
  : Stage 1 — read, repair, scope, and collapse to identities
- [`pf_read_grants()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_read_grants.md)
  : Read and prepare the sample grant CSVs
- [`pf_prepare_grants()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_prepare_grants.md)
  : Prepare a raw 990-PF grants extract
- [`pf_recover_name_from_street()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_recover_name_from_street.md)
  : Recover a recipient name typed into the street field
- [`pf_recipient_type`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_recipient_type.md)
  : Standardize the 990-PF recipient foundation-status field
  (SIGOCPYRFSTA)
- [`pf_standardize_status()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_standardize_status.md)
  : Standardize SIGOCPYRFSTA into recipient types
- [`pf_status_audit()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_status_audit.md)
  : Audit the standardization
- [`pf_schedule_a_status()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_schedule_a_status.md)
  : Schedule A Part I public-charity status flags
- [`pf_is_placeholder()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_is_placeholder.md)
  : Flag grant rows whose recipient is a pointer to an attachment
- [`pf_placeholder_pattern()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_placeholder_pattern.md)
  : Patterns that mark a recipient name as a pointer rather than a name
- [`pf_attached`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_attached.md)
  : Returns that do not report grants directly
- [`pf_attached_report()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_attached_report.md)
  : Report on returns that do not itemize their grants

## Stage 2 — collapse to recipient identities

Repeated grant rows become one identity, so the cascade scores each
recipient once rather than once per grant.

- [`pf_dedup_doc`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_dedup_doc.md)
  : Collapse grant rows to distinct recipient identities
- [`pf_dedup()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_dedup.md)
  : Deduplicate grant recipients
- [`pf_recipients()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_recipients.md)
  : The distinct recipient frame to actually match
- [`pf_dedup_report()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_dedup_report.md)
  : Report on a dedup run
- [`pf_propagate_matches()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_propagate_matches.md)
  : Propagate a match back from identities to grant rows
- [`pf_group_siblings()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_group_siblings.md)
  : Federated siblings from the BMF group exemption

## Stage 3 — the reference

Compile the BMF side: layers, name variants, enrichment text.

- [`pf_reference()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_reference.md)
  : Stage 2 — the BMF reference bundle
- [`pf_build_reference()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_build_reference.md)
  : Build the BMF reference once
- [`pf_bmf_augment()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_bmf_augment.md)
  : Append Schedule I alias rows to the BMF
- [`pf_collapse_reference()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_collapse_reference.md)
  : Collapse reference rows the matcher cannot tell apart
- [`pf_partition_reference()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_partition.md)
  [`pf_route_queries()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_partition.md)
  [`pf_run_partitioned()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_partition.md)
  : Partition the reference by state, and run the cascade over the
  partition
- [`pf_bmf_context()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_bmf_context.md)
  : Build a compact BMF context table keyed by EIN
- [`pf_text`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_text.md)
  : Organization self-description text, keyed by EIN
- [`pf_build_org_text()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_build_org_text.md)
  : Build the EIN -\> self-description table
- [`pf_attach_missions()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_attach_missions.md)
  : Attach an external mission table
- [`nteev2`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/nteev2.md)
  : NTEE codes rendered as text

## Stage 4 — the matching cascade

The staged blocking passes and the match itself. See the cascade article
for what each pass does and which cases it clears.

- [`pf_match`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_match.md)
  : Match 990-PF grant recipients to the BMF
- [`pf_match_grants()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_match_grants.md)
  : Run the grant-recipient match
- [`pf_staged_passes()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_staged_passes.md)
  : Staged cascade: state-blocked bulk, then an unblocked residual sweep
- [`pf_recover`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_recover.md)
  : Stage 4 — alias and repair passes
- [`pf_recovery_passes()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_recovery_passes.md)
  : Stage 4 recovery passes
- [`pf_add_recovery_keys()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_add_recovery_keys.md)
  : Add acronym and prefix recovery columns to a normalized frame
- [`pf_drop_self_matches()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_drop_self_matches.md)
  : Never match a grant to the foundation that made it
- [`pf_status()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_status.md)
  : Per-grant outcome frame
- [`pf_crosstab()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_crosstab.md)
  : Outcome x recipient-type crosstab
- [`pf_geo_agreement()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_geo_agreement.md)
  : Geographic-agreement diagnostics

## Stage 5 — adjudication

Build the sheet a human or an LLM reviews. There is no safe automatic
acceptance of the MAYBE tier; see `dev/ADJUDICATION-PLAN.md`.

- [`pf_adjudicate()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_adjudicate.md)
  : Stage 4 — build the adjudication sheet
- [`pf_candidate_frame()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_candidate_frame.md)
  : Candidate-level adjudication frame
- [`pf_enrich`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_enrich.md)
  : Enrich match results with BMF context for adjudication
- [`pf_purpose`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_purpose.md)
  : Grant purpose as a tiebreak signal
- [`pf_purpose_tiebreak()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_purpose_tiebreak.md)
  : Break near-ties on grant purpose and filing presence
- [`pf_purpose_is_contentful()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_purpose_is_contentful.md)
  : Does the purpose say anything?
- [`pf_purpose_coverage()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_purpose_coverage.md)
  : IDF-weighted containment of a purpose in a document
- [`pf_purpose_tokens()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_purpose_tokens.md)
  : Tokenize purpose or organization text

## Evaluation against ground truth

Score a configuration instead of arguing about its clear rate: a
clear-rate delta cannot separate recall from false accepts.

- [`pf_evaluate()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_evaluate.md)
  : Score a run against ground truth
- [`pf_consistency()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_consistency.md)
  : Consistency across renderings of one organisation
- [`pf_validate_grants()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_validate_grants.md)
  : Validate a grant file
- [`pf_truth_schema()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_truth_schema.md)
  : Ground-truth table columns
- [`pf_population_id()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_population_id.md)
  : Fingerprint a grant population

## Affiliates, dyads and sibling structure

Parent, chapter and auxiliary relationships — the dominant source of
wrong-but-plausible matches.

- [`pf_affiliation`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_affiliation.md)
  : Affiliated organizations: operating entities and their fundraising
  arms
- [`pf_build_affiliation_links()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_build_affiliation_links.md)
  : Build the EIN-to-EIN affiliation link table
- [`pf_dyads`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_dyads.md)
  : Disclosed EIN dyads: substitutable pairs and merely related ones
- [`pf_build_dyads()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_build_dyads.md)
  : Build the dyad table
- [`pf_dyad_annotate()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_dyad_annotate.md)
  : Attach dyad context to a match result
- [`pf_dyad_collapse()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_dyad_collapse.md)
  : Collapse substitutable candidates before selection
- [`pf_dyad_config()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_dyad_config.md)
  : Dyad collapse settings
- [`pf_dyad_lookup()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_dyad_lookup.md)
  : Look up the dyad class for pairs of EINs
- [`pf_dyad_sources()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_dyad_sources.md)
  : Default locations of the linkid dyad extracts
- [`pf_dyad_summary()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_dyad_summary.md)
  : Summarise a dyad table
- [`pf_cluster_arms()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_cluster_arms.md)
  : Group a candidate list into operating/arm clusters
- [`pf_arm_core()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_arm_core.md)
  : The shared core of an organization name
- [`pf_arm_order()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_arm_order.md)
  : Order the members of an operating/arm cluster
- [`pf_is_arm()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_is_arm.md)
  : Is this name a fundraising or support arm?

## Source data

Build the grant file from the NCCS e-file extracts, and Schedule I
aliases.

- [`pf_efilepf_years()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_efilepf.md)
  [`pf_efilepf_table()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_efilepf.md)
  [`pf_efilepf_dir()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_efilepf.md)
  : 990-PF Part XV grants paid, direct from the NCCS e-file extracts
- [`pf_efilepf_fetch()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_efilepf_fetch.md)
  : Fetch the 990-PF grants-paid extracts via panel990
- [`pf_efilepf_build()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_efilepf_build.md)
  : Build the rebuilt grant file from the downloaded extracts
- [`pf_efilepf_download()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_efilepf_download.md)
  : Download the e-file 990-PF grants-paid extracts
- [`pf_source_provenance()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_source_provenance.md)
  : The release pfmatch would read, as panel990 resolves it
- [`pf_concordance_vars()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_concordance_vars.md)
  : The grants-paid variables, taken from concordance990
- [`pf_efilepf_dedup()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_efilepf_dedup.md)
  : Drop superseded and duplicate 990-PF filings, keeping every grant
  reported
- [`pf_grant_content_cols()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_grant_content_cols.md)
  : Grant fields compared when deciding whether two filings are the same
- [`pf_efilepf_map()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_efilepf_map.md)
  : The e-file to GTDC column mapping
- [`pf_efilepf_url()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_efilepf_url.md)
  : URL for one year of the e-file 990-PF grants-paid extract
- [`pf_schedi`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_schedi.md)
  : Form 990 Schedule I as an alias source for the BMF
- [`pf_schedi_alias()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_schedi_alias.md)
  : Read the alias table, one row per (EIN, name)
- [`pf_schedi_build()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_schedi_build.md)
  : Load the extracts into DuckDB and reduce them to an alias table
- [`pf_schedi_download()`](https://nonprofit-open-data-collective.github.io/pfmatch/reference/pf_schedi_download.md)
  : Download the Schedule I extracts
