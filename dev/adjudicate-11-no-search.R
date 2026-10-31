#!/usr/bin/env Rscript
# ============================================================================
# adjudicate-11-no-search.R -- investigate 100 NO cases with Opus + web search.
#
# One arm, not three. The MAYBE experiment ran light / deep / deep+search
# because the question there was which tier to buy, and all three could answer
# it: the candidate set contained the answer 71% of the time, so a reviewer
# confined to the packet had something to decide.
#
# Here it does not. A NO case has no candidate worth offering -- 100% of the
# answer, when there is one, is outside the packet. A model with no search can
# only report that the filed name does not resemble the rejected records, which
# is what the cascade already said. Running a light arm would measure nothing,
# so this stage runs only the arm that can answer the question, and the
# vignette says plainly that no cheap alternative was tested because none is
# applicable.
#
# WHAT THE MODEL DECIDES AND WHAT THE PIPELINE DECIDES.
#
# The model has no access to the reference and is told so. It answers: who is
# this payee, what is its EIN if a source states one, what kind of entity is
# it, and should an exempt-organization record exist at all. Stage 12 then does
# the mechanical part -- is that EIN in the reference, was it ever offered to
# the scorer -- by exact lookup.
#
# That division is deliberate. dev/NO-RESIDUAL-AUDIT.md's one unambiguous
# result was the mechanical one ("it is a mechanical lookup"), and its softer
# ones carried "a few points of slack" from a single adjudicator. Asking the
# model only what requires world knowledge, and reserving set membership for
# code, keeps the load-bearing number out of the model's hands.
#
# THE SAME TWO API DETAILS AS STAGE 02, for the same reasons.
#
# 1. Forced tool use 400s on claude-opus-5-5, so the verdict comes back through
#    a strict `submit_no_verdict` tool under tool_choice auto, and the code
#    checks the call was made. output_config.format is NOT used: search results
#    carry citations and structured outputs reject citations.
# 2. stop_reason "pause_turn" is not an error. The partial turn is appended and
#    re-sent, up to PF_NO_ROUNDS times.
#
# MAXSEARCH is 15 rather than stage 02's 12. This task is open-ended in a way
# the MAYBE task is not: there, five candidate names bound the search space and
# twelve uses were ample; here the model is identifying an organisation from a
# free-text name with no shortlist, and the first few searches are often spent
# establishing that the obvious reading is wrong. Still a cap, still billed per
# use, and the run reports the distribution so a later run can tell whether it
# bound.
#
# OUTPUT  data-dev/ADJ-NO-SEARCH<tag>.rds
#
# USAGE
#   Rscript dev/adjudicate-11-no-search.R
#   PF_NO_LIMIT=3 Rscript dev/adjudicate-11-no-search.R     # smoke test
#   PF_NO_EFFORT=xhigh PF_NO_MAXSEARCH=20 Rscript dev/adjudicate-11-no-search.R
# ============================================================================
suppressWarnings(suppressMessages(library(data.table)))
PF <- Sys.getenv("PFMATCH_DIR", ".")
source(file.path(PF, "dev", "adjudicate-no-lib.R"))
DD <- file.path(PF, "data-dev")

LIMIT     <- as.integer(Sys.getenv("PF_NO_LIMIT", "0"))
WORKERS   <- as.integer(Sys.getenv("PF_NO_WORKERS", "4"))
EFFORT    <- Sys.getenv("PF_NO_EFFORT", "high")
MAXSEARCH <- as.integer(Sys.getenv("PF_NO_MAXSEARCH", "15"))
ROUNDS    <- as.integer(Sys.getenv("PF_NO_ROUNDS", "4"))
TAG       <- Sys.getenv("PF_NO_TAG", "")
MODEL     <- ADJ_MODEL_DEEP
# SET=exp  the 100-case random sample; SET=cal  the prior audit's own cases,
# for the human head-to-head. Separate prefixes so the two verdict sets cannot
# overwrite each other or be silently pooled -- the same guard PF_ADJ_SET gives
# the MAYBE stages.
SET       <- tolower(Sys.getenv("PF_NO_SET", "exp"))
stopifnot(SET %in% c("exp", "cal"))
PFX       <- if (SET == "cal") "ADJ-NOCAL" else "ADJ-NO"
OUT       <- file.path(DD, sprintf("%s-SEARCH%s.rds", PFX, TAG))

say <- function(...) { cat(sprintf(...), "\n"); flush.console() }
hr  <- function() cat(strrep("=", 78), "\n")

