#!/usr/bin/env Rscript
# ============================================================================
# Generate the reference index of _pkgdown.yml from the package's real topics.
#
# Hand-curating this list is error-prone for a specific reason: pfmatch groups
# several functions onto one Rd page, so the TOPIC names are not the function
# names. `pf_efilepf` documents pf_efilepf_years / _table / _dir; `pf_partition`
# documents pf_partition_reference / pf_route_queries / pf_run_partitioned. A
# hand-written index listing the function names fails pkgdown::check_pkgdown()
# with "indexed but not a topic" while simultaneously leaving the real topics
# unindexed -- which is exactly what happened on the first attempt.
#
# So the group assignments below are by topic name, and anything unassigned
# lands in a catch-all section. check_pkgdown() then passes by construction, and
# a newly added topic shows up in the catch-all rather than vanishing.
# ============================================================================
suppressWarnings(suppressMessages(library(pkgdown)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
say <- function(...) message(sprintf(...))

GROUPS <- list(
  list(title = "Run the pipeline",
       desc = paste("End to end. `pf_run()` is the whole thing; the staged",
                    "functions are the same work with the seams exposed."),
       topics = c("pf_pipeline", "pf_run", "pf_run_batches", "pf_link",
                  "pf_batch_doc", "pf_batch_report", "pf_report")),
  list(title = "Stage 1 — read and prepare grants",
       desc = paste("Parse Part XIV Table 3a, standardize the uncontrolled",
                    "recipient-status field, resolve the two-line recipient",
                    "name, and decide what is in scope."),
       topics = c("pf_prepare", "pf_read_grants", "pf_prepare_grants",
                  "pf_recover_name_from_street", "pf_recipient_type",
                  "pf_standardize_status", "pf_status_audit",
                  "pf_schedule_a_status", "pf_type_labels", "pf_oos_details",
                  "pf_is_placeholder", "pf_placeholder_pattern",
                  "pf_attached", "pf_attached_report", "pf_map_grants")),
  list(title = "Stage 2 — collapse to recipient identities",
       desc = paste("Repeated grant rows become one identity, so the cascade",
                    "scores each recipient once rather than once per grant."),
       topics = c("pf_dedup_doc", "pf_dedup", "pf_recipients",
                  "pf_dedup_report", "pf_propagate_matches",
                  "pf_group_siblings")),
  list(title = "Stage 3 — the reference",
       desc = "Compile the BMF side: layers, name variants, enrichment text.",
       topics = c("pf_reference", "pf_build_reference", "pf_bmf_augment",
                  "pf_collapse_reference", "pf_partition", "pf_bmf_context",
                  "pf_text", "pf_build_org_text", "pf_attach_missions",
                  "nteev2", "pf_ntee_text")),
  list(title = "Stage 4 — the matching cascade",
       desc = paste("The staged blocking passes and the match itself. See the",
                    "cascade article for what each pass does and which cases",
                    "it clears."),
       topics = c("pf_match", "pf_match_grants", "pf_staged_passes",
                  "pf_default_passes", "pf_recover", "pf_recovery_passes",
                  "pf_add_recovery_keys", "pf_pass_stage", "pf_initials",
                  "pf_drop_self_matches", "pf_status", "pf_crosstab",
                  "pf_geo_agreement")),
  list(title = "Stage 5 — adjudication",
       desc = paste("Build the sheet a human or an LLM reviews. There is no",
                    "safe automatic acceptance of the MAYBE tier; see",
                    "`dev/ADJUDICATION-PLAN.md`."),
       topics = c("pf_adjudicate", "pf_candidate_frame", "pf_enrich",
                  "pf_purpose", "pf_purpose_tiebreak", "pf_tiebreak_config",
                  "pf_purpose_is_contentful", "pf_purpose_coverage",
                  "pf_purpose_tokens", "pf_purpose_stopwords")),
  list(title = "Evaluation against ground truth",
       desc = paste("Score a configuration instead of arguing about its clear",
                    "rate: a clear-rate delta cannot separate recall from",
                    "false accepts."),
       topics = c("pf_evaluate", "pf_consistency", "pf_truth_schema",
                  "pf_population_id")),
  list(title = "Affiliates, dyads and sibling structure",
       desc = paste("Parent, chapter and auxiliary relationships — the",
                    "dominant source of wrong-but-plausible matches."),
       topics = c("pf_affiliation", "pf_build_affiliation_links", "pf_dyads",
                  "pf_build_dyads", "pf_dyad_annotate", "pf_dyad_collapse",
                  "pf_dyad_config", "pf_dyad_lookup", "pf_dyad_sources",
                  "pf_dyad_summary", "pf_cluster_arms", "pf_arm_core",
                  "pf_arm_order", "pf_is_arm")),
  list(title = "Source data",
       desc = paste("Build the grant file from the NCCS e-file extracts, and",
                    "Schedule I aliases."),
       topics = c("pf_efilepf", "pf_efilepf_build", "pf_efilepf_download",
                  "pf_efilepf_map", "pf_efilepf_url", "pf_schedi",
                  "pf_schedi_alias", "pf_schedi_build", "pf_schedi_download",
                  "pf_schedi_url", "pf_schedi_years")))

pkg <- pkgdown::as_pkgdown(PF)
have <- pkg$topics$name[!pkg$topics$internal]
assigned <- unlist(lapply(GROUPS, `[[`, "topics"), use.names = FALSE)

ghost <- setdiff(assigned, have)
if (length(ghost)) {
  say("DROPPING %d assigned name(s) that are not real topics:", length(ghost))
  for (x in ghost) say("    %s", x)
}
leftover <- sort(setdiff(have, assigned))
if (length(leftover)) {
  say("")
  say("%d topic(s) unassigned -> catch-all section:", length(leftover))
  for (x in leftover) say("    %s", x)
}

esc <- function(s) gsub('"', '\\\\"', s)
out <- c("", "reference:")
emit <- function(title, desc, topics) {
  topics <- intersect(topics, have)
  if (!length(topics)) return(character(0))
  c("", sprintf("- title: %s", title),
    "  desc: >",
    paste0("    ", strwrap(desc, width = 72)),
    "  contents:",
    paste0("  - ", topics))
}
for (g in GROUPS) out <- c(out, emit(g$title, g$desc, g$topics))
if (length(leftover))
  out <- c(out, emit("Other", paste("Topics not yet grouped. A new topic lands",
                                    "here rather than vanishing from the index."),
                     leftover))

yml <- readLines(file.path(PF, "_pkgdown.yml"))
head_end <- grep("^reference:", yml)
if (!length(head_end)) stop("no `reference:` key in _pkgdown.yml", call. = FALSE)
writeLines(c(yml[seq_len(head_end - 1L)], out), file.path(PF, "_pkgdown.yml"))
say("")
say("wrote _pkgdown.yml: %d topics across %d sections",
    length(intersect(assigned, have)) + length(leftover),
    length(GROUPS) + (length(leftover) > 0))
