#!/usr/bin/env Rscript
# ============================================================================
# build-purpose-testset.R -- the GOLD labeled (grant, candidate) frame for
# testing grant-purpose -> organization-text similarity.
#
# Source of truth: the 100 hand-adjudicated MAYBE cases
#   data-dev/AUDIT-MAYBE-100.csv   485 candidate rows, k=5 per grant, already
#                                  carrying BMF context for the candidate (CAND_)
#                                  and the filing foundation (FDN_)
#   dev/maybe-verdicts.csv         verdict + correct_rank per grant
#
# Enrichment (NTEE reference text, 990 mission, 990 programs, purpose
# contentfulness) is shared with the silver set via dev/purpose-enrich.R.
#
# Out: data-dev/PURPOSE-TESTSET.csv   (contentful-purpose grants sorted first)
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
setDTthreads(0)
PF <- Sys.getenv("PFMATCH_DIR", ".")
source(file.path(PF, "dev", "purpose-enrich.R"))
say <- pt_say
rd  <- function(p) fread(file.path(PF, p), colClasses = "character",
                         na.strings = NULL, showProgress = FALSE)

d <- rd("data-dev/AUDIT-MAYBE-100.csv")
v <- rd("dev/maybe-verdicts.csv")
d[, rank := as.integer(rank)]
d[, c("verdict", "verdict_note") := NULL]        # empty placeholders in the audit sheet
d <- merge(d, v[, .(grant_id, verdict, correct_rank, failure_mode, ntee_decisive,
                    verdict_note = note)], by = "grant_id", all.x = TRUE)
d[, correct_rank := suppressWarnings(as.integer(correct_rank))]
d[, is_correct   := !is.na(correct_rank) & rank == correct_rank]
d[, has_truth    := !is.na(correct_rank)]
say("candidates %d over %d grants; %d grants have an adjudicated correct rank",
    nrow(d), uniqueN(d$grant_id), uniqueN(d[has_truth == TRUE]$grant_id))

d <- pt_enrich(d)

say("candidate rows with NTEE ref text    : %4.1f%%", 100*mean(nzchar(d$cand_ntee_ref_text)))
say("candidate rows with 990 mission text : %4.1f%%", 100*mean(nzchar(d$cand_mission)))
say("candidate rows with 990 program text : %4.1f%%", 100*mean(nzchar(d$cand_prog_all)))
say("grants whose FOUNDATION has 990 text : %4.1f%%",
    100*mean(nzchar(unique(d, by = "grant_id")$fdn_mission)))
say("grants whose FOUNDATION has NTEE text: %4.1f%%",
    100*mean(nzchar(unique(d, by = "grant_id")$fdn_ntee_ref_text)))

keep <- c("grant_id","rank","is_top_pick","is_correct","has_truth","verdict",
  "correct_rank","failure_mode","ntee_decisive","verdict_note",
  "grant_purpose","purpose_ctoks","purpose_contentful","grant_amount",
  "fdn_ein","fdn_name","FDN_ntee_code_clean","FDN_ntee_code_definition",
  "FDN_nteev2_subsector","fdn_ntee_ref_text","fdn_mission","fdn_prog_all",
  "recip_name","recip_name_alt","recip_city","recip_state","recip_zip5",
  "recipient_type","ein","cand_name","cand_city","cand_state","cand_zip5",
  "score","name_sim","geo_zip5","geo_city","geo_state","pass","same_sector",
  "CAND_ntee_code_clean","CAND_ntee_code_definition","CAND_nteev2",
  "CAND_nteev2_subsector","CAND_activity_code_definitions","cand_ntee_ref_text",
  "cand_return_type","cand_n_programs","cand_mission","cand_prog_all")
out <- d[, ..keep]
gp <- out[, .(gmax = max(purpose_ctoks)), by = grant_id]     # contentful grants first
out[, gmax := gp$gmax[match(grant_id, gp$grant_id)]]
setorder(out, -gmax, grant_id, rank)
out[, gmax := NULL]
fwrite(out, file.path(PF, "data-dev", "PURPOSE-TESTSET.csv"), na = "")

g <- unique(out, by = "grant_id")
say("")
say("wrote data-dev/PURPOSE-TESTSET.csv : %d rows, %d grants", nrow(out), nrow(g))
say("  grants with adjudicated answer     : %d", sum(g$has_truth))
say("  ... and a contentful purpose       : %d", sum(g$has_truth & g$purpose_contentful))
say("  ... and correct NOT already rank 1 : %d",
    sum(g$has_truth & g$purpose_contentful & g$correct_rank > 1))
print(out[, .(rows = .N,
              with_ntee_text = sum(nzchar(cand_ntee_ref_text)),
              with_mission   = sum(nzchar(cand_mission)),
              with_program   = sum(nzchar(cand_prog_all)),
              with_activity  = sum(nzchar(CAND_activity_code_definitions))),
          by = .(purpose_contentful)])