hr(); say("NO-TIER EXPERIMENT  stage 11: investigate with search"); hr()
say("model=%s  effort=%s  search=max %d uses  workers=%d%s", MODEL, EFFORT,
    MAXSEARCH, WORKERS,
    if (LIMIT > 0) sprintf("  LIMIT=%d (smoke test)", LIMIT) else "")

cf <- file.path(DD, sprintf("%s-CASES.rds", PFX))
if (!file.exists(cf))
  stop(sprintf("%s absent. Run PF_NO_SET=%s Rscript dev/adjudicate-10-no-packet.R first.",
       basename(cf), SET), call. = FALSE)
cases <- as.data.table(readRDS(cf))
pk    <- as.data.table(readRDS(file.path(DD, sprintf("%s-PACKET.rds", PFX))))
setorder(cases, batch_order)
if (LIMIT > 0) cases <- head(cases, LIMIT)
say("%d cases (%d with a rejected near-miss, %d with none)", nrow(cases),
    sum(cases$n_cand > 0), sum(cases$n_cand == 0))

## ---- the prompt ------------------------------------------------------------
system_prompt <- paste(readLines(file.path(PF, "dev", "LLM-NO-INSTRUCTIONS.md"),
                                warn = FALSE), collapse = "\n")
say("system prompt: %d characters", nchar(system_prompt))

tools <- list(
  list(type = "web_search_20260209", name = "web_search", max_uses = MAXSEARCH),
  list(name = "submit_no_verdict",
       description = paste("Record the investigation's conclusion for this case.",
                           "Call this exactly once, after searching is finished."),
       input_schema = adj_no_schema(), strict = TRUE))

## ---- fire, continuing any paused turn --------------------------------------
convos <- lapply(seq_len(nrow(cases)), function(i) {
  cr <- cases[i]
  cd <- if (nrow(pk)) pk[grant_id == cr$grant_id][order(rank)] else NULL
  if (!is.null(cd) && !nrow(cd)) cd <- NULL
  list(grant_id = cr$grant_id,
       messages = list(list(role = "user", content = adj_render_no_case(cr, cd))),
       done = FALSE, body = NULL, rounds = 0L,
       usage = c(input = 0, output = 0, cache_read = 0, cache_write = 0, web_search = 0),
       error = NA_character_)
})

t0 <- proc.time()[["elapsed"]]
for (round in seq_len(ROUNDS)) {
  pending <- which(!vapply(convos, function(x) x$done, logical(1)))
  if (!length(pending)) break
  say("\nround %d: %d request%s ...", round, length(pending),
      if (length(pending) == 1L) "" else "s")
  reqs <- lapply(pending, function(i) adj_request(
    model = MODEL, system = adj_system_cached(system_prompt),
    messages = convos[[i]]$messages,
    max_tokens = 8192, effort = EFFORT, tools = tools,
    tool_choice = list(type = "auto"), timeout = 1800))
  resps <- adj_perform(reqs, workers = WORKERS)
  paused <- 0L
  for (j in seq_along(pending)) {
    i <- pending[j]
    r <- adj_body(resps[[j]])
    convos[[i]]$rounds <- round
    if (!isTRUE(r$ok)) {
      convos[[i]]$done  <- TRUE
      convos[[i]]$error <- sprintf("HTTP %s: %s", r$status, r$error)
      next
    }
    b <- r$body
    convos[[i]]$usage <- convos[[i]]$usage + adj_usage(b)
    convos[[i]]$body  <- b
    if (identical(b$stop_reason, "pause_turn")) {
      convos[[i]]$messages <- c(convos[[i]]$messages,
                                list(list(role = "assistant", content = b$content)))
      paused <- paused + 1L
    } else {
      convos[[i]]$done <- TRUE
    }
  }
  say("  %d finished, %d paused mid-turn", length(pending) - paused, paused)
}
el <- proc.time()[["elapsed"]] - t0
say("\n%.1f s elapsed (%.1f s/case wall)", el, el / nrow(cases))

unfinished <- sum(!vapply(convos, function(x) x$done, logical(1)))
if (unfinished)
  say("WARNING: %d case%s still paused after %d rounds -- raise PF_NO_ROUNDS",
      unfinished, if (unfinished == 1L) "" else "s", ROUNDS)

## ---- collect ---------------------------------------------------------------
rows <- lapply(convos, function(cv) {
  base <- data.frame(api_ok = is.na(cv$error), api_error = cv$error,
                     rounds = cv$rounds, stop_reason = NA_character_,
                     tool_called = FALSE, stringsAsFactors = FALSE)
  if (!is.na(cv$error) || is.null(cv$body))
    return(cbind(adj_no_row(NULL, cv$grant_id), base))
  v <- adj_tool_input(cv$body, "submit_no_verdict")
  base$stop_reason <- as.character(cv$body$stop_reason %||% NA)
  base$tool_called <- !is.null(v)
  if (is.null(v)) v <- adj_parse_json(adj_text(cv$body))
  cbind(adj_no_row(v, cv$grant_id), base)
})
out <- as.data.table(rbindlist(rows, fill = TRUE))
um  <- do.call(rbind, lapply(convos, function(x) x$usage))
out[, `:=`(model = MODEL, effort = EFFORT, searches = um[, "web_search"],
           in_tokens = um[, "input"], out_tokens = um[, "output"],
           cache_read = um[, "cache_read"], cache_write = um[, "cache_write"])]
# `ein` is normalised here, not in stage 12. The model returns whatever its
# source printed -- "05-0448102", "050448102", sometimes with stray text -- and
# an un-normalised value fails an exact set-membership test against the
# reference for a formatting reason that looks exactly like a real absence.
out[, ein_raw := ein]
out[, ein := .pf_ein_local(ein_raw)]
nbad <- sum(!is.na(out$ein_raw) & nzchar(trimws(out$ein_raw)) & is.na(out$ein))
if (nbad)
  say("NOTE: %d reported EIN%s did not normalise to nine digits and are held as NA.",
      nbad, if (nbad == 1L) "" else "s")
out <- merge(cases[, .(grant_id, stratum, batch_order, recip_name, n_cand)],
             out, by = "grant_id")
setorder(out, batch_order)

## ---- read-out --------------------------------------------------------------
hr()
bad <- out[api_ok == FALSE]
if (nrow(bad)) {
  say("API FAILURES: %d of %d", nrow(bad), nrow(out))
  for (k in seq_len(min(10L, nrow(bad)))) say("  %s: %s", bad$grant_id[k], bad$api_error[k])
}
ok <- out[api_ok == TRUE]
say("\nverdicts returned: %d of %d  (tool call used on %d)",
    sum(!is.na(ok$org_found)), nrow(out), sum(ok$tool_called))
say("")
print(table(org_found = ok$org_found, useNA = "ifany"))
say("")
print(table(entity_class = ok$entity_class, useNA = "ifany"))
say("")
print(table(bmf_expectation = ok$bmf_expectation, useNA = "ifany"))
say("")
print(table(outside_reason = ok$outside_reason, useNA = "ifany"))
say("")
print(table(miss_hypothesis = ok$miss_hypothesis, useNA = "ifany"))
say("")
print(table(ein_source = ok$ein_source, useNA = "ifany"))
say("")
print(table(search_confirmed = ok$search_confirmed, confidence = ok$confidence))

say("\nEINs reported: %d (%d WEB-sourced, %d read off a rejected candidate)",
    sum(!is.na(ok$ein)), sum(!is.na(ok$ein) & ok$ein_source == "WEB", na.rm = TRUE),
    sum(!is.na(ok$ein) & ok$ein_source == "CANDIDATE", na.rm = TRUE))
say("searches: %d total, %.1f/case, %d cases with none, %d at the cap of %d",
    sum(out$searches), mean(out$searches), sum(out$searches == 0),
    sum(out$searches >= MAXSEARCH), MAXSEARCH)

tin <- sum(out$in_tokens); tout <- sum(out$out_tokens)
cost <- adj_cost(MODEL, tin, tout, sum(out$cache_read), sum(out$cache_write))
say("\ntokens: %s in, %s out   cache: %s read, %s WRITTEN",
    format(tin, big.mark = ","), format(tout, big.mark = ","),
    format(sum(out$cache_read), big.mark = ","),
    format(sum(out$cache_write), big.mark = ","))
say("token cost: $%.3f over %d cases ($%.6f/case)", cost, nrow(out), cost / nrow(out))
# 845, not the baseline's published 725: pf_status()'s NO tier also holds the
# 120 in-scope identities that never reached the result frame, and those are in
# this sample. Projecting onto 725 would price the wrong population.
if (SET == "exp")
  say("  projected for the 845-case NO tier: $%.2f", cost / nrow(out) * 845)
say("  PLUS %d web searches, billed per search and NOT in that figure.",
    sum(out$searches))

saveRDS(out, OUT)
say("\nwrote %s", OUT)
say("next: Rscript dev/adjudicate-12-no-score.R")
hr()
